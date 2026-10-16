-- easing.lua
local easing = {}

local function make(name, fn)
    easing[name] = fn
end

-- Линейная
make("linear", function(t) return t end)

-- Quad
make("easeInQuad",  function(t) return t * t end)
make("easeOutQuad", function(t) return t * (2 - t) end)
make("easeInOutQuad", function(t)
    if t < 0.5 then return 2 * t * t end
    return -1 + (4 - 2 * t) * t
end)

-- Cubic
make("easeInCubic",  function(t) return t * t * t end)
make("easeOutCubic", function(t) local u = t - 1; return u * u * u + 1 end)
make("easeInOutCubic", function(t)
    if t < 0.5 then return 4 * t * t * t end
    local u = 2 * t - 2; return 0.5 * u * u * u + 1
end)

-- Quart, Quint, Sine, Expo, Circ, Back, Elastic, Bounce
make("easeInQuart",  function(t) return t ^ 4 end)
make("easeOutQuart", function(t) return 1 - (t - 1) ^ 4 end)
make("easeInQuint",  function(t) return t ^ 5 end)
make("easeOutQuint", function(t) return 1 + (t - 1) ^ 5 end)
make("easeInSine",   function(t) return 1 - math.cos(t * math.pi / 2) end)
make("easeOutSine",  function(t) return math.sin(t * math.pi / 2) end)
make("easeInOutSine",function(t) return -(math.cos(math.pi * t) - 1) / 2 end)
make("easeInExpo",   function(t) return t == 0 and 0 or 2 ^ (10 * t - 10) end)
make("easeOutExpo",  function(t) return t == 1 and 1 or 1 - 2 ^ (-10 * t) end)
make("easeInCirc",   function(t) return 1 - math.sqrt(1 - t * t) end)
make("easeOutCirc",  function(t) return math.sqrt(1 - (t - 1) ^ 2) end)
make("easeInBack",   function(t)
    local c1, c3 = 1.70158, 2.70158
    return c3 * t * t * t - c1 * t * t
end)
make("easeOutBack",  function(t)
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end)
make("easeInElastic", function(t)
    if t == 0 or t == 1 then return t end
    local c4 = 2 * math.pi / 3
    return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * c4)
end)
make("easeOutElastic", function(t)
    if t == 0 or t == 1 then return t end
    local c4 = 2 * math.pi / 3
    return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * c4) + 1
end)
make("easeOutBounce", function(t)
    local n1, d1 = 7.5625, 2.75
    if t < 1 / d1 then return n1 * t * t end
    if t < 2 / d1 then t = t - 1.5 / d1; return n1 * t * t + 0.75 end
    if t < 2.5 / d1 then t = t - 2.25 / d1; return n1 * t * t + 0.9375 end
    t = t - 2.625 / d1
    return n1 * t * t + 0.984375
end)

-- Catmull-Rom (GeckoLib использует его для smooth-переходов)
function easing.catmull_rom(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * (
        (2 * p1) +
        (-p0 + p2) * t +
        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
        (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    )
end

function easing.get(name)
    return easing[name] or easing.linear
end

return easing