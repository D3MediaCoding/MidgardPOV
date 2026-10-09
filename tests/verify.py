"""Behavior tests using Unreal API stand-ins; not an in-game compatibility test."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "test-runtime"))
from lupa import LuaRuntime

lua = LuaRuntime()
lua.execute(r'''
keys, logs, work, hooks = {}, {}, {}, {}
Key = {MIDDLE_MOUSE_BUTTON=4, F6=117, F7=118, F8=119, F9=120, F10=121, F11=122}
EFindName = {FNAME_Add=1}
PropertyTypes = {StructProperty=1}
notifications={}
function NotifyOnNewObject(path,fn) notifications[path]=fn end
local names={__eq=function(a,b) return a.name==b.name end}
function FName(s) return setmetatable({name=s,ToString=function(self) return self.name end},names) end
function FText(s) return s end
local files={}
function io.open(path, mode)
    if mode=='r' then
        if not files[path] then return nil end
        return {lines=function() return files[path]:gmatch('[^\n]+') end,close=function() return true end}
    end
    return {write=function(self,text) files[path]=text; return self end,close=function() return true end}
end
function RegisterHook(path, callback) hooks[path]=callback end
function RegisterLoadMapPreHook(callback) hooks.loadMapPre=callback end
function RegisterLoadMapPostHook(callback) hooks.loadMapPost=callback end
function RegisterEndPlayPreHook(callback) hooks.endPlayPre=callback end
function print(s) table.insert(logs, s) end
function RegisterKeyBind(k, fn) keys[k] = fn end
function ExecuteInGameThread(fn) table.insert(work, fn) end
function LoopInGameThreadAfterFrames(frames, fn) assert(frames==1); loop = fn end
function drain()
    local pending=work; work={}
    for _,fn in ipairs(pending) do fn() end
end
function press(key)
    local cursorKey=key==Key.F8 or key==Key.MIDDLE_MOUSE_BUTTON
    if cursorKey then for _=1,15 do tick() end end
    keys[key](); drain()
    if cursorKey then tick() end
end
function render()
    local fn=hooks['/Script/Engine.PlayerCameraManager:BlueprintUpdateCamera']
    if not fn then return end
    local function output() return {set=function(self,v) self.value=v end} end
    local location,rotation,fov=output(),output(),output()
    local handled=fn({get=function() return pc.PlayerCameraManager end},
        {get=function() return pc.target end},location,rotation,fov)
    if handled then pc.target.position=location.value; pc.target.rotation=rotation.value; pc.target.component.fov=fov.value end
end
function tick() loop(); drain(); render() end
function object(label)
    local o={alive=true,label=label}
    function o:IsValid() return self.alive end
    function o:GetFullName() return self.label end
    function o:GetOwner() return nil end
    function o:Reflection() error('Runtime class reflection must not be used by the mod') end
    return o
end
mesh=object('Mesh'); mesh.bOwnerNoSee=false; mesh.headHidden=false
function mesh:SetOwnerNoSee(v) self.bOwnerNoSee=v end
pawn=object('LocalPawn'); pawn.Mesh=mesh
mesh.SkeletalMesh=object('BodyAsset')
function mesh:GetNumMaterials() return 0 end
function mesh:GetOwner() return pawn end
function mesh:GetNumBones() return 3 end
function mesh:GetBoneIndex(bone) return bone.name=='head' and 1 or -1 end
function mesh:GetBoneName(index) return FName(({[0]='root',[1]='head',[2]='hand_r'})[index]) end
function mesh:IsBoneHiddenByName() return self.headHidden end
function mesh:HideBoneByName(bone,physics) assert(bone.name=='head' and physics==0); self.headHidden=true end
function mesh:UnHideBoneByName(bone) assert(bone.name=='head'); self.headHidden=false end
function mesh:GetSocketBoneName(socket) return socket end
helmet=object('Helmet'); helmet.bHiddenInGame=false
weapon=object('Weapon'); weapon.bHiddenInGame=false
function helmet:GetOwner() return pawn end
function weapon:GetOwner() return pawn end
function helmet:GetAttachParent() return mesh end
function weapon:GetAttachParent() return mesh end
function helmet:GetAttachSocketName() return FName('head') end
function weapon:GetAttachSocketName() return FName('hand_r') end
function helmet:SetHiddenInGame(hidden) self.bHiddenInGame=hidden end
function weapon:SetHiddenInGame(hidden) self.bHiddenInGame=hidden end
pawn.bUseControllerRotationYaw=false
pawn.bUseControllerRotationPitch=false
movement=object('CharacterMovement')
movement.bOrientRotationToMovement=true; movement.bUseControllerDesiredRotation=false
pawn.CharacterMovement=movement
function pawn:ConsumeMovementInputVector() self.move=nil end
function pawn:AddMovementInput(direction,scale,force)
    assert(force==true and scale==1 and pc.moveLocks==1)
    self.move=direction
end
function pawn:K2_GetActorLocation() return {X=self.testX or 100,Y=200,Z=300} end
function pawn:K2_GetActorRotation() return {Pitch=0,Yaw=90,Roll=0} end
original=object('OriginalCamera')
pc=object('LocalController'); pc.Pawn=pawn; pc.target=original
pc.PlayerCameraManager=object('CameraManager')
pc.bShowMouseCursor=true; pc.moveLocks=0; pc.down={}; pc.dx=0; pc.dy=0
pc.rotation={Pitch=12,Yaw=23,Roll=0}
pc.LookAtRotation={Pitch=0,Yaw=12,Roll=0}; pc.AutoTargetDirection={X=1,Y=0}
pawn.ProjectileTargetPosition={X=11,Y=22,Z=33}; pawn.AimPitch=7; pawn.bAutoTargetForcedByCharacter=true
pawn.bAutoRotationIgnoreVelocity=false
originalAimActor=object('OriginalAimTarget')
pc.SelectedTarget=originalAimActor; pawn.ProjectileTargetActor=originalAimActor
function pc:UpdateCharacterLookDirection(point)
    local fn=hooks['/Script/TOM.TOMPlayerController:UpdateCharacterLookDirection']
    local output={value=point,set=function(self,v) self.value=v end}
    if fn then fn({get=function() return self end},output) end
    self.lookRotation=output.value
end
function pc:SetIgnoreMoveInput(ignored) self.moveLocks=self.moveLocks+(ignored and 1 or -1) end
function pc:IsMoveInputIgnored() return self.moveLocks>0 end
function pc:GetControlRotation() return self.rotation end
function pc:SetControlRotation(rotation) self.rotation=rotation end
-- UE4SS 3.0.1-1161 references argument one for both scalar output parameters.
function pc:GetInputMouseDelta(x,y)
    x.DeltaX=self.dx
    if self.separateMouseOutputs then y.DeltaY=self.dy else x.DeltaY=self.dy end
end
function pc:IsInputKeyDown(key) return self.down[key.KeyName.name] or false end
function pc:IsLocalController() return true end
function pc:GetViewTarget() return self.target end
function pc:SetViewTargetWithBlend(v) self.target=v end
remote=object('RemoteController')
function remote:IsLocalController() return false end
function remote:SetViewTargetWithBlend() error('remote player modified') end
gameplay=object('GameplayStatics')
system=object('KismetSystemLibrary')
cvars={['r.Tonemapper.Sharpen']=-1,['r.MaxAnisotropy']=8}
function system:GetConsoleVariableFloatValue(key) return cvars[key] end
function system:GetConsoleVariableIntValue(key) return cvars[key] end
function system:ExecuteConsoleCommand(context,command,controller)
    assert(context==pawn and controller==pc)
    local key,value=command:match('^(%S+) (.+)$')
    cvars[key]=assert(tonumber(value))
end
function system:LineTraceSingle(context,start,finish,channel,complex,ignore,draw,hit)
    traceCalls=(traceCalls or 0)+1
    assert(context==pawn and channel==0 and draw==0 and ignore[1]==pawn)
    if aimHit then hit.ImpactPoint=aimHit; return true end
    return false
end
inputSettings=object('InputSettings'); inputSettings.mappings=0; inputSettings.bEnableMouseSmoothing=true
function inputSettings:AddAxisMapping(mapping,rebuild) assert(rebuild); self.mappings=self.mappings+1 end
function inputSettings:RemoveAxisMapping(mapping,rebuild) assert(rebuild); self.mappings=self.mappings-1 end
function system:SphereTraceSingle(context,start,finish,radius,channel,complex,ignored,draw,hit)
    assert(context==pawn and ignored[1]==pawn and radius==12)
    if blocked then hit.Location={X=1,Y=2,Z=3}; return true end
    return false
end
widget=object('WidgetLibrary')
widget.modeCalls=0
function widget:SetInputMode_GameOnly(controller)
    self.modeCalls=self.modeCalls+1
    local fn=hooks['/Script/UMG.WidgetBlueprintLibrary:SetInputMode_GameOnly']
    if fn then fn(nil,{get=function() return controller end}) end
    self.mode='game'
end
function widget:SetInputMode_GameAndUIEx(controller)
    self.modeCalls=self.modeCalls+1
    local fn=hooks['/Script/UMG.WidgetBlueprintLibrary:SetInputMode_GameAndUIEx']
    if fn then fn(nil,{get=function() return controller end}) end
    self.mode='ui'
    controller.bShowMouseCursor=true
end
function widget:SetInputMode_UIOnlyEx(controller) self.mode='uiOnly' end
spawned={}
function gameplay:BeginDeferredActorSpawnFromClass(context, class, transform, collision, owner)
    assert(context==pawn and owner==pawn and collision==1)
    local camera=object('PrototypeCamera')
    local component=object('CameraComponent')
    component.PostProcessSettings={}
    component.PostProcessBlendWeight=0
    camera.component=component
    function component:SetFieldOfView(v) self.fov=v end
    function camera:GetComponentByClass() return component end
    function camera:AddComponentByClass() return component end
    function camera:K2_SetActorLocationAndRotation(position,rotation)
        self.position=position; self.rotation=rotation
    end
    function camera:K2_DestroyActor() self.alive=false end
    table.insert(spawned,camera)
    return camera
end
function gameplay:FinishSpawningActor(camera) if failSpawn then error('test failure') end return camera end
world=object('World'); nativeSpawns=0
function pawn:GetWorld() return world end
local originalBegin=gameplay.BeginDeferredActorSpawnFromClass
function world:SpawnActor(class,location,rotation)
    nativeSpawns=nativeSpawns+1
    return originalBegin(gameplay,pawn,class,{Translation=location},1,pawn)
end
scans=0
canvas=object('CanvasPanel /Test.BP_HUD_C_123.WidgetTree.CanvasPanel_0'); canvas.children={}
mapCanvas=object('CanvasPanel /Test.BP_HUD_C_123.WidgetTree.BP_HUD_Compass_127.WidgetTree.BP_WorldmapWidget.WidgetTree.ContentRoot')
mapCanvas.RenderTransform={Angle=7}; mapCanvas.RenderTransformPivot={X=0.2,Y=0.3}
function mapCanvas:SetRenderTransformAngle(angle) self.RenderTransform.Angle=angle; self.writes=(self.writes or 0)+1 end
function mapCanvas:SetRenderTransformPivot(pivot) self.RenderTransformPivot=pivot end
unrelatedMap=object('CanvasPanel /Test.BP_MainTab_Map.WidgetTree.BP_WorldmapWidget.WidgetTree.ContentRoot')
function unrelatedMap:SetRenderTransformAngle() error('Full map must not rotate') end
tree=object('WidgetTree'); viewportWidget=object('BP_HUD_C /Game/LocalViewportWidget')
tree.RootWidget=canvas
function canvas:IsA(class) return class.label=='/Script/UMG.CanvasPanel' end
function viewportWidget:GetVisibility() return 3 end
candidateCanvas=object('NestedHUDCanvas')
function candidateCanvas:GetOuter() return tree end
function canvas:GetVisibility() return 3 end
function canvas:GetCachedGeometry() error('Opaque geometry must not be queried for crosshair attachment') end
slate=object('SlateBlueprintLibrary')
function slate:GetLocalSize(geometry) return geometry end
function canvas:GetOuter() return tree end
function tree:GetOuter() return viewportWidget end
function tree:IsA(class) return class.label=='/Script/UMG.WidgetTree' end
function viewportWidget:IsA(class) return class.label=='/Script/UMG.UserWidget' end
function viewportWidget:GetOwningPlayer() return pc end
function viewportWidget:IsInViewport() return true end
function canvas:AddChildToCanvas(image)
    image.parent=self; table.insert(self.children,image)
    local slot=object('CanvasSlot'); image.slot=slot
    function slot:SetAnchors(v) self.anchors=v end
    function slot:SetAlignment(v) self.alignment=v end
    function slot:SetAutoSize(v) self.autoSize=v end
    function slot:SetPosition(v) self.position=v end
    function slot:SetSize(v) self.size=v end
    function slot:SetZOrder(v) self.z=v end
    return slot
end
mapTree=object('MinimapWidgetTree')
miniRoot=object('MinimapRoot'); miniRoot.children={}; miniRoot.AddChildToCanvas=canvas.AddChildToCanvas
mapTree.RootWidget=miniRoot
function mapCanvas:GetOuter() return mapTree end
nativeMap=object('BP_WorldmapWidget_C /Test.BP_HUD_C_123.WidgetTree.BP_HUD_Compass_127.WidgetTree.BP_WorldmapWidget')
foreignMap=object('BP_WorldmapWidget_C /Test.BP_HUD_C_999.WidgetTree.BP_HUD_Compass_127.WidgetTree.BP_WorldmapWidget')
pinClass=object('Class /Script/TOM.TestPingWidget')
local pinProperty=object('StructProperty /Script/TOM.TestPingWidget:Info')
function pinProperty:IsA(kind) return kind==PropertyTypes.StructProperty end
function pinProperty:GetFName() return FName('Info') end
function pinProperty:GetStruct()
    local schema=object('ScriptStruct /Script/TOM.PingMapInfo')
    function schema:ForEachProperty(callback)
        local world=object('StructProperty /Script/TOM.PingMapInfo:WorldPos')
        function world:IsA(kind) return kind==PropertyTypes.StructProperty end
        function world:GetFName() return FName('WorldPos') end
        function world:GetStruct() return object('ScriptStruct /Script/CoreUObject.Vector') end
        callback(world)
    end
    return schema
end
function pinClass:ForEachProperty(callback) pinMetadataReads=(pinMetadataReads or 0)+1; callback(pinProperty) end
function pinClass:GetSuperStruct() return nil end
nativePin=object('NativeMapPin'); nativePin.Info={ID=1,WorldPos={X=100,Y=1200,Z=300}}
function nativePin:GetClass() return pinClass end
nativeMap.PingWidgets={{PingWidget=nativePin}} -- placed before the mod camera is enabled
function StaticConstructObject(class,outer)
    assert(outer==tree or outer==mapTree)
    local image=object(class.label)
    if class.label=='/Script/UMG.CanvasPanel' then
        image.children={}; image.AddChildToCanvas=canvas.AddChildToCanvas
    elseif class.label=='/Script/UMG.TextBlock' then
        image.Font={Size=18}
        function image:SetText(text) self.text=text end
        function image:SetFont(font) self.Font=font end
        function image:SetJustification(value) self.justification=value end
    elseif class.label=='/Script/UMG.Button' then
        function image:SetBackgroundColor(color) self.background=color end
        function image:SetContent(text) self.content=text; text.parent=self end
        function image:IsPressed() return self.pressed or false end
    else assert(class.label=='/Script/UMG.Image') end
    function image:SetBrushFromTexture(texture) self.texture=texture end
    function image:SetBrush(brush) self.brush=brush; self.brushWrites=(self.brushWrites or 0)+1 end
    function image:SetColorAndOpacity(color) self.color=color end
    function image:SetVisibility(v) self.visibility=v end
    function image:SetClipping(v) self.clipping=v end
    function image:SetRenderTransformAngle(v) self.angle=v end
    function image:RemoveFromParent() self.parent=nil end
    return image
end
nativeMenu=object('BP_Menu_Container_C /Engine/Transient.LocalMenu')
nativeMenu.visibility=1; nativeMenu.opacity=1
function nativeMenu:GetOwningPlayer() return pc end
function nativeMenu:GetVisibility() return self.visibility end
function nativeMenu:GetRenderOpacity() return self.opacity end
remoteMenu=object('BP_Menu_Container_C /Engine/Transient.RemoteMenu')
function remoteMenu:GetOwningPlayer() return remote end
function remoteMenu:GetVisibility() error('Remote menu must not be polled') end
function FindAllOf(class)
    scans=scans+1
    if class=='PlayerController' then return {remote,pc} end
    if class=='SkeletalMeshComponent' then return {mesh} end
    if class=='StaticMeshComponent' then return {helmet,weapon} end
    if class=='CanvasPanel' then return {candidateCanvas,unrelatedMap,mapCanvas} end
    if class=='BP_WorldmapWidget_C' then return {foreignMap,nativeMap} end
    if class=='BP_Menu_Container_C' then return {remoteMenu,nativeMenu} end
    return {}
end
function StaticFindObject(path)
    if path=='/Script/Engine.Default__GameplayStatics' then return gameplay end
    if path=='/Script/UMG.Default__WidgetBlueprintLibrary' then return widget end
    if path=='/Script/Engine.Default__KismetSystemLibrary' then return system end
    if path=='/Script/Engine.Default__InputSettings' then return inputSettings end
    if path=='/Script/UMG.Default__SlateBlueprintLibrary' then return slate end
    return object(path)
end
''')
config = (root / "Mods/MidgardFirstPerson/Scripts/config.lua").read_text(encoding="utf-8")
lua.globals().package.preload["config"] = lua.eval("function() " + config + " end")
lua.globals().package.preload["controls"] = lua.eval("function() " + (root / "Mods/MidgardFirstPerson/Scripts/controls.lua").read_text(encoding="utf-8") + " end")
for module in ("appearance", "preferences", "crosshair", "aim", "graphics", "menu", "navigation"):
    lua.globals().package.preload[module] = lua.eval("function() " + (root / f"Mods/MidgardFirstPerson/Scripts/{module}.lua").read_text(encoding="utf-8") + " end")
lua.execute((root / "Mods/MidgardFirstPerson/Scripts/main.lua").read_text(encoding="utf-8"))
lua.execute(r'''
require('config').AimTraceIntervalFrames=1 -- immediate trace scenarios below
local nav=require('navigation')
assert(nav.relative(359,1)==2 and nav.relative(1,359)==-2)
assert(nav.direction(359)=='N' and nav.direction(90)=='E')
local bearing,distance=nav.destination({X=0,Y=0,Z=0},{X=0,Y=300,Z=400})
assert(bearing==45 and distance==5) -- Unreal centimetres, including elevation
assert(nav.relative(nav.heading(90),bearing)==0) -- forward lies at compass center
assert(pc.target==original and #spawned==0) -- starts disabled
local beginSpawn=gameplay.BeginDeferredActorSpawnFromClass
gameplay.BeginDeferredActorSpawnFromClass=nil -- reproduce observed loader failure
press(Key.F6)
assert(nativeSpawns==1)
gameplay.BeginDeferredActorSpawnFromClass=beginSpawn
assert(pc.target==spawned[1] and mesh.headHidden and not mesh.bOwnerNoSee)
assert(#canvas.children==10)
local center=canvas.children[2]
assert(center.slot.anchors.Minimum.X==0.5 and center.slot.anchors.Maximum.Y==0.5)
assert(center.slot.position.X==-1 and center.slot.position.Y==-1 and center.slot.size.X==2)
assert(center.visibility==3)
press(Key.F10); assert(center.visibility==1)
press(Key.F10); assert(center.visibility==3)
local scansBeforeStatus=scans
press(Key.F7); assert(scans==scansBeforeStatus)
assert(helmet.bHiddenInGame and not weapon.bHiddenInGame)
assert(pc.target.component.fov==105)
local pp=pc.target.component.PostProcessSettings
assert(pp.ColorSaturation.X==1.23 and pp.bOverride_ColorSaturation)
assert(pp.MotionBlurAmount==0 and pc.target.component.PostProcessBlendWeight==1)
assert(cvars['r.Tonemapper.Sharpen']==0.35 and cvars['r.MaxAnisotropy']==16)
press(Key.F11) -- vivid -> original
assert(pc.target.component.PostProcessBlendWeight==0)
assert(cvars['r.Tonemapper.Sharpen']==-1 and cvars['r.MaxAnisotropy']==8)
press(Key.F11); assert(pp.ColorSaturation.X==1.12)
press(Key.F11); assert(pp.ColorContrast.X==1.13)
press(Key.F11); assert(pp.ColorSaturation.X==1.23)
press(0x21); assert(pc.target.component.fov==110)
press(0x22); assert(pc.target.component.fov==105)
press(0x24); press(0x23)
press(Key.F9)
assert(not mesh.headHidden and not helmet.bHiddenInGame and not weapon.bHiddenInGame)
assert(math.abs(pc.target.position.X-55)<0.001 and math.abs(pc.target.position.Y+80)<0.001)
-- A hit on the third-person camera's center ray must be aimed at from the
-- character, rather than using a parallel ray or the strafe direction.
aimHit={X=55,Y=2000,Z=385}; pc.down.D=true; tick()
local expectedYaw=math.deg(math.atan(1800,-45))
assert(math.abs(pc.rotation.Yaw-expectedYaw)<0.001)
assert(pc.target.rotation.Yaw==90)
assert(math.abs(pawn.move.X+1)<0.001 and math.abs(pawn.move.Y)<0.001)
assert(math.abs(pc.lookRotation.Yaw-expectedYaw)<0.001 and pawn.ProjectileTargetPosition.Y==2000)
assert(pc.lookRotation.X==nil and pc.AutoTargetDirection.Z==nil)
assert(pc.SelectedTarget==nil and pawn.ProjectileTargetActor==nil)
assert(pawn.bAutoRotationIgnoreVelocity)
local function parameter(value) return {value=value,set=function(self,v) self.value=v end} end
local shotRotation=parameter({Pitch=0,Yaw=-90,Roll=0})
local attack=hooks['/Script/TOM.TOMCharacter:StackLightAttack']
attack({get=function() return pawn end},shotRotation,parameter(1))
assert(math.abs(shotRotation.value.Yaw-expectedYaw)<0.001 and shotRotation.value.Pitch==0)
local remoteRotation=parameter({Pitch=3,Yaw=-90,Roll=0})
attack({get=function() return remote end},remoteRotation,parameter(1))
assert(remoteRotation.value.Yaw==-90 and remoteRotation.value.Pitch==3)
local shotTarget=parameter({X=-100,Y=-100,Z=0})
hooks['/Script/TOM.TOMCharacter:DelayedProjectile']({get=function() return pawn end},shotTarget)
assert(shotTarget.value.X==55 and shotTarget.value.Y==2000)
pc.LookAtRotation={Pitch=0,Yaw=-45,Roll=0}
hooks['/Game/TOMRuntime/Blueprints/BP_GamePlayerController.BP_GamePlayerController_C:UpdateAutoTarget']({get=function() return pc end})
assert(math.abs(pc.LookAtRotation.Yaw-expectedYaw)<0.001)
aimHit=nil; pc.down={}
blocked=true; tick(); assert(pc.target.position.X==1 and pc.target.position.Z==3)
blocked=false; press(Key.F9); assert(mesh.headHidden and helmet.bHiddenInGame)
assert(math.abs(spawned[1].position.X-100)<0.001)
assert(spawned[1].position.Y==236 and spawned[1].position.Z==365)
assert(inputSettings.mappings==2)
assert(not inputSettings.bEnableMouseSmoothing)
local scansBefore=scans
for _=1,120 do tick() end
assert(scans==scansBefore) -- no periodic global discovery scans
-- Streaming hundreds of unrelated components must never cause global scans.
for _=1,200 do
    notifications['/Script/Engine.SkeletalMeshComponent'](object('DistantMesh'))
    notifications['/Script/Engine.StaticMeshComponent'](object('DistantScenery'))
end
for _=1,45 do tick() end
assert(scans==scansBefore)
-- Local equipment discovered incrementally still receives head hiding.
local newHead=object('NewHelmetMesh')
for k,v in pairs(mesh) do if type(v)=='function' then newHead[k]=v end end
newHead.headHidden=false
notifications['/Script/Engine.SkeletalMeshComponent'](newHead)
for _=1,10 do tick() end
assert(newHead.headHidden and scans==scansBefore)
-- Half as many visibility traces at the configured interval.
require('config').AimTraceIntervalFrames=2
local tracesBefore=traceCalls
for _=1,20 do tick() end
assert(traceCalls-tracesBefore==10)
require('config').AimTraceIntervalFrames=1
-- A local projectile starts with horizontal velocity but may target above or
-- below its actual launch position; speed, gravity and remote shots survive.
local projectile=object('LocalArrow')
function projectile:GetOwner() return pawn end
function projectile:GetInstigator() return pawn end
function projectile:K2_GetActorLocation() return {X=100,Y=200,Z=365} end
local flight=object('ArrowMovement'); flight.Velocity={X=0,Y=1000,Z=0}
flight.ProjectileGravityScale=0.75; flight.bConstrainToPlane=true
function flight:GetOwner() return projectile end
aimHit={X=100,Y=1200,Z=1365}; tick()
notifications['/Script/Engine.ProjectileMovementComponent'](flight)
tick()
assert(flight.Velocity.Z>700 and not flight.bConstrainToPlane)
assert(math.abs(flight.Velocity.Y^2+flight.Velocity.Z^2-1000000)<0.001)
assert(flight.ProjectileGravityScale==0.75 and not flight.bIsHomingProjectile)
aimHit={X=100,Y=1200,Z=-635}; tick()
flight.Velocity={X=0,Y=1000,Z=0}
notifications['/Script/Engine.ProjectileMovementComponent'](flight)
tick(); assert(flight.Velocity.Z < -700)
function projectile:GetOwner() return remote end
function projectile:GetInstigator() return remote end
flight.Velocity={X=0,Y=1000,Z=0}; flight.bConstrainToPlane=true
notifications['/Script/Engine.ProjectileMovementComponent'](flight)
for _=1,5 do tick() end
assert(flight.Velocity.Z==0 and flight.bConstrainToPlane)
aimHit=nil; tick()
pawn.testX=300; render(); assert(math.abs(pc.target.position.X-300)<0.001)
pawn.testX=nil; render()
assert(pc.moveLocks==1 and not pc.bShowMouseCursor and widget.mode=='game')
pc.down.W=true; tick()
assert(math.abs(pawn.move.X)<0.0001 and math.abs(pawn.move.Y-1)<0.0001)
pc.down.W=false; pc.down.D=true; tick()
assert(math.abs(pawn.move.X+1)<0.0001 and math.abs(pawn.move.Y)<0.0001)
pc.down.W=true; tick()
assert(math.abs(pawn.move.X*pawn.move.X+pawn.move.Y*pawn.move.Y-1)<0.0001)
pc.down={W=true,S=true}; tick(); assert(pawn.move==nil)
pc.down={}; pc.dx=300; pc.dy=1000; tick()
assert(math.abs(math.abs(pc.rotation.Yaw)-180)<0.001 and pc.target.rotation.Yaw==-180)
assert(pc.target.rotation.Pitch==85)
assert(pc.rotation.Pitch>84 and pc.rotation.Pitch<=85 and not pawn.bUseControllerRotationPitch)
pc.dx=0; pc.dy=-1000; tick(); assert(pc.target.rotation.Pitch==-85)
pc.separateMouseOutputs=true
pc.dy=1000; tick(); assert(pc.target.rotation.Pitch==85)
pc.dy=-1000; tick(); assert(pc.target.rotation.Pitch==-85)
pc.dy=0
-- The menu releases mouse look, balances the movement lock, applies settings
-- by mouse buttons and resumes controls without changing the camera actor.
local menuPanel
for _,child in ipairs(canvas.children) do
    if child.label=='/Script/UMG.CanvasPanel' and child.parent==canvas and child.slot.size.X==460 then menuPanel=child end
end
assert(menuPanel)
local function menuButton(label)
    for _,child in ipairs(menuPanel.children) do
        if child.content and child.content.text==label then return child end
    end
    error('Missing menu button: ' .. label)
end
local function click(button)
    button.pressed=true; tick(); button.pressed=false; tick()
end
local menuCamera=pc.target
press(0x2D)
assert(menuPanel.visibility==0 and pc.bShowMouseCursor and pc.moveLocks==1 and widget.mode=='uiOnly')
assert(center.visibility==1)
local plus=menuButton('+')
plus.pressed=true; tick(); tick()
assert(pc.target.component.fov==105) -- action waits for release
plus.pressed=false; tick(); assert(pc.target.component.fov==110)
click(menuButton('-'))
assert(pc.target.component.fov==105)
local crossButton=menuButton('Crosshair: On')
click(crossButton); assert(crossButton.content.text=='Crosshair: Off')
click(crossButton); assert(crossButton.content.text=='Crosshair: On')
local invertButton=menuButton('Invert vertical look: Off')
click(invertButton); assert(invertButton.content.text=='Invert vertical look: On')
click(invertButton)
click(menuButton('Save & return to game'))
assert(pc.target==menuCamera and menuPanel.visibility==1 and not pc.bShowMouseCursor)
assert(pc.moveLocks==1 and widget.mode=='game' and center.visibility==3)
press(0x2D); press(0x1B)
assert(menuPanel.visibility==1 and pc.moveLocks==1 and not pc.bShowMouseCursor)
press(Key.F8); assert(pc.moveLocks==0 and pc.bShowMouseCursor and widget.mode=='ui')
assert(center.visibility==1)
press(Key.F8); assert(pc.moveLocks==1 and not pc.bShowMouseCursor and widget.mode=='game')
press(Key.MIDDLE_MOUSE_BUTTON)
assert(pc.moveLocks==0 and pc.bShowMouseCursor and widget.mode=='ui' and center.visibility==1)
press(Key.MIDDLE_MOUSE_BUTTON)
assert(pc.moveLocks==1 and not pc.bShowMouseCursor and widget.mode=='game' and center.visibility==3)
press(0x2D)
press(Key.MIDDLE_MOUSE_BUTTON)
assert(menuPanel.visibility==0 and pc.bShowMouseCursor and pc.moveLocks==1)
press(0x1B)
press(Key.F6)
assert(center.parent==nil)
assert(pc.target==original and not mesh.headHidden and not helmet.bHiddenInGame and not spawned[1].alive)
assert(pc.moveLocks==0 and pc.bShowMouseCursor and widget.mode=='ui')
assert(inputSettings.mappings==0)
press(Key.MIDDLE_MOUSE_BUTTON)
assert(pc.target==original and pc.bShowMouseCursor) -- inactive camera leaves game input alone
assert(inputSettings.bEnableMouseSmoothing)
assert(cvars['r.Tonemapper.Sharpen']==-1 and cvars['r.MaxAnisotropy']==8)
assert(not pawn.bUseControllerRotationYaw and movement.bOrientRotationToMovement)
assert(pc.rotation.Yaw==23 and pc.rotation.Pitch==12)
assert(pc.LookAtRotation.Yaw==12 and pc.AutoTargetDirection.X==1)
assert(pawn.ProjectileTargetPosition.X==11 and pawn.AimPitch==7 and pawn.bAutoTargetForcedByCharacter)
assert(not pawn.bAutoRotationIgnoreVelocity)
assert(pc.SelectedTarget==originalAimActor and pawn.ProjectileTargetActor==originalAimActor)
press(Key.F6); local active=pc.target
pc.Pawn=object('RespawnPawn'); tick()
assert(pc.target==original and not active.alive and not mesh.headHidden)
pc.Pawn=pawn
press(Key.F6); active=pc.target
local cutscene=object('Cutscene'); pc.target=cutscene; tick()
assert(pc.target==cutscene and not active.alive and not mesh.headHidden)
pc.target=original; press(Key.F6); active=pc.target
widget:SetInputMode_GameAndUIEx(pc)
pc:SetIgnoreMoveInput(true) -- chest/inventory's own movement lock
local nativeModeCalls=widget.modeCalls
tick()
assert(pc.target==active and active.alive and pc.moveLocks==1 and pc.bShowMouseCursor)
assert(widget.modeCalls==nativeModeCalls) -- opening must not rewrite native focus
for _=1,1000 do keys[Key.MIDDLE_MOUSE_BUTTON]() end
tick()
assert(pc.moveLocks==1 and pc.bShowMouseCursor and widget.modeCalls==nativeModeCalls)
pc.bShowMouseCursor=false
for _=1,5 do tick() end
assert(pc.moveLocks==1 and widget.modeCalls==nativeModeCalls) -- lock still belongs to game
pc:SetIgnoreMoveInput(false)
tick(); tick()
assert(pc.moveLocks==0)
tick()
assert(pc.target==active and pc.moveLocks==1 and not pc.bShowMouseCursor and widget.mode=='game')
assert(widget.modeCalls==nativeModeCalls+1)
pc.dx=2; tick(); assert(pc.rotation.Yaw~=90); pc.dx=0
-- Menus that expose the cursor without a movement lock also suspend/resume.
widget:SetInputMode_GameAndUIEx(pc); tick()
assert(pc.target==active and pc.moveLocks==0)
pc.bShowMouseCursor=false; tick(); tick(); tick()
assert(pc.moveLocks==1 and widget.mode=='game')
-- Manual toggles use the tick, coalesce bursts and keep the cursor visible.
for _=1,15 do tick() end
local beforeToggle=widget.modeCalls
for _=1,1000 do keys[Key.F8]() end
assert(widget.modeCalls==beforeToggle and not pc.bShowMouseCursor)
tick(); assert(pc.bShowMouseCursor and pc.moveLocks==0 and widget.modeCalls==beforeToggle+1)
for _=1,1000 do keys[Key.F8]() end
tick(); assert(pc.bShowMouseCursor and widget.modeCalls==beforeToggle+1)
press(Key.F8); assert(not pc.bShowMouseCursor and pc.moveLocks==1 and widget.mode=='game')
-- The real game leaves bShowMouseCursor false when its menu container opens.
-- Observe the container itself, not permanently visible cached descendants.
local menuCalls=widget.modeCalls
nativeMenu.visibility=0
tick()
assert(pc.target==active and pc.bShowMouseCursor and pc.moveLocks==0 and widget.mode=='ui')
assert(widget.modeCalls==menuCalls+1)
for _=1,1000 do keys[Key.MIDDLE_MOUSE_BUTTON]() end
tick(); tick()
assert(pc.bShowMouseCursor and pc.moveLocks==0 and widget.modeCalls==menuCalls+1)
-- Close while our shown cursor is still true. Return to GameOnly capture.
nativeMenu.visibility=1
tick(); tick(); tick()
assert(not pc.bShowMouseCursor and pc.moveLocks==1 and widget.mode=='game')
assert(widget.modeCalls==menuCalls+2)
-- Never resume early if closing leaves a native lock behind.
nativeMenu.visibility=0; tick(); pc:SetIgnoreMoveInput(true)
nativeMenu.visibility=1
for _=1,6 do tick() end
assert(pc.bShowMouseCursor and pc.moveLocks==1 and widget.mode=='ui')
pc:SetIgnoreMoveInput(false); tick(); tick(); tick()
assert(not pc.bShowMouseCursor and pc.moveLocks==1 and widget.mode=='game')
-- Hidden or fully transparent cached containers do not steal mouse look.
nativeMenu.visibility=2; tick(); assert(not pc.bShowMouseCursor)
nativeMenu.visibility=0; nativeMenu.opacity=0; tick(); assert(not pc.bShowMouseCursor)
nativeMenu.visibility=1; nativeMenu.opacity=1
local scansBeforeMenu=scans
for _=1,100 do
    nativeMenu.visibility=0; tick(); tick()
    nativeMenu.visibility=1; tick(); tick(); tick()
    assert(pc.target==active and pc.moveLocks==1 and widget.mode=='game')
end
assert(scans==scansBeforeMenu) -- cached container polling does not rescan widgets
press(Key.F6)
assert(pc.target==original and not active.alive and pc.moveLocks==0)
pc.target=original; failSpawn=true; press(Key.F6)
assert(pc.target==original and not spawned[#spawned].alive)
failSpawn=false; mesh.headHidden=true
press(Key.F6); press(Key.F6); assert(mesh.headHidden)
mesh.headHidden=false; pawn.alive=false; press(Key.F6)
assert(pc.target==original)
pawn.alive=true; press(Key.F7)
assert(logs[#logs]:find('Diagnostic END'))
local preferences=require('preferences')
local config=require('config')
local prefs=preferences.load(config,'test_settings.ini')
prefs.FOV=120; prefs.MouseSensitivity=0.6; prefs.ThirdPerson=true; prefs.Crosshair=false; prefs.GraphicsPreset=0; assert(prefs:save())
local reloaded=preferences.load(config,'test_settings.ini')
assert(reloaded.FOV==120 and reloaded.MouseSensitivity==0.6 and reloaded.ThirdPerson)
assert(not reloaded.Crosshair)
assert(reloaded.GraphicsPreset==0)
local unavailable=require('graphics').create({controller=pc,pawn=pawn,systemLibrary=system,cameraComponent={}},function() end)
assert(not unavailable:apply(3)) -- optional failure must retain camera/control mod
assert(cvars['r.Tonemapper.Sharpen']==-1 and cvars['r.MaxAnisotropy']==8)
local crosshair=require('crosshair')
local ownership=viewportWidget.GetOwningPlayer
function viewportWidget:GetOwningPlayer() return remote end
local detached=crosshair.create(pc,function() end)
assert(not detached.attached and #detached.images==0)
viewportWidget.GetOwningPlayer=ownership
local ui=crosshair.create(pc,function() end)
assert(ui.attached and #ui.images==10)
local pieces=ui.images
ui:destroy(); assert(not ui.attached and #ui.images==0)
for _,piece in ipairs(pieces) do assert(piece.parent==nil) end
-- Save-and-quit must clean up before outgoing objects become unsafe.
pc.target=original; press(Key.F6); local outgoing=pc.target
pc.dx=0; pc.dy=0; for _=1,120 do tick() end -- allow HUD reattachment after respawn cases
assert(mapCanvas.RenderTransformPivot.X==0.5 and mapCanvas.RenderTransformPivot.Y==0.5)
local heading=(pc.target.rotation.Yaw-45)%360
assert(math.abs(mapCanvas.RenderTransform.Angle-(7-heading))<0.001)
local compassPanel,compass
for _,child in ipairs(canvas.children) do
    if child.parent==canvas and child.slot.size.X==620 then compassPanel=child end
end
assert(compassPanel and compassPanel.clipping==1 and compassPanel.slot.anchors.Minimum.X==0.5)
for _,child in ipairs(compassPanel.children) do
    if child.slot.position.Y==31 then compass=child end
end
assert(compass and compass.text:find('°',1,true) and compass.visibility==3)
local pinSymbol
for _,child in ipairs(compassPanel.children) do
    if child.angle==45 and child.visibility==3 then pinSymbol=child end
end
assert(pinSymbol and math.abs(pinSymbol.slot.position.X-305)<0.01 and pinSymbol.color.R==1)
assert(keys[0x72]==nil and keys[0x73]==nil and keys[0x74]==nil) -- game map is the waypoint control
local metadataBefore=pinMetadataReads
nativeMap.PingWidgets={} -- removing the game marker removes its compass symbol
for _=1,15 do tick() end
assert(pinSymbol.visibility==1)
-- Exercise UE4SS's native array callback shape, not just plain Lua arrays.
nativeMap.PingWidgets={ForEach=function(_,callback)
    callback(0,{get=function() return {PingWidget=nativePin} end})
end}
for _=1,15 do tick() end
assert(pinSymbol.visibility==3 and pinMetadataReads==metadataBefore)
-- Verify the observed AddPing hook copies coordinates and isolates the HUD.
local fallbackClass=object('Class /Script/TOM.PingWithoutExposedPosition')
function fallbackClass:ForEachProperty() end
function fallbackClass:GetSuperStruct() return nil end
local fallbackPin=object('FallbackPin')
function fallbackPin:GetClass() return fallbackClass end
local function wrapped(value) return {get=function() return value end} end
nativeMap.PingWidgets={{PingWidget=fallbackPin}}
local info={ID=2,WorldPos={X=100,Y=1200,Z=300},MapPingType=0}
hooks['/Script/TOM.WorldmapWidget:RefreshPings'](wrapped(nativeMap))
hooks['/Script/TOM.WorldmapWidget:AddPing'](wrapped(foreignMap),wrapped(info))
assert(#nav.mapPoints(nativeMap)==0)
hooks['/Script/TOM.WorldmapWidget:AddPing'](wrapped(nativeMap),wrapped(info))
info.WorldPos.Y=-1200 -- hook parameters must not be retained as borrowed references
assert(nav.mapPoints(nativeMap)[1].Y==1200)
nativeMap.PingWidgets={}; assert(#nav.mapPoints(nativeMap)==0)
local markerClass=object('Class /Script/TOM.WorldmapMarkerWidget')
function markerClass:ForEachProperty(callback) pinClass:ForEachProperty(callback) end
function markerClass:GetSuperStruct() return nil end
local markerIcon=object('NativeWaypointMarker')
markerIcon.Info={ID=3,WorldPos={X=200,Y=1200,Z=300}}
function markerIcon:GetClass() return markerClass end
nativeMap.MarkerIcons={markerIcon}
assert(nav.mapPoints(nativeMap)[1].X==200) -- persistent marker list is separate from pings
markerIcon.alive=false
assert(#nav.mapPoints(nativeMap)==0) -- no stale fallback for destroyed marker widgets
nativeMap.MarkerIcons={}
local dynamicClass=object('Class /Script/TOM.DynamicMapIconBaseWidget')
function dynamicClass:GetSuperStruct() return nil end
function dynamicClass:ForEachProperty(callback)
    local info=object('StructProperty /Script/TOM.DynamicMapIconBaseWidget:Info')
    function info:IsA(kind) return kind==PropertyTypes.StructProperty end
    function info:GetFName() return FName('Info') end
    function info:GetStruct()
        local schema=object('ScriptStruct /Script/TOM.DynamicMapIconInfo')
        function schema:ForEachProperty(fieldCallback)
            local position=object('StructProperty /Script/TOM.DynamicMapIconInfo:WorldPosition')
            function position:IsA(kind) return kind==PropertyTypes.StructProperty end
            function position:GetFName() return FName('WorldPosition') end
            function position:GetStruct() return object('ScriptStruct /Script/CoreUObject.Vector2D') end
            fieldCallback(position)
        end
        return schema
    end
    callback(info)
end
local blueprintMarkerClass=object('WidgetBlueprintGeneratedClass /Game/BP_DynamicMarker.BP_DynamicMarker_C')
function blueprintMarkerClass:ForEachProperty() end
function blueprintMarkerClass:GetSuperStruct() return dynamicClass end
local dynamicMarker=object('DynamicPin'); dynamicMarker.Info={WorldPosition={X=400,Y=1200}}
function dynamicMarker:GetClass() return blueprintMarkerClass end
nativeMap.MarkerIcons={dynamicMarker}
local dynamicPoint=nav.mapPoints(nativeMap)[1]
assert(dynamicPoint.X==400 and dynamicPoint.Y==1200 and dynamicPoint.Z==0)
dynamicMarker.Info.WorldPosition.X=600
assert(nav.mapPoints(nativeMap)[1].X==600) -- read current data through the cached inherited field path
nativeMap.MarkerIcons={}
local integerMarkerClass=object('Class /Script/TOM.IntegerPinMarker')
function integerMarkerClass:GetSuperStruct() return nil end
function integerMarkerClass:ForEachProperty(callback)
    local info=object('StructProperty /Script/TOM.DynamicMapIconBaseWidget:Info')
    function info:IsA(kind) return kind==PropertyTypes.StructProperty end
    function info:GetFName() return FName('Info') end
    function info:GetStruct() return object('ScriptStruct /Script/TOM.MovingNPCMapInfo') end
    callback(info)
end
local integerMarker=object('IntegerPinMarker'); integerMarker.Info={X=12,Y=24}
function integerMarker:GetClass() return integerMarkerClass end
nativeMap.MarkerIcons={integerMarker}
assert(#nav.mapPoints(nativeMap)==0) -- integer grid coordinates are not world centimeters
local pinActor=object('Actor /Test.Pin')
function pinActor:K2_GetActorLocation() return {X=12000,Y=24000,Z=50} end
integerMarker.Info.ActorRef=pinActor
local actorPoint=nav.mapPoints(nativeMap)[1]
assert(actorPoint.X==12000 and actorPoint.Y==24000 and actorPoint.Z==50)
pinActor.alive=false
assert(#nav.mapPoints(nativeMap)==0) -- never call a destroyed pin actor
nativeMap.MarkerIcons={}
local canvasPinClass=object('WidgetBlueprintGeneratedClass /Game/TOM/BP_MapIcon_PinMarker.BP_MapIcon_PinMarker_C')
function canvasPinClass:ForEachProperty() error('Canvas pin should not read its default Info struct') end
local canvasPin=object('CanvasPin'); canvasPin.Info={X=0,Y=0}
function canvasPin:GetClass() return canvasPinClass end
canvasPin.Slot=object('CanvasPanelSlot /Test.PinSlot')
canvasPin.Icon=object('Image /Test.PinIcon')
canvasPin.Icon.Brush={ResourceObject='SwordTexture'}; canvasPin.IconId=1
local canvasPosition={X=120,Y=-240}
function canvasPin.Slot:GetPosition() return canvasPosition end
local conversions=0
function nativeMap:MapToWorldPosition(position)
    conversions=conversions+1
    return {X=position.X*100+300,Y=-position.Y*100+400,Z=25}
end
nativeMap.MarkerIcons={canvasPin}
local canvasPoint=nav.mapPoints(nativeMap)[1]
assert(canvasPoint.X==12300 and canvasPoint.Y==24400 and canvasPoint.Z==25)
assert(canvasPoint.iconSource==canvasPin.Icon and canvasPoint.iconId==1)
local iconCompass=nav.create(canvas)
iconCompass:update(45,{X=0,Y=0,Z=0},{{X=100,Y=100,Z=0,iconSource=canvasPin.Icon,iconId=1}})
local iconImage=iconCompass.markers[1].widget
assert(iconImage.brush.ResourceObject=='SwordTexture' and iconImage.angle==0 and iconImage.color.G==1)
assert(iconCompass.markers[1].slot.size.X==24)
local brushWrites=iconImage.brushWrites
iconCompass:update(45,{X=0,Y=0,Z=0},{{X=100,Y=100,Z=0,iconSource=canvasPin.Icon,iconId=1}})
assert(iconImage.brushWrites==brushWrites) -- no native brush copy every frame
canvasPin.Icon.Brush={ResourceObject='ShieldTexture'}; canvasPin.IconId=2
iconCompass:update(45,{X=0,Y=0,Z=0},{{X=100,Y=100,Z=0,iconSource=canvasPin.Icon,iconId=2}})
assert(iconImage.brush.ResourceObject=='ShieldTexture') -- selection changes on the same pin
canvasPin.Icon.alive=false
iconCompass:update(45,{X=0,Y=0,Z=0},{{X=100,Y=100,Z=0,iconSource=canvasPin.Icon,iconId=2}})
assert(iconImage.angle==45 and iconCompass.markers[1].slot.size.X==10)
iconCompass:destroy()
canvasPosition.X=140
assert(nav.mapPoints(nativeMap)[1].X==14300 and conversions==2)
assert(canvasPoint.X==12300) -- copy the converter result; retain no native struct
canvasPin.Slot.alive=false
assert(#nav.mapPoints(nativeMap)==0 and conversions==2)
nativeMap.MarkerIcons={}
nativeMap.PingWidgets={{PingWidget=nativePin}}
local northLabel
for _,child in ipairs(compassPanel.children) do
    if child.text=='N' then northLabel=child end
end
local northPosition=northLabel.slot.position.X
local mapScans=scans; local mapWrites=mapCanvas.writes
for _=1,5 do tick() end
assert(scans==mapScans and mapCanvas.writes==mapWrites)
pc.dx=30; tick(); pc.dx=0
assert(mapCanvas.writes>mapWrites)
assert(northLabel.slot.position.X<northPosition) -- headings scroll left on a right turn
press(Key.F9); tick() -- the same rotation follows the third-person camera
assert(compass.parent==compassPanel and compassPanel.parent==canvas)
press(Key.F6) -- Original view restores all map state and removes the compass
assert(mapCanvas.RenderTransform.Angle==7 and compass.parent==nil and compassPanel.parent==nil)
assert(mapCanvas.RenderTransformPivot.X==0.2 and mapCanvas.RenderTransformPivot.Y==0.3)
tick(); assert(mapCanvas.RenderTransform.Angle==7)
press(Key.F6); tick(); outgoing=pc.target

press(0x2D) -- also cover an open settings panel with its movement lock
assert(pc.moveLocks==1)
local function ref(o) return {get=function() return o end} end
assert(hooks.loadMapPre()==nil) -- never override the engine's return value
assert(pc.target==original and not outgoing.alive and not mesh.headHidden)
assert(mapCanvas.RenderTransform.Angle==7)
assert(pc.moveLocks==0 and inputSettings.mappings==0)
assert(cvars['r.Tonemapper.Sharpen']==-1 and cvars['r.MaxAnisotropy']==8)
local findBefore=findCalls
local oldValid=pc.IsValid
function pc:IsValid() error('Outgoing controller must not be touched during travel') end
tick(); press(Key.F6); press(0x2D); render()
assert(findCalls==findBefore)
pc.IsValid=oldValid
nativeMap.PingWidgets={} -- the next world owns a fresh native map widget/list
assert(hooks.loadMapPost()==nil)
press(Key.F6); assert(pc.target~=original) -- next world can enable normally
tick()
for _,child in ipairs(canvas.children) do
    if child.parent==canvas and child.slot.size.X==620 then
        for _,marker in ipairs(child.children) do
            if marker.angle==45 then assert(marker.visibility==1) end
        end
    end
end
-- Remote actor destruction must not stop local play.
hooks.endPlayPre(ref(remote)); assert(pc.target~=original)
hooks['/Script/Engine.KismetSystemLibrary:QuitGame']()
assert(pc.target==original and pc.moveLocks==0 and inputSettings.mappings==0)
hooks.loadMapPost(); press(Key.F6)
-- Fallback EndPlay abandons references without mutating a dying pawn.
local oldLocation=pawn.K2_GetActorLocation
function pawn:K2_GetActorLocation() error('Dying pawn must not be queried') end
hooks.endPlayPre(ref(pawn)); tick(); render(); press(Key.F6)
pawn.K2_GetActorLocation=oldLocation
hooks.loadMapPost()
assert(inputSettings.mappings==0 and inputSettings.bEnableMouseSmoothing)
''')
print("PASS: menu mouse actions, cursor/lock restoration, preferences; graphics, local projectile aim, streaming budget, camera and controls.")
