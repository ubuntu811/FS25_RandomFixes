-- plain Lua with a fake frame: the vehicles list selects the vehicle the player is in
local passed, failed = 0, 0
local realPrint = print
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end
local log = {}
print = function(text) log[#log + 1] = text end
Utils = { appendedFunction = function(old, new) return function(...) local r = old(...); new(...); return r end end }
InGameMenuStatisticsFrame = { onFrameOpen = function() end }
dofile("scripts/SelectOwnVehicle.lua")

local mower, tractor, sprayer = { name = "mower" }, { name = "tractor" }, { name = "sprayer" }
local function frame()
    local selected
    local f = { vehicles = { { vehicle = mower }, { vehicle = sprayer }, { vehicle = tractor } } }
    f.vehiclesList = { setSelectedItem = function(self, section, index, scroll) selected = { section, index, scroll } end }
    f.selected = function() return selected end
    return f
end

g_localPlayer = { getCurrentVehicle = function() return tractor end }
local f = frame()
InGameMenuStatisticsFrame.onFrameOpen(f)
check("opening the list selects the vehicle the player is in (third row), scrolled to", f.selected() ~= nil and f.selected()[1] == 1 and f.selected()[2] == 3 and f.selected()[3] == true)

g_localPlayer = { getCurrentVehicle = function() return nil end }
f = frame()
InGameMenuStatisticsFrame.onFrameOpen(f)
check("on foot: nothing is selected, the list stays as it was", f.selected() == nil)

g_localPlayer = { getCurrentVehicle = function() return { name = "not in the list" } end }
f = frame()
InGameMenuStatisticsFrame.onFrameOpen(f)
check("a vehicle that is not listed (another farm's, hidden): nothing is selected", f.selected() == nil)

g_localPlayer = nil
f = frame()
InGameMenuStatisticsFrame.onFrameOpen(f)
check("no local player: nothing happens and nothing breaks", f.selected() == nil)

g_localPlayer = { getCurrentVehicle = function() return tractor end }
f = frame()
f.vehiclesList.setSelectedItem = function() error("boom") end
InGameMenuStatisticsFrame.onFrameOpen(f)
check("a list that does not fit: one line says so, nothing breaks", #log == 1 and log[1]:find("could not select", 1, true) ~= nil)

print = realPrint
print(string.format("select_own_vehicle_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
