local preferences = {}
function preferences.load(config, path)
    local settings = {FOV=config.FOV, MouseSensitivity=config.MouseSensitivity, ThirdPerson=false, Crosshair=config.Crosshair ~= false, GraphicsPreset=config.GraphicsPreset or 1, InvertMouseY=config.InvertMouseY or false}
    local file = io.open(path, "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("^(%w+)%s*=%s*([%d%.%-]+)$")
            value = tonumber(value)
            if key == "FOV" and value and value >= 60 and value <= 130 then settings.FOV = value end
            if key == "MouseSensitivity" and value and value >= 0.05 and value <= 2 then settings.MouseSensitivity = value end
            if key == "ThirdPerson" and value then settings.ThirdPerson = value == 1 end
            if key == "Crosshair" and value then settings.Crosshair = value == 1 end
            if key == "GraphicsPreset" and value and value>=0 and value<=3 and value%1==0 then settings.GraphicsPreset=value end
            if key == "InvertMouseY" and value then settings.InvertMouseY=value==1 end
        end
        file:close()
    end
    function settings:save()
        local file, err = io.open(path, "w")
        if not file then return false, err end
        local ok, reason = file:write(string.format("FOV=%.1f\nMouseSensitivity=%.3f\nThirdPerson=%d\nCrosshair=%d\nGraphicsPreset=%d\nInvertMouseY=%d\n",
            self.FOV, self.MouseSensitivity, self.ThirdPerson and 1 or 0, self.Crosshair and 1 or 0,self.GraphicsPreset,self.InvertMouseY and 1 or 0))
        local closed, closeError = file:close()
        if not ok or not closed then return false, reason or closeError end
        return true
    end
    return settings
end
return preferences
