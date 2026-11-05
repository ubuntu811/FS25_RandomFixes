--[[
    SelectOwnVehicle.lua -- the vehicles list of the menu (Vehicles tab) opens with the machine you are sitting in selected, not the
    first one of the alphabet. On foot nothing changes. Read from the game's own InGameMenuStatisticsFrame: onFrameOpen fills the list
    (updateVehicles, then the sort), each item keeps its vehicle; the list is a SmoothListElement (setSelectedItem(section, index, forceScroll)
    is what the game itself calls). Everything in a pcall: if it does not fit, the list stays as it was.
]]
SelectOwnVehicle = {}

-- The list index of the vehicle the player is in (or of the vehicle that carries it), nil when on foot or not in the list.
function SelectOwnVehicle.indexOf(frame)
    local player = g_localPlayer
    local current = player ~= nil and player.getCurrentVehicle ~= nil and player:getCurrentVehicle() or nil
    if current == nil then
        return nil
    end
    for index, item in ipairs(frame.vehicles or {}) do
        if item.vehicle == current then
            return index
        end
    end
    return nil
end

function SelectOwnVehicle.select(frame)
    local ok, err = pcall(function()
        local index = SelectOwnVehicle.indexOf(frame)
        if index ~= nil and frame.vehiclesList ~= nil then
            frame.vehiclesList:setSelectedItem(1, index, true)
        end
    end)
    if not ok then
        print(string.format("[RandomFixes] the vehicles list could not select your vehicle (%s)", tostring(err)))
    end
end

if InGameMenuStatisticsFrame ~= nil and not SelectOwnVehicle.hooked then
    SelectOwnVehicle.hooked = true
    InGameMenuStatisticsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuStatisticsFrame.onFrameOpen, function(self)
        SelectOwnVehicle.select(self)
    end)
end
