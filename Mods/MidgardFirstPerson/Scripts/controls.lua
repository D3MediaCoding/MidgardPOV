-- Pure direction math shared by camera placement and movement.
local controls = {}
function controls.nativeMovement(pawn, viewTarget)
    local movement=pawn.CharacterMovement
    -- MOVE_None and MOVE_Custom mean native gameplay owns the character.
    if movement and movement:IsValid() and (movement.MovementMode==0 or movement.MovementMode==6) then return true end
    local function vessel(actor)
        if not actor or not actor:IsValid() then return false end
        local name=actor:GetFullName():lower()
        return name:find('boat',1,true) or name:find('ship',1,true) or name:find('rudder',1,true)
    end
    if vessel(viewTarget) then return true end
    local ok,parent=pcall(function() return pawn:GetAttachParentActor() end)
    return ok and not not vessel(parent)
end
function controls.look(yaw, pitch, dx, dy, sensitivity, invert, limit)
    yaw = (yaw + dx * sensitivity + 180) % 360 - 180
    -- Unreal's MouseY is positive when the mouse moves upward.
    pitch = pitch + dy * sensitivity * (invert and -1 or 1)
    return yaw, math.max(-limit, math.min(limit, pitch))
end
function controls.direction(yaw, forward, right)
    local radians = math.rad(yaw)
    local x = math.cos(radians) * forward - math.sin(radians) * right
    local y = math.sin(radians) * forward + math.cos(radians) * right
    local length = math.sqrt(x*x + y*y)
    if length > 1 then x, y = x / length, y / length end
    return {X=x, Y=y, Z=0}, length > 0
end
function controls.aimRay(position, yaw, pitch, distance)
    local y, p = math.rad(yaw), math.rad(pitch)
    return {X=position.X+math.cos(y)*math.cos(p)*distance,
        Y=position.Y+math.sin(y)*math.cos(p)*distance,
        Z=position.Z+math.sin(p)*distance}
end
function controls.rotationTo(origin, target, fallbackYaw)
    local x,y,z = target.X-origin.X, target.Y-origin.Y, target.Z-origin.Z
    local horizontal = math.sqrt(x*x+y*y)
    if horizontal < 0.000001 and math.abs(z) < 0.000001 then
        return {Pitch=0,Yaw=fallbackYaw,Roll=0}
    end
    return {Pitch=math.deg(math.atan(z,horizontal)),Yaw=math.deg(math.atan(y,x)),Roll=0}
end
function controls.camera(location, yaw, pitch, config, thirdPerson)
    local y, p = math.rad(yaw), math.rad(pitch)
    local anchor = {X=location.X, Y=location.Y, Z=location.Z + config.EyeHeight}
    local position
    if thirdPerson then
        anchor.Z = anchor.Z + config.ThirdPersonHeight
        position = {
            X=anchor.X - math.cos(y)*math.cos(p)*config.ThirdPersonDistance - math.sin(y)*config.ThirdPersonShoulderOffset,
            Y=anchor.Y - math.sin(y)*math.cos(p)*config.ThirdPersonDistance + math.cos(y)*config.ThirdPersonShoulderOffset,
            Z=anchor.Z - math.sin(p)*config.ThirdPersonDistance,
        }
    else
        position = {X=anchor.X+math.cos(y)*config.ForwardOffset,
            Y=anchor.Y+math.sin(y)*config.ForwardOffset, Z=anchor.Z}
    end
    return position, {Pitch=pitch,Yaw=yaw,Roll=0}, anchor
end
return controls
