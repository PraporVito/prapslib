-- keyframes.lua
local keyframes = {}

-- handlers[entity_key][controller_name] = { sound=fn, particle=fn, custom=fn }
local handlers = {}

local function key_of(e)
    local ok, id = pcall(function() return e:get_id() end)
    return (ok and id) and id or tostring(e)
end

-- Регистрация обработчиков (аналог setSoundKeyframeHandler и т.д.)
function keyframes.set_sound_handler(entity, controller_name, fn)
    local k = key_of(entity)
    handlers[k] = handlers[k] or {}
    handlers[k][controller_name] = handlers[k][controller_name] or {}
    handlers[k][controller_name].sound = fn
end

function keyframes.set_particle_handler(entity, controller_name, fn)
    local k = key_of(entity)
    handlers[k] = handlers[k] or {}
    handlers[k][controller_name] = handlers[k][controller_name] or {}
    handlers[k][controller_name].particle = fn
end

function keyframes.set_custom_handler(entity, controller_name, fn)
    local k = key_of(entity)
    handlers[k] = handlers[k] or {}
    handlers[k][controller_name] = handlers[k][controller_name] or {}
    handlers[k][controller_name].custom = fn
end

-- Встроенный авто-handler для звуков (аналог AutoPlayingSoundKeyframeHandler)
function keyframes.auto_sound_handler(entity, data)
    -- data = "namespace:soundid|volume|pitch" или "namespace:soundid"
    local parts = {}
    for part in data:gmatch("[^|]+") do table.insert(parts, part) end
    local sound = parts[1]
    local volume = tonumber(parts[2]) or 1.0
    local pitch = tonumber(parts[3]) or 1.0
    if sound and sound ~= "" then
        minetest.sound_play(sound, {
            object = entity,
            gain = volume,
            pitch = pitch,
            max_hear_distance = 32,
        })
    end
end

-- Проверка и вызов событий при обновлении контроллера
-- prev_time, curr_time — время в секундах
-- events — список событий из JSON (sound_effects, particle_effects, timeline)
function keyframes.tick(entity, controller_name, prev_time, curr_time, events, looped)
    if not events then return end
    local k = key_of(entity)
    local h = handlers[k] and handlers[k][controller_name]
    if not h then return end

    for _, ev in ipairs(events) do
        local t = ev.time or ev.timestamp or 0
        local fired = false

        if looped then
            -- При зацикливании: событие сработало, если время перескочило через t
            fired = (prev_time <= t and curr_time > t) or (prev_time > curr_time and (t >= prev_time or t < curr_time))
        else
            fired = prev_time <= t and curr_time > t
        end

        if fired then
            local ev_type = ev.type or "custom"
            local data = ev.data or ev.value or ""

            if ev_type == "sound" and h.sound then
                h.sound(entity, controller_name, data)
            elseif ev_type == "particle" and h.particle then
                h.particle(entity, controller_name, data)
            elseif ev_type == "custom" and h.custom then
                h.custom(entity, controller_name, data)
            end
        end
    end
end

function keyframes.clear(entity)
    handlers[key_of(entity)] = nil
end

return keyframes