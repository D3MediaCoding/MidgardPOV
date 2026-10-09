-- Camera-local color grading. Console overrides are snapshotted and restored.
local graphics = {}
graphics.names = {[0]="Original", "Natural", "Atmospheric", "Vivid"}
local presets = {
    {saturation=1.12,contrast=1.06,gamma=1.02,bloom=0.35,vignette=0.08},
    {saturation=0.96,contrast=1.13,gamma=0.99,bloom=0.45,vignette=0.18},
    {saturation=1.23,contrast=1.07,gamma=1.03,bloom=0.45,vignette=0.08},
}
local function vector(value) return {X=value,Y=value,Z=value,W=1} end
function graphics.create(current, log)
    local tracker={saved={},component=current.cameraComponent}
    local library=current.systemLibrary
    -- Do not change an engine variable unless its original value is readable.
    local function capture(name, getter, desired)
        local ok,value=pcall(function() return library[getter](library,name) end)
        if ok and type(value)=="number" then
            tracker.saved[#tracker.saved+1]={name=name,value=value,desired=desired}
        else log("Graphics console override unavailable: " .. name) end
    end
    capture("r.Tonemapper.Sharpen","GetConsoleVariableFloatValue",0.35)
    capture("r.MaxAnisotropy","GetConsoleVariableIntValue",16)
    local function console(entry, value)
        local ok,err=pcall(function()
            library:ExecuteConsoleCommand(current.pawn,entry.name .. " " .. tostring(value),current.controller)
        end)
        if not ok then log("Graphics console command skipped: " .. tostring(err)) end
    end
    function tracker:restore()
        pcall(function() self.component.PostProcessBlendWeight=0 end)
        for _,entry in ipairs(self.saved) do console(entry,entry.value) end
    end
    function tracker:apply(mode)
        if mode==0 then self:restore(); return true end
        local preset=presets[mode]
        if not preset then return false end
        local ok,err=pcall(function()
            local pp=self.component.PostProcessSettings
            local function set(key,value)
                pp["bOverride_" .. key]=true
                pp[key]=value
            end
            set("ColorSaturation",vector(preset.saturation))
            set("ColorContrast",vector(preset.contrast))
            set("ColorGamma",vector(preset.gamma))
            set("BloomIntensity",preset.bloom)
            set("VignetteIntensity",preset.vignette)
            set("MotionBlurAmount",0)
            set("SceneFringeIntensity",0)
            set("GrainIntensity",0)
            self.component.PostProcessBlendWeight=1
        end)
        if not ok then
            self:restore()
            log("Graphics preset unavailable; camera retained: " .. tostring(err))
            return false
        end
        for _,entry in ipairs(self.saved) do console(entry,entry.desired) end
        log("Graphics preset: " .. graphics.names[mode] .. ". F11 cycles looks, including Original.")
        return true
    end
    return tracker
end
return graphics
