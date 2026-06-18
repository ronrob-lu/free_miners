free_miners = free_miners or {}

-- Make the NPC look at a position
function free_miners.look_at(entity, target_pos)
    local pos = entity.object:get_pos()
    if not pos then return end
    local dx = target_pos.x - pos.x
    local dz = target_pos.z - pos.z
    if dx == 0 and dz == 0 then return end
    local yaw = math.atan2(-dx, dz)
    entity.object:set_yaw(yaw)
end

-- Fly toward a target position in 3D.
-- Slows down near the target to prevent overshoot.
-- Disables gravity during flight.
-- Returns "arrived" if within arrive_dist, otherwise "moving".
function free_miners.fly_toward(entity, target_pos, arrive_dist)
    local pos = entity.object:get_pos()
    if not pos then return "arrived" end

    local dist = vector.distance(pos, target_pos)

    if dist < arrive_dist then
        entity.object:set_velocity({x = 0, y = 0, z = 0})
        return "arrived"
    end

    free_miners.look_at(entity, target_pos)

    -- Slow down when close to prevent overshoot
    local speed = 4.0
    if dist < 3.0 then
        speed = 2.0
    end

    local dir = vector.direction(pos, target_pos)
    entity.object:set_velocity(vector.multiply(dir, speed))
    entity.object:set_acceleration({x = 0, y = 0, z = 0}) -- disable gravity while flying

    return "moving"
end
