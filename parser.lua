-- parser.lua
local parser = {}
local modpath = minetest.get_modpath("prapslib")
local math_utils = dofile(modpath .. "/math_utils.lua")
local easing = dofile(modpath .. "/easing.lua")
local molang = dofile(modpath .. "/molang.lua")

-- ============================================================
-- ENTRYPOINTS
-- ============================================================

function parser.parse_animation_file(filepath)
    local file = io.open(filepath, "r")
    if not file then
        return nil, "File not found: " .. filepath
    end
    local content = file:read("*all")
    file:close()

    if not content or #content == 0 then
        return nil, "Empty animation file: " .. filepath
    end

    local ok, data = pcall(minetest.parse_json, content)
    if not ok then
        return nil, "JSON parse error in " .. filepath .. ": " .. tostring(data)
    end

    return parser.process_animation_data(data, filepath)
end

function parser.process_animation_data(data, source_path)
    if not data or not data.animations then
        return nil, "Invalid animation data: no 'animations' table"
    end

    local processed = {
        format_version = data.format_version or "1.8.0",
        source = source_path,
        animations = {},
    }

    for anim_name, anim_data in pairs(data.animations) do
        local anim = parser.process_single_animation(anim_name, anim_data)
        processed.animations[anim_name] = anim
    end

    return processed
end

-- ============================================================
-- ANIMATION
-- ============================================================

function parser.process_single_animation(name, data)
    local anim = {
        name = name,
        loop = data.loop or "play_once",
        animation_length = tonumber(data.animation_length) or 1.0,
        interpolation = data.interpolation or "cubic",
        bones = {},
        -- Events
        sound_effects = {},
        particle_effects = {},
        timeline = {},
        -- Meta
        blend_weight = data.blend_weight,
        anim_time_update = data.anim_time_update,
        override_previous = data.override_previous_animation or false,
    }

    -- Bones
    if data.bones then
        for bone_name, bone_data in pairs(data.bones) do
            anim.bones[bone_name] = parser.process_bone(bone_name, bone_data)
        end
    end

    -- Sound events
    if data.sound_effects then
        if data.sound_effects[1] then
            -- массив
            for _, ev in ipairs(data.sound_effects) do
                table.insert(anim.sound_effects, {
                    time = tonumber(ev.time or ev.timestamp or ev[1]) or 0,
                    data = ev.data or ev.value or ev.effect or ev[2] or "",
                })
            end
        else
            -- ключи-времена
            for time_str, val in pairs(data.sound_effects) do
                local t = tonumber(time_str)
                if t then
                    local d = type(val) == "table" and (val.effect or val.data or val.value) or val
                    table.insert(anim.sound_effects, { time = t, data = d or "" })
                end
            end
        end
    end

    -- Particle events
    if data.particle_effects then
        if data.particle_effects[1] then
            for _, ev in ipairs(data.particle_effects) do
                table.insert(anim.particle_effects, {
                    time = tonumber(ev.time or ev.timestamp or ev[1]) or 0,
                    data = ev.data or ev.value or ev.effect or ev[2] or "",
                    locator = ev.locator,
                })
            end
        else
            for time_str, val in pairs(data.particle_effects) do
                local t = tonumber(time_str)
                if t then
                    local d = type(val) == "table" and (val.effect or val.data or val.value) or val
                    table.insert(anim.particle_effects, { time = t, data = d or "" })
                end
            end
        end
    end

    -- Timeline (Blockbench Animate Effects)
    if data.timeline then
        for time_str, ev_list in pairs(data.timeline) do
            local t = tonumber(time_str)
            if t and type(ev_list) == "table" then
                for _, ev in ipairs(ev_list) do
                    if type(ev) == "table" then
                        table.insert(anim.timeline, {
                            time = t,
                            type = ev.type or "custom",
                            data = ev.data or ev.value or ev.effect or "",
                        })
                    end
                end
            end
        end
    end

    -- Сортируем события
    local function by_time(a, b) return a.time < b.time end
    table.sort(anim.sound_effects, by_time)
    table.sort(anim.particle_effects, by_time)
    table.sort(anim.timeline, by_time)

    -- Считаем max time для отладки
    local max_time = 0
    for _, bone_data in pairs(anim.bones) do
        for _, keyframes in pairs(bone_data) do
            if type(keyframes) == "table" then
                for _, kf in ipairs(keyframes) do
                    if kf.time > max_time then max_time = kf.time end
                end
            end
        end
    end
    for _, ev in ipairs(anim.sound_effects) do
        if ev.time > max_time then max_time = ev.time end
    end
    anim._max_keyframe = max_time

    return anim
end

-- ============================================================
-- BONES
-- ============================================================

function parser.process_bone(bone_name, data)
    local bone = {
        name = bone_name,
        rotation = nil,
        position = nil,
        scale = nil,
        -- Bedrock-specific
        rotation_global = nil,
    }

    if data.rotation        then bone.rotation        = parser.process_keyframes(data.rotation, "rotation") end
    if data.position        then bone.position        = parser.process_keyframes(data.position, "position") end
    if data.scale           then bone.scale           = parser.process_keyframes(data.scale, "scale")       end
    if data.rotation_global then bone.rotation_global = parser.process_keyframes(data.rotation_global, "rotation") end

    -- Parent / pivot (полезно для IK)
    bone.parent = data.parent
    bone.pivot  = data.pivot

    return bone
end

-- ============================================================
-- KEYFRAMES
-- ============================================================

function parser.process_keyframes(raw_keyframes, property_type)
    local keyframes = {}

    if type(raw_keyframes) ~= "table" then
        return keyframes
    end

    -- Форма 1: {0, 0, 0} — единственное значение на t=0
    if raw_keyframes[1] ~= nil and type(raw_keyframes[1]) ~= "table" then
        local vec = parser.extract_value(raw_keyframes)
        table.insert(keyframes, {
            time = 0, value = vec, pre = vec, post = vec, easing = nil,
        })
    -- Форма 2: { ["0"] = {...}, ["0.5"] = {...} }
    else
        for time_str, value in pairs(raw_keyframes) do
            local time = tonumber(time_str)
            if time then
                local kf = parser.process_single_keyframe(time, value)
                if kf then table.insert(keyframes, kf) end
            end
        end
    end

    table.sort(keyframes, function(a, b) return a.time < b.time end)

    -- Convert degrees→radians для вращений
    if property_type == "rotation" then
        for _, kf in ipairs(keyframes) do
            kf.value = math_utils.deg_to_rad_vec3(kf.value)
            kf.pre   = math_utils.deg_to_rad_vec3(kf.pre)
            kf.post  = math_utils.deg_to_rad_vec3(kf.post)
            -- per-axis control points тоже в градусы
            if kf.cp_before then
                kf.cp_before = math_utils.deg_to_rad_vec3(kf.cp_before)
            end
            if kf.cp_after then
                kf.cp_after = math_utils.deg_to_rad_vec3(kf.cp_after)
            end
        end
    end

    return keyframes
end

function parser.process_single_keyframe(time, value)
    local kf = {
        time = time,
        value = nil,
        pre = nil,   -- используется как P1 для кубической интерполяции
        post = nil,  -- P2
        easing = nil,
        -- Per-axis control points (Blockbench Molang)
        cp_before = nil,
        cp_after = nil,
        -- Molang-выражение (строки)
        molang_expr = nil,
    }

    -- Простое число (для одномерных свойств)
    if type(value) == "number" then
        kf.value = {value, 0, 0}
        kf.pre   = kf.value
        kf.post  = kf.value
        return kf
    end

    -- Строка = Molang-выражение
    if type(value) == "string" then
        kf.molang_expr = value
        local evaluated = molang.eval(value, {})
        kf.value = {evaluated, 0, 0}
        kf.pre   = kf.value
        kf.post  = kf.value
        return kf
    end

    -- Таблица
    if type(value) == "table" then
        -- {"pre": [...], "post": [...], "easing": "..."}
        local vec, pre_vec, post_vec = parser.extract_value_full(value)
        if not vec then return nil end

        kf.value = vec
        kf.pre   = pre_vec or vec
        kf.post  = post_vec or vec

        -- Easing
        if value.easing then
            kf.easing = value.easing
        end

        -- Per-axis контрольные точки (Blockbench)
        if value.catmullrom or value.cp then
            kf.cp_before = value.cp and value.cp[1] or value.pre
            kf.cp_after  = value.cp and value.cp[2] or value.post
        end

        return kf
    end

    return nil
end

-- ============================================================
-- VALUE EXTRACTORS
-- ============================================================

-- Возвращает (value_vec, pre_vec, post_vec)
function parser.extract_value_full(value)
    -- {pre: [...], post: [...]}
    if type(value) == "table" and value.pre and value.post then
        local pre_vec  = parser._to_vec3(value.pre)
        local post_vec = parser._to_vec3(value.post)
        return post_vec, pre_vec, post_vec
    end

    -- ["expr1", "expr2", "expr3"] с Molang
    if type(value) == "table" and value[1] ~= nil then
        local vec = parser._to_vec3_molang(value)
        return vec, vec, vec
    end

    if type(value) == "number" then
        local vec = {value, 0, 0}
        return vec, vec, vec
    end

    if type(value) == "string" then
        local v = molang.eval(value, {})
        local vec = {v, v, v}
        return vec, vec, vec
    end

    return nil, nil, nil
end

function parser.extract_value(value)
    local vec = parser.extract_value_full(value)
    return vec
end

-- ============================================================
-- HELPERS
-- ============================================================

function parser._to_vec3(t)
    if type(t) ~= "table" then
        if type(t) == "number" then return {t, t, t} end
        if type(t) == "string" then
            local v = molang.eval(t, {})
            return {v, v, v}
        end
        return {0, 0, 0}
    end
    return {
        tonumber(t[1]) or (type(t[1]) == "string" and molang.eval(t[1], {})) or 0,
        tonumber(t[2]) or (type(t[2]) == "string" and molang.eval(t[2], {})) or 0,
        tonumber(t[3]) or (type(t[3]) == "string" and molang.eval(t[3], {})) or 0,
    }
end

function parser._to_vec3_molang(t)
    local function conv(v)
        if type(v) == "number" then return v end
        if type(v) == "string" then return molang.eval(v, {}) end
        return 0
    end
    return {conv(t[1]), conv(t[2]), conv(t[3])}
end

-- Валидация: все ли bones имеют корректную структуру
function parser.validate(processed)
    local errors = {}
    if not processed or not processed.animations then
        return {"no animations"}
    end
    for anim_name, anim in pairs(processed.animations) do
        if anim.animation_length <= 0 then
            table.insert(errors, anim_name .. ": length <= 0")
        end
        for bone_name, bone in pairs(anim.bones) do
            if not bone.rotation and not bone.position and not bone.scale then
                table.insert(errors, anim_name .. "/" .. bone_name .. ": no channels")
            end
        end
    end
    return errors
end

return parser