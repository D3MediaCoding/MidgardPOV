-- Native HUD controls; no delegate hooks or per-frame world scans.
local menu = {}
local function valid(o) return o and o:IsValid() end
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
        place(root,panel,-230,-258,460,516,0.5,0.5,20010)
        panel:SetVisibility(1)
        local texture=StaticFindObject("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")
        if not valid(texture) then texture=LoadAsset("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture") end
        local background=construct("Image")
        background:SetBrushFromTexture(texture,false)
        background:SetColorAndOpacity({R=0.025,G=0.035,B=0.055,A=0.97})
        background:SetVisibility(0) -- block clicks falling through panel gaps
        place(panel,background,0,0,460,516,0,0,0)
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
        button(panel,"close","Save & return to game",22,400,416,42,function() callbacks.close() end)
        text(panel,"Settings save automatically. Insert opens this menu.",22,465,416,30,13)
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
    end
    function ui:show(open)
        self.opened=open
        self.panel:SetVisibility(open and 0 or 1)
        for _,entry in ipairs(self.buttons) do entry.pressed=false end
    end
    function ui:tick()
        if not self.opened and not self.controller.bShowMouseCursor then return end
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
