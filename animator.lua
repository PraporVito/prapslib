-- animator.lua
local animator = {}

local modpath = minetest.get_modpath("prapslib")
local math_utils = dofile(modpath .. "/math_utils.lua")
local controller = dofile(modpath .. "/controller.lua")
local molang     = dofile(modpath .. "/molang.lua")

-- ============================================================
-- РЕЕСТР СУЩНОСТЕЙ
-- ============================================================

animator._entity_registry = {}

function animator.register_entity(entity)
    if not entity then return end
    local ok, id = pcall(function() return entity:get_id() end)
    if ok and id then
        animator._entity_registry[id] = entity
    end
end

function animator.unregister_entity(entity)
    if not entity then return end
    local ok, id = pcall(function() return entity:get_id() end)
    if ok and id then
        animator._entity_registry[id] = nil
    end
end

local function safe_call(entity, method, ...)
    if not entity or type(entity[method]) ~= "function" then return nil end
    local ok, a, b, c = pcall(entity[method], entity, ...)
    if ok then return a, b, c end
    return nil
end

-- ============================================================
-- ОСНОВНОЙ ЦИКЛ
-- ============================================================

function animator.update_all(dtime)
    local safe = math.min(dtime, 0.1)
    local POSITION_SCALE = 1.0 / 16.0

    local to_remove = {}

    for id, entity in pairs(animator._entity_registry) do
        if not entity or not safe_call(entity, "get_pos") then
            table.insert(to_remove, id)
        else
            -- Собираем состояние сущности
            local vel = safe_call(entity, "get_velocity") or {x=0, y=0, z=0}
            local speed = math.sqrt(vel.x*vel.x + vel.y*vel.y + vel.z*vel.z)

            local entity_state = {
                speed = speed,
                is_moving = speed > 0.1,
                on_ground = true,   -- переопредели под свою физику
                health = 20,
                anim_time = 0,
                life_time = 0,
                yaw = 0,
                pitch = 0,
            }

            -- 1) Обновляем контроллеры (они продвигают время, дёргают события)
            controller.update_all(entity, safe, entity_state)

            -- 2) Собираем финальную позу
            local ctx = {
                anim_time = 0,
                life_time = 0,
                is_moving = entity_state.is_moving,
                entity = entity,
            }
            local pose = controller.build_pose(entity, ctx)

            -- 3) Применяем bone override
            for bone_name, b in pairs(pose) do
                local override = {}
                if b.rotation then
                    override.rotation = {
                        vec = {x = b.rotation[1], y = b.rotation[2], z = b.rotation[3]},
                        absolute = false,
                    }
                end
                if b.position then
                    override.position = {
                        vec = {
                            x = b.position[1] * POSITION_SCALE,
                            y = b.position[2] * POSITION_SCALE,
                            z = b.position[3] * POSITION_SCALE,
                        },
                        absolute = false,
                    }
                end
                if b.scale then
                    override.scale = {
                        vec = {x = b.scale[1], y = b.scale[2], z = b.scale[3]},
                        absolute = false,
                    }
                end
                if next(override) then
                    pcall(function()
                        entity:set_bone_override(bone_name, override)
                    end)
                end
            end
        end
    end

    -- Убираем мёртвые сущности
    for _, id in ipairs(to_remove) do
        animator._entity_registry[id] = nil
        if controller.clear_by_key then controller.clear_by_key(id) end
    end
end

-- ============================================================
-- ИНТЕРПОЛЯЦИЯ KEYFRAMES (используется в controller и др.)
-- ============================================================

function animator.interpolate_keyframes(keyframes, current_time, interpolation)
    if not keyframes or #keyframes == 0 then return nil end

    local kf_before, kf_after = nil, nil

    for _, kf in ipairs(keyframes) do
        if kf.time <= current_time then kf_before = kf end
        if kf.time >= current_time and not kf_after then kf_after = kf end
    end

    if not kf_before then return keyframes[1].value end
    if not kf_after then return keyframes[#keyframes].value end
    if kf_before == kf_after then return kf_before.value end

    local span = kf_after.time - kf_before.time
    if span <= 0 then return kf_after.value end
    local t = math_utils.clamp((current_time - kf_before.time) / span, 0, 1)

    if interpolation == "step" then
        return math_utils.step_value(kf_before.value)

    elseif interpolation == "linear" then
        if #kf_before.value == 3 and type(kf_before.value[1]) == "number" then
            -- если это эйлеровы углы — slerp, иначе lerp
            local max_val = math.max(
                math.abs(kf_before.value[1]),
                math.abs(kf_before.value[2]),
                math.abs(kf_before.value[3])
            )
            if max_val < math.pi * 2 then
                return math_utils.slerp_euler(kf_before.value, kf_after.value, t)
            end
        end
        return math_utils.lerp_vec3(kf_before.value, kf_after.value, t)

    else -- cubic / catmullrom
        local p0 = kf_before.value
        local p1 = kf_before.post or kf_before.value
        local p2 = kf_after.pre   or kf_after.value
        local p3 = kf_after.value
        return math_utils.cubic_bezier(p0, p1, p2, p3, t)
    end
end

-- ============================================================
-- РЕСЕТ КОСТЕЙ
-- ============================================================

function animator.reset_bones(entity)
    if not entity then return end
    -- Сбрасываем через пустые override (Luanti вернёт дефолтную позу)
    -- Точный список костей не знаем, поэтому пробуем найти из активной анимации
    local ctrls = controller.get_all(entity)
    local bones_set = {}
    for _, ctrl in pairs(ctrls) do
        if ctrl.current_animation and ctrl.current_animation.bones then
            for bone_name in pairs(ctrl.current_animation.bones) do
                bones_set[bone_name] = true
            end
        end
    end
    for bone_name in pairs(bones_set) do
        pcall(function()
            entity:set_bone_override(bone_name, {
                rotation = {vec = {x=0, y=0, z=0}, absolute = false},
                position = {vec = {x=0, y=0, z=0}, absolute = false},
                scale    = {vec = {x=1, y=1, z=1}, absolute = false},
            })
        end)
    end
end

-- ============================================================
-- УТИЛИТЫ (для совместимости со старым API)
-- ============================================================

function animator.is_playing(entity)
    for _, ctrl in pairs(controller.get_all(entity)) do
        if ctrl.is_playing then return true end
    end
    return false
end

function animator.get_animation_time(entity)
    for _, ctrl in pairs(controller.get_all(entity)) do
        return ctrl.animation_time or 0
    end
    return 0
end

function animator.stop_animation(entity)
    for _, ctrl in pairs(controller.get_all(entity)) do
        ctrl.is_playing = false
        ctrl.current_animation = nil
    end
end

function animator.cleanup_finished()
    -- Больше не нужно: контроллеры сами себя чистят.
end

return animator