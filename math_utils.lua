-- math_utils.lua
local math_utils = {}

local math  = math
local sqrt  = math.sqrt
local sin   = math.sin
local cos   = math.cos
local acos  = math.acos
local asin  = math.asin
local atan2 = math.atan2
local abs   = math.abs
local floor = math.floor
local ceil  = math.ceil
local pi    = math.pi
local rad   = math.rad
local deg   = math.deg
local min   = math.min
local max   = math.max
local huge  = math.huge

local EPS = 1e-6
math_utils.EPS = EPS
math_utils.PI  = pi
math_utils.TAU = pi * 2

-- ============================================================
-- БАЗОВОЕ
-- ============================================================

function math_utils.clamp(v, lo, hi)
    if v ~= v then return lo end -- NaN guard
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function math_utils.clamp01(v) return math_utils.clamp(v, 0, 1) end

function math_utils.sign(v)
    if v > 0 then return 1 elseif v < 0 then return -1 else return 0 end
end

function math_utils.approach(current, target, delta)
    if current < target then
        return min(current + delta, target)
    else
        return max(current - delta, target)
    end
end

function math_utils.approach_angle(current, target, delta)
    local diff = math_utils.shortest_angle(current, target)
    if abs(diff) <= delta then return target end
    return current + math_utils.sign(diff) * delta
end

-- Кратчайший угол от a к b (-pi..pi)
function math_utils.shortest_angle(a, b)
    local d = (b - a) % (2 * pi)
    if d > pi then d = d - 2 * pi end
    return d
end

-- Wrap в диапазон
function math_utils.wrap(v, lo, hi)
    local range = hi - lo
    if range <= 0 then return lo end
    return v - floor((v - lo) / range) * range
end

function math_utils.wrap_angle(a)
    return math_utils.wrap(a, -pi, pi)
end

function math_utils.remap(v, in_lo, in_hi, out_lo, out_hi, clamped)
    if abs(in_hi - in_lo) < EPS then return out_lo end
    local t = (v - in_lo) / (in_hi - in_lo)
    if clamped then t = math_utils.clamp01(t) end
    return out_lo + (out_hi - out_lo) * t
end

-- ============================================================
-- ИНТЕРПОЛЯЦИИ
-- ============================================================

function math_utils.lerp(a, b, t)  return a + (b - a) * t end
function math_utils.lerp_unclamped(a, b, t) return a + (b - a) * t end

function math_utils.lerp_angle(a, b, t)
    return a + math_utils.shortest_angle(a, b) * t
end

function math_utils.lerp_vec3(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    }
end

function math_utils.inverse_lerp(a, b, v)
    if abs(b - a) < EPS then return 0 end
    return (v - a) / (b - a)
end

-- Smoothstep (Hermite)
function math_utils.smoothstep(t)
    t = math_utils.clamp01(t)
    return t * t * (3 - 2 * t)
end

function math_utils.smootherstep(t)
    t = math_utils.clamp01(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

-- ============================================================
-- BEZIER
-- ============================================================

-- Классический cubic bezier по 4 точкам (одномерно)
function math_utils.cubic_bezier_1d(p0, p1, p2, p3, t)
    local mt = 1 - t
    local mt2 = mt * mt
    local t2 = t * t
    return mt2 * mt * p0 + 3 * mt2 * t * p1 + 3 * mt * t2 * p2 + t2 * t * p3
end

-- Cubic bezier по 4 vec3 (для позиций/скейлов)
function math_utils.cubic_bezier(p0, p1, p2, p3, t)
    local mt = 1 - t
    local mt2 = mt * mt
    local t2 = t * t
    local a = mt2 * mt
    local b = 3 * mt2 * t
    local c = 3 * mt * t2
    local d = t2 * t
    return {
        a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
        a * p0[2] + b * p1[2] + c * p2[2] + d * p3[2],
        a * p0[3] + b * p1[3] + c * p2[3] + d * p3[3],
    }
end

-- Per-axis cubic bezier: каждая ось имеет свои контрольные точки (как в Blockbench Molang)
-- p0, p3 = точки на кадрах; p1, p2 = по одной паре контрольных точек НА ОСЬ
function math_utils.cubic_bezier_per_axis(p0, p3, p1_x, p2_x, p1_y, p2_y, p1_z, p2_z, t)
    return {
        math_utils.cubic_bezier_1d(p0[1], p1_x, p2_x, p3[1], t),
        math_utils.cubic_bezier_1d(p0[2], p1_y, p2_y, p3[2], t),
        math_utils.cubic_bezier_1d(p0[3], p1_z, p2_z, p3[3], t),
    }
end

-- Catmull-Rom (GeckoLib default для smooth)
function math_utils.catmull_rom_1d(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * (
        (2 * p1) +
        (-p0 + p2) * t +
        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
        (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    )
end

function math_utils.catmull_rom(p0, p1, p2, p3, t)
    return {
        math_utils.catmull_rom_1d(p0[1], p1[1], p2[1], p3[1], t),
        math_utils.catmull_rom_1d(p0[2], p1[2], p2[2], p3[2], t),
        math_utils.catmull_rom_1d(p0[3], p1[3], p2[3], p3[3], t),
    }
end

-- ============================================================
-- ВЕКТОРА
-- ============================================================

function math_utils.v3_add(a, b) return {a[1]+b[1], a[2]+b[2], a[3]+b[3]} end
function math_utils.v3_sub(a, b) return {a[1]-b[1], a[2]-b[2], a[3]-b[3]} end
function math_utils.v3_mul(a, s) return {a[1]*s, a[2]*s, a[3]*s} end
function math_utils.v3_neg(a)    return {-a[1], -a[2], -a[3]} end

function math_utils.v3_dot(a, b) return a[1]*b[1] + a[2]*b[2] + a[3]*b[3] end

function math_utils.v3_cross(a, b)
    return {
        a[2]*b[3] - a[3]*b[2],
        a[3]*b[1] - a[1]*b[3],
        a[1]*b[2] - a[2]*b[1],
    }
end

function math_utils.v3_len(a)
    return sqrt(a[1]*a[1] + a[2]*a[2] + a[3]*a[3])
end

function math_utils.v3_len_sq(a)
    return a[1]*a[1] + a[2]*a[2] + a[3]*a[3]
end

function math_utils.v3_dist(a, b)
    local dx, dy, dz = a[1]-b[1], a[2]-b[2], a[3]-b[3]
    return sqrt(dx*dx + dy*dy + dz*dz)
end

function math_utils.v3_normalize(a)
    local l = math_utils.v3_len(a)
    if l < EPS then return {0, 0, 0} end
    return {a[1]/l, a[2]/l, a[3]/l}
end

function math_utils.v3_lerp(a, b, t)
    return {a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t, a[3]+(b[3]-a[3])*t}
end

-- ============================================================
-- QUATERNIONS
-- ============================================================

local Q = {}

function Q.new(w, x, y, z) return {w=w, x=x, y=y, z=z} end
function Q.identity() return {w=1, x=0, y=0, z=0} end

function Q.mul(a, b)
    return {
        w = a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z,
        x = a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
        y = a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
        z = a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w,
    }
end

function Q.conjugate(q)
    return {w=q.w, x=-q.x, y=-q.y, z=-q.z}
end

function Q.normalize(q)
    local l = sqrt(q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z)
    if l < EPS then return Q.identity() end
    return {w=q.w/l, x=q.x/l, y=q.y/l, z=q.z/l}
end

function Q.dot(a, b)
    return a.w*b.w + a.x*b.x + a.y*b.y + a.z*b.z
end

function Q.from_euler(x, y, z)
    local cx, sx = cos(x*0.5), sin(x*0.5)
    local cy, sy = cos(y*0.5), sin(y*0.5)
    local cz, sz = cos(z*0.5), sin(z*0.5)
    return {
        w = cx*cy*cz + sx*sy*sz,
        x = sx*cy*cz - cx*sy*sz,
        y = cx*sy*cz + sx*cy*sz,
        z = cx*cy*sz - sx*sy*cz,
    }
end

-- Возвращает roll(X), pitch(Y), yaw(Z)
function Q.to_euler(q)
    local sinr_cosp = 2 * (q.w * q.x + q.y * q.z)
    local cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y)
    local roll = atan2(sinr_cosp, cosr_cosp)

    local sinp = 2 * (q.w * q.y - q.z * q.x)
    local pitch
    if abs(sinp) >= 1 then
        pitch = math_utils.sign(sinp) * (pi / 2)
    else
        pitch = asin(sinp)
    end

    local siny_cosp = 2 * (q.w * q.z + q.x * q.y)
    local cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z)
    local yaw = atan2(siny_cosp, cosy_cosp)

    return roll, pitch, yaw
end

-- Короткий slerp с anti-flip
function Q.slerp(q1, q2, t)
    local dot = Q.dot(q1, q2)
    local q2a = q2
    if dot < 0 then
        dot = -dot
        q2a = {w=-q2.w, x=-q2.x, y=-q2.y, z=-q2.z}
    end

    if dot > 0.9995 then
        -- Линейная интерполяция + нормализация (быстро и точно для малых углов)
        return Q.normalize({
            w = q1.w + t*(q2a.w - q1.w),
            x = q1.x + t*(q2a.x - q1.x),
            y = q1.y + t*(q2a.y - q1.y),
            z = q1.z + t*(q2a.z - q1.z),
        })
    end

    local theta_0 = acos(math_utils.clamp(dot, -1, 1))
    local sin_theta_0 = sin(theta_0)
    local theta = theta_0 * t
    local s1 = cos(theta) - dot * sin(theta) / sin_theta_0
    local s2 = sin(theta) / sin_theta_0

    return {
        w = s1*q1.w + s2*q2a.w,
        x = s1*q1.x + s2*q2a.x,
        y = s1*q1.y + s2*q2a.y,
        z = s1*q1.z + s2*q2a.z,
    }
end

-- Публичные обёртки (сохраняем старый API)
function math_utils.quat_from_euler(x, y, z) return Q.from_euler(x, y, z) end
function math_utils.quat_to_euler(q) local r,p,y = Q.to_euler(q); return r, p, y end
function math_utils.quat_slerp(q1, q2, t) return Q.slerp(q1, q2, t) end
function math_utils.quat_normalize(q) return Q.normalize(q) end
function math_utils.quat_mul(a, b) return Q.mul(a, b) end
function math_utils.quat_dot(a, b) return Q.dot(a, b) end
math_utils.quat = Q

-- ============================================================
-- УГЛЫ / EULER-ВЕКТОР
-- ============================================================

function math_utils.slerp_euler(e1, e2, t)
    local q1 = Q.from_euler(e1[1], e1[2], e1[3])
    local q2 = Q.from_euler(e2[1], e2[2], e2[3])
    local q = Q.slerp(q1, q2, t)
    local rx, ry, rz = Q.to_euler(q)
    return {rx, ry, rz}
end

function math_utils.deg_to_rad_vec3(v)
    if type(v) ~= "table" then return {0, 0, 0} end
    return {
        rad(tonumber(v[1]) or 0),
        rad(tonumber(v[2]) or 0),
        rad(tonumber(v[3]) or 0),
    }
end

function math_utils.rad_to_deg_vec3(v)
    return {deg(v[1] or 0), deg(v[2] or 0), deg(v[3] or 0)}
end

function math_utils.normalize_euler(e)
    return {
        math_utils.wrap_angle(e[1] or 0),
        math_utils.wrap_angle(e[2] or 0),
        math_utils.wrap_angle(e[3] or 0),
    }
end

-- ============================================================
-- PROCEDURAL / NOISE
-- ============================================================

-- ✅ ВСТАВЬ ЭТО
local function hash1(n)
    local x = math.sin(n * 12.9898) * 43758.5453
    return 2 * (x - floor(x)) - 1   -- -1..1
end

function math_utils.noise1(x)
    local xi = floor(x)
    local xf = x - xi
    local a = hash1(xi)
    local b = hash1(xi + 1)
    local t = math_utils.smoothstep(xf)
    return a + (b - a) * t
end

-- Fractal Brownian Motion
function math_utils.fbm1(x, octaves, lacunarity, gain)
    octaves   = octaves   or 3
    lacunarity= lacunarity or 2.0
    gain      = gain       or 0.5
    local sum, amp, freq, norm = 0, 1, 1, 0
    for _ = 1, octaves do
        sum  = sum + math_utils.noise1(x * freq) * amp
        norm = norm + amp
        freq = freq * lacunarity
        amp  = amp * gain
    end
    return sum / (norm > 0 and norm or 1)
end

-- ============================================================
-- RAYCAST / GEOMETRY HELPERS
-- ============================================================

-- Точка пересечения луча (origin, dir) с плоскостью y = plane_y
function math_utils.ray_plane_y(origin, dir, plane_y)
    if abs(dir[2]) < EPS then return nil end
    local t = (plane_y - origin[2]) / dir[2]
    if t < 0 then return nil end
    return {origin[1] + dir[1]*t, origin[2] + dir[2]*t, origin[3] + dir[3]*t}
end

-- Ближайшая точка на отрезке ab к точке p
function math_utils.closest_point_on_segment(p, a, b)
    local ab = math_utils.v3_sub(b, a)
    local ap = math_utils.v3_sub(p, a)
    local ab_len_sq = math_utils.v3_len_sq(ab)
    if ab_len_sq < EPS then return {a[1], a[2], a[3]} end
    local t = math_utils.clamp01(math_utils.v3_dot(ap, ab) / ab_len_sq)
    return {a[1] + ab[1]*t, a[2] + ab[2]*t, a[3] + ab[3]*t}
end

-- ============================================================
-- LOOK-AT (процедурный поворот головы)
-- ============================================================

-- Возвращает euler {pitch, yaw, 0} для взгляда из from в to с clamp по амплитуде
function math_utils.look_at_euler(from, to, max_pitch, max_yaw)
    local dx = to[1] - from[1]
    local dy = to[2] - from[2]
    local dz = to[3] - from[3]
    local horiz = sqrt(dx*dx + dz*dz)
    local pitch = -atan2(dy, horiz)
    local yaw   = atan2(dx, dz)

    if max_pitch then pitch = math_utils.clamp(pitch, -max_pitch, max_pitch) end
    if max_yaw   then yaw   = math_utils.clamp(yaw,   -max_yaw,   max_yaw)   end

    return {pitch, yaw, 0}
end

-- ============================================================
-- STOCHASTIC
-- ============================================================

function math_utils.random_range(a, b)
    if a == b then return a end
    return a + math.random() * (b - a)
end

function math_utils.random_sign()
    return math.random() < 0.5 and -1 or 1
end

-- ============================================================
-- STEP (мгновенное значение)
-- ============================================================

function math_utils.step_value(v) return v end

return math_utils