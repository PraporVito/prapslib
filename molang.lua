-- molang.lua
local molang = {}

-- Регистрируемые queries
local queries = {}

-- Встроенные queries (аналог Minecraft Bedrock)
function molang.register_defaults()
    molang.register_query("anim_time", function(ctx) return ctx.anim_time or 0 end)
    molang.register_query("life_time", function(ctx) return ctx.life_time or 0 end)
    molang.register_query("is_moving", function(ctx) return ctx.is_moving and 1 or 0 end)
    molang.register_query("is_on_ground", function(ctx) return ctx.on_ground and 1 or 0 end)
    molang.register_query("health", function(ctx) return ctx.health or 20 end)
    molang.register_query("yaw", function(ctx) return ctx.yaw or 0 end)
    molang.register_query("pitch", function(ctx) return ctx.pitch or 0 end)
end

function molang.register_query(name, fn)
    queries[name] = fn
end

-- Трансформация Molang-выражения в Lua
local function transform(expr)
    -- query.foo → queries["foo"](ctx)
    expr = expr:gsub("query%.([%w_]+)", function(name)
        return string.format('(queries["%s"] and queries["%s"](__ctx) or 0)', name, name)
    end)
    -- math.foo → math.foo
    expr = expr:gsub("math%.", "math.")
    -- Операторы: && → and, || → or, ! → not
    expr = expr:gsub("&&", " and "):gsub("||", " or ")
    -- Тернарный оператор: a ? b : c → (a and b or c)
    -- Простой парсер для одного уровня
    local ternary = expr:match("(.+)%s*%?%s*(.-)%s*:%s*(.+)")
    if ternary then
        -- Не идеально, но работает для простых случаев
        expr = "(" .. transform(ternary) .. ")"
    end
    return expr
end

function molang.eval(expr, ctx)
    if type(expr) == "number" then return expr end
    if type(expr) ~= "string" then return 0 end

    -- Если это просто число — вернуть
    local num = tonumber(expr)
    if num then return num end

    -- Трансформируем
    local lua_expr = transform(expr)

    -- Загружаем
    local fn, err = load("return " .. lua_expr, "molang", "t", {
        queries = queries,
        __ctx = ctx or {},
        math = math,
        pi = math.pi,
    })

    if not fn then
        minetest.log("warning", "[PrapsLib/Molang] Parse error: " .. tostring(err) .. " in '" .. expr .. "'")
        return 0
    end

    local ok, result = pcall(fn)
    if not ok then return 0 end
    return tonumber(result) or 0
end

-- Вычислить вектор из Molang-строк
function molang.eval_vec3(vec, ctx)
    if type(vec) ~= "table" then return {0, 0, 0} end
    return {
        molang.eval(vec[1], ctx),
        molang.eval(vec[2], ctx),
        molang.eval(vec[3], ctx),
    }
end

molang.register_defaults()
return molang