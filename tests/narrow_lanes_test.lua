-- plain Lua: the lane-width filter and the wrapper round the base game's FieldCourseSettings.generate
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end
end
local function near(a, b) return math.abs(a - b) < 1e-9 end

AIModeSelection = { MODE = { WORKER = 1, STEERING_ASSIST = 2 } }
dofile("scripts/NarrowLanes.lua")
local N = NarrowLanes

local function implement(width, areaWidth)
    local object = { width = width, updates = 0 }
    object.updateAIMarkerWidth = function(self) self.updates = self.updates + 1 end
    object.getAIMarkers = function(self) return "l", "r", "b", false, self.width end
    object.getAIWorkAreaWidth = function() return areaWidth or 0 end
    return { object = object }
end

-- the filter
local mower, windrower, tedder = implement(3.0), implement(9.0), implement(3.02)
local kept = N.narrowest({ windrower, mower })
check("mower (3 m) and windrower (9 m): only the mower is planned for", #kept == 1 and kept[1] == mower)
kept = N.narrowest({ mower, tedder, windrower })
check("two implements within 5 cm of the smallest are both kept", #kept == 2 and kept[1] == mower and kept[2] == tedder)
local single = { mower }
check("one implement: the list is returned as it is", N.narrowest(single) == single)
local noWidth = implement(nil)
kept = N.narrowest({ windrower, noWidth, mower })
check("an implement with no width at all is left in the list (as the game would treat it)", #kept == 2 and kept[1] == noWidth and kept[2] == mower)
local allNone = { implement(nil), implement(0) }
check("none with a width: unchanged", N.narrowest(allNone) == allNone)
check("the marker width is refreshed before it is read", mower.object.updates > 0)

-- the wrapper
local seen = nil
local original = function(root, settings)
    seen = root:getAttachedAIImplements()
    return { marker = "settings", count = #seen }, "data"
end
local vehicle = { attached = { windrower, mower } }
vehicle.getAttachedAIImplements = function(self) return self.attached end
vehicle.mode = AIModeSelection.MODE.STEERING_ASSIST
vehicle.getAIModeSelection = function(self) return self.mode end
local settings, data = N.generate(original, vehicle, nil)
check("generate: the base planner saw only the narrowest implement", seen ~= nil and #seen == 1 and seen[1] == mower)
check("... its results are passed back unchanged (both return values)", settings.count == 1 and data == "data")
check("... and the vehicle reports all its implements again afterwards", #vehicle:getAttachedAIImplements() == 2)
vehicle.getAttachedAIImplements = function(self) return self.attached end
local exploding = function() error("boom") end
local ok, err = pcall(N.generate, exploding, vehicle, nil)
check("an error inside the planner is passed on, and the vehicle is restored anyway", ok == false and tostring(err):find("boom") ~= nil and #vehicle:getAttachedAIImplements() == 2)
N.ENABLED = false
vehicle.getAttachedAIImplements = function(self) return self.attached end
N.generate(original, vehicle, nil)
check("switched off: the game's own list", #seen == 2)
N.ENABLED = true
local noImplements = { getAttachedAIImplements = function() return {} end, getAIModeSelection = function() return AIModeSelection.MODE.STEERING_ASSIST end }
N.generate(function(root) seen = root:getAttachedAIImplements() return {}, {} end, noImplements, nil)
check("no implements at all: nothing to filter, no error", #seen == 0)


-- the AI helper (worker mode) plans its lanes with the same function: it gets the narrow lanes too
vehicle.getAttachedAIImplements = function(self) return self.attached end
vehicle.mode = AIModeSelection.MODE.WORKER
N.generate(original, vehicle, nil)
check("worker mode (the AI helper): only the narrowest as well", #seen == 1)
vehicle.getAIModeSelection = nil
N.generate(original, vehicle, nil)
check("the mode is not read at all: same result", #seen == 1)


-- the planner's second result (implementData) is indexed by the vehicle's own implement list by the AI helper's strategy: it must have an entry for every implement
local function planner(root)
    local list = root:getAttachedAIImplements()
    local data = {}
    for i, implement in ipairs(list) do data[i] = { width = implement.object.width, isLowered = true } end
    return { count = #list }, data
end
vehicle.mode = AIModeSelection.MODE.STEERING_ASSIST
vehicle.attached = { windrower, mower }
vehicle.getAttachedAIImplements = function(self) return self.attached end
local s2, d2 = N.generate(planner, vehicle, nil)
check("the planner saw one implement, but implementData has an entry for each of the vehicle's two", s2.count == 1 and #d2 == 2 and d2[1] ~= nil and d2[2] ~= nil)
check("... the kept implement's entry is its own (index 2 = mower, width 3), the dropped one gets a copy that is not lowered", d2[2].width == 3.0 and d2[2].isLowered == true and d2[1].isLowered == false)
vehicle.getIsAIActive = function() return true end
s2, d2 = N.generate(planner, vehicle, nil)
check("an AI helper running on the vehicle: narrow lanes, and a complete implementData for its strategy", s2.count == 1 and #d2 == 2 and d2[1] ~= nil and d2[2] ~= nil)
local parent = { isLowered = false }
local planner3 = function(root)
    local list = root:getAttachedAIImplements()
    return {}, { { width = 3.0, isLowered = true, parentAIImplement = parent } }
end
local _, d3 = N.generate(planner3, vehicle, nil)
check("the copy made for the dropped implement has no parent link (it cannot lower somebody else's parent)", d3[1].parentAIImplement == nil and d3[2].parentAIImplement == parent)
vehicle.getIsAIActive = nil

-- the width the assist compares
local root = { childVehicles = {
    { },                                                     -- the tractor: no markers, no work area
    { width = 9.0, getAIMarkers = windrower.object.getAIMarkers, updateAIMarkerWidth = function() end, getAIWorkAreaWidth = function() return 8.5 end },
    { width = 3.0, getAIMarkers = mower.object.getAIMarkers, updateAIMarkerWidth = function() end, getAIWorkAreaWidth = function() return 2.8 end },
} }
check("the working width the assist compares with is the narrowest (a vehicle counts by its larger own width: 3.0)", near(N.narrowestWorkingWidth(root), 3.0))
check("a rig with no work widths at all: 0 (the game's own answer)", N.narrowestWorkingWidth({ childVehicles = { {} } }) == 0)

print(string.format("narrow_lanes_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
