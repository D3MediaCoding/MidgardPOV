-- Changes are confined to components owned by the local pawn. Never hide torso
-- or weapon components merely because their names happen to contain 'head'.
local appearance = {}
local function valid(object) return object and object:IsValid() end
local function ownedBy(object, pawn)
    local actor = object:GetOwner()
    for _ = 1, 8 do
        if not valid(actor) then return false end
        if actor == pawn then return true end
        actor = actor:GetOwner()
    end
    return false
end
local function headBone(mesh, candidates)
    for _, candidate in ipairs(candidates) do
        local bone = FName(candidate)
        if mesh:GetBoneIndex(bone) >= 0 then return bone end
    end
    local count = math.min(mesh:GetNumBones(), 512)
    for index = 0, count-1 do
        local bone = mesh:GetBoneName(index)
        local lower = bone:ToString():lower()
        if lower == "head" or lower:match("[_%s%.]head$") then return bone end
    end
end
function appearance.create(pawn, config, log)
    local tracker = {bones={}, attachments={}, seen={}, hiding=false}
    function tracker:consider(mesh, kind)
        if kind == "skeletal" then
            if valid(mesh) and ownedBy(mesh, pawn) then
                local address = mesh:GetFullName()
                if not self.seen[address] then
                    local bone = headBone(mesh, config.HeadBones)
                    if bone then
                        local entry = {mesh=mesh, bone=bone, hidden=mesh:IsBoneHiddenByName(bone)}
                        table.insert(self.bones, entry)
                        self.seen[address] = true
                        if self.hiding and not entry.hidden then mesh:HideBoneByName(bone, 0) end
                        log("Head bone: " .. bone:ToString() .. " on " .. address)
                    end
                end
            end
        else
        -- Head-mounted rigid hair/helmets may not share the skeletal skin.
        local component = mesh
            if valid(component) and ownedBy(component, pawn) then
                local address = component:GetFullName()
                if not self.seen[address] then
                    local parent = component:GetAttachParent()
                    local socket = component:GetAttachSocketName()
                    if valid(parent) then
                        -- Not every attachment parent is skeletal.
                        local ok, resolved = pcall(function() return parent:GetSocketBoneName(socket) end)
                        if ok then
                            for _, entry in ipairs(self.bones) do
                                if parent == entry.mesh and resolved == entry.bone then
                                    local attachment = {component=component, hidden=component.bHiddenInGame}
                                    table.insert(self.attachments, attachment)
                                    self.seen[address] = true
                                    if self.hiding then component:SetHiddenInGame(true, false) end
                                    log("Head attachment: " .. address)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    function tracker:discover()
        -- One initial scan; streaming notifications use consider instead.
        for _, mesh in ipairs(FindAllOf("SkeletalMeshComponent") or {}) do self:consider(mesh, "skeletal") end
        for _, mesh in ipairs(FindAllOf("StaticMeshComponent") or {}) do self:consider(mesh, "static") end
    end
    function tracker:setHidden(hidden)
        self.hiding = hidden
        for _, entry in ipairs(self.bones) do
            if valid(entry.mesh) then
                if hidden or entry.hidden then entry.mesh:HideBoneByName(entry.bone, 0)
                else entry.mesh:UnHideBoneByName(entry.bone) end
            end
        end
        for _, entry in ipairs(self.attachments) do
            if valid(entry.component) then entry.component:SetHiddenInGame(hidden or entry.hidden, false) end
        end
    end
    function tracker:restore() self:setHidden(false) end
    return tracker
end
return appearance
