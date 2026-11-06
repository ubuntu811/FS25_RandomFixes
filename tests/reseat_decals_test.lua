-- plain Lua with a fake scene: puddles are found by name, their normal height over the ground is the median, and a stretch of ground that was lowered gets its puddles moved down with it
local passed, failed = 0, 0
local realPrint = print
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end
local log = {}
print = function(text) log[#log + 1] = text end
Utils = { appendedFunction = function(old, new) return function(...) old(...); new(...) end end }

-- a fake scene: root -> group -> shapes (name, world x/y/z)
local nodes, nextId = {}, 1
local function newNode(name, parent, x, y, z, isShape)
    local id = nextId; nextId = nextId + 1
    nodes[id] = { name = name, children = {}, x = x or 0, y = y or 0, z = z or 0, shape = isShape }
    if parent then table.insert(nodes[parent].children, id) end
    return id
end
local root = newNode("root")
local group = newNode("wetnessPieces", root)
local ground = function(x, z) return 100 + 0.01 * x end                  -- a gentle slope
local terrainAt = function(x, z) return ground(x, z) end
local puddles = {}
for i = 0, 99 do
    local x = i
    puddles[#puddles + 1] = newNode(i % 2 == 0 and "roadPuddlePiece" or "intersectionPuddles", group, x, ground(x, 0) + 0.02, 0, true)
end
local other = newNode("roadPiece", group, 5, ground(5, 0), 0, true)
local sign = newNode("trafficSignDecal_vis", group, 5, 101, 0, true)

g_currentMission, g_terrainNode, g_client = {}, 1, {}
ClassIds = { SHAPE = 1 }
getRootNode = function() return root end
getHasClassId = function(n) return nodes[n].shape == true end
getName = function(n) return nodes[n].name end
getNumOfChildren = function(n) return #nodes[n].children end
getChildAt = function(n, i) return nodes[n].children[i + 1] end
getShapeWorldBoundingSphere = function(n) return nodes[n].x, nodes[n].y, nodes[n].z, 1 end
getWorldTranslation = function(n) return nodes[n].x, nodes[n].y, nodes[n].z end
setWorldTranslation = function(n, x, y, z) nodes[n].x, nodes[n].y, nodes[n].z = x, y, z end
getTerrainHeightAtWorldPos = function(_, x, _, z) return terrainAt(x, z) end
local clock = 0
getTimeSec = function() clock = clock + 0.00002; return clock end          -- every call costs 0.02 ms: the slices are cut by the budget
FSBaseMission = { update = function() end }
local queued = 0
g_terrainDeformationQueue = { queueJob = function() queued = queued + 1 end }
local applied = 0
TerrainDeformation = { apply = function() applied = applied + 1 end }
dofile("scripts/ReseatDecals.lua")

check("names: puddles match, road pieces and sign decals do not", ReseatDecals.matches("roadPuddlePiece") and ReseatDecals.matches("intersectionPuddles") and not ReseatDecals.matches("roadPiece") and not ReseatDecals.matches("trafficSignDecal_vis"))
check("median of odd and even lists", ReseatDecals.median({ 3, 1, 2 }) == 2 and ReseatDecals.median({ 4, 1, 3, 2 }) == 2.5 and ReseatDecals.median({}) == nil)
check("shift: within the tolerance nothing, beyond it the difference", ReseatDecals.shiftFor(10.02, 10, 0.02, 0.06) == nil and math.abs(ReseatDecals.shiftFor(9.6, 10, 0.02, 0.06) - 0.42) < 1e-9)

local function run(seconds)
    for _ = 1, seconds * 60 do ReseatDecals.update(16) end
end
run(ReseatDecals.START_DELAY_S + 30)
local st = ReseatDecals.state
check("found only the puddles, 100", #st.pieces == 100)
check("the offset is the untouched 2 cm", st.offset ~= nil and math.abs(st.offset - 0.02) < 1e-6)
check("nothing moved while the ground is as it was", st.movedTotal == 0)

-- someone lowers the road between x = 50 and 60 by 40 cm: nothing runs until an edit is seen
local before = {}
for _, id in ipairs(puddles) do before[id] = nodes[id].y end
local base = ground
terrainAt = function(x, z) return base(x, z) + ((x >= 50 and x < 60) and -0.4 or 0) end
run(60)
local still = 0
for _, id in ipairs(puddles) do if nodes[id].y == before[id] then still = still + 1 end end
check("no polling: without an edit event nothing is looked at, a minute on", still == 100 and st.phase == "idle")
check("both hooks took", ReseatDecals.hookCount == 2)
g_terrainDeformationQueue:queueJob()
check("the wrapped queueJob still calls the original", queued == 1)
run(ReseatDecals.SETTLE_S + 1)
local moved, wrong = 0, 0
for _, id in ipairs(puddles) do
    local x = nodes[id].x
    local want = terrainAt(x, 0) + 0.02
    if math.abs(nodes[id].y - want) > 1e-6 then wrong = wrong + 1 end
    if math.abs(nodes[id].y - before[id]) > 0.3 then moved = moved + 1 end
end
check("the ten puddles over the lowered stretch moved down by 40 cm", moved == 10)
check("every puddle sits at its ground + 2 cm again, none of the others moved", wrong == 0)
check("the sign decal and the road piece were not touched", nodes[sign].y == 101 and nodes[other].y == ground(5, 0))
check("the first pass is done and a second one is booked for a little later", st.due ~= nil)
run(ReseatDecals.LATE_S + 2)
check("after the second pass it rests again: nothing booked", st.phase == "idle" and st.due == nil)
check("it said what it did", #log > 0 and (function() for _, l in ipairs(log) do if l:find("moved back", 1, true) then return true end end end)())

-- raised ground buries them: moved up
terrainAt = function(x, z) return base(x, z) + ((x >= 50 and x < 60) and -0.4 or 0) + ((x >= 10 and x < 15) and 0.3 or 0) end
TerrainDeformation.apply()
run(ReseatDecals.SETTLE_S + ReseatDecals.LATE_S + 3)
local up = 0
for _, id in ipairs(puddles) do if nodes[id].x >= 10 and nodes[id].x < 15 and math.abs(nodes[id].y - (terrainAt(nodes[id].x, 0) + 0.02)) < 1e-6 then up = up + 1 end end
check("raised ground lifts its puddles too", up == 5)
-- saving: the moved puddles go to the savegame's file and are put back at the next load, before anything is measured
local files = {}
local function fakeXml(path)
    local x = { data = files[path] or {}, path = path }
    function x:hasProperty(k) for key in pairs(self.data) do if key:sub(1, #k) == k then return true end end return false end
    function x:getString(k) return self.data[k] end
    function x:getFloat(k) return self.data[k] end
    function x:setString(k, v) self.data[k] = v end
    function x:setFloat(k, v) self.data[k] = v end
    function x:save() files[self.path] = self.data end
    function x:delete() end
    return x
end
XMLFile = { create = function(_, path) files[path] = nil; return fakeXml(path) end, loadIfExists = function(_, path) if files[path] then return fakeXml(path) end end }
g_currentMission.missionInfo = { savegameDirectory = "save1" }
ReseatDecals.save()
local saved = files["save1/reseatDecals.xml"]
local down, up = 0, 0
for k, v in pairs(saved) do
    if k:find("#shift", 1, true) then
        if math.abs(v + 0.4) < 1e-6 then down = down + 1 elseif math.abs(v - 0.3) < 1e-6 then up = up + 1 end
    end
end
check("the moved puddles are in the file: ten 40 cm down, five 30 cm up", down == 10 and up == 5)
check("records: untouched ones are not written, unmatched file entries are kept", #ReseatDecals.records({ { key = "a", shift = 0 }, { key = "b", shift = 0.5 } }, { c = 0.1 }) == 2)

-- the next session: the nodes are back at the map's heights, the terrain is still lowered
for _, id in ipairs(puddles) do nodes[id].y = before[id] end
terrainAt = function(x, z) return base(x, z) + ((x >= 50 and x < 60) and -0.4 or 0) + ((x >= 10 and x < 15) and 0.3 or 0) end
dofile("scripts/ReseatDecals.lua")
local restoredLog
local oldPrint = print
print = function(text) if tostring(text):find("put back", 1, true) then restoredLog = text end end
run(ReseatDecals.START_DELAY_S + 2)
print = oldPrint
local back = 0
for _, id in ipairs(puddles) do if math.abs(nodes[id].y - (terrainAt(nodes[id].x, 0) + 0.02)) < 1e-6 then back = back + 1 end end
check("all 100 sit on the lowered ground right after the load", back == 100)
check("it put the fifteen back from the file, not by sweeping", restoredLog ~= nil and restoredLog:find("15 put back", 1, true) ~= nil and ReseatDecals.state.movedTotal == 0)

-- no hooks possible: a slow pass every FALLBACK_S instead
g_terrainDeformationQueue, TerrainDeformation = nil, nil
dofile("scripts/ReseatDecals.lua")
ReseatDecals.FALLBACK_S = 30
terrainAt = base
run(ReseatDecals.START_DELAY_S + 10)
check("without hooks it says so and keeps a fallback", ReseatDecals.hookCount == 0 and ReseatDecals.state.due ~= nil)
terrainAt = function(x, z) return base(x, z) - 0.5 end
run(40)
check("the fallback pass moves them", math.abs(nodes[puddles[1]].y - (terrainAt(nodes[puddles[1]].x, 0) + ReseatDecals.state.offset)) < 1e-6)
print = realPrint
realPrint(string.format("reseat_decals_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
