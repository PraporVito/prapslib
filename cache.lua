local cache = {}
local parser = dofile(minetest.get_modpath("prapslib") .. "/parser.lua")

local animation_cache = {}

function cache.get_or_load(modname, entity_type)
    if animation_cache[modname] and animation_cache[modname][entity_type] then
        return animation_cache[modname][entity_type]
    end

    local modpath = minetest.get_modpath(modname)
    if not modpath then
        return nil, "Mod not found: " .. modname
    end

    -- Извлекаем имя без префикса мода: "the_broken_script:integrity" → "integrity"
    local entity_name = entity_type:match(":(.+)$") or entity_type

    -- Приоритет 1: специфичный файл
    local specific_path = modpath .. "/prapslib/" .. entity_name .. ".animation.json"
    local data, err = parser.parse_animation_file(specific_path)

    -- Приоритет 2: общий файл
    if not data then
        local general_path = modpath .. "/prapslib/entity.animation.json"
        data, err = parser.parse_animation_file(general_path)
    end

    if not data then
        return nil, err or "Animation file not found for " .. entity_type
    end

    if not animation_cache[modname] then
        animation_cache[modname] = {}
    end
    animation_cache[modname][entity_type] = data

    return data
end

function cache.get_animation(modname, entity_type, animation_name)
    local data, err = cache.get_or_load(modname, entity_type)
    if not data then
        return nil, err
    end
    local anim = data.animations[animation_name]
    if not anim then
        return nil, "Animation not found: " .. animation_name
    end
    return anim
end

function cache.clear()
    animation_cache = {}
end

return cache