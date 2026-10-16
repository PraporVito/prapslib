-- net.lua
local net = {}
local modpath = minetest.get_modpath("prapslib")

local CHANNEL = "prapslib:anim"
local PROTOCOL_VERSION = 2

-- ✅ ВСТАВЬ
-- PrapsLib всегда работает от лица сервера:
-- в singleplayer — встроенный сервер, в мультиплеере — выделенный.
-- Сетевые вызовы (send_to_player) безопасны в обоих случаях.
local IS_SERVER = true

-- ============================================================
-- СОСТОЯНИЕ
-- ============================================================

net._server_seq  = {}
net._client_state = {}
net._active_entity_ids = {}
net._resolve_animation = nil
net._full_state_provider = nil

-- ============================================================
-- API: РЕЗОЛВЕР АНИМАЦИЙ (устанавливается из init.lua)
-- ============================================================

function net.set_animation_resolver(fn)
    net._resolve_animation = fn
end

function net.set_full_state_provider(fn)
    net._full_state_provider = fn
end

-- ============================================================
-- УТИЛИТА: безопасно достать ID сущности
-- ============================================================

local function get_entity_id(entity)
    if not entity then return nil end
    if type(entity.get_id) ~= "function" then return nil end
    local ok, id = pcall(function() return entity:get_id() end)
    if ok and id then return id end
    return nil
end

-- Отправить сообщение всем игрокам через mod channel
local function send_to_all(payload)
    for _, player in ipairs(minetest.get_connected_players()) do
        -- Luanti API: send_to_player(name, channel, message)
        minetest.send_to_player(player:get_player_name(), CHANNEL, payload)
    end
end

-- ============================================================
-- BROADCAST
-- ============================================================

function net.broadcast_set(entity, controller_name, anim_name, opts)
    if not IS_SERVER then return end
    opts = opts or {}

    local id = get_entity_id(entity)
    if not id then return end

    net._server_seq[id] = (net._server_seq[id] or 0) + 1

    local payload = minetest.serialize({
        v = PROTOCOL_VERSION,
        op = "SET",
        eid = id,
        ctrl = controller_name,
        anim = anim_name,
        weight = opts.weight or 1.0,
        loop = opts.loop or "loop",
        blend_ticks = opts.blend_ticks or 0,
        speed = opts.speed or 1.0,
        additive = opts.additive or false,
        start_offset = opts.start_offset or 0,
        seq = net._server_seq[id],
        t_sent = minetest.get_us_time() / 1e6,
    })

    send_to_all(payload)
end

function net.broadcast_trigger(entity, controller_name, trigger_name)
    if not IS_SERVER then return end
    local id = get_entity_id(entity)
    if not id then return end

    local payload = minetest.serialize({
        v = PROTOCOL_VERSION,
        op = "TRIGGER",
        eid = id,
        ctrl = controller_name,
        trigger = trigger_name,
        t_sent = minetest.get_us_time() / 1e6,
    })

    send_to_all(payload)
end

function net.broadcast_stop(entity, controller_name)
    if not IS_SERVER then return end
    local id = get_entity_id(entity)
    if not id then return end

    local payload = minetest.serialize({
        v = PROTOCOL_VERSION,
        op = "STOP",
        eid = id,
        ctrl = controller_name,
        t_sent = minetest.get_us_time() / 1e6,
    })

    send_to_all(payload)
end

-- ============================================================
-- JOIN: переслать всё состояние новому игроку
-- ============================================================

function net.send_full_state(player)
    if not IS_SERVER then return end
    local provider = net._full_state_provider
    if not provider then return end

    for eid, _ in pairs(net._active_entity_ids) do
        local state = provider(eid)
        if state then
            for _, entry in ipairs(state) do
                local payload = minetest.serialize({
                    v = PROTOCOL_VERSION,
                    op = "SET",
                    eid = eid,
                    ctrl = entry.ctrl,
                    anim = entry.anim,
                    weight = entry.weight or 1.0,
                    loop = entry.loop or "loop",
                    blend_ticks = entry.blend_ticks or 0,
                    speed = entry.speed or 1.0,
                    additive = entry.additive or false,
                    start_offset = entry.start_offset or 0,
                    seq = net._server_seq[eid] or 0,
                    t_sent = minetest.get_us_time() / 1e6,
                })
                minetest.send_to_player(player:get_player_name(), CHANNEL, payload)
            end
        end
    end
end

-- ============================================================
-- CLIENT RECEIVER
-- ============================================================

function net.register_client_receiver(on_set, on_trigger, on_stop)
    minetest.register_on_modchannel_message(function(channel_name, sender, message)
        if channel_name ~= CHANNEL then return end

        local ok, msg = pcall(minetest.deserialize, message)
        if not ok or type(msg) ~= "table" then return end
        if msg.v ~= PROTOCOL_VERSION then return end

        local eid = msg.eid

        if msg.op == "SET" then
            local st = net._client_state[eid]
            if not st then st = {}; net._client_state[eid] = st end

            local existing = st[msg.ctrl]
            if existing and existing.seq and msg.seq and existing.seq > msg.seq then
                return
            end

            local now = minetest.get_us_time() / 1e6
            local latency = math.max(0, now - (msg.t_sent or now))

            st[msg.ctrl] = {
                anim = msg.anim,
                loop = msg.loop,
                weight = msg.weight,
                blend_ticks = msg.blend_ticks,
                speed = msg.speed,
                additive = msg.additive,
                start_time = (msg.start_offset or 0) + latency * (msg.speed or 1.0),
                seq = msg.seq,
                received_at = now,
            }

            if on_set then on_set(eid, msg.ctrl, msg.anim, st[msg.ctrl]) end

        elseif msg.op == "TRIGGER" then
            if on_trigger then on_trigger(eid, msg.ctrl, msg.trigger) end

        elseif msg.op == "STOP" then
            local st = net._client_state[eid]
            if st then st[msg.ctrl] = nil end
            if on_stop then on_stop(eid, msg.ctrl) end
        end
    end)
end

-- ============================================================
-- УТИЛИТЫ КЛИЕНТА
-- ============================================================

function net.get_client_time(eid, ctrl)
    local st = net._client_state[eid]
    if not st or not st[ctrl] then return 0 end
    local entry = st[ctrl]
    local now = minetest.get_us_time() / 1e6
    local elapsed = (now - entry.received_at) * (entry.speed or 1.0)
    return entry.start_time + elapsed
end

function net.get_client_anim(eid, ctrl)
    local st = net._client_state[eid]
    if not st or not st[ctrl] then return nil end
    return st[ctrl].anim
end

function net.clear_client(eid)
    net._client_state[eid] = nil
end

-- ============================================================
-- ИНТЕГРАЦИЯ С КОНТРОЛЛЕРАМИ
-- ============================================================

function net.wrap_controller_set(entity, controller_name, anim_name, opts)
    net.broadcast_set(entity, controller_name, anim_name, opts)
end

function net.apply_client_set(eid, controller_name, anim_name, entry, entity, controller)
    if not entity or not controller then return end
    local resolver = net._resolve_animation
    if not resolver then return end
    local anim = resolver(entity, anim_name)
    if not anim then return end

    local ctrl = controller.get(entity, controller_name)
    if not ctrl then
        ctrl = controller.register(entity, controller_name, entry.blend_ticks or 0, nil)
    end

    ctrl.current_animation = anim
    ctrl.animation_time = entry.start_time or 0
    ctrl.is_playing = true
    ctrl.loop_type = entry.loop or "loop"
    ctrl.speed = entry.speed or 1.0
    ctrl.additive = entry.additive or false
    ctrl.net_driven = true
end

-- ============================================================
-- JOIN / LEAVE
-- ============================================================

-- ✅ ВСТАВЬ
function net.register_join_leave()
    minetest.register_on_joinplayer(function(player)
        -- В after() держим ссылку только через имя — объект может устареть
        local name = player:get_player_name()
        minetest.after(1.0, function()
            local p = minetest.get_player_by_name(name)
            if p then
                net.send_full_state(p)
            end
        end)
    end)
end

-- ============================================================
-- TRACK / UNTRACK
-- ============================================================

function net.track_entity(entity)
    local id = get_entity_id(entity)
    if not id then return end
    net._active_entity_ids[id] = true
end

function net.untrack_entity(entity)
    local id = get_entity_id(entity)
    if id then net._active_entity_ids[id] = nil end
end

return net