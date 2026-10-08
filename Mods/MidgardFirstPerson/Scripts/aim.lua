-- Bind the game's observed TOM look/attack API to the center-camera target.
-- All traces and gameplay calls run from the frame loop, outside hook callbacks.
local aim = {}
local installed = false
local controls = require("controls")
local function valid(o)
    if not o then return false end
    local ok,v=pcall(function() return o:IsValid() end)
    return ok and v
end
local function structKind(value)
    local function numberField(key)
        local ok,result=pcall(function() return value[key] end)
        return ok and type(result)=="number"
    end
    if numberField("Pitch") and numberField("Yaw") then return "Rotator" end
    if numberField("X") and numberField("Y") then
        return numberField("Z") and "Vector" or "Vector2D"
    end
end
local function copyStruct(value, kind)
    if kind=="Vector" then return {X=value.X,Y=value.Y,Z=value.Z} end
    if kind=="Vector2D" then return {X=value.X,Y=value.Y} end
    if kind=="Rotator" then return {Pitch=value.Pitch,Yaw=value.Yaw,Roll=value.Roll} end
end
local function lookValue(current)
    if current.aimLookType=="Rotator" then return current.aimRotation end
    if current.aimLookType=="Vector2D" then return {X=current.aimPoint.X,Y=current.aimPoint.Y} end
    return current.aimPoint
end
function aim.prepare(current, log)
    current.aimSaved = {}
    current.newProjectiles = {}
    local function remember(object,name,kind)
        local value=object[name]
        local typeName=kind or structKind(value)
        log("Aim property binding: " .. name .. "=" .. tostring(typeName))
        if typeName=="Object" or typeName=="Vector" or typeName=="Vector2D" or typeName=="Rotator" or typeName=="number" or typeName=="boolean" then
            current.aimSaved[#current.aimSaved+1]={object=object,name=name,kind=typeName,
                value=copyStruct(value,typeName) or value}
        end
    end
    local ok,err=pcall(function()
        -- Confirmed in this installed game build: LookPoint is Rotator,
        -- attack AutoRotation is Rotator, delayed CurrentTarget is Vector.
        -- Avoid live class/parameter reflection in the experimental loader.
        current.aimLookType="Rotator"
        remember(current.controller,"LookAtRotation")
        remember(current.controller,"AutoTargetDirection")
        remember(current.pawn,"ProjectileTargetPosition")
        remember(current.pawn,"AimPitch","number")
        remember(current.pawn,"bAutoTargetForcedByCharacter","boolean")
        remember(current.pawn,"bAutoRotationIgnoreVelocity","boolean")
        remember(current.controller,"SelectedTarget","Object")
        remember(current.pawn,"ProjectileTargetActor","Object")
    end)
    current.aimAvailable = ok
    if not ok then log("Aim binding unavailable: " .. tostring(err)) end
end
function aim.restore(current)
    for _,entry in ipairs(current.aimSaved or {}) do
        if valid(entry.object) then
            local value=entry.value
            if entry.kind=="Object" and not valid(value) then value=nil end
            entry.object[entry.name]=value
        end
    end
end
local function apply(current)
    if not current.aimAvailable or not current.aimPoint or not current.aimRotation then return end
    for _,entry in ipairs(current.aimSaved) do
        if entry.kind=="Object" then
            -- An auto-selected actor would take precedence over the point.
            entry.object[entry.name]=nil
        elseif entry.name=="ProjectileTargetPosition" then
            entry.object[entry.name]=entry.kind=="Vector2D" and {X=current.aimPoint.X,Y=current.aimPoint.Y} or current.aimPoint
        elseif entry.name=="AimPitch" then
            entry.object[entry.name]=current.aimRotation.Pitch
        elseif entry.name=="bAutoTargetForcedByCharacter" then
            entry.object[entry.name]=false
        elseif entry.name=="bAutoRotationIgnoreVelocity" then
            entry.object[entry.name]=true
        elseif entry.kind=="Rotator" then
            entry.object[entry.name]={Pitch=current.aimRotation.Pitch,Yaw=current.aimRotation.Yaw,Roll=0}
        elseif entry.kind=="Vector" or entry.kind=="Vector2D" then
            local yaw=math.rad(current.aimRotation.Yaw)
            local direction={X=math.cos(yaw),Y=math.sin(yaw)}
            if entry.kind=="Vector" then direction.Z=0 end
            entry.object[entry.name]=direction
        end
    end
end
function aim.update(current, cameraPosition, config)
    if not current.aimAvailable then return end
    local target=controls.aimRay(cameraPosition,current.yaw,current.pitch,config.AimRayDistance)
    current.aimTraceFrame=(current.aimTraceFrame or -1)+1
    if valid(current.systemLibrary) and current.aimTraceFrame % (config.AimTraceIntervalFrames or 1)==0 then
        local hit,color={}, {R=0,G=0,B=0,A=1}
        local ignore={current.pawn,current.camera}
        if valid(current.pawn.CurrentWeaponActor) then ignore[#ignore+1]=current.pawn.CurrentWeaponActor end
        if current.systemLibrary:LineTraceSingle(current.pawn,cameraPosition,target,0,false,ignore,0,hit,true,color,color,0) then
            target={X=hit.ImpactPoint.X,Y=hit.ImpactPoint.Y,Z=hit.ImpactPoint.Z}
        end
        current.cachedAimPoint=target
    elseif current.cachedAimPoint then
        target=current.cachedAimPoint
    end
    local origin=current.pawn:K2_GetActorLocation()
    origin={X=origin.X,Y=origin.Y,Z=origin.Z+config.EyeHeight}
    current.aimPoint=target
    current.aimRotation=controls.rotationTo(origin,target,current.yaw)
    apply(current)
    local previous=current.lastLookRotation
    if not previous or math.abs(previous.Yaw-current.aimRotation.Yaw)>0.01 or math.abs(previous.Pitch-current.aimRotation.Pitch)>0.01 then
        current.controller:UpdateCharacterLookDirection(lookValue(current))
        current.lastLookRotation={Yaw=current.aimRotation.Yaw,Pitch=current.aimRotation.Pitch}
    end
end
-- Construction callbacks only queue objects. Velocity is changed on the game
-- thread after initialization, once, and only for the local pawn's projectile.
function aim.processProjectiles(current, config, log)
    if not current.captured or not config.VerticalProjectiles then current.newProjectiles={}; return end
    for index=#current.newProjectiles,1,-1 do
        local entry=current.newProjectiles[index]
        local finished=false
        local ok,err=pcall(function()
            local movement=entry.object
            if not valid(movement) then finished=true; return end
            local actor=movement:GetOwner()
            if not valid(actor) then return end
            local owner=actor
            local localShot=false
            for _=1,8 do
                if not valid(owner) then break end
                if owner==current.pawn then localShot=true; break end
                owner=owner:GetOwner()
            end
            if not localShot then
                localShot=actor:GetInstigator()==current.pawn
            end
            if not localShot then return end
            local v=movement.Velocity
            local speed=math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)
            if speed<1 then return end
            local rotation=controls.rotationTo(actor:K2_GetActorLocation(),entry.target,entry.yaw)
            -- Preserve the weapon's horizontal spread around its intended yaw.
            local spread=(math.deg(math.atan(v.Y,v.X))-entry.yaw+180)%360-180
            local direction=controls.aimRay({X=0,Y=0,Z=0},rotation.Yaw+spread,rotation.Pitch,speed)
            movement.bConstrainToPlane=false
            movement.bIsHomingProjectile=false
            movement.Velocity=direction
            current.verticalLaunches=(current.verticalLaunches or 0)+1
            if current.verticalLaunches==1 then log("Vertical launch applied to " .. actor:GetFullName()) end
            finished=true
        end)
        entry.age=entry.age+1
        if not ok then log("Vertical launch skipped: " .. tostring(err)); finished=true end
        if finished or entry.age>=4 then table.remove(current.newProjectiles,index) end
    end
end
function aim.install(getState, log)
    if installed then return end
    installed=true
    NotifyOnNewObject("/Script/Engine.ProjectileMovementComponent",function(object)
        local current=getState()
        if not current or not current.captured or not current.aimAvailable or not current.aimPoint or not require("config").VerticalProjectiles then return end
        if #current.newProjectiles>=64 then return end
        local target=current.aimPoint
        current.newProjectiles[#current.newProjectiles+1]={object=object,age=0,
            target={X=target.X,Y=target.Y,Z=target.Z},yaw=current.aimRotation.Yaw}
    end)
    local function hook(path, callback)
        local ok,err=pcall(function()
            RegisterHook(path,function(...)
                local current=getState()
                if not current or not current.captured or not current.aimAvailable or not current.aimPoint then return end
                local okCall,callError=pcall(callback,current,...)
                if not okCall then
                    current.aimAvailable=false
                    log("Aim hook disabled after error: " .. tostring(callError))
                end
            end)
        end)
        if not ok then log("Aim hook unavailable " .. path .. ": " .. tostring(err)) end
    end
    hook("/Script/TOM.TOMPlayerController:UpdateCharacterLookDirection",function(current,context,point)
        if context:get()==current.controller then
            point:set(lookValue(current))
            current.aimLookCalls=(current.aimLookCalls or 0)+1
        end
    end)
    local function rotationHook(method,index)
        local path="/Script/TOM.TOMCharacter:" .. method
        hook(path,function(current,context,...)
            if context:get()~=current.pawn then return end
            local parameter=select(index,...)
            parameter:set({Pitch=0,Yaw=current.aimRotation.Yaw,Roll=0})
            apply(current)
            current.aimAttackCalls=(current.aimAttackCalls or 0)+1
        end)
    end
    rotationHook("StackLightAttack",1)
    rotationHook("StackSpecialAttack",2)
    rotationHook("StackSpecificAttack",2)
    rotationHook("StackSpecificAttackById",2)
    -- ApplyAutoRotation is used by queued attacks as well as their animation.
    rotationHook("ApplyAutoRotation",1)
    hook("/Script/TOM.TOMCharacter:FireProjectile",function(current,context)
        if context:get()==current.pawn then
            apply(current)
            current.aimProjectileCalls=(current.aimProjectileCalls or 0)+1
        end
    end)
    hook("/Script/TOM.TOMCharacter:DelayedProjectile",function(current,context,target)
        if context:get()==current.pawn then
            target:set(current.aimPoint)
            current.aimProjectileCalls=(current.aimProjectileCalls or 0)+1
        end
    end)
    hook("/Game/TOMRuntime/Blueprints/BP_GamePlayerController.BP_GamePlayerController_C:UpdateAutoTarget",function(current,context)
        if context:get()==current.controller then apply(current) end
    end)
end
return aim
