-- plain Lua: the island rule and the hooks round FieldCourseField.finishTask and the field-creating tools' AI requirements
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end
end
Utils = {
    prependedFunction = function(old, new) return function(...) new(...); return old(...) end end,
    appendedFunction = function(old, new) return function(...) local r = old(...); new(...); return r end end,
    overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end,
}
local allowedNow = true
g_currentMission = { getHasPlayerPermission = function(self, permission, connection) return permission == "createFields" and allowedNow end }
local finished = {}
local detected = {}
FieldCourseField = {
    finishTask = function(self, success) finished[#finished + 1] = { success = success, islands = self.islandBoundaries } end,
    detectAtPosition = function(self, x, z, callback) detected[#detected + 1] = { x = x, z = z, field = self } end,
}
AIImplement = { onPostLoad = function(self) end }
local courseLoaded = {}
AIDriveStrategyFieldCourse = { onFieldCourseLoadedCallback = function(self, fieldCourse) courseLoaded[#courseLoaded + 1] = fieldCourse end }
local registered = {}
addConsoleCommand = function(name, help, method, target) registered[name] = { method = method, target = target } end
local realPrint, lines = print, {}
print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
dofile("scripts/OutlineFields.lua")
print = realPrint
local O = OutlineFields

local function rect(x0, z0, x1, z1) return { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } } end
local outer = rect(0, 0, 200, 200)                      -- a 200 x 200 m field, 4 ha

check("hooked, and it says so", #lines == 1 and lines[1]:find("outline field", 1, true) ~= nil)
check("polygon area", math.abs(O.polygonArea(outer) - 40000) < 1e-6 and math.abs(O.polygonArea({ { 0, 0 }, { 10, 0 }, { 0, 10 } }) - 50) < 1e-6)
check("distance to a polyline", math.abs(O.distanceToLine(100, 3, outer) - 3) < 1e-6 and math.abs(O.distanceToLine(100, 100, outer) - 100) < 1e-6)

-- the islands
check("the inside of a plowed outline (a ring 8 m wide round the field): a hole to be filled", O.isOutlineHole(outer, rect(8, 8, 192, 192)))
check("... a ring 20 m wide too", O.isOutlineHole(outer, rect(20, 20, 180, 180)))
check("a pond (20 x 20 m) in the middle of the field stays an island", not O.isOutlineHole(outer, rect(90, 90, 110, 110)))
check("a big island far from the boundary (a 120 x 120 m patch in the middle: a ring 40 m wide) stays", not O.isOutlineHole(outer, rect(40, 40, 160, 160)))
check("a lake along one edge (150 x 20 m, big enough? 7.5% of the field): too small, stays", not O.isOutlineHole(outer, rect(25, 5, 175, 25)))
check("a large island along one side only (190 x 60 m = 28%): not all round the boundary, stays", not O.isOutlineHole(outer, rect(5, 5, 195, 65)))
-- spurs plowed into the hole (the helper's first try left one 38 m long): notches, not a different hole
local function holeWithLegs(w, h, ring, legs)
    local x0, z0, x1, z1 = ring, ring, w - ring, h - ring
    local pts = { { x0, z0 }, { x1, z0 }, { x1, z1 } }
    local cx = (x0 + x1) / 2
    for _, leg in ipairs(legs) do          -- legs from the bottom edge (z1) up into the hole: { x of the middle, length }
        pts[#pts + 1] = { leg[1] + 4, z1 }
        pts[#pts + 1] = { leg[1] + 4, z1 - leg[2] }
        pts[#pts + 1] = { leg[1] - 4, z1 - leg[2] }
        pts[#pts + 1] = { leg[1] - 4, z1 }
    end
    pts[#pts + 1] = { x0, z1 }
    return pts
end
local small = { { 0, 0 }, { 220, 0 }, { 220, 100 }, { 0, 100 } }
local allLegs = true
for _, length in ipairs({ 0, 20, 40, 60, 80, 120, 160 }) do
    if length < 100 - 16 and not O.isOutlineHole(small, holeWithLegs(220, 100, 8, { { 110, length } })) then allLegs = false end
end
check("a 220 x 100 m field, a spur of any length (up to 76 m, as far as the hole goes) plowed into the hole: still an outline hole (the hull ignores the notch)", allLegs)
check("... three spurs", O.isOutlineHole(small, holeWithLegs(220, 100, 8, { { 50, 40 }, { 110, 60 }, { 170, 30 } })))
check("a C-shaped lake along three sides of a field (a hull like a ring, but half empty): not a hole", not O.isOutlineHole(outer, { { 5, 5 }, { 195, 5 }, { 195, 40 }, { 40, 40 }, { 40, 160 }, { 195, 160 }, { 195, 195 }, { 5, 195 } }))
local hull = O.convexHull({ { 0, 0 }, { 4, 0 }, { 4, 4 }, { 2, 1 }, { 0, 4 }, { 2, 2 } })
check("the convex hull of a notched square is the square", #hull == 4 and math.abs(O.polygonArea(hull) - 16) < 1e-9)
check("point in polygon", O.pointInPolygon(5, 5, rect(0, 0, 10, 10)) and not O.pointInPolygon(15, 5, rect(0, 0, 10, 10)) and not O.pointInPolygon(5, 5, { { 0, 0 }, { 10, 0 }, { 10, 10 }, { 6, 10 }, { 6, 4 }, { 4, 4 }, { 4, 10 }, { 0, 10 } }))
check("odd input: no island, no outer boundary, too few points: not a hole, no error", not O.isOutlineHole(nil, outer) and not O.isOutlineHole(outer, nil) and not O.isOutlineHole(outer, { { 0, 0 }, { 1, 1 } }))

-- the hook on finishTask
local function fieldWith(islands) return { fieldRootBoundary = { boundaryLine = outer }, islandBoundaries = islands } end
local ring, pond = { boundaryLine = rect(8, 8, 192, 192) }, { boundaryLine = rect(90, 90, 110, 110) }
local f = fieldWith({ ring, pond })
FieldCourseField.finishTask(f, true)
check("finishTask: the ring's hole is dropped before the game builds field.islands, the pond stays, the original still runs", #finished == 1 and #finished[1].islands == 1 and finished[1].islands[1] == pond)
f = fieldWith({ ring })
FieldCourseField.finishTask(f, false)
check("a failed detection: nothing touched", finished[2].success == false and #finished[2].islands == 1)
allowedNow = false
f = fieldWith({ ring })
FieldCourseField.finishTask(f, true)
check("without the createFields permission: the game's own islands", #finished[3].islands == 1)
allowedNow = true
O.ENABLED = false
f = fieldWith({ ring })
FieldCourseField.finishTask(f, true)
check("switched off (OutlineFields.ENABLED = false): the game's own islands", #finished[4].islands == 1)
O.ENABLED = true
check("no islands / no boundary: no error", pcall(FieldCourseField.finishTask, { islandBoundaries = nil }, true) and pcall(FieldCourseField.finishTask, { islandBoundaries = { ring } }, true))

-- the tools
local function vehicle(kind)
    local v = { spec_aiImplement = { terrainDetailRequiredValueRanges = {}, groundTypeFirstChannel = 4, groundTypeNumChannels = 5 }, queries = 0 }
    v["spec_" .. kind] = {}
    v.getOwnerConnection = function() return nil end
    v.updateFieldCropsQuery = function(self) self.queries = self.queries + 1 end
    -- what the game does: clear, then add the ground types the tool can work (value, value, first channel, number of channels)
    v.clearAITerrainDetailRequiredRange = function(self) self.spec_aiImplement.terrainDetailRequiredValueRanges = {} end
    v.addAIGroundTypeRequirements = function(self, types)
        for _, t in ipairs(types) do table.insert(self.spec_aiImplement.terrainDetailRequiredValueRanges, { t, t, 4, 5 }) end
        self:updateFieldCropsQuery()
    end
    return v
end
local function hasZero(v) for _, r in ipairs(v.spec_aiImplement.terrainDetailRequiredValueRanges) do if r[1] == 0 and r[2] == 0 then return true end end return false end
local plow = vehicle("plow")
plow:addAIGroundTypeRequirements({ 3, 8, 14 })
AIImplement.onPostLoad(plow)
check("a plow after loading: ground type 0 (not a field yet) counts as workable, next to the game's own ground types", hasZero(plow) and #plow.spec_aiImplement.terrainDetailRequiredValueRanges == 4)
check("... in the channels of the ground type map (first channel 4, 5 channels)", (function() for _, r in ipairs(plow.spec_aiImplement.terrainDetailRequiredValueRanges) do if r[1] == 0 then return r[3] == 4 and r[4] == 5 end end end)())
plow:clearAITerrainDetailRequiredRange()
check("the game clears the requirements ...", not hasZero(plow))
plow:addAIGroundTypeRequirements({ 3, 8 })
check("... and adds its own again: 0 is added again too (and only once)", hasZero(plow) and #plow.spec_aiImplement.terrainDetailRequiredValueRanges == 3)
plow:addAIGroundTypeRequirements({ 3 })
local zeros = 0
for _, r in ipairs(plow.spec_aiImplement.terrainDetailRequiredValueRanges) do if r[1] == 0 then zeros = zeros + 1 end end
check("... never twice", zeros == 1)
check("the tool's field crops query is made again after 0 is added", plow.queries >= 2)
local sprayer = vehicle("sprayer")
sprayer:addAIGroundTypeRequirements({ 3 })
AIImplement.onPostLoad(sprayer)
check("an implement that does not create fields (a sprayer): left alone", not hasZero(sprayer))
local cultivator = vehicle("cultivator")
cultivator:addAIGroundTypeRequirements({ 3, 4 })
AIImplement.onPostLoad(cultivator)
check("a cultivator (it creates fields too): 0 counts", hasZero(cultivator))
allowedNow = false
local noPermission = vehicle("plow")
noPermission:addAIGroundTypeRequirements({ 3 })
AIImplement.onPostLoad(noPermission)
check("without the createFields permission: the game's own requirements", not hasZero(noPermission))
allowedNow = true
local emptyPlow = vehicle("plow")
AIImplement.onPostLoad(emptyPlow)
check("a tool with no requirements of its own yet: 0 is not added alone (it would make everything workable)", not hasZero(emptyPlow))
check("a vehicle without the AI implement table: no error", pcall(O.hookVehicle, { spec_plow = {} }) and pcall(O.hookVehicle, nil))

-- a field whose outline was filled is marked, and the helper's tools create fields for that job
f = fieldWith({ ring, pond })
FieldCourseField.finishTask(f, true)
check("a field whose outline hole was dropped is marked (rfFilledOutline)", f.rfFilledOutline == true)
f = fieldWith({ pond })
FieldCourseField.finishTask(f, true)
check("a field with nothing dropped is not", f.rfFilledOutline == nil)

local function tool(kind, limit)
    local t = vehicle(kind)
    t.limit = limit
    t.aiActive = true
    t.getIsAIActive = function(self) return self.aiActive end
    t.getCultivatorLimitToField = function(self) return self.limit end
    t.getPlowLimitToField = function(self) return self.limit end
    return t
end
local plowTool, cultTool, spray = tool("plow", true), tool("cultivator", true), tool("sprayer", true)
for _, t in ipairs({ plowTool, cultTool, spray }) do t:addAIGroundTypeRequirements({ 3 }); AIImplement.onPostLoad(t) end
local rig = { getAttachedAIImplements = function() return { { object = plowTool }, { object = cultTool }, { object = spray } } end }
local strategy = { vehicle = rig }
local filled = { fieldCourse = { courseField = { rfFilledOutline = true } } }            -- (an AIFieldCourse wrapping the course)
check("before the helper: the tools keep the player's 'limit to field' (on)", plowTool:getPlowLimitToField() == true and cultTool:getCultivatorLimitToField() == true)
AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback(strategy, filled)
check("the helper's course fills an outline: the plow and the cultivator create fields now (limit to field: off), the sprayer is not touched",
    plowTool:getPlowLimitToField() == false and cultTool:getCultivatorLimitToField() == false and spray.rfCreateFields == nil and #courseLoaded == 1)
check("... a bare FieldCourse (no wrapper) works too", (function()
    local p2 = tool("plow", true); p2:addAIGroundTypeRequirements({ 3 }); AIImplement.onPostLoad(p2)
    local s2 = { vehicle = { getAttachedAIImplements = function() return { { object = p2 } } end } }
    AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback(s2, { courseField = { rfFilledOutline = true } })
    return p2:getPlowLimitToField() == false
end)())
plowTool.aiActive, cultTool.aiActive = false, false
check("the helper has stopped: the player's own setting is back (on), and the flag is gone", plowTool:getPlowLimitToField() == true and plowTool.rfCreateFields == nil and cultTool:getCultivatorLimitToField() == true)
plowTool.aiActive = true
check("a later helper job on an ordinary course does not create fields", plowTool:getPlowLimitToField() == true)
plowTool.limit = false
check("the player's own setting 'off' is respected after the job too", plowTool:getPlowLimitToField() == false)
local ordinary = tool("plow", true); ordinary:addAIGroundTypeRequirements({ 3 }); AIImplement.onPostLoad(ordinary)
AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback({ vehicle = { getAttachedAIImplements = function() return { { object = ordinary } } end } }, { courseField = {} })
check("an ordinary course (no outline filled): nothing is switched", ordinary:getPlowLimitToField() == true and ordinary.rfCreateFields == nil)
allowedNow = false
local noPerm = tool("plow", true); allowedNow = true; noPerm:addAIGroundTypeRequirements({ 3 }); AIImplement.onPostLoad(noPerm); allowedNow = false
AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback({ vehicle = { getAttachedAIImplements = function() return { { object = noPerm } } end } }, filled)
check("without the createFields permission: not switched", noPerm.rfCreateFields == nil)
allowedNow = true
check("odd input (no course, no vehicle): no error", pcall(O.onCourseLoaded, nil, nil) and pcall(O.onCourseLoaded, {}, filled) and pcall(O.onCourseLoaded, strategy, nil))

-- standing on the grass INSIDE the outline: the game finds no field there; the nearest field ground is used, and only a hole that holds the start point counts
local groundType = {}                                       -- by 1 m cell: > 0 = field (the plowed ring: the frame of a 200 x 200 m square, 8 m wide)
for gx = 0, 199 do
    for gz = 0, 199 do
        if gx < 8 or gx >= 192 or gz < 8 or gz >= 192 then groundType[gx .. "," .. gz] = 5 end
    end
end
FieldDensityMap = { GROUND_TYPE = 1 }
g_currentMission.fieldGroundSystem = { getValueAtWorldPos = function(self, level, x, y, z) return groundType[math.floor(x) .. "," .. math.floor(z)] or 0 end }
g_fieldCourseManager = { roundToTerrainDetailPixel = function(self, x, z) return math.floor(x) + 0.5, math.floor(z) + 0.5 end }
check("the ground type map: the ring is field, the inside and the outside are not", O.isFieldAt(3, 100) and not O.isFieldAt(100, 100) and not O.isFieldAt(-20, 100))
local nx, nz = O.nearestField(100, 100)
check("the nearest field ground to the middle of the meadow is on the ring", nx ~= nil and (nx < 8 or nx >= 192 or nz < 8 or nz >= 192))
local cx, cz = O.nearestField(150, 100)
check("... from 42 m off the east side: the east side of the ring", cx ~= nil and cx >= 191 and math.abs(cz - 100) < 12)
check("... from far outside the search range: none", O.nearestField(5000, 5000) == nil)
detected = {}
local inside = fieldWith({ ring })
FieldCourseField.detectAtPosition(inside, 100.5, 100.5, function() end)
check("detection started on the grass inside: it is made from field ground (a ring pixel), the original start remembered",
    #detected == 1 and O.isFieldAt(detected[1].x, detected[1].z) and inside.rfInsideStart ~= nil and inside.rfInsideStart[1] == 100.5)
local before = #finished
FieldCourseField.finishTask(inside, true)
check("... finished: the hole that holds the start point is dropped and the detection stands", finished[#finished].success == true and #finished[#finished].islands == 0 and #finished == before + 1)
local outside = fieldWith({ ring })
detected = {}
FieldCourseField.detectAtPosition(outside, 100.5, 100.5, function() end)
outside.rfInsideStart = { 300, 300 }                      -- (a start point that is in no hole)
FieldCourseField.finishTask(outside, true)
check("a start point that is not inside a dropped hole (some other field's ground was found near it): it fails as the game would", finished[#finished].success == false)
detected = {}
local onRing = fieldWith({ ring })
FieldCourseField.detectAtPosition(onRing, 3.5, 100.5, function() end)
check("started on the ring (a field): nothing changes, the original coordinates", detected[1].x == 3.5 and detected[1].z == 100.5 and onRing.rfInsideStart == nil)
FieldCourseField.finishTask(onRing, true)
check("... and the island is dropped as before", finished[#finished].success == true and #finished[#finished].islands == 0)
allowedNow = false
detected = {}
local noPermission2 = fieldWith({ ring })
FieldCourseField.detectAtPosition(noPermission2, 100.5, 100.5, function() end)
check("without the createFields permission: started where the player is, as the game does", detected[1].x == 100.5 and noPermission2.rfInsideStart == nil)
allowedNow = true
detected = {}
local nothing = fieldWith({})
FieldCourseField.detectAtPosition(nothing, 5000.5, 5000.5, function() end)
check("no field ground anywhere near: the original start point (the game says 'no field' as before)", detected[1].x == 5000.5 and nothing.rfInsideStart == nil)
g_currentMission.fieldGroundSystem = nil
check("no ground type map known: nothing is interfered with", O.isFieldAt(100, 100) == true and (function() local d = fieldWith({}); detected = {}; FieldCourseField.detectAtPosition(d, 100.5, 100.5); return detected[1].x == 100.5 end)())

-- ===== a field that is part plowed: the hole left is judged by what is in it =====
local pondRect = nil                                        -- { x0, z0, x1, z1 }: water in there; set by the tests
local objects = {}                                          -- extra things: { x0, z0, x1, z1, flag, height }
CollisionFlag = { BUILDING = 1, STATIC_OBJECT = 2, WATER = 4, getHasGroupFlagSet = function(node, flag) return node == flag end }
bit32 = { bor = function(a, b) return a + b end }
g_terrainNode = 1
getTerrainHeightAtWorldPos = function() return 0 end
raycastClosest = function(x, y, z, dx, dy, dz, length, callback, target, mask)
    for _, o in ipairs(objects) do
        if x >= o[1] and x <= o[3] and z >= o[2] and z <= o[4] then
            target[callback](target, o[5], x, o[6], z)           -- hit node = the flag, the hit's y = its height above the (flat) terrain
            return
        end
    end
end
local function put(x0, z0, x1, z1, flag, height) objects[#objects + 1] = { x0, z0, x1, z1, flag, height } end

check("obstacleAt: nothing there, a puddle (0.05 m of water), a low wall (1 m, a building), a shed (4 m), a bush (2 m), a tree (6 m)", (function()
    put(0, 0, 10, 10, CollisionFlag.WATER, 0.05); put(20, 0, 30, 10, CollisionFlag.BUILDING, 1.0); put(40, 0, 50, 10, CollisionFlag.BUILDING, 4.0)
    put(60, 0, 70, 10, CollisionFlag.STATIC_OBJECT, 2.0); put(80, 0, 90, 10, CollisionFlag.STATIC_OBJECT, 6.0); put(100, 0, 110, 10, CollisionFlag.WATER, 1.0)
    return O.obstacleAt(500, 500) == false and O.obstacleAt(5, 5) == false and O.obstacleAt(25, 5) == false and O.obstacleAt(45, 5) == true
        and O.obstacleAt(65, 5) == false and O.obstacleAt(85, 5) == true and O.obstacleAt(105, 5) == true
end)())
objects = {}
check("the grid inside a 100 x 100 m square: 8 m apart, 144 points; a hole in it (excluded) has none", (function()
    local sq = rect(0, 0, 100, 100)
    return #O.samplesInside(sq, 8, 400) == 144 and #O.samplesInside(sq, 8, 400, { rect(0, 0, 100, 100) }) == 0 and #O.samplesInside(sq, 8, 400, { rect(0, 0, 50, 100) }) == 72
end)())
check("a big polygon (1 km square): the step grows, at most the maximum number of points", #O.samplesInside(rect(0, 0, 1000, 1000), 8, 400) <= 400 + 80)

-- the field of the screenshot: 220 x 100 m, the left half plowed, the right half (the hole) still meadow
local fieldOuter = { { 0, 0 }, { 220, 0 }, { 220, 100 }, { 0, 100 } }
local rightHalf = rect(110, 8, 212, 92)
check("the hole of a half plowed field is not an outline hole any more (one side borders plowed ground) ...", not O.isOutlineHole(fieldOuter, rightHalf))
check("... but it is bare meadow: filled (the rays find nothing in it)", O.shouldFill(fieldOuter, rightHalf))
put(140, 30, 190, 70, CollisionFlag.WATER, 1.0)                    -- a pond that covers a third of the hole
local pondPlan = O.fillPlan(fieldOuter, rightHalf)
check("a pond in the hole (a third of it): the hole is filled, the pond becomes an island of its own", pondPlan ~= nil and #pondPlan.obstacles == 1)
local pondLine = pondPlan and pondPlan.obstacles[1]
check("... the carved island covers the pond (with a margin) and lies inside the hole", pondLine ~= nil and O.pointInPolygon(165, 50, pondLine) and (function()
    for _, v in ipairs(pondLine) do
        if not O.pointInPolygon(v[1], v[2], rightHalf) then return false end
    end
    return true
end)())
check("... wound like the island it replaces", pondLine ~= nil and (O.signedArea(pondLine) >= 0) == (O.signedArea(rightHalf) >= 0))
put(112, 12, 122, 22, CollisionFlag.STATIC_OBJECT, 8.0)
put(112, 78, 122, 88, CollisionFlag.STATIC_OBJECT, 8.0)
local twoPlan = O.fillPlan(fieldOuter, rightHalf)
check("a pond and two stands of trees far apart: three carved islands, the biggest first", twoPlan ~= nil and #twoPlan.obstacles == 3)
objects = {}
put(115, 10, 210, 90, CollisionFlag.WATER, 1.0)
check("a lake that is most of the hole: kept as the island the game made", O.fillPlan(fieldOuter, rightHalf) == nil)
objects = {}
put(140, 30, 190, 70, CollisionFlag.WATER, 1.0)
-- finishTask on the half plowed field with a pond in the hole: the hole is replaced by an island of the pond, made with the game's own boundary class
FieldCourseBoundary = { createByBoundaryLine = function(line, angle)
    local made = { boundaryLine = line, angle = angle, regenerated = 0 }
    made.extend = function(self) return self end
    made.regenerateSegments = function(self) self.regenerated = self.regenerated + 1 end
    return made
end }
objects = {}
put(140, 30, 190, 70, CollisionFlag.WATER, 1.0)
local before = #finished
local halfField = { fieldRootBoundary = { boundaryLine = fieldOuter }, islandBoundaries = { { boundaryLine = rightHalf } }, segmentSplitAngle = 0.5 }
FieldCourseField.finishTask(halfField, true)
local after = finished[before + 1].islands
check("finishTask: the hole is dropped, an island of the pond takes its place (made by the game's boundary class, segments regenerated)",
    #after == 1 and after[1].boundaryLine ~= rightHalf and after[1].regenerated == 1 and after[1].angle == 0.5 and halfField.rfFilledOutline == true)
FieldCourseBoundary.createByBoundaryLine = function() return nil end
halfField = { fieldRootBoundary = { boundaryLine = fieldOuter }, islandBoundaries = { { boundaryLine = rightHalf } } }
FieldCourseField.finishTask(halfField, true)
check("when the pond cannot be carved out, the hole stays as the game made it (no lanes through a lake)", #finished[before + 2].islands == 1 and finished[before + 2].islands[1].boundaryLine == rightHalf and not halfField.rfFilledOutline)
FieldCourseBoundary = nil
objects = {}
put(150, 40, 154, 44, CollisionFlag.STATIC_OBJECT, 8.0)            -- one tree
check("a single tree in the hole: still filled (the helper's own collision check deals with the tree)", O.shouldFill(fieldOuter, rightHalf))
objects = {}
put(110, 8, 212, 92, CollisionFlag.BUILDING, 6.0)                  -- a farmyard
check("a hole that is all farmyard (buildings): kept", not O.shouldFill(fieldOuter, rightHalf))
objects = {}
check("a small bare hole (40 x 40 m = 0.16 ha): filled (it is what is left of plowing round something)", O.shouldFill(fieldOuter, rect(90, 30, 130, 70)))
put(110, 50, 111, 51, CollisionFlag.STATIC_OBJECT, 8.0)            -- a trunk in the middle of it (found on the fine grid)
check("... unless anything at all stands on it: a trunk keeps it an island", not O.shouldFill(fieldOuter, rect(90, 30, 130, 70)))
objects = {}
-- the wedge left between the first line of an outline and the corrected one: small, thin, bare
local wedge = { { 150, 20 }, { 160, 20 }, { 156, 62 }, { 154, 62 } }
local wedgePlan = O.fillPlan(fieldOuter, wedge)
check("a thin wedge of grass (a corrected outline's): filled, no carved islands", wedgePlan ~= nil and #wedgePlan.obstacles == 0 and wedgePlan.small == true)
put(154.5, 38, 155.5, 40, CollisionFlag.STATIC_OBJECT, 8.0)       -- a post / a trunk in it
check("a wedge with something on it (found on the fine grid) is kept", O.fillPlan(fieldOuter, wedge) == nil)
put(0, 0, 400, 400, CollisionFlag.WATER, 1.0)
check("a small hole that is under water is kept", not O.shouldFill(fieldOuter, rect(100, 30, 110, 40)))
objects = {}
check("a 10 x 10 m hole, bare: filled", O.shouldFill(fieldOuter, rect(100, 30, 110, 40)))
check("a hole too small for a single grid point (1 x 1 m) cannot be judged: kept", not O.shouldFill(fieldOuter, rect(100, 30, 101, 31)))
local sliverField = { fieldRootBoundary = { boundaryLine = fieldOuter }, islandBoundaries = { { boundaryLine = rightHalf }, { boundaryLine = wedge } } }
local beforeSliver = #finished
FieldCourseField.finishTask(sliverField, true)
check("finishTask: the big hole and the wedge are both dropped when bare", #finished[beforeSliver + 1].islands == 0 and sliverField.rfFilledOutline == true)
check("a C-shaped hole: left alone (not solid)", not O.shouldFill(outer, { { 5, 5 }, { 195, 5 }, { 195, 40 }, { 40, 40 }, { 40, 160 }, { 195, 160 }, { 195, 195 }, { 5, 195 } }))
-- the same hole where no ray can be cast (an API that is not there): only the outline signature counts
local savedRay = raycastClosest
raycastClosest = nil
check("no ray available: the outline signature decides (a ring hole is filled, the half plowed hole is not)", O.shouldFill(outer, rect(8, 8, 192, 192)) and not O.shouldFill(fieldOuter, rightHalf))
raycastClosest = savedRay

-- the finishTask hook uses it
local halfField = fieldWith({ { boundaryLine = rightHalf } })
halfField.fieldRootBoundary = { boundaryLine = fieldOuter }
FieldCourseField.finishTask(halfField, true)
check("finishTask on the half plowed field: the leftover meadow is dropped as an island, and the field is marked", finished[#finished].islands ~= nil and #finished[#finished].islands == 0 and halfField.rfFilledOutline == true)

-- the create-fields switch no longer depends on the mark: a course restored from a savegame
local ground = {}
for gx = 0, 219 do for gz = 0, 99 do if gx < 110 then ground[gx .. "," .. gz] = 5 end end end         -- the left half is field, the right half is not
g_currentMission.fieldGroundSystem = { getValueAtWorldPos = function(self, level, x, y, z) return ground[math.floor(x) .. "," .. math.floor(z)] or 0 end }
local restored = { boundaryPositions = fieldOuter, islands = {} }                  -- as FieldCourseField:loadFromXML leaves it: boundary positions, islands, no mark
check("a restored course over a half bare field: it covers ground that is not a field", O.coversNonField(restored) == true)
check("... and not when the islands cover the bare part", O.coversNonField({ boundaryPositions = fieldOuter, islands = { { rootBoundary = { boundaryLine = rect(110, 0, 220, 100) } } } }) == false)
for gx = 110, 219 do for gz = 0, 99 do ground[gx .. "," .. gz] = 5 end end
check("a field that is all field: no", O.coversNonField(restored) == false)
ground[130 .. "," .. 50], ground[131 .. "," .. 50] = nil, nil
check("two stray bare pixels do not count (3 points needed)", O.coversNonField(restored) == false)
check("odd input: no field, no boundary: no error", O.coversNonField(nil) == false and O.coversNonField({}) == false)
for gx = 110, 219 do for gz = 0, 99 do ground[gx .. "," .. gz] = nil end end
local plowTool2 = tool("plow", true); plowTool2:addAIGroundTypeRequirements({ 3 }); AIImplement.onPostLoad(plowTool2)
local rig2 = { getAttachedAIImplements = function() return { { object = plowTool2 } } end }
courseLoaded = {}
AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback({ vehicle = rig2 }, { fieldCourse = { courseField = restored } })
check("the helper's job is restored after a game restart: the course has no mark, but it covers bare ground: the plow creates the field (as the first time)", plowTool2:getPlowLimitToField() == false)
plowTool2.aiActive = false
check("... and when the job is over, the player's own setting is back", plowTool2:getPlowLimitToField() == true)
local plowTool3 = tool("plow", true); plowTool3:addAIGroundTypeRequirements({ 3 }); AIImplement.onPostLoad(plowTool3)
for gx = 110, 219 do for gz = 0, 99 do ground[gx .. "," .. gz] = 5 end end
AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback({ vehicle = { getAttachedAIImplements = function() return { { object = plowTool3 } } end } }, { fieldCourse = { courseField = restored } })
check("a restored course over an ordinary field (all field ground): nothing is switched", plowTool3:getPlowLimitToField() == true)
g_currentMission.fieldGroundSystem = nil
CollisionFlag, bit32, raycastClosest = nil, nil, nil

-- the console switch
check("rfOutlineFields is a console command", registered.rfOutlineFields ~= nil and registered.rfOutlineFields.method == "consoleToggle")
local text = O.consoleToggle(nil, "off")
check("... off: the game's own islands again", O.ENABLED == false and text:find("OFF", 1, true) ~= nil)
f = fieldWith({ ring })
FieldCourseField.finishTask(f, true)
check("... and it takes effect on the next course", #finished[#finished].islands == 1)
check("... on again", (function() O.consoleToggle(nil, "on"); return O.ENABLED == true end)())
check("... no argument toggles", (function() O.consoleToggle(nil); local off = O.ENABLED == false; O.consoleToggle(nil); return off and O.ENABLED == true end)())

-- ===== fences: the player's outline of a keep-out =====
CollisionFlag = { BUILDING = 1, STATIC_OBJECT = 2, WATER = 4, getHasGroupFlagSet = function(node, flag) return node == flag end }
bit32 = { bor = function(a, b) return a + b end }
raycastClosest = savedRay
local function sq(x0, z0, x1, z1) return { { x1 = x0, z1 = z0, x2 = x1, z2 = z0 }, { x1 = x1, z1 = z0, x2 = x1, z2 = z1 }, { x1 = x1, z1 = z1, x2 = x0, z2 = z1 }, { x1 = x0, z1 = z1, x2 = x0, z2 = z0 } } end
check("four fence segments that close are one loop of four corners", (function() local l = O.fenceLoops(sq(0, 0, 10, 10)); return #l == 1 and #l[1] == 4 end)())
check("ends that are 0.5 m apart are still one corner, 3 m apart are not", #O.fenceLoops({ { x1 = 0, z1 = 0, x2 = 10, z2 = 0 }, { x1 = 10.5, z1 = 0, x2 = 10, z2 = 10 }, { x1 = 10, z1 = 10, x2 = 0, z2 = 10 }, { x1 = 0, z1 = 10, x2 = 0.3, z2 = 0 } }) == 1
    and #O.fenceLoops({ { x1 = 0, z1 = 0, x2 = 10, z2 = 0 }, { x1 = 13, z1 = 0, x2 = 10, z2 = 10 }, { x1 = 10, z1 = 10, x2 = 0, z2 = 10 }, { x1 = 0, z1 = 10, x2 = 0, z2 = 0 } }) == 0)
check("an open fence, a triangle with a spur (a fork) and a lone segment are no loops", (function()
    local open = sq(0, 0, 10, 10); table.remove(open)
    local fork = sq(0, 0, 10, 10); fork[#fork + 1] = { x1 = 10, z1 = 10, x2 = 20, z2 = 20 }
    return #O.fenceLoops(open) == 0 and #O.fenceLoops(fork) == 0 and #O.fenceLoops({ { x1 = 0, z1 = 0, x2 = 5, z2 = 5 } }) == 0
end)())
check("two separate closed fences are two loops", #O.fenceLoops((function() local a = sq(0, 0, 10, 10); for _, seg in ipairs(sq(50, 50, 60, 60)) do a[#a + 1] = seg end; return a end)()) == 2)
local fenceHole = rect(0, 0, 100, 100)
local fencedIslands = O.fenceIslands(fenceHole, O.fenceLoops(sq(40, 40, 50, 50)), O.signedArea(fenceHole))
check("a closed fence inside the hole is an island, padded by the margin (2 m), wound like the hole", #fencedIslands == 1 and O.pointInPolygon(38.1, 45, fencedIslands[1]) and not O.pointInPolygon(37.8, 45, fencedIslands[1]) and O.pointInPolygon(51.9, 41, fencedIslands[1]) and not O.pointInPolygon(30, 45, fencedIslands[1]) and (O.signedArea(fencedIslands[1]) >= 0) == (O.signedArea(fenceHole) >= 0))
check("a fence outside the hole, one outside the field and one bigger than the hole are not its islands", #O.fenceIslands(fenceHole, O.fenceLoops(sq(190, 190, 195, 195)), 1) == 0 and #O.fenceIslands(fenceHole, O.fenceLoops(sq(40, 40, 50, 50)), 1, rect(0, 0, 45, 45)) == 0 and #O.fenceIslands(rect(0, 0, 100, 100), O.fenceLoops(sq(-5, -5, 105, 105)), 1, rect(0, 0, 100, 100)) == 0 and #O.fenceIslands(rect(30, 30, 40, 40), O.fenceLoops(sq(0, 0, 100, 100)), 1, rect(0, 0, 100, 100)) == 0)
check("a fence round the whole inside of an outline (its corners a little outside the hole's own line) is one island that covers the hole", (function()
    local hole = rect(10, 10, 90, 90)
    local fence = O.fenceIslands(hole, O.fenceLoops(sq(8, 8, 92, 92)), O.signedArea(hole), rect(0, 0, 100, 100))
    return #fence == 1 and O.pointInPolygon(50, 50, fence[1]) and O.pointInPolygon(12, 12, fence[1])
end)())
objects = {}
put(40, 40, 50, 50, CollisionFlag.STATIC_OBJECT, 20.0)             -- a pylon: the grid finds it with one point or none
local fencePlan = O.fillPlan(fieldOuter, rightHalf, O.fenceLoops(sq(150, 40, 160, 50)))
check("a fenced keep-out in the hole: the plan carves the fence as an island (fenced = 1), and the hole is filled", fencePlan ~= nil and fencePlan.fenced == 1 and #fencePlan.obstacles >= 1 and O.pointInPolygon(155, 45, fencePlan.obstacles[1]))
objects = {}
put(150, 40, 160, 50, CollisionFlag.STATIC_OBJECT, 20.0); put(140, 30, 190, 70, CollisionFlag.WATER, 1.0)
local mixed = O.fillPlan(fieldOuter, rightHalf, O.fenceLoops(sq(150, 40, 160, 50)))
check("a thing the scan finds inside a fence is not carved twice (the fence is its outline); the pond round it still is", mixed ~= nil and mixed.fenced == 1)
objects = {}
check("no fences: the plan is the scan's alone, as before", (function() local plan = O.fillPlan(fieldOuter, rightHalf, {}); return plan ~= nil and plan.fenced == 0 and #plan.obstacles == 0 end)())

print(string.format("outline_fields_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
