-- Native HUD controls; no delegate hooks or per-frame world scans.
local menu = {}
local function valid(o) return o and o:IsValid() end
function menu.nativeUIOpen(controller)
    local controllerName=controller:GetFullName()
    local userClass=StaticFindObject('/Script/UMG.UserWidget')
    local widgetClass=StaticFindObject('/Script/UMG.Widget')
    local treeClass=StaticFindObject('/Script/UMG.WidgetTree')
    local switchClass=StaticFindObject('/Script/UMG.WidgetSwitcher')
    for _,candidate in ipairs(FindAllOf('UserWidget') or {}) do
        if valid(candidate) then
            local name=candidate:GetFullName()
            local lower=name:lower()
            local passive=lower:find('hud',1,true) or lower:find('crosshair',1,true) or
                lower:find('cursor',1,true) or lower:find('compass',1,true) or lower:find('notification',1,true)
            local topLevel=candidate:IsInViewport() and not passive
            local modal=lower:find('maintab',1,true) or lower:find('workbench',1,true) or
                lower:find('crafting',1,true) or lower:find('inventory',1,true) or
                lower:find('chest',1,true) or lower:find('container',1,true) or
                lower:find('pausemenu',1,true)
            if topLevel or (modal and not lower:find('icon',1,true)) then
                local node=candidate
                for _=1,24 do
                    if not valid(node) or not node:IsA(widgetClass) then break end
                    local visibility=node:GetVisibility()
                    if visibility==1 or visibility==2 then break end
                    local opaque,opacity=pcall(function() return node:GetRenderOpacity() end)
                    if opaque and type(opacity)=='number' and opacity<=0.01 then break end
                    if node:IsA(userClass) and node:IsInViewport() then
                        -- UserWidgets can stay in the viewport while their
                        -- actual root is collapsed or faded out.
                        local hasRoot,root=pcall(function() return node.WidgetTree.RootWidget end)
                        if hasRoot and valid(root) then
                            local rootVisibility=root:GetVisibility()
                            if rootVisibility==1 or rootVisibility==2 then break end
                            local success,alpha=pcall(function() return root:GetRenderOpacity() end)
                            if success and type(alpha)=='number' and alpha<=0.01 then break end
                        end
                        local owner=node:GetOwningPlayer()
                        if valid(owner) and owner:GetFullName()==controllerName then return true,name end
                        break
                    end
                    local parent=node:GetParent()
                    if valid(parent) then
                        if parent:IsA(switchClass) then
                            local active=parent:GetActiveWidget()
                            if not valid(active) or active:GetFullName()~=node:GetFullName() then break end
                        end
                        node=parent
                    else
                        local outer=node:GetOuter()
                        if not valid(outer) or not outer:IsA(treeClass) then break end
                        node=outer:GetOuter()
                    end
                end
            end
        end
    end
    return false
end
local function host(controller)
    for _,candidate in ipairs(FindAllOf("CanvasPanel") or {}) do
        if valid(candidate) then
            local tree=candidate:GetOuter()
            if valid(tree) and tree:IsA(StaticFindObject("/Script/UMG.WidgetTree")) then
                local widget=tree:GetOuter()
                if valid(widget) and widget:IsA(StaticFindObject("/Script/UMG.UserWidget")) and
                    widget:GetOwningPlayer()==controller and widget:IsInViewport() and
                    widget:GetFullName():match("^BP_HUD_C ") then
                    local root=tree.RootWidget
                    if valid(root) and root:IsA(StaticFindObject("/Script/UMG.CanvasPanel")) then return root,tree end
                end
            end
        end
    end
end
function menu.create(controller, callbacks, log)
    local ui={controller=controller,widgets={},buttons={},labels={},opened=false,attached=false}
    function ui:destroy()
        for i=#self.widgets,1,-1 do
            if valid(self.widgets[i]) then self.widgets[i]:RemoveFromParent() end
        end
        self.widgets={}; self.buttons={}; self.attached=false; self.opened=false
    end
    local ok,err=pcall(function()
        local root,tree=host(controller)
        if not root then return end
        ui.root=root
        local classes={}
        local function construct(kind)
            classes[kind]=classes[kind] or StaticFindObject("/Script/UMG." .. kind)
            local widget=StaticConstructObject(classes[kind],tree)
            if not valid(widget) then error("Could not construct menu " .. kind) end
            ui.widgets[#ui.widgets+1]=widget
            return widget
        end
        local function place(parent,widget,x,y,w,h,anchorX,anchorY,z)
            local slot=parent:AddChildToCanvas(widget)
            slot:SetAnchors({Minimum={X=anchorX or 0,Y=anchorY or 0},Maximum={X=anchorX or 0,Y=anchorY or 0}})
            slot:SetAlignment({X=0,Y=0})
            slot:SetPosition({X=x,Y=y}); slot:SetSize({X=w,Y=h}); slot:SetAutoSize(false); slot:SetZOrder(z or 1)
            return slot
        end
        local panel=construct("CanvasPanel"); ui.panel=panel
        place(root,panel,-230,-298,460,596,0.5,0.5,20010)
        panel:SetVisibility(1)
        local texture=StaticFindObject("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")
        if not valid(texture) then texture=LoadAsset("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture") end
        local background=construct("Image")
        background:SetBrushFromTexture(texture,false)
        background:SetColorAndOpacity({R=0.025,G=0.035,B=0.055,A=0.97})
        background:SetVisibility(0) -- block clicks falling through panel gaps
        place(panel,background,0,0,460,596,0,0,0)
        local function text(parent,value,x,y,w,h,size)
            local label=construct("TextBlock")
            label:SetText(FText(value)); label:SetVisibility(3)
            -- Preserve the engine's default font object and typeface.
            local font=label.Font; font.Size=size or 18; label:SetFont(font)
            if parent then place(parent,label,x,y,w,h) end
            return label
        end
        text(panel,"MIDGARD POV",22,18,410,32,24)
        text(panel,"Camera & visuals",22,52,410,26,16)
        local function button(parent,id,value,x,y,w,h,action,ax,ay,z)
            local control=construct("Button")
            control:SetBackgroundColor({R=0.12,G=0.21,B=0.30,A=1})
            local label=text(nil,value,0,0,0,0,16)
            control:SetContent(label)
            place(parent,control,x,y,w,h,ax,ay,z)
            ui.buttons[#ui.buttons+1]={widget=control,action=action,pressed=false,id=id}
            ui.labels[id]=label
        end
        button(panel,"first","First person",22,94,132,38,function() callbacks.action("first") end)
        button(panel,"third","Third person",164,94,132,38,function() callbacks.action("third") end)
        button(panel,"original","Original view",306,94,132,38,function() callbacks.action("original") end)
        local fov=text(panel,"",22,151,252,28); ui.labels.fov=fov
        button(panel,"fovMinus","-",300,146,62,36,function() callbacks.action("fovDown") end)
        button(panel,"fovPlus","+",374,146,64,36,function() callbacks.action("fovUp") end)
        ui.labels.sensitivity=text(panel,"",22,199,252,28)
        button(panel,"sensMinus","-",300,194,62,36,function() callbacks.action("sensDown") end)
        button(panel,"sensPlus","+",374,194,64,36,function() callbacks.action("sensUp") end)
        button(panel,"crosshair","",22,246,416,38,function() callbacks.action("crosshair") end)
        button(panel,"graphics","",22,294,416,38,function() callbacks.action("graphics") end)
        button(panel,"invert","",22,342,416,38,function() callbacks.action("invert") end)
        ui.labels.renderDistance=text(panel,'Render distance: 1.00x',22,394,416,28)
        local slider=construct('Slider'); ui.distanceSlider=slider
        slider:SetValue(0); slider:SetStepSize(0.025)
        place(panel,slider,22,427,416,28)
        text(panel,'Higher distance can reduce performance.',22,458,416,22,13)
        button(panel,"close","Save & return to game",22,492,416,42,function() callbacks.close() end)
        text(panel,"Settings save automatically. Insert opens this menu.",22,552,416,30,13)
        button(root,"launcher","Mod settings",-158,22,136,36,function() callbacks.toggle() end,1,0,20011)
        ui.launcher=ui.buttons[#ui.buttons].widget
        ui.attached=true
    end)
    if not ok then ui:destroy(); log("Mod menu unavailable: " .. tostring(err)) end
    function ui:refresh(settings, enabled, graphicsNames)
        local function set(id,value) self.labels[id]:SetText(FText(value)) end
        set("fov",string.format("Field of view: %.0f",settings.FOV))
        set("sensitivity",string.format("Mouse sensitivity: %.2f",settings.MouseSensitivity))
        set("crosshair","Crosshair: " .. (settings.Crosshair and "On" or "Off"))
        set("graphics","Graphics: " .. graphicsNames[settings.GraphicsPreset] .. "  >")
        set("invert","Invert vertical look: " .. (settings.InvertMouseY and "On" or "Off"))
        self.distance=settings.RenderDistance or 1
        self.sliderValue=(self.distance-1)/2
        self.distanceSlider:SetValue(self.sliderValue)
        set('renderDistance',string.format('Render distance: %.2fx',self.distance))
    end
    function ui:show(open)
        if not open and self.sliderReadyAt then
            self.sliderReadyAt=nil
            callbacks.action('renderDistance',1+self.sliderValue*2)
        end
        self.opened=open
        self.panel:SetVisibility(open and 0 or 1)
        for _,entry in ipairs(self.buttons) do entry.pressed=false end
    end
    function ui:tick()
        if not self.opened and not self.controller.bShowMouseCursor then return end
        if self.opened and self.distanceSlider then
            local value=math.max(0,math.min(1,self.distanceSlider:GetValue()))
            if value~=self.sliderValue then
                self.sliderValue=value; self.sliderReadyAt=os.clock()+0.15
                self.labels.renderDistance:SetText(FText(string.format('Render distance: %.2fx',1+value*2)))
            end
            if self.sliderReadyAt and os.clock()>=self.sliderReadyAt then
                self.sliderReadyAt=nil
                callbacks.action('renderDistance',1+self.sliderValue*2)
            end
        end
        -- IsPressed is a regular UFunction; unsupported delegate hooks aren't used.
        for _,entry in ipairs(self.buttons) do
            if self.opened or entry.id=="launcher" then
                local pressed=entry.widget:IsPressed()
                if not pressed and entry.pressed then
                    entry.pressed=false
                    entry.action()
                    break -- action may close/rebuild the menu
                end
                entry.pressed=pressed
            end
        end
    end
    return ui
end
return menu
