-- Experimental first-person controls for the Windows Steam version.
-- Uses reflected input and character movement, without game-specific offsets.
local config = require("config")
local controls = require("controls")
local appearance = require("appearance")
local preferences = require("preferences")
local crosshair = require("crosshair")
local aim = require("aim")
local graphics = require("graphics")
local menu = require("menu")
local navigation = require("navigation")
local scriptDirectory = debug.getinfo(1, "S").source:match("^@(.+[\\/])") or "Mods/MidgardFirstPerson/Scripts/"
local settings = preferences.load(config, scriptDirectory .. "user_settings.ini")
local state = nil
local changingInputMode = false
local lateCameraAvailable = false
local menuUI, menuController, menuLibrary
local menuLock, menuOriginalCursor = false, false
local menuFrame = 0
local serviceMenu
local transitioning = false
local pendingInputRestore




local function log(message)
    print("[MidgardFirstPerson] " .. tostring(message) .. "\n")
end

local function valid(object)
    if not object then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result
end

local function name(object)
    if not valid(object) then return "<invalid>" end
    return object:GetFullName()
end

local function localController()
    -- Do not use FindFirstOf: it can select a remote co-op player's controller.
    for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
        if valid(controller) and controller:IsLocalController() then
            return controller
        end
    end
end

local function viewPose(pawn, facing)
    local location = pawn:K2_GetActorLocation()
    local rotation = pawn:K2_GetActorRotation()
    local cameraYaw = facing and facing.yaw or rotation.Yaw
    local position, viewRotation, anchor = controls.camera(location, cameraYaw,
        facing and facing.pitch or config.Pitch, config, settings.ThirdPerson)
    if facing and valid(facing.systemLibrary) then
        local hit = {}
        local color = {R=0,G=0,B=0,A=1}
        if facing.systemLibrary:SphereTraceSingle(pawn, anchor, position, config.CameraCollisionRadius,
            0, false, {pawn, facing.camera}, 0, hit, true, color, color, 0) then
            -- Location is the swept sphere's safe centre at the blocking hit.
            position = {X=hit.Location.X, Y=hit.Location.Y, Z=hit.Location.Z}
        end
    end
    return position, viewRotation
end

local function setInputMode(callback)
    changingInputMode = true
    local ok, err = pcall(callback)
    changingInputMode = false
    if not ok then error(err) end
end

local function updateAim(current, position)
    local ok, err = pcall(aim.update, current, position, config)
    if not ok then
        current.aimAvailable = false
        log("Aim update disabled after error: " .. tostring(err))
    end
    local rotation = current.aimAvailable and current.aimRotation or {Pitch=current.pitch,Yaw=current.yaw,Roll=0}
    current.controller:SetControlRotation(rotation)
end

local function releaseControls(current, restoreMode)
    if current.moveLock and valid(current.controller) then
        current.controller:SetIgnoreMoveInput(false)
        current.moveLock = false
    end
    current.captured = false
    if current.aimSaved then aim.restore(current) end
    if current.crosshair then current.crosshair:show(false) end
    if restoreMode and valid(current.controller) then
        current.controller.bShowMouseCursor = current.showCursor
        setInputMode(function()
            if current.showCursor then
                current.widgetLibrary:SetInputMode_GameAndUIEx(current.controller, nil, 0, false)
            else
                current.widgetLibrary:SetInputMode_GameOnly(current.controller)
            end
        end)
    end
end

local function captureControls(current)
    -- Do not bypass pre-existing locks from cutscenes, menus or disabled input.
    if current.controller:IsMoveInputIgnored() then
        log("Movement is locked by the game. Close the menu, then press middle mouse or F8.")
        return
    end
    current.controller:SetIgnoreMoveInput(true)
    current.moveLock = true
    current.controller.bShowMouseCursor = false
    setInputMode(function() current.widgetLibrary:SetInputMode_GameOnly(current.controller) end)
    current.captured = true
    if current.crosshair then current.crosshair:show(settings.Crosshair) end
end

-- The game rotates its map texture 45 degrees. In-game forward movement
-- confirmed the heading basis needs the opposite orientation: yaw - 45.
local function updateMinimap(current)
    local root=menuUI and menuUI.root
    if not valid(root) then return end
    if not current.minimap and current.minimapTriedRoot~=root then
        current.minimapTriedRoot=root
        local hudPath=root:GetFullName():match("^%S+ (.*)%.WidgetTree%.CanvasPanel_0$")
        if not hudPath then return end
        for _,widget in ipairs(FindAllOf("CanvasPanel") or {}) do
            if valid(widget) then
                local fullName=widget:GetFullName()
                if fullName:find(hudPath .. ".WidgetTree.BP_HUD_Compass",1,true) and
                    fullName:match("%.BP_WorldmapWidget%.WidgetTree%.ContentRoot$") then
                    local pivot=widget.RenderTransformPivot
                    current.minimap={widget=widget,angle=widget.RenderTransform.Angle,
                        pivot={X=pivot.X,Y=pivot.Y}}
                    widget:SetRenderTransformPivot({X=0.5,Y=0.5})
                    log("Camera-relative minimap attached.")
                    break
                end
            end
        end
    end
    local map=current.minimap
    if not map or not valid(map.widget) then return end
    local heading=navigation.heading(current.yaw)
    if not map.lastYaw or math.abs(current.yaw-map.lastYaw)>0.01 then
        map.widget:SetRenderTransformAngle(map.angle-heading)
        map.lastYaw=current.yaw
    end

end

local function restoreMinimap(previous)
    local map=previous.minimap
    previous.minimap=nil
    if not map then return end
    if valid(map.widget) then
        map.widget:SetRenderTransformAngle(map.angle)
        map.widget:SetRenderTransformPivot(map.pivot)
    end

end

local function stop(reason)
    local previous = state
    state = nil
    if not previous then return end
    local function restore(label, callback)
        local ok, err = pcall(callback)
        if not ok then log("Could not restore " .. label .. ": " .. tostring(err)) end
    end
    restore("minimap",function() restoreMinimap(previous) end)
    restore("navigation",function() if previous.navigation then previous.navigation:destroy() end end)
    restore("view target", function()
        if valid(previous.controller) and valid(previous.camera) and
            previous.controller:GetViewTarget() == previous.camera then
            local target = previous.viewTarget
            if not valid(target) then target = previous.pawn end
            if valid(target) then
                previous.controller:SetViewTargetWithBlend(target, 0, 0, 0, false)
            end
        end
    end)
    restore("head visibility", function() if previous.appearance then previous.appearance:restore() end end)
    restore("crosshair", function() if previous.crosshair then previous.crosshair:destroy() end end)
    restore("graphics", function() if previous.graphics then previous.graphics:restore() end end)
    restore("weapon aim", function() aim.restore(previous) end)
    restore("input controls", function() releaseControls(previous, not previous.gameChangedInputMode) end)
    restore("character rotation settings", function()
        if valid(previous.pawn) and previous.useControllerYaw ~= nil then
            previous.pawn.bUseControllerRotationYaw = previous.useControllerYaw
            previous.pawn.bUseControllerRotationPitch = previous.useControllerPitch
        end
        if valid(previous.movement) then
            previous.movement.bOrientRotationToMovement = previous.orientToMovement
            previous.movement.bUseControllerDesiredRotation = previous.desiredRotation
        end
        if valid(previous.controller) and previous.controlRotation then
            previous.controller:SetControlRotation(previous.controlRotation)
        end
    end)
    restore("temporary mouse mappings", function()
        if valid(previous.inputSettings) then
            for _, mapping in ipairs(previous.axisMappings or {}) do previous.inputSettings:RemoveAxisMapping(mapping, true) end
            if previous.mouseSmoothing ~= nil then previous.inputSettings.bEnableMouseSmoothing = previous.mouseSmoothing end
        end
    end)
    restore("temporary camera", function()
        if valid(previous.camera) then previous.camera:K2_DestroyActor() end
    end)
    log("Disabled: " .. (reason or "F6"))
end

local function start()
    local controller = localController()
    if not valid(controller) then log("Enter a world before pressing F6.") return end
    local pawn = controller.Pawn
    if not valid(pawn) then log("No possessed pawn; enter a world first.") return end
    if controller:IsMoveInputIgnored() then log("Close menus before enabling first person.") return end
    -- A generic actor with a CameraComponent also passes through the camera
    -- manager's BlueprintUpdateCamera event; CameraActor bypasses that event.
    local cameraClass = StaticFindObject("/Script/Engine.Actor")
    local componentClass = StaticFindObject("/Script/Engine.CameraComponent")
    local gameplay = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not valid(cameraClass) or not valid(componentClass) or not valid(gameplay) then
        error("Engine camera classes are unavailable; press F7 for diagnostics.")
    end
    local location = viewPose(pawn)
    local transform = {
        Translation = location,
        Rotation = {X = 0, Y = 0, Z = 0, W = 1},
        Scale3D = {X = 1, Y = 1, Z = 1},
    }
    -- AlwaysSpawn = 1. CameraActor is non-replicating by default.
    local camera, deferred
    if gameplay.BeginDeferredActorSpawnFromClass and gameplay.FinishSpawningActor then
        camera = gameplay:BeginDeferredActorSpawnFromClass(pawn, cameraClass, transform, 1, pawn)
        deferred = true
    else
        -- The experimental loader can fail Lua member lookup on this library.
        -- Its native world helper resolves the spawn functions internally.
        local world = pawn:GetWorld()
        if not valid(world) then error("Pawn has no valid world for camera spawning.") end
        camera = world:SpawnActor(cameraClass, location, {Pitch=config.Pitch,Yaw=pawn:K2_GetActorRotation().Yaw,Roll=0})
        log("Camera spawned through the native world helper.")
    end
    if not valid(camera) then error("CameraActor spawn failed.") end
    -- Record immediately so a later failure can clean up the deferred actor.
    state = {
        controller = controller, pawn = pawn, camera = camera,
        viewTarget = controller:GetViewTarget(),
        yaw = pawn:K2_GetActorRotation().Yaw, pitch = config.Pitch,
        showCursor = controller.bShowMouseCursor,
        controlRotation = nil,
    }
    if deferred then camera = gameplay:FinishSpawningActor(camera, transform) end
    if not valid(camera) then error("CameraActor finish-spawn failed.") end
    state.camera = camera
    state.systemLibrary = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local component = camera:AddComponentByClass(componentClass, false,
        {Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}, false)
    if not valid(component) then error("Spawned camera has no CameraComponent.") end
    state.cameraComponent = component
    component.bUsePawnControlRotation = false
    component:SetFieldOfView(settings.FOV)
    state.graphics=graphics.create(state,log)
    state.graphics:apply(settings.GraphicsPreset)
    local position, rotation = viewPose(pawn, state)
    camera:K2_SetActorLocationAndRotation(position, rotation, false, {}, true)
    state.appearance = appearance.create(pawn, config, log)
    state.appearance:discover()
    state.appearance:setHidden(config.HideHead and not settings.ThirdPerson)
    state.newMeshes = {}
    state.frame = 0
    if #state.appearance.bones == 0 then log("No head bone identified yet.") end
    controller:SetViewTargetWithBlend(camera, 0, 0, 0, false)
    state.widgetLibrary = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not valid(state.widgetLibrary) then error("WidgetBlueprintLibrary is unavailable.") end
    local savedRotation = controller:GetControlRotation()
    state.controlRotation = {Pitch=savedRotation.Pitch, Yaw=savedRotation.Yaw, Roll=savedRotation.Roll}
    state.useControllerYaw = pawn.bUseControllerRotationYaw
    state.useControllerPitch = pawn.bUseControllerRotationPitch
    state.movement = pawn.CharacterMovement
    if not valid(state.movement) then error("Pawn has no CharacterMovement component.") end
    state.orientToMovement = state.movement.bOrientRotationToMovement
    state.desiredRotation = state.movement.bUseControllerDesiredRotation
    pawn.bUseControllerRotationYaw = true
    pawn.bUseControllerRotationPitch = false
    state.movement.bOrientRotationToMovement = false
    state.movement.bUseControllerDesiredRotation = false
    state.inputKeys = {}
    for _, key in ipairs({"W", "A", "S", "D"}) do
        state.inputKeys[key] = {KeyName = FName(key)}
    end
    state.mouseDelta = {}
    state.inputSettings = StaticFindObject("/Script/Engine.Default__InputSettings")
    state.axisMappings = {}
    if valid(state.inputSettings) then
        state.mouseSmoothing = state.inputSettings.bEnableMouseSmoothing
        state.inputSettings.bEnableMouseSmoothing = false
        for _, axis in ipairs({"X", "Y"}) do
            local mapping = {AxisName=FName("MidgardLook" .. axis, EFindName.FNAME_Add),
                Key={KeyName=FName("Mouse" .. axis)}, Scale=1}
            table.insert(state.axisMappings, mapping)
            state.inputSettings:AddAxisMapping(mapping, true)
        end
    end
    aim.prepare(state, log)
    aim.install(function() return state end, log)
    captureControls(state)
    state.crosshair = crosshair.create(controller, log)
    state.crosshair:show(settings.Crosshair and state.captured)
    if state.captured then updateAim(state, position) end
    log("Enabled v0.8.1: " .. (settings.ThirdPerson and "third person" or "first person") ..
        ", FOV " .. settings.FOV .. ", sensitivity " .. settings.MouseSensitivity .. ". F9 switches view; middle mouse or F8 releases cursor.")
end

local function guarded(callback)
    if transitioning then return end
    local ok, err = pcall(callback)
    if not ok then
        log("Error: " .. tostring(err))
        stop("error; see UE4SS.log")
    end
end

-- Detach while the outgoing world is still usable. Set the gate first so
-- destroying our camera cannot re-enter camera, aim, menu or EndPlay work.
local function leaveWorld(reason)
    if transitioning then return end
    transitioning = true
    local hadCamera = state ~= nil
    stop(reason)
    navigation.reset()
    local ui, controller, library = menuUI, menuController, menuLibrary
    local locked, originalCursor = menuLock, menuOriginalCursor
    menuUI, menuController, menuLibrary = nil, nil, nil
    menuLock = false
    menuFrame = 0
    if valid(controller) then
        if locked then pcall(function() controller:SetIgnoreMoveInput(false) end) end
        if ui and ui.opened and not hadCamera then
            pcall(function()
                controller.bShowMouseCursor = originalCursor
                if originalCursor then library:SetInputMode_GameAndUIEx(controller,nil,0,false)
                else library:SetInputMode_GameOnly(controller) end
            end)
        end
    end
    if ui then pcall(ui.destroy,ui) end
    log("World transition cleanup: " .. reason)
end
local function abandonWorld(reason)
    -- EndPlay can arrive after subclass teardown. Never inspect or mutate
    -- outgoing UObjects here; the world owns their destruction.
    transitioning = true
    if state then
        pendingInputRestore = {inputSettings=state.inputSettings,
            axisMappings=state.axisMappings, mouseSmoothing=state.mouseSmoothing}
    end
    state, menuUI, menuController, menuLibrary = nil, nil, nil, nil
    navigation.reset()
    menuLock = false
    menuFrame = 0
    log("Stopped callbacks during teardown: " .. reason)
end
local function lifecycle(label, register, callback)
    local ok, err = pcall(function() register(callback) end)
    if not ok then log(label .. " unavailable: " .. tostring(err)) end
end
lifecycle("LoadMap pre-hook", RegisterLoadMapPreHook, function()
    leaveWorld("map travel / save and quit")
    -- nil preserves the game's return value and save/travel behavior.
end)
lifecycle("LoadMap post-hook", RegisterLoadMapPostHook, function()
    local pending = pendingInputRestore
    pendingInputRestore = nil
    -- InputSettings belongs to the engine, not the outgoing world.
    if pending and valid(pending.inputSettings) then
        pcall(function()
            for _,mapping in ipairs(pending.axisMappings or {}) do
                pending.inputSettings:RemoveAxisMapping(mapping,true)
            end
            if pending.mouseSmoothing~=nil then
                pending.inputSettings.bEnableMouseSmoothing=pending.mouseSmoothing
            end
        end)
    end
    transitioning = false
    menuFrame = 0
end)
lifecycle("QuitGame pre-hook", function(callback)
    RegisterHook("/Script/Engine.KismetSystemLibrary:QuitGame",callback)
end, function() leaveWorld("quit game") end)
lifecycle("EndPlay pre-hook", RegisterEndPlayPreHook, function(context)
    if transitioning then return end
    local actor = context:get()
    if (state and (actor == state.pawn or actor == state.controller or actor == state.camera))
        or (menuController and actor == menuController) then
        abandonWorld("local actor EndPlay")
    end
end)

local function diagnostic()
    -- Report cached Lua values only. No UObject scans, material enumeration,
    -- equipment changes or reflected calls on the F7 path.
    log("Diagnostic BEGIN")
    log("Enabled/captured: " .. tostring(state ~= nil) .. "/" .. tostring(state and state.captured or false))
    if state then
        log("Look yaw/pitch: " .. state.yaw .. "/" .. state.pitch)
        log("Mouse X/Y: " .. tostring(state.lastDeltaX or 0) .. "/" .. tostring(state.lastDeltaY or 0))
        log("Crosshair attached: " .. tostring(state.crosshair and state.crosshair.attached or false))
        log("Aim enabled/look/attack/projectile calls: " .. tostring(state.aimAvailable) .. "/" ..
            tostring(state.aimLookCalls or 0) .. "/" .. tostring(state.aimAttackCalls or 0) .. "/" .. tostring(state.aimProjectileCalls or 0))
        log("Vertical projectile launches: " .. tostring(state.verticalLaunches or 0))
    end
    log("FOV/sensitivity: " .. settings.FOV .. "/" .. settings.MouseSensitivity)
    log("Diagnostic END")
end
-- Final POV is calculated when Unreal updates its camera, using the pawn's
-- current position rather than the pre-world-tick camera actor position.
local okLateCamera, lateError = pcall(function()
    RegisterHook("/Script/Engine.PlayerCameraManager:BlueprintUpdateCamera",
        function(context, target, outputLocation, outputRotation, outputFOV)
            if transitioning or not state or context:get() ~= state.controller.PlayerCameraManager or target:get() ~= state.camera then return end
            local ok, location, rotation = pcall(viewPose, state.pawn, state)
            if not ok then log("Late camera error: " .. tostring(location)); return end
            outputLocation:set(location)
            outputRotation:set(rotation)
            outputFOV:set(settings.FOV)
            state.lateCameraFrames = (state.lateCameraFrames or 0) + 1
            return true
        end)
end)
lateCameraAvailable = okLateCamera
if not okLateCamera then log("Late camera hook unavailable; using component fallback: " .. tostring(lateError)) end

-- Mesh creation/equipment changes trigger a refresh, replacing continuous
-- world-wide scans.
local function queueMesh(object, kind)
    if state and #state.newMeshes < 512 then
        state.newMeshes[#state.newMeshes+1] = {object=object,kind=kind,ready=state.frame+8}
    end
end
NotifyOnNewObject("/Script/Engine.SkeletalMeshComponent", function(object) queueMesh(object,"skeletal") end)
NotifyOnNewObject("/Script/Engine.StaticMeshComponent", function(object) queueMesh(object,"static") end)

RegisterKeyBind(Key.F6, function()
    ExecuteInGameThread(function()
        guarded(function()
            if state then stop("F6") else start() end
        end)
    end)
end)

RegisterKeyBind(Key.F7, function()
    ExecuteInGameThread(function() guarded(diagnostic) end)
end)

local function toggleCursor()
    ExecuteInGameThread(function()
        guarded(function()
            if not state or (menuUI and menuUI.opened) then return end
            if state.captured then
                releaseControls(state, true)
                log("Cursor released. Middle mouse or F8 resumes mouse look and camera-relative movement.")
            else
                captureControls(state)
                log("Mouse look resumed.")
            end
        end)
    end)
end
RegisterKeyBind(Key.MIDDLE_MOUSE_BUTTON, toggleCursor)
RegisterKeyBind(Key.F8, toggleCursor)

local function saveSettings()
    local ok, err = settings:save()
    if not ok then log("Settings could not be saved: " .. tostring(err)) end
    if menuUI and menuUI.attached then menuUI:refresh(settings,state~=nil,graphics.names) end
    log(string.format("%s | FOV %.0f | sensitivity %.2f", settings.ThirdPerson and "Third person" or "First person",
        settings.FOV, settings.MouseSensitivity))
end

local function closeMenu(resume)
    if not menuUI or not menuUI.opened then return end
    menuUI:show(false)
    if valid(menuController) then
        if menuLock then menuController:SetIgnoreMoveInput(false) end
        menuLock=false
        if resume~=false and state and valid(state.controller) then
            captureControls(state)
        elseif resume~=false then
            menuController.bShowMouseCursor=menuOriginalCursor
            if menuOriginalCursor then menuLibrary:SetInputMode_GameAndUIEx(menuController,nil,0,false)
            else menuLibrary:SetInputMode_GameOnly(menuController) end
        end
    end
end
local function toggleMenu()
    if not menuUI or not menuUI.attached then log("Enter a world to open Mod settings."); return end
    if menuUI.opened then closeMenu(true); return end
    menuOriginalCursor=menuController.bShowMouseCursor
    if state and state.captured then releaseControls(state,false) end
    if not menuController:IsMoveInputIgnored() then
        menuController:SetIgnoreMoveInput(true); menuLock=true
    end
    menuController.bShowMouseCursor=true
    menuLibrary:SetInputMode_UIOnlyEx(menuController,nil,0)
    menuUI:refresh(settings,state~=nil,graphics.names)
    menuUI:show(true)
end
local function menuAction(action)

    if action=="first" or action=="third" or action=="original" then
        closeMenu(true)
        if action=="original" then stop("menu: original view"); return end
        settings.ThirdPerson=action=="third"
        if not state then start()
        else
            state.appearance:setHidden(config.HideHead and not settings.ThirdPerson)
            local position,rotation=viewPose(state.pawn,state)
            state.camera:K2_SetActorLocationAndRotation(position,rotation,false,{},true)
        end
    elseif action=="fovUp" or action=="fovDown" then
        settings.FOV=math.max(60,math.min(130,settings.FOV+(action=="fovUp" and 5 or -5)))
        if state then state.cameraComponent:SetFieldOfView(settings.FOV) end
    elseif action=="sensUp" or action=="sensDown" then
        settings.MouseSensitivity=math.max(0.05,math.min(2,settings.MouseSensitivity+(action=="sensUp" and 0.05 or -0.05)))
    elseif action=="crosshair" then
        settings.Crosshair=not settings.Crosshair
        if state and state.crosshair then state.crosshair:show(settings.Crosshair and state.captured) end
    elseif action=="graphics" then
        settings.GraphicsPreset=(settings.GraphicsPreset+1)%4
        if state and state.graphics then state.graphics:apply(settings.GraphicsPreset) end
    elseif action=="invert" then settings.InvertMouseY=not settings.InvertMouseY end
    saveSettings()
end
serviceMenu=function()
    menuFrame=menuFrame+1
    if menuUI and (not valid(menuController) or not valid(menuUI.root) or menuController.Pawn~=menuUI.pawn) then
        -- The host may already be tearing down; do not call widget methods.
        menuUI=nil; menuController=nil; menuLibrary=nil; menuLock=false
    end
    if not menuUI and (menuFrame==1 or menuFrame%120==0) then
        local controller=state and state.controller or localController()
        if valid(controller) and valid(controller.Pawn) then
            menuController=controller
            menuLibrary=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
            local candidate=menu.create(controller,{action=menuAction,close=function() closeMenu(true) end,toggle=toggleMenu},log)
            if candidate.attached then
                menuUI=candidate; menuUI.pawn=controller.Pawn



                log("Mod settings ready: click the HUD button with the cursor visible, or press Insert.")
            end
        end
    end
    if menuUI then menuUI:tick() end
end
RegisterKeyBind(0x2D,function() ExecuteInGameThread(function() guarded(toggleMenu) end) end)
RegisterKeyBind(0x1B,function() ExecuteInGameThread(function() guarded(function() if menuUI and menuUI.opened then closeMenu(true) end end) end) end)

RegisterKeyBind(Key.F11, function()
    ExecuteInGameThread(function()
        guarded(function()
            settings.GraphicsPreset=(settings.GraphicsPreset+1)%4
            if state and state.graphics then state.graphics:apply(settings.GraphicsPreset) end
            saveSettings()
            log("Selected graphics: " .. graphics.names[settings.GraphicsPreset])
        end)
    end)
end)

RegisterKeyBind(Key.F10, function()
    ExecuteInGameThread(function()
        guarded(function()
            settings.Crosshair = not settings.Crosshair
            if state then
                if not state.crosshair or not state.crosshair.attached then
                    state.crosshair = crosshair.create(state.controller, log)
                end
                state.crosshair:show(settings.Crosshair and state.captured)
            end
            saveSettings()
            log("Crosshair " .. (settings.Crosshair and "enabled" or "disabled") .. ".")
        end)
    end)
end)

RegisterKeyBind(Key.F9, function()
    ExecuteInGameThread(function()
        guarded(function()
            settings.ThirdPerson = not settings.ThirdPerson
            if state then
                state.appearance:setHidden(config.HideHead and not settings.ThirdPerson)
                local position, rotation = viewPose(state.pawn, state)
                state.camera:K2_SetActorLocationAndRotation(position, rotation, false, {}, true)
            end
            saveSettings()
        end)
    end)
end)

local function adjustSetting(key, field, step, minimum, maximum)
    RegisterKeyBind(key, function()
        ExecuteInGameThread(function()
            guarded(function()
                settings[field] = math.max(minimum, math.min(maximum, settings[field] + step))
                if state and field == "FOV" then state.cameraComponent:SetFieldOfView(settings.FOV) end
                saveSettings()
            end)
        end)
    end)
end
-- Windows virtual key codes: Page Up/Down and Home/End.
adjustSetting(0x21, "FOV", 5, 60, 130)
adjustSetting(0x22, "FOV", -5, 60, 130)
adjustSetting(0x24, "MouseSensitivity", 0.05, 0.05, 2)
adjustSetting(0x23, "MouseSensitivity", -0.05, 0.05, 2)

-- Once per engine frame, rather than a timer that can repeat/miss mouse deltas.
LoopInGameThreadAfterFrames(1, function()
        if transitioning then return false end
        guarded(function()
            local menuOk,menuError=pcall(serviceMenu)
            if not menuOk then
                log("Mod menu disabled after error: " .. tostring(menuError))
                pcall(closeMenu,true)
                if menuUI then pcall(menuUI.destroy,menuUI); menuUI=nil end
                menuFrame=1 -- wait before retrying without stopping camera
            end
            if not state then return end
            local current = state
            current.frame = current.frame + 1
            if not valid(current.controller) or not valid(current.pawn) or not valid(current.camera) then
                stop("world or actor changed") return
            end
            if current.controller.Pawn ~= current.pawn then
                stop("pawn changed; press F6 again after respawn") return
            end
            -- Let menus, cutscenes and other game camera transitions take over.
            if current.controller:GetViewTarget() ~= current.camera then
                stop("game changed its camera") return
            end
            -- Observe menu cursor changes after the game's own input-mode call
            -- finishes; avoid reflected input-mode calls inside their hooks.
            if current.captured and current.controller.bShowMouseCursor then
                current.gameChangedInputMode = true
                stop("game released its mouse cursor; F6 resumes after closing the menu") return
            end
            if current.captured then
                -- This loader references the first argument for every scalar
                -- out parameter. Share the table so both loader behaviors work.
                local delta = current.mouseDelta
                current.controller:GetInputMouseDelta(delta, delta)
                current.lastDeltaX, current.lastDeltaY = delta.DeltaX or 0, delta.DeltaY or 0
                current.yaw, current.pitch = controls.look(current.yaw, current.pitch,
                    current.lastDeltaX, current.lastDeltaY,
                    settings.MouseSensitivity, settings.InvertMouseY, config.MaxPitch)
                local function down(key)
                    return current.controller:IsInputKeyDown(current.inputKeys[key]) and 1 or 0
                end
                local direction, moving = controls.direction(current.yaw, down("W")-down("S"), down("D")-down("A"))
                -- Drain residual native input once per frame. The controller's
                -- move lock blocks normal AddMovementInput; only ours is forced.
                current.pawn:ConsumeMovementInputVector()
                if moving then current.pawn:AddMovementInput(direction, 1, true) end
            end
            -- Allow construction to finish, then check a bounded number of
            -- individual objects. Distant streaming never triggers a world scan.
            for _=1,16 do
                local entry=current.newMeshes[1]
                if not entry or entry.ready>current.frame then break end
                table.remove(current.newMeshes,1)
                local ok,err=pcall(current.appearance.consider,current.appearance,entry.object,entry.kind)
                if not ok then log("New mesh check skipped: " .. tostring(err)) end
            end
            if not current.minimapFailed then
                local ok,err=pcall(updateMinimap,current)
                if not ok then
                    current.minimapFailed=true
                    pcall(restoreMinimap,current)
                    log("Minimap disabled after error: " .. tostring(err))
                end
            end
            if not current.navigationFailed and menuUI and valid(menuUI.root) then
                local ok,err=pcall(function()
                    if current.navigation and current.navigation.root~=menuUI.root then
                        current.navigation:destroy(); current.navigation=nil
                    end
                    if not current.navigation then
                        current.navigation=navigation.create(menuUI.root)
                        log("Scrolling compass and waypoint navigation attached.")
                    end
                    if not current.mapPoints or current.frame%15==0 then
                        local pinsOk,points=pcall(navigation.mapPoints,current.navigation.map)
                        if pinsOk then
                            current.mapPoints=points
                            if current.mapPointCount~=#points then
                                current.mapPointCount=#points
                                log("Map pins on compass: " .. #points)
                            end
                        else
                            current.mapPoints={}
                            if not current.pinErrorReported then
                                current.pinErrorReported=true
                                log("Map pin read skipped: " .. tostring(points))
                            end
                        end
                    end
                    current.navigation:update(current.yaw,current.pawn:K2_GetActorLocation(),current.mapPoints)
                end)
                if not ok then
                    current.navigationFailed=true
                    if current.navigation then pcall(current.navigation.destroy,current.navigation) end
                    log("Navigation disabled after error: " .. tostring(err))
                end
            end
            aim.processProjectiles(current, config, log)
            local position, rotation = viewPose(current.pawn, current)
            if current.captured then updateAim(current, position) end
            if not lateCameraAvailable or not current.lateCameraFrames then
                current.camera:K2_SetActorLocationAndRotation(position, rotation, false, {}, true)
            end
        end)
    return false
end)

navigation.install(function() return not transitioning and menuUI and menuUI.root end,log)

log("Loaded v0.8.1. Late camera=" .. tostring(lateCameraAvailable) .. "; world-exit cleanup enabled.")
log("Settings file: " .. scriptDirectory .. "user_settings.ini")
