"""Behavior tests using Unreal API stand-ins; not an in-game compatibility test."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "test-runtime"))
from lupa import LuaRuntime

lua = LuaRuntime()
lua.execute(r'''
keys, logs, work, hooks = {}, {}, {}, {}
Key = {F6=117, F7=118, F8=119, F9=120, F10=121, F11=122}
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
function press(key) keys[key](); drain() end
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
function widget:SetInputMode_GameOnly(controller)
    local fn=hooks['/Script/UMG.WidgetBlueprintLibrary:SetInputMode_GameOnly']
    if fn then fn(nil,{get=function() return controller end}) end
    self.mode='game'
end
function widget:SetInputMode_GameAndUIEx(controller)
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
canvas=object('ViewportRootCanvas'); canvas.children={}
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
function StaticConstructObject(class,outer)
    assert(outer==tree)
    local image=object(class.label)
    if class.label=='/Script/UMG.CanvasPanel' then
        image.children={}; image.AddChildToCanvas=canvas.AddChildToCanvas
    elseif class.label=='/Script/UMG.TextBlock' then
        image.Font={Size=18}
        function image:SetText(text) self.text=text end
        function image:SetFont(font) self.Font=font end
    elseif class.label=='/Script/UMG.Button' then
        function image:SetBackgroundColor(color) self.background=color end
        function image:SetContent(text) self.content=text; text.parent=self end
        function image:IsPressed() return self.pressed or false end
    else assert(class.label=='/Script/UMG.Image') end
    function image:SetBrushFromTexture(texture) self.texture=texture end
    function image:SetColorAndOpacity(color) self.color=color end
    function image:SetVisibility(v) self.visibility=v end
    function image:RemoveFromParent() self.parent=nil end
    return image
end
function FindAllOf(class)
    scans=scans+1
    if class=='PlayerController' then return {remote,pc} end
    if class=='SkeletalMeshComponent' then return {mesh} end
    if class=='StaticMeshComponent' then return {helmet,weapon} end
    if class=='CanvasPanel' then return {candidateCanvas} end
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
config = (root / "Mods/MidgardFirstPerson/Scripts/config.lua").read_text()
lua.globals().package.preload["config"] = lua.eval("function() " + config + " end")
lua.globals().package.preload["controls"] = lua.eval("function() " + (root / "Mods/MidgardFirstPerson/Scripts/controls.lua").read_text() + " end")
for module in ("appearance", "preferences", "crosshair", "aim", "graphics", "menu"):
    lua.globals().package.preload[module] = lua.eval("function() " + (root / f"Mods/MidgardFirstPerson/Scripts/{module}.lua").read_text() + " end")
lua.execute((root / "Mods/MidgardFirstPerson/Scripts/main.lua").read_text())
lua.execute(r'''
require('config').AimTraceIntervalFrames=1 -- immediate trace scenarios below
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
    if child.label=='/Script/UMG.CanvasPanel' and child.parent==canvas then menuPanel=child end
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
press(Key.F6)
assert(center.parent==nil)
assert(pc.target==original and not mesh.headHidden and not helmet.bHiddenInGame and not spawned[1].alive)
assert(pc.moveLocks==0 and pc.bShowMouseCursor and widget.mode=='ui')
assert(inputSettings.mappings==0)
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
tick()
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
press(0x2D) -- also cover an open settings panel with its movement lock
assert(pc.moveLocks==1)
local function ref(o) return {get=function() return o end} end
assert(hooks.loadMapPre()==nil) -- never override the engine's return value
assert(pc.target==original and not outgoing.alive and not mesh.headHidden)
assert(pc.moveLocks==0 and inputSettings.mappings==0)
assert(cvars['r.Tonemapper.Sharpen']==-1 and cvars['r.MaxAnisotropy']==8)
local findBefore=findCalls
local oldValid=pc.IsValid
function pc:IsValid() error('Outgoing controller must not be touched during travel') end
tick(); press(Key.F6); press(0x2D); render()
assert(findCalls==findBefore)
pc.IsValid=oldValid
assert(hooks.loadMapPost()==nil)
press(Key.F6); assert(pc.target~=original) -- next world can enable normally
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
