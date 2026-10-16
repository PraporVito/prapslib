-- controller.lua
local controller = {}
local easing = dofile(minetest.get_modpath("prapslib") .. "/easing.lua")
local molang = dofile(minetest.get_modpath("prapslib") .. "/molang.lua")
local keyframes = dofile(minetest.get_modpath("prapslib") .. "/keyframes.lua")
local math_utils = dofile(minetest.get_modpath("prapslib") .. "/math_utils.lua")

-- controllers[entity_key] = { [controller_name] = ControllerInstance }
local controllers = {}

-- ==================== ControllerInstance ====================

local ControllerInstance = {}
ControllerInstance.__index = ControllerInstance

function ControllerInstance.new(entity, name, transition_ticks, state_handler)
    local self = setmetatable({}, ControllerInstance)
    self.entity = entity
    self.name = name
    self.transition_ticks = transition_ticks or 0
    self.state_handler = state_handler

    self.current_animation = nil
    self.previous_animation = nil
    self.animation_time = 0
    self.previous_time = 0
    self.transition_time = 0
    self.transition_progress = 0
    self.is_transitioning = false
    self.is_playing = false
    self.speed = 1.0
    self.loop_type = "loop"
    self.additive = false
    self.override_easing = nil
    self.triggerable = {} -- name -> animation
    self.active_trigger = nil
    self.active_trigger_time = 0

    -- Данные для событий
    self.sound_events = {}
    self.particle_events = {}
    self.custom_events = {}

    return self
end

-- Аналог setAnimation / setAndContinue
function ControllerInstance:set_animation(anim_name, loop_type)
    if self.current_animation and self.current_animation.name == anim_name then
        return -- Уже играет
    end

    if self.current_animation then
        self.previous_animation = self.current_animation
        self.previous_time = self.animation_time
        self.is_transitioning = self.transition_ticks > 0
        self.transition_progress = 0
        self.transition_time = self.transition_ticks / 20 -- тиков в секунды
    end

    self.current_animation = self.animation_data and self.animation_data.animations[anim_name] or nil
    self.animation_time = 0
    self.is_playing = true
    self.loop_type = loop_type or (self.current_animation and self.current_animation.loop) or "loop"

    -- Извлекаем события из анимации
    self:_extract_events()
end

function ControllerInstance:_extract_events()
    if not self.current_animation then return end
    local anim = self.current_animation

    self.sound_events = {}
    self.particle_events = {}
    self.custom_events = {}

    -- Из timeline (Blockbench "Animate Effects")
    if anim.timeline then
        for _, ev in ipairs(anim.timeline) do
            local entry = { time = ev.time, data = ev.data or ev.value or "", type = ev.type }
            if ev.type == "sound" then
                table.insert(self.sound_events, entry)
            elseif ev.type == "particle" then
                table.insert(self.particle_events, entry)
            else
                table.insert(self.custom_events, entry)
            end
        end
    end

    -- Из sound_effects / particle_effects (прямые поля)
    if anim.sound_effects then
        for _, ev in ipairs(anim.sound_effects) do
            table.insert(self.sound_events, { time = ev.time or ev.timestamp or 0, data = ev.data or ev.value or "" })
        end
    end
    if anim.particle_effects then
        for _, ev in ipairs(anim.particle_effects) do
            table.insert(self.particle_events, { time = ev.time or ev.timestamp or 0, data = ev.data or ev.value or "" })
        end
    end
end

-- Аналог triggerAnim
function ControllerInstance:register_triggerable(name, anim_name)
    self.triggerable[name] = anim_name
end

function ControllerInstance:trigger(name)
    local anim_name = self.triggerable[name]
    if not anim_name then return false end
    self.active_trigger = anim_name
    self.active_trigger_time = 0
    self:set_animation(anim_name, "hold_on_last_frame")
    return true
end

function ControllerInstance:stop_trigger()
    if self.active_trigger then
        self.active_trigger = nil
        self.is_playing = false
        self.current_animation = nil
    end
end

function controller.clear_by_key(entity_key)
    controllers[entity_key] = nil
end

function controller._get_all()
    return controllers
end

-- ==================== Обновление ====================

function ControllerInstance:update(dtime, entity_state)
    -- Вызываем state handler (аналог AnimationStateHandler)
    if self.state_handler and not self.active_trigger then
        local play_state, anim_name = self.state_handler(entity_state, self)
        if play_state == "stop" then
            self.is_playing = false
            self.current_animation = nil
        elseif play_state == "play" and anim_name then
            self:set_animation(anim_name)
        end
    end

    if not self.current_animation or not self.is_playing then return end

    -- Продвигаем время
    local anim = self.current_animation
    local length = anim.animation_length or 1.0
    local prev_t = self.animation_time

    self.animation_time = self.animation_time + dtime * self.speed

    -- Обработка loop
    if self.animation_time >= length then
        if self.loop_type == "loop" then
            self.animation_time = self.animation_time % length
        elseif self.loop_type == "hold_on_last_frame" then
            self.animation_time = length
            self.is_playing = false
        else
            self.animation_time = length
            self.is_playing = false
        end
    end

    -- События
    keyframes.tick(self.entity, self.name, prev_t, self.animation_time, self.sound_events, self.loop_type == "loop")
    keyframes.tick(self.entity, self.name, prev_t, self.animation_time, self.particle_events, self.loop_type == "loop")
    keyframes.tick(self.entity, self.name, prev_t, self.animation_time, self.custom_events, self.loop_type == "loop")

    -- Обновляем transition
    if self.is_transitioning then
        self.transition_progress = self.transition_progress + dtime
        if self.transition_progress >= self.transition_time then
            self.is_transitioning = false
            self.previous_animation = nil
        end
    end
end

-- Получить текущую позу (для микширования)
function ControllerInstance:get_pose(ctx)
    if not self.current_animation then return {} end

    local pose = {}
    local anim = self.current_animation
    local t = self.animation_time

    -- Если transitioning — берём позу из старой анимации и миксуем
    local blend_weight = 1.0
    if self.is_transitioning and self.previous_animation then
        blend_weight = self.transition_progress / self.transition_time
        blend_weight = math_utils.clamp(blend_weight, 0, 1)
    end

    for bone_name, bone_data in pairs(anim.bones) do
        local b = {}
        if bone_data.rotation then
            b.rotation = self:_sample_channel(bone_data.rotation, t, ctx)
        end
        if bone_data.position then
            b.position = self:_sample_channel(bone_data.position, t, ctx)
        end
        if bone_data.scale then
            b.scale = self:_sample_channel(bone_data.scale, t, ctx)
        end
        pose[bone_name] = b
    end

    -- Миксуем со старой позой
    if blend_weight < 1.0 and self.previous_animation then
        local old_pose = {}
        local old_anim = self.previous_animation
        local old_t = self.previous_time
        for bone_name, bone_data in pairs(old_anim.bones) do
            local b = {}
            if bone_data.rotation then b.rotation = self:_sample_channel(bone_data.rotation, old_t, ctx) end
            if bone_data.position then b.position = self:_sample_channel(bone_data.position, old_t, ctx) end
            if bone_data.scale then b.scale = self:_sample_channel(bone_data.scale, old_t, ctx) end
            old_pose[bone_name] = b
        end
        -- Миксуем: pose = old * (1-w) + new * w
        for bone_name, new_b in pairs(pose) do
            local old_b = old_pose[bone_name]
            if old_b then
                if new_b.rotation and old_b.rotation then
                    new_b.rotation = self:_mix_rotation(old_b.rotation, new_b.rotation, blend_weight)
                end
                if new_b.position and old_b.position then
                    new_b.position = self:_mix_vec3(old_b.position, new_b.position, blend_weight)
                end
                if new_b.scale and old_b.scale then
                    new_b.scale = self:_mix_vec3(old_b.scale, new_b.scale, blend_weight)
                end
            end
        end
    end

    return pose
end

function ControllerInstance:_sample_channel(keyframes, t, ctx)
    if not keyframes or #keyframes == 0 then return nil end

    -- Находим до и после
    local kf_before, kf_after = nil, nil
    for _, kf in ipairs(keyframes) do
        if kf.time <= t then kf_before = kf end
        if kf.time >= t and not kf_after then kf_after = kf end
    end
    if not kf_before then return keyframes[1].value end
    if not kf_after then return keyframes[#keyframes].value end
    if kf_before == kf_after then return kf_before.value end

    local dt = kf_after.time - kf_before.time
    if dt <= 0 then return kf_after.value end
    local raw_t = (t - kf_before.time) / dt

    -- Easing
    local ease_name = self.override_easing or kf_before.easing or "linear"
    local eased_t = easing.get(ease_name)(raw_t)
    if kf_before.easing == "catmull_rom" or (kf_before.pre and kf_after.post) then
        -- Catmull-Rom для smooth
        local p0 = kf_before.value
        local p1 = kf_before.post or kf_before.value
        local p2 = kf_after.pre or kf_after.value
        local p3 = kf_after.value
        return {
            easing.catmull_rom(p0[1], p1[1], p2[1], p3[1], eased_t),
            easing.catmull_rom(p0[2], p1[2], p2[2], p3[2], eased_t),
            easing.catmull_rom(p0[3], p1[3], p2[3], p3[3], eased_t),
        }
    end

    -- Lerp
    return {
        math_utils.lerp(kf_before.value[1], kf_after.value[1], eased_t),
        math_utils.lerp(kf_before.value[2], kf_after.value[2], eased_t),
        math_utils.lerp(kf_before.value[3], kf_after.value[3], eased_t),
    }
end

function ControllerInstance:_mix_vec3(a, b, w)
    return {
        math_utils.lerp(a[1], b[1], w),
        math_utils.lerp(a[2], b[2], w),
        math_utils.lerp(a[3], b[3], w),
    }
end

function ControllerInstance:_mix_rotation(a, b, w)
    local qa = math_utils.quat_from_euler(a[1], a[2], a[3])
    local qb = math_utils.quat_from_euler(b[1], b[2], b[3])
    local qm = math_utils.quat_slerp(qa, qb, w)
    local x, y, z = math_utils.quat_to_euler(qm)
    return {x, y, z}
end

-- ==================== API ====================

function controller.register(entity, name, transition_ticks, state_handler)
    local k = key_of(entity)
    controllers[k] = controllers[k] or {}
    local ctrl = ControllerInstance.new(entity, name, transition_ticks, state_handler)
    controllers[k][name] = ctrl
    return ctrl
end

function controller.get(entity, name)
    local k = key_of(entity)
    return controllers[k] and controllers[k][name]
end

function controller.get_all(entity)
    local k = key_of(entity)
    return controllers[k] or {}
end

function controller.clear(entity)
    controllers[key_of(entity)] = nil
end

function controller.update_all(entity, dtime, entity_state)
    local k = key_of(entity)
    local ctrls = controllers[k]
    if not ctrls then return end
    for _, ctrl in pairs(ctrls) do
        ctrl:update(dtime, entity_state)
    end
end

-- Сборка финальной позы из всех контроллеров (в порядке регистрации)
function controller.build_pose(entity, ctx)
    local k = key_of(entity)
    local ctrls = controllers[k]
    if not ctrls then return {} end

    local final = {}
    -- Сортируем по порядку регистрации (GeckoLib: поздние перекрывают ранние)
    local ordered = {}
    for name, ctrl in pairs(ctrls) do
        table.insert(ordered, { name = name, ctrl = ctrl })
    end
    -- Lua не хранит порядок, поэтому используем priority
    table.sort(ordered, function(a, b)
        return (a.ctrl.priority or 0) < (b.ctrl.priority or 0)
    end)

    for _, entry in ipairs(ordered) do
        local pose = entry.ctrl:get_pose(ctx)
        if entry.ctrl.additive then
            -- Аддитивно: прибавляем
            for bone_name, b in pairs(pose) do
                final[bone_name] = final[bone_name] or {}
                local fb = final[bone_name]
                for prop, val in pairs(b) do
                    if fb[prop] then
                        fb[prop][1] = fb[prop][1] + val[1]
                        fb[prop][2] = fb[prop][2] + val[2]
                        fb[prop][3] = fb[prop][3] + val[3]
                    else
                        fb[prop] = {val[1], val[2], val[3]}
                    end
                end
            end
        else
            -- Override: заменяем
            for bone_name, b in pairs(pose) do
                final[bone_name] = final[bone_name] or {}
                for prop, val in pairs(b) do
                    final[bone_name][prop] = {val[1], val[2], val[3]}
                end
            end
        end
    end

    return final
end

local function key_of(e)
    local ok, id = pcall(function() return e:get_id() end)
    return (ok and id) and id or tostring(e)
end

return controller