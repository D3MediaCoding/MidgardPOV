-- Local navigation HUD. Positions are copied vectors; icon sources are guarded
-- UMG image references and are discarded with the outgoing compass.
local navigation={}
local directions={"N","NE","E","SE","S","SW","W","NW"}
function navigation.heading(yaw) return (yaw-45)%360 end
function navigation.direction(heading) return directions[math.floor((heading+22.5)/45)%8+1] end
function navigation.relative(heading,bearing) return (bearing-heading+180)%360-180 end
function navigation.destination(origin,target)
    local x,y,z=target.X-origin.X,target.Y-origin.Y,target.Z-origin.Z
    local bearing=navigation.heading(math.deg(math.atan(y,x)))
    return bearing,math.sqrt(x*x+y*y+z*z)/100
end
local function valid(object) return object and object:IsValid() end
local pingCache,readers={},{}
local reporter=function() end
function navigation.reset() pingCache={} end
local function hudPath(root)
    return root:GetFullName():match("^%S+ (.*)%.WidgetTree%.CanvasPanel_0$")
end
function navigation.install(getRoot,log)
    reporter=log
    local function localMap(context)
        local root=getRoot()
        if not valid(root) then return end
        local object=context:get()
        if not valid(object) then return end
        local path=hudPath(root)
        local name=object:GetFullName()
        if path and name:find(path .. ".WidgetTree.BP_HUD_Compass",1,true) then return name end
    end
    local function hook(path,callback)
        local ok,err=pcall(RegisterHook,path,callback)
        if not ok then log("Map pin hook unavailable: " .. tostring(err)) end
    end
    hook("/Script/TOM.WorldmapWidget:RefreshPings",function(context)
        local name=localMap(context)
        if name then pingCache[name]={} end
    end)
    hook("/Script/TOM.WorldmapWidget:AddPing",function(context,parameter)
        local name=localMap(context)
        if not name then return end
        local ok,err=pcall(function()
            local ping=parameter:get()
            local point=ping.WorldPos
            pingCache[name]=pingCache[name] or {}
            pingCache[name][ping.ID]={X=point.X,Y=point.Y,Z=point.Z}
        end)
        if not ok then log("Map pin capture skipped: " .. tostring(err)) end
    end)
end
-- Resolve reflected coordinate fields once per ping-widget class. Runtime
-- polling then reads only those fields; it does not rescan class metadata.
local function reader(widget)
    local class=widget:GetClass()
    local className=class:GetFullName()
    if readers[className]~=nil then return readers[className] end
    if className:lower():find("bp_mapicon_pinmarker",1,true) then
        local descriptor={path={},canvasPosition=true}
        readers[className]=descriptor
        reporter("Map pin coordinate binding: " .. className .. ":CanvasPanelSlot -> MapToWorldPosition")
        return descriptor
    end
    local descriptor
    local function inspectField(property,path,depth)
        if descriptor or not property:IsA(PropertyTypes.StructProperty) then return end
        local key=property:GetFName():ToString()
        local keys={}
        for _,part in ipairs(path) do keys[#keys+1]=part end
        keys[#keys+1]=key
        local schema=property:GetStruct()
        local name=schema:GetFullName()
        if name:match("/Script/TOM%.MovingNPCMapInfo$") then
            descriptor={path=keys,mapCoordinates=true}
        elseif name:match("/Script/CoreUObject%.Vector$") then descriptor={path=keys}
        elseif name:match("/Script/CoreUObject%.Vector2D$") and
            (key:lower():find("pos",1,true) or key:lower():find("location",1,true) or key:lower():find("world",1,true)) then
            descriptor={path=keys,twoDimensional=true}
        elseif depth<2 and name:find("/Script/TOM.",1,true) then
            reporter("Map pin info struct: " .. name)
            schema:ForEachProperty(function(field)
                reporter("Map pin info field: " .. field:GetFullName())
                inspectField(field,keys,depth+1)
            end)
        end
    end
    for _=1,4 do
        if not valid(class) or descriptor then break end
        class:ForEachProperty(function(property)
            inspectField(property,{},0)
        end)
        class=class:GetSuperStruct()
    end
    readers[className]=descriptor or false
    if descriptor then reporter("Map pin coordinate binding: " .. className .. ":" .. table.concat(descriptor.path,"."))
    else reporter("Map pin widget uses captured AddPing data: " .. className) end
    return descriptor
end
function navigation.mapFor(root)
    local path=hudPath(root)
    if not path then return end
    for _,map in ipairs(FindAllOf("BP_WorldmapWidget_C") or {}) do
        if valid(map) and map:GetFullName():find(path .. ".WidgetTree.BP_HUD_Compass",1,true) then
            reporter("Map marker source: " .. map:GetFullName())
            return map
        end
    end
    reporter("Map marker source missing for HUD: " .. path)
end
function navigation.mapPoints(map)
    if not valid(map) then return {} end
    local array=map.PingWidgets
    local points={}
    local count,visited,unresolved=0,0,0
    local function entry(value)
        visited=visited+1
        if visited>32 then return true end
        local widget=value.PingWidget
        if not valid(widget) then return end
        count=count+1
        local firstPoint=#points+1
        local descriptor=reader(widget)
        if descriptor then
            local point=widget
            for _,key in ipairs(descriptor.path) do point=point[key] end
            if descriptor.canvasPosition then
                local slot=widget.Slot
                if valid(slot) then
                    local mapPosition=slot:GetPosition()
                    local position=map:MapToWorldPosition({X=mapPosition.X,Y=mapPosition.Y})
                    if type(position.X)=="number" and type(position.Y)=="number" and type(position.Z)=="number" then
                        points[#points+1]={X=position.X,Y=position.Y,Z=position.Z}
                        local key=widget:GetFullName() .. ":converted"
                        if not readers[key] then
                            readers[key]=true
                            reporter(string.format("Map pin canvas conversion: map=(%.2f, %.2f), world=(%.2f, %.2f, %.2f)",mapPosition.X,mapPosition.Y,position.X,position.Y,position.Z))
                        end
                    end
                end
            elseif descriptor.mapCoordinates then
                -- Some moving map icons carry a real actor; persistent pins
                -- without one need the map's coordinate conversion instead.
                local actor=point.ActorRef
                if valid(actor) then
                    local position=actor:K2_GetActorLocation()
                    points[#points+1]={X=position.X,Y=position.Y,Z=position.Z}
                end
            else
                points[#points+1]={X=point.X,Y=point.Y,Z=descriptor.twoDimensional and 0 or point.Z}
            end
        else unresolved=unresolved+1 end
        if #points>=firstPoint then
            local ok,source,id=pcall(function() return widget.Icon,widget.IconId end)
            if ok and valid(source) then
                points[#points].iconSource=source
                points[#points].iconId=id
            end
        end
    end
    local function each(collection,callback)
        if not collection then return end
        if type(collection)=="table" and not collection.ForEach then
            for _,value in ipairs(collection) do if callback(value) then break end end
        else collection:ForEach(function(_,value) return callback(value:get()) end) end
    end
    each(array,entry)
    local markerCount=0
    each(map.MarkerIcons,function(widget)
        markerCount=markerCount+1
        if markerCount>32 then return true end
        if not valid(widget) then return end
        local name=widget:GetFullName()
        if markerCount<=4 and not readers[name] then
            readers[name]=true
            reporter("Map marker icon: " .. name)
        end
        -- The separate marker collection may also contain game landmarks.
        -- Only marker/ping widgets contribute navigation symbols.
        local className=widget:GetClass():GetFullName():lower()
        if className:find("marker",1,true) or className:find("ping",1,true) then entry({PingWidget=widget}) end
    end)
    local counts=count .. "/" .. markerCount
    local name=map:GetFullName()
    readers._counts=readers._counts or {}
    if readers._counts[name]~=counts then
        readers._counts[name]=counts
        reporter("Map marker collection counts: pins=" .. count .. ", marker-icons=" .. markerCount)
    end
    -- The widget list is authoritative for removal. Empty list means no pin,
    -- even if a prior registration was captured while the camera was disabled.
    if count==0 then return {} end
    if #points==0 and unresolved>0 then
        for _,point in pairs(pingCache[map:GetFullName()] or {}) do
            points[#points+1]=point
            if #points>=math.min(unresolved,32) then break end
        end
    end
    return points
end
function navigation.create(root)
    local ui={widgets={},ticks={},markers={},root=root}
    function ui:destroy()
        for index=#self.widgets,1,-1 do
            if valid(self.widgets[index]) then self.widgets[index]:RemoveFromParent() end
        end
        self.widgets={}
    end
    local tree=root:GetOuter()
    local function construct(kind)
        local widget=StaticConstructObject(StaticFindObject("/Script/UMG." .. kind),tree)
        if not valid(widget) then error("Could not create navigation " .. kind) end
        ui.widgets[#ui.widgets+1]=widget
        widget:SetVisibility(3) -- decorative HUD never intercepts input
        return widget
    end
    local function place(parent,widget,x,y,width,height)
        local slot=parent:AddChildToCanvas(widget)
        slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=0,Y=0}})
        slot:SetAlignment({X=0,Y=0}); slot:SetAutoSize(false)
        slot:SetPosition({X=x,Y=y}); slot:SetSize({X=width,Y=height})
        slot:SetZOrder(1)
        return slot
    end
    local function label(value,x,y,width,size)
        local widget=construct("TextBlock")
        widget:SetText(FText(value)); widget:SetJustification(1)
        local font=widget.Font; font.Size=size; widget:SetFont(font)
        return {widget=widget,slot=place(ui.panel,widget,x,y,width,24),width=width,y=y}
    end
    local ok,err=pcall(function()
        ui.panel=construct("CanvasPanel")
        local slot=place(root,ui.panel,-310,12,620,72)
        slot:SetAnchors({Minimum={X=0.5,Y=0},Maximum={X=0.5,Y=0}})
        slot:SetZOrder(20000)
        ui.panel:SetClipping(1) -- scrolling labels clip at the strip edges
        local texture=StaticFindObject("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")
        if valid(texture) then
            local background=construct("Image")
            background:SetBrushFromTexture(texture,false)
            background:SetColorAndOpacity({R=0.015,G=0.025,B=0.04,A=0.55})
            place(ui.panel,background,0,0,620,72):SetZOrder(0)
        end
        for angle=0,345,15 do
            local value=angle%45==0 and directions[angle/45+1] or tostring(angle)
            local tick=label(value,0,7,58,angle%45==0 and 20 or 13)
            tick.angle=angle; ui.ticks[#ui.ticks+1]=tick
        end
        ui.center=label("|",293,0,34,24)
        ui.bearing=label("",220,31,180,16)
        for index=1,32 do
            if valid(texture) then
                -- Draw a diamond from the engine texture rather than relying
                -- on the default font containing a particular symbol glyph.
                local marker=construct("Image")
                marker:SetBrushFromTexture(texture,false)
                marker:SetColorAndOpacity({R=1,G=0.78,B=0.2,A=1})
                marker:SetRenderTransformAngle(45)
                ui.markers[index]={widget=marker,slot=place(ui.panel,marker,0,53,10,10),width=10,y=53,fallbackTexture=texture}
            else ui.markers[index]=label("+",0,48,24,17) end
        end
        ui.map=navigation.mapFor(root)
    end)
    if not ok then ui:destroy(); error(err) end
    local function move(entry,center)
        local x=center-entry.width/2
        if not entry.x or math.abs(entry.x-x)>=0.25 then
            entry.slot:SetPosition({X=x,Y=entry.y}); entry.x=x
        end
    end
    local function show(entry,visible)
        if entry.visible~=visible then
            entry.widget:SetVisibility(visible and 3 or 1); entry.visible=visible
        end
    end
    local function artwork(marker,target)
        local source=target and target.iconSource
        if not valid(source) then source=nil end
        local id=target and target.iconId
        -- UE4SS may create a fresh Lua wrapper for the same native Image on
        -- every read. Compare its stable object path instead of wrapper identity.
        local sourceName=source and source:GetFullName()
        if marker.iconSourceName==sourceName and marker.iconId==id then return end
        marker.iconSourceName=sourceName; marker.iconId=id
        local copied=false
        if source and marker.fallbackTexture then
            local ok,err=pcall(function()
                -- SetBrush copies the native Slate brush immediately. Do not
                -- keep a borrowed brush struct across frames or world travel.
                marker.widget:SetBrush(source.Brush)
                marker.widget:SetColorAndOpacity({R=1,G=1,B=1,A=1})
                marker.widget:SetRenderTransformAngle(0)
                marker.slot:SetSize({X=24,Y=24})
                marker.width=24; marker.y=48; marker.x=nil
            end)
            copied=ok
            if ok then reporter("Compass pin icon copied: " .. source:GetFullName() .. ", icon=" .. tostring(id))
            elseif not marker.iconError then
                marker.iconError=true
                reporter("Compass pin icon copy skipped: " .. tostring(err))
            end
        end
        if not copied and marker.fallbackTexture then
            marker.widget:SetBrushFromTexture(marker.fallbackTexture,false)
            marker.widget:SetColorAndOpacity({R=1,G=0.78,B=0.2,A=1})
            marker.widget:SetRenderTransformAngle(45)
            marker.slot:SetSize({X=10,Y=10})
            marker.width=10; marker.y=53; marker.x=nil
        end
    end
    function ui:update(yaw,origin,points)
        local heading=navigation.heading(yaw)
        for _,tick in ipairs(self.ticks) do
            local relative=navigation.relative(heading,tick.angle)
            local visible=math.abs(relative)<=105
            show(tick,visible)
            if visible then move(tick,310+relative*3) end
        end
        local degree=math.floor(heading+0.5)%360
        if self.degree~=degree then
            self.bearing.widget:SetText(FText(navigation.direction(heading) .. "  " .. degree .. "°"))
            self.degree=degree
        end
        for index,marker in ipairs(self.markers) do
            local target=points[index]
            local visible=false
            if target then
                artwork(marker,target)
                local bearing=navigation.destination(origin,target)
                local relative=navigation.relative(heading,bearing)
                visible=math.abs(relative)<=99
                if visible then move(marker,310+relative*3) end
            end
            show(marker,visible)
        end
    end
    return ui
end
return navigation
