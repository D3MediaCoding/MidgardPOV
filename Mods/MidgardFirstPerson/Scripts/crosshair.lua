-- Persistent UMG rectangles; independent of the unused ReceiveDrawHUD event.
local crosshair = {}
local function valid(o)
    if not o then return false end
    local ok, result = pcall(function() return o:IsValid() end)
    return ok and result
end
function crosshair.create(controller, log)
    local result = {images={}, attached=false}
    function result:show(visible)
        for _, image in ipairs(self.images) do
            -- HitTestInvisible / Collapsed: never intercept gameplay input.
            if valid(image) then image:SetVisibility(visible and 3 or 1) end
        end
    end
    function result:destroy()
        for _, image in ipairs(self.images) do
            if valid(image) then image:RemoveFromParent() end
        end
        self.images = {}; self.attached = false
    end
    local ok, err = pcall(function()
        local canvas, tree
        for _, candidate in ipairs(FindAllOf("CanvasPanel") or {}) do
            if valid(candidate) then
                local candidateTree = candidate:GetOuter()
                if valid(candidateTree) and candidateTree:IsA(StaticFindObject("/Script/UMG.WidgetTree")) then
                    local widget = candidateTree:GetOuter()
                    if valid(widget) and widget:IsA(StaticFindObject("/Script/UMG.UserWidget")) and
                        widget:GetOwningPlayer() == controller and widget:IsInViewport() then
                        local widgetName = widget:GetFullName()
                        -- Use the actual root object, without comparing wrapper
                        -- identities or round-tripping opaque FGeometry data.
                        if widgetName:match("^BP_HUD_C ") then
                            local root = candidateTree.RootWidget
                            if valid(root) and root:IsA(StaticFindObject("/Script/UMG.CanvasPanel")) then
                                canvas, tree = root, candidateTree
                                log("Crosshair root visibility: widget=" .. tostring(widget:GetVisibility()) .. ", canvas=" .. tostring(root:GetVisibility()))
                                break
                            end
                        elseif candidateTree.RootWidget == candidate and not canvas then
                            canvas, tree = candidate, candidateTree
                        end
                    end
                end
            end
        end
        if not canvas then
            log("Crosshair: no visible local HUD canvas found; F10 can retry after the world UI loads.")
            return
        end
        local imageClass = StaticFindObject("/Script/UMG.Image")
        if not valid(imageClass) then error("UMG Image class unavailable") end
        local texture = StaticFindObject("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")
        if not valid(texture) then texture = LoadAsset("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture") end
        local function image(x,y,w,h,color,z)
            local piece = StaticConstructObject(imageClass, tree)
            if not valid(piece) then error("Image construction failed") end
            table.insert(result.images,piece)
            if valid(texture) then piece:SetBrushFromTexture(texture,false) end
            piece:SetColorAndOpacity(color)
            piece:SetVisibility(3)
            local slot = canvas:AddChildToCanvas(piece)
            if not valid(slot) then error("Canvas slot construction failed") end
            slot:SetAnchors({Minimum={X=0.5,Y=0.5},Maximum={X=0.5,Y=0.5}})
            slot:SetAlignment({X=0,Y=0})
            slot:SetAutoSize(false)
            slot:SetPosition({X=x,Y=y})
            slot:SetSize({X=w,Y=h})
            slot:SetZOrder(z)
        end
        local white, black = {R=1,G=1,B=1,A=1},{R=0,G=0,B=0,A=1}
        for _, r in ipairs({{-1,-1,2,2},{-9,-1,5,2},{4,-1,5,2},{-1,-9,2,5},{-1,4,2,5}}) do
            image(r[1]-1,r[2]-1,r[3]+2,r[4]+2,black,10000)
            image(r[1],r[2],r[3],r[4],white,10001)
        end
        result.attached = true
        log("Crosshair attached to " .. canvas:GetFullName())
    end)
    if not ok then
        result:destroy()
        log("Crosshair UI error: " .. tostring(err))
    end
    return result
end
return crosshair
