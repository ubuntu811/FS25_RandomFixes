-- plain Lua: the hook round FSDensityMapUtil.updateRollerArea
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end

local rolled, cleared = {}, {}
FSDensityMapUtil = { updateRollerArea = function(sx, sz, wx, wz, hx, hz, angle) rolled[#rolled + 1] = { sx, hz, angle }; return 7 end }
DensityMapHeightUtil = { clearArea = function(sx, sz, wx, wz, hx, hz) cleared[#cleared + 1] = { sx, sz, wx, wz, hx, hz } end }
g_currentMission = { snowSystem = { height = 0 } }
dofile("scripts/SoilRollerSnow.lua")

check("no snow: the roller rolls, nothing is cleared", FSDensityMapUtil.updateRollerArea(1, 2, 3, 4, 5, 6, 0.5) == 7 and #rolled == 1 and #cleared == 0)
g_currentMission.snowSystem.height = 0.2
local result = FSDensityMapUtil.updateRollerArea(1, 2, 3, 4, 5, 6, 0.5)
check("snow: the game's own result comes back and the same area is cleared", result == 7 and #cleared == 1 and cleared[1][1] == 1 and cleared[1][6] == 6)
check("the angle still reaches the original", rolled[2][3] == 0.5)
SoilRollerSnow.ENABLED = false
FSDensityMapUtil.updateRollerArea(1, 2, 3, 4, 5, 6, 0)
check("switched off: nothing is cleared", #cleared == 1)
SoilRollerSnow.ENABLED = true
g_currentMission = nil
check("no mission: no error, no clearing", FSDensityMapUtil.updateRollerArea(1, 2, 3, 4, 5, 6, 0) == 7 and #cleared == 1)
print(string.format("soil_roller_snow_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
