-- ik.lua
local ik = {}

-- Решение 2-костного IK: найти углы для бедра и колена, чтобы достичь цели
-- a = длина бедра, b = длина голени
-- target = {x, y, z} относительно корня бедра
function ik.solve_2bone(a, b, target)
    local dist = math.sqrt(target.x^2 + target.y^2 + target.z^2)
    -- Ограничиваем дистанцию
    dist = math.min(dist, a + b - 0.001)
    dist = math.max(dist, math.abs(a - b) + 0.001)

    -- Угол колена (закон косинусов)
    local cos_knee = (a^2 + b^2 - dist^2) / (2 * a * b)
    cos_knee = math.max(-1, math.min(1, cos_knee))
    local knee_angle = math.pi - math.acos(cos_knee)

    -- Угол бедра
    local cos_hip = (a^2 + dist^2 - b^2) / (2 * a * dist)
    cos_hip = math.max(-1, math.min(1, cos_hip))
    local hip_angle = math.acos(cos_hip)

    -- Угол до цели в вертикальной плоскости
    local target_angle = math.atan2(target.y, target.z)

    -- Итоговые вращения (в радианах)
    local hip_rot = target_angle + hip_angle
    local knee_rot = -knee_angle

    return {
        hip = {x = 0, y = 0, z = hip_rot},
        knee = {x = 0, y = 0, z = knee_rot},
    }
end

-- FABRIK для цепочек любой длины (упрощённый, 3 итерации)
function ik.fabrik(chain, target, iterations)
    iterations = iterations or 3
    local n = #chain
    if n < 2 then return end

    for _ = 1, iterations do
        -- Forward: двигаем конец к цели
        chain[n].pos = {x = target.x, y = target.y, z = target.z}
        for i = n - 1, 1, -1 do
            local dir = {
                x = chain[i+1].pos.x - chain[i].pos.x,
                y = chain[i+1].pos.y - chain[i].pos.y,
                z = chain[i+1].pos.z - chain[i].pos.z,
            }
            local len = math.sqrt(dir.x^2 + dir.y^2 + dir.z^2)
            if len > 0.0001 then
                dir.x, dir.y, dir.z = dir.x/len, dir.y/len, dir.z/len
            end
            chain[i].pos = {
                x = chain[i+1].pos.x - dir.x * chain[i].length,
                y = chain[i+1].pos.y - dir.y * chain[i].length,
                z = chain[i+1].pos.z - dir.z * chain[i].length,
            }
        end

        -- Backward: возвращаем корень на место
        chain[1].pos = {x = chain[1].origin.x, y = chain[1].origin.y, z = chain[1].origin.z}
        for i = 2, n do
            local dir = {
                x = chain[i].pos.x - chain[i-1].pos.x,
                y = chain[i].pos.y - chain[i-1].pos.y,
                z = chain[i].pos.z - chain[i-1].pos.z,
            }
            local len = math.sqrt(dir.x^2 + dir.y^2 + dir.z^2)
            if len > 0.0001 then
                dir.x, dir.y, dir.z = dir.x/len, dir.y/len, dir.z/len
            end
            chain[i].pos = {
                x = chain[i-1].pos.x + dir.x * chain[i].length,
                y = chain[i-1].pos.y + dir.y * chain[i].length,
                z = chain[i-1].pos.z + dir.z * chain[i].length,
            }
        end
    end

    -- Конвертируем позиции в углы
    local angles = {}
    for i = 1, n - 1 do
        local dir = {
            x = chain[i+1].pos.x - chain[i].pos.x,
            y = chain[i+1].pos.y - chain[i].pos.y,
            z = chain[i+1].pos.z - chain[i].pos.z,
        }
        angles[i] = {
            x = math.atan2(dir.y, math.sqrt(dir.x^2 + dir.z^2)),
            y = math.atan2(dir.x, dir.z),
            z = 0,
        }
    end
    return angles
end

return ik