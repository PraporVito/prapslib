-- state_machine.lua
local sm = {}
local modpath = minetest.get_modpath("prapslib")
local math_utils = dofile(modpath .. "/math_utils.lua")
local controller = dofile(modpath .. "/controller.lua")
local molang = dofile(modpath .. "/molang.lua")

-- ============================================================
-- STATE DEFINITION
-- ============================================================
-- state = {
--   name = "walk",
--   layers = {
--     { controller = "movement", anim = "walk", weight = 1, blend = "override", mask = {...} },
--     { controller = "breath",   anim = "breathe", weight = 0.3, blend = "additive" },
--   },
--   speed = 1.0,
--   events = {
--     on_enter = fn(entity, prev_state),
--     on_exit  = fn(entity, next_state),
--     on_update = fn(entity, dtime, state),
--   },
--   transitions = {
--     { to = "idle", when = function(ctx) return not ctx.is_moving end, duration_ticks = 5, priority = 0 },
--     { to = "attack", when = "query.is_attacking", duration_ticks = 2, priority = 10 },
--   },
-- }

-- ============================================================
-- MACHINE STRUCTURE
-- ============================================================

local Machine = {}
Machine.__index = Machine

function Machine.new(entity, name)
    return setmetatable({
        entity = entity,
        name = name,
        states = {},              -- name -> state
        current = nil,
        previous = nil,
        time_in_state = 0,
        transition = nil,         -- { from, to, duration, elapsed, data }
        params = {},              -- float/bool/trigger parameters
        triggers = {},            -- consumed each tick
        listeners = {},           -- on_state_change
        any_transitions = {},     -- глобальные переходы (из любого состояния)
        _paused = false,
        _dirty = false,
    }, Machine)
end

-- ============================================================
-- AUTHORING
-- ============================================================

function Machine:add_state(name, def)
    def.name = name
    def.layers = def.layers or {}
    def.transitions = def.transitions or {}
    def.events = def.events or {}
    self.states[name] = def
    return self
end

function Machine:add_any_transition(def)
    table.insert(self.any_transitions, def)
    return self
end

function Machine:set_initial(name)
    self.initial_state = name
    return self
end

function Machine:add_listener(fn)
    table.insert(self.listeners, fn)
    return self
end

-- ============================================================
-- PARAMETERS (аналог Unity Animator Parameters)
-- ============================================================

function Machine:set_bool(name, val)
    val = val and true or false
    if self.params[name] ~= val then
        self.params[name] = val
        self._dirty = true
    end
end

function Machine:set_float(name, val)
    if self.params[name] ~= val then
        self.params[name] = val
        self._dirty = true
    end
end

function Machine:set_int(name, val)
    if self.params[name] ~= val then
        self.params[name] = val
        self._dirty = true
    end
end

function Machine:trigger(name)
    self.triggers[name] = true
end

function Machine:get_param(name)
    return self.params[name]
end

-- ============================================================
-- RUNTIME
-- ============================================================

function Machine:_build_context()
    -- Контекст для Molang и when-функций
    local ctx = {}
    for k, v in pairs(self.params) do ctx[k] = v end
    for k, v in pairs(self.triggers) do ctx[k] = true end
    ctx.time_in_state = self.time_in_state
    ctx.entity = self.entity
    ctx.state = self.current and self.current.name
    return ctx
end

function Machine:_eval_when(when, ctx)
    if type(when) == "function" then
        return when(ctx) and true or false
    elseif type(when) == "string" then
        -- Molang-подобное выражение: "is_moving && !is_attacking"
        return sm.eval_condition(when, ctx)
    end
    return false
end

function Machine:_start_transition(to_state_name, duration_ticks, data)
    if self.transition then
        -- уже в переходе — игнорируем, если не приоритетнее
        return false
    end
    local to_state = self.states[to_state_name]
    if not to_state then return false end

    local from_state = self.current
    if from_state and from_state.events.on_exit then
        from_state.events.on_exit(self.entity, to_state_name)
    end

    self.transition = {
        from = from_state,
        to = to_state,
        duration = (duration_ticks or 0) / 20, -- тиков в секунды
        elapsed = 0,
        data = data,
    }

    if duration_ticks == 0 or duration_ticks == nil then
        self:_complete_transition()
    end

    return true
end

function Machine:_complete_transition()
    local t = self.transition
    if not t then return end

    self.previous = t.from
    self.current = t.to
    self.time_in_state = 0
    self.transition = nil

    -- Применяем слои нового состояния к контроллерам
    for _, layer in ipairs(self.current.layers) do
        local ctrl = controller.get(self.entity, layer.controller)
        if not ctrl then
            ctrl = controller.register(self.entity, layer.controller, layer.blend_ticks or 0, nil)
        end
        -- Устанавливаем анимацию в контроллер
        ctrl:set_animation(layer.anim, layer.loop or "loop")
        ctrl.weight = layer.weight or 1.0
        ctrl.blend_mode = layer.blend or "override"
        ctrl.mask = layer.mask
        ctrl.speed = layer.speed or (self.current.speed or 1.0) * (layer.speed_mult or 1.0)
    end

    -- Событие on_enter
    if self.current.events.on_enter then
        self.current.events.on_enter(self.entity, t.from and t.from.name)
    end

    -- Listeners
    for _, fn in ipairs(self.listeners) do
        pcall(fn, self.entity, self.current.name, t.from and t.from.name)
    end
end

function Machine:_check_transitions(ctx)
    if self.transition then
        -- Продолжаем переход
        self.transition.elapsed = self.transition.elapsed + 0 -- прибавим в update
        return
    end
    if not self.current then return end

    -- Сортируем переходы по приоритету (высокий первым)
    local candidates = {}

    for i, tr in ipairs(self.any_transitions) do
        table.insert(candidates, { tr = tr, idx = i })
    end
    for i, tr in ipairs(self.current.transitions) do
        table.insert(candidates, { tr = tr, idx = i + 1000 })
    end

    table.sort(candidates, function(a, b)
        return (a.tr.priority or 0) > (b.tr.priority or 0)
    end)

    for _, entry in ipairs(candidates) do
        local tr = entry.tr
        if tr.to ~= (self.current and self.current.name) then
            if self:_eval_when(tr.when, ctx) then
                self:_start_transition(tr.to, tr.duration_ticks or 0, tr)
                return
            end
        end
    end
end

function Machine:update(dtime)
    if self._paused then return end

    self.time_in_state = self.time_in_state + dtime
    local ctx = self:_build_context()

    -- Обновляем текущее состояние
    if self.current and self.current.events.on_update then
        self.current.events.on_update(self.entity, dtime, self.current)
    end

    -- Проверяем переходы
    self:_check_transitions(ctx)

    -- Прогресс перехода
    if self.transition then
        self.transition.elapsed = self.transition.elapsed + dtime
        if self.transition.elapsed >= self.transition.duration then
            self:_complete_transition()
        end
    end

    -- Сбрасываем триггеры каждый tick
    self.triggers = {}
    self._dirty = false
end

function Machine:force_state(name, duration_ticks)
    self:_start_transition(name, duration_ticks or 0)
end

function Machine:pause()  self._paused = true  end
function Machine:resume() self._paused = false end

function Machine:get_current_name()
    return self.current and self.current.name
end

function Machine:is_transitioning()
    return self.transition ~= nil
end

-- ============================================================
-- REGISTRY
-- ============================================================

local machines = {}  -- entity_key -> { [machine_name] = Machine }

local function key_of(e)
    local ok, id = pcall(function() return e:get_id() end)
    return (ok and id) and id or tostring(e)
end

function sm.register(entity, name)
    local k = key_of(entity)
    machines[k] = machines[k] or {}
    local m = Machine.new(entity, name)
    machines[k][name] = m
    return m
end

function sm.get(entity, name)
    local k = key_of(entity)
    return machines[k] and machines[k][name]
end

function sm.remove(entity, name)
    local k = key_of(entity)
    if not machines[k] then return end
    if name == "*" or name == nil then
        machines[k] = nil
    else
        machines[k][name] = nil
        if next(machines[k]) == nil then machines[k] = nil end
    end
end

function sm.update_all(dtime)
    for k, set in pairs(machines) do
        for name, m in pairs(set) do
            m:update(dtime)
        end
    end
end

-- ============================================================
-- CONDITION EVALUATOR (Molang-lite)
-- ============================================================

-- Простой evaluator для строк вида: "is_moving && !is_attacking && health < 10"
function sm.eval_condition(expr, ctx)
    if not expr or expr == "" then return false end

    -- Быстрый путь: одиночный параметр
    if expr:match("^[%w_]+$") then
        return ctx[expr] and true or false
    end

    -- Трансформируем в Lua
    local lua_expr = expr
        :gsub("&&", " and ")
        :gsub("||", " or ")
        :gsub("!=", "~=")

    -- Заменяем идентификаторы на ctx.x, кроме true/false/nil/and/or/not
    lua_expr = lua_expr:gsub("([%a_][%w_]*)", function(word)
        if word == "true" or word == "false" or word == "nil"
           or word == "and" or word == "or" or word == "not"
           or word == "math" then
            return word
        end
        return "ctx." .. word
    end)

    -- Заменяем ! на not (осторожно, чтобы не сломать ~=)
    lua_expr = lua_expr:gsub("([^~<>=!])!([^=])", "%1 not %2")
    lua_expr = lua_expr:gsub("^!", "not ")

    local fn = load("local ctx = ... ; return (" .. lua_expr .. ")")
    if not fn then return false end

    local ok, result = pcall(fn, ctx)
    if not ok then return false end
    return result and true or false
end

-- ============================================================
-- ПРЕДУСТАНОВЛЕННЫЕ ШАБЛОНЫ
-- ============================================================

-- Создать типичный locomotion machine (idle/walk/run/jump)
function sm.create_locomotion(entity, opts)
    opts = opts or {}
    local m = sm.register(entity, opts.name or "locomotion")
    m:add_state("idle", {
        layers = {
            { controller = "main", anim = opts.idle or "idle" },
        },
        transitions = {
            { to = "walk", when = function(ctx) return ctx.speed > 0.1 and ctx.speed < 4.0 end, duration_ticks = 5 },
            { to = "run",  when = function(ctx) return ctx.speed >= 4.0 end, duration_ticks = 3 },
        },
    })
    m:add_state("walk", {
        layers = {
            { controller = "main", anim = opts.walk or "walk" },
            { controller = "breath", anim = opts.breath or "breath", blend = "additive", weight = 0.3 },
        },
        transitions = {
            { to = "idle", when = function(ctx) return ctx.speed <= 0.1 end, duration_ticks = 5 },
            { to = "run",  when = function(ctx) return ctx.speed >= 4.0 end, duration_ticks = 3 },
            { to = "jump", when = function(ctx) return not ctx.on_ground end, duration_ticks = 2, priority = 10 },
        },
    })
    m:add_state("run", {
        layers = {
            { controller = "main", anim = opts.run or "run" },
            { controller = "breath", anim = opts.breath or "breath", blend = "additive", weight = 0.6 },
        },
        transitions = {
            { to = "walk", when = function(ctx) return ctx.speed < 4.0 and ctx.speed > 0.1 end, duration_ticks = 3 },
            { to = "idle", when = function(ctx) return ctx.speed <= 0.1 end, duration_ticks = 5 },
            { to = "jump", when = function(ctx) return not ctx.on_ground end, duration_ticks = 2, priority = 10 },
        },
    })
    m:add_state("jump", {
        layers = {
            { controller = "main", anim = opts.jump or "jump", loop = "hold_on_last_frame" },
        },
        transitions = {
            { to = "idle", when = function(ctx) return ctx.on_ground and ctx.speed <= 0.1 end, duration_ticks = 5 },
            { to = "walk", when = function(ctx) return ctx.on_ground and ctx.speed > 0.1 end, duration_ticks = 5 },
        },
    })
    m:set_initial("idle")
    m:force_state("idle", 0)
    return m
end

return sm