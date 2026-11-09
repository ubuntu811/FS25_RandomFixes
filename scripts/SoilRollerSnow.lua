--[[
    SoilRollerSnow.lua -- the soil roller does not clear snow, the cultivator, the disc harrow, direct sowing, the mulcher and the grass roller do.

    Snow is a layer of the density map's height system. Those tools end their work-area update with DensityMapHeightUtil.clearArea, which wipes the height layer of the area (snow included).
    FSDensityMapUtil.updateRollerArea (what Roller.lua calls for a soil roller) never does: it sets the ground to rolled seedbed and leaves the snow on top, so a roller you cannot even lift
    drives through white ground. Here the roller does what the cultivator does, but only while there is snow on the map (a roller then keeps what lies on the ground, as before).
    It is deliberately not SnowSystem:removeSnow (what wheels use: it presses ruts that come back).
]]
SoilRollerSnow = {}
SoilRollerSnow.ENABLED = true

function SoilRollerSnow.hasSnow()
    local snowSystem = g_currentMission ~= nil and g_currentMission.snowSystem or nil
    return snowSystem ~= nil and (snowSystem.height or 0) > 0
end

if FSDensityMapUtil ~= nil and FSDensityMapUtil.updateRollerArea ~= nil and DensityMapHeightUtil ~= nil and not SoilRollerSnow.hooked then
    SoilRollerSnow.hooked = true
    local original = FSDensityMapUtil.updateRollerArea
    FSDensityMapUtil.updateRollerArea = function(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, ...)
        local result = original(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, ...)
        if SoilRollerSnow.ENABLED and SoilRollerSnow.hasSnow() then
            DensityMapHeightUtil.clearArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
        end
        return result
    end
    print("[RandomFixes] soil roller: clears the snow it rolls over, like the cultivator")
end
