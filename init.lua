-- prapslib/init.lua
prapslib = {}
local modpath = minetest.get_modpath("prapslib")

local cache      = dofile(modpath .. "/cache.lua")
local controller = dofile(modpath .. "/controller.lua")
local animator   = dofile(modpath .. "/animator.lua")
local net        = dofile(modpath .. "/net.lua")
local sm         = dofile(modpath .. "/state_machine.lua")
local keyframes  = dofile(modpath .. "/keyframes.lua")
local molang     = dofile(modpath .. "/molang.lua")
local math_utils = dofile(modpath .. "/math_utils.lua")
local easing     = dofile(modpath .. "/easing.lua")
local parser     = dofile(modpath .. "/parser.lua")
local ik         = dofile(modpath .. "/ik.lua")

prapslib.cache      = cache
prapslib.controller = controller
prapslib.animator   = animator
prapslib.net        = net
prapslib.sm         = sm
prapslib.keyframes  = keyframes
prapslib.molang     = molang
prapslib.math       = math_utils
prapslib.easing     = easing
prapslib.parser     = parser
prapslib.ik         = ik

-- ================= ПУБЛИЧНЫЙ API =================

function prapslib.register_entity(entity)
    animator.register_entity(entity)
    net.track_entity(entity)
end

function prapslib.unregister_entity(entity)
    animator.unregister_entity(entity)
    net.untrack_entity(entity)
    controller.clear(entity)
    sm.remove(entity, "*")
end

function prapslib.register_entity_data(modname, entity_type)
    return cache.get_or_load(modname, entity_type)
end

function prapslib.play_animation(entity, animation_name, options)
    local luaentity = entity:get_luaentity()
    if not luaentity then return nil end
    local entity_type = luaentity.name
    local modname = entity_type:match("^(.-):") or "unknown"
    local anim = cache.get_animation(modname, entity_type, animation_name)
    if not anim then
        minetest.log("error", "[PrapsLib] Animation not found: " .. animation_name)
        return nil
    end
    local ctrl = controller.register(entity, "default", 0, nil)
    ctrl:set_animation(animation_name, anim.loop or "loop")
    return ctrl
end

function prapslib.stop_animation(entity)
    for _, ctrl in pairs(controller.get_all(entity)) do
        ctrl.is_playing = false
        ctrl.current_animation = nil
    end
end

function prapslib.reset_bones(entity)
    animator.reset_bones(entity)
end

function prapslib.is_playing(entity)
    for _, ctrl in pairs(controller.get_all(entity)) do
        if ctrl.is_playing then return true end
    end
    return false
end

function prapslib.get_animation_time(entity)
    for _, ctrl in pairs(controller.get_all(entity)) do
        return ctrl.animation_time
    end
    return 0
end

function prapslib.clear_cache()
    cache.clear()
end

-- ================= NET =================

net.set_animation_resolver(function(entity, anim_name)
    local lua
    if entity.get_luaentity then
        lua = entity:get_luaentity()
    end
    if not lua then return nil end
    local modname = lua.name:match("^(.-):") or "unknown"
    return cache.get_animation(modname, lua.name, anim_name)
end)

net.register_client_receiver(
    function(eid, ctrl_name, anim_name, entry)
        local entity = animator._entity_registry[eid]
        if not entity then return end
        net.apply_client_set(eid, ctrl_name, anim_name, entry, entity, controller)
    end,
    function(eid, ctrl_name, trigger_name)
        local entity = animator._entity_registry[eid]
        if not entity then return end
        local ctrl = controller.get(entity, ctrl_name)
        if ctrl then ctrl:trigger(trigger_name) end
    end,
    function(eid, ctrl_name)
        local entity = animator._entity_registry[eid]
        if not entity then return end
        local ctrl = controller.get(entity, ctrl_name)
        if ctrl then
            ctrl.is_playing = false
            ctrl.current_animation = nil
        end
    end
)

if net.register_join_leave then
    net.register_join_leave()
end

-- ================= GLOBALSTEP =================

minetest.register_globalstep(function(dtime)
    local safe = math.min(dtime, 0.1)
    sm.update_all(safe)
    animator.update_all(safe)
end)

minetest.log("action", "[PrapsLib 2.0] Loaded successfully")
return prapslib