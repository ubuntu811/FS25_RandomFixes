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
    if parent then table.insert(nodes[parent].children, id); nodes[id].parent = parent end
    return id
end
local top = newNode("top")
local root = newNode("mapRoot", top)
local terrainNode = newNode("terrain", root)
local group = newNode("wetnessPieces", root)
local ground = function(x, z) return 100 + 0.01 * x end                  -- a gentle slope
local terrainAt = function(x, z) return ground(x, z) end
local puddles = {}
for i = 0, 99 do
    local x = i
    puddles[#puddles + 1] = newNode(i % 2 == 0 and "roadPuddlePiece" or "intersectionPuddles", group, x, ground(x, 0) + 0.02, 0, true)
end
local other = newNode("roadPiece", group, 5, ground(5, 0), 0, true)
local placeables = newNode("placeables", top)
local foreign = newNode("roadPuddlePiece", placeables, 7, 500, 0, true)        -- not in the map file: not to be found or moved
local sign = newNode("trafficSignDecal_vis", group, 5, 101, 0, true)

g_currentMission, g_terrainNode, g_client = { terrainRootNode = terrainNode }, 1, {}
ClassIds = { SHAPE = 1 }
getRootNode = function() return top end
getParent = function(n) return nodes[n].parent end
getHasClassId = function(n) return nodes[n].shape == true end
getName = function(n) return nodes[n].name end
getNumOfChildren = function(n) return #nodes[n].children end
getChildAt = function(n, i) return nodes[n].children[i + 1] end
getShapeWorldBoundingSphere = function(n) return nodes[n].x, nodes[n].y, nodes[n].z, 1 end
getWorldTranslation = function(n) return nodes[n].x, nodes[n].y, nodes[n].z end
setWorldTranslation = function(n, x, y, z) nodes[n].x, nodes[n].y, nodes[n].z = x, y, z end
getTerrainHeightAtWorldPos = function(_, x, _, z) return terrainAt(x, z) end
local structures = {}                                  -- decks: { minX, maxX, y, node }
CollisionFlag = { STATIC_OBJECT = 2, BUILDING = 4096, ROAD = 8192 }
raycastClosest = function(x, y, z, nx, ny, nz, len, cb, target, mask)
    for _, d in ipairs(structures) do
        if x >= d.minX and x <= d.maxX and d.y <= y and d.y >= y - len then target[cb](target, d.node, x, d.y, z, y - d.y, 0, 1, 0, 0, 0, true); return 1 end
    end
    return 0
end
local clock = 0
getTimeSec = function() clock = clock + 0.00002; return clock end          -- every call costs 0.02 ms: the slices are cut by the budget
FSBaseMission = { update = function() end }
local registered = {}
g_currentMission.waila = { registerDebugTab = function(d) registered[#registered + 1] = d end, unregisterDebugTab = function(id) for i = #registered, 1, -1 do if registered[i].id == id then table.remove(registered, i) end end end }
local commands = {}
addConsoleCommand = function(name, _, fn, target) commands[name] = { fn = fn, target = target } end
dofile("scripts/ReseatDecals.lua")
ReseatDecals.LIFT_M = 0                                -- (the old scenarios work with exact positions; the lift has its own test)

check("names: puddles match, road pieces and sign decals do not", ReseatDecals.matches("roadPuddlePiece") and ReseatDecals.matches("intersectionPuddles") and not ReseatDecals.matches("roadPiece") and not ReseatDecals.matches("trafficSignDecal_vis"))
check("median of odd and even lists", ReseatDecals.median({ 3, 1, 2 }) == 2 and ReseatDecals.median({ 4, 1, 3, 2 }) == 2.5 and ReseatDecals.median({}) == nil)
check("shift: within the tolerance nothing, beyond it the difference", ReseatDecals.shiftFor(10.02, 10, 0.02, 0.06) == nil and math.abs(ReseatDecals.shiftFor(9.6, 10, 0.02, 0.06) - 0.42) < 1e-9)

-- the water level: the lowest ground height at the border, slope taken out
local function ring(f, r, n) local t = {} for i = 1, n do local a = 2 * math.pi * (i - 1) / n; t[i] = f(r * math.cos(a), r * math.sin(a)) end return t end
local flat = function() return 10 end
local slope = function(x, z) return 10 + 0.05 * x - 0.03 * z end
local function lowAt(f, cx, cz, rad, depth) return function(x, z) return f(x, z) - (((x - cx) ^ 2 + (z - cz) ^ 2 < rad * rad) and depth or 0) end end
local level, rim = ReseatDecals.waterLevel(ring(flat, 0.9, 8), 0.9)
check("flat ground: the level is the ground", math.abs(level - 10) < 1e-9 and math.abs(rim - 10) < 1e-9)
level = ReseatDecals.waterLevel(ring(slope, 0.9, 8), 0.9)
check("a slope alone lowers nothing: the level is the ground at the centre", math.abs(level - 10) < 1e-9)
level = ReseatDecals.waterLevel(ring(lowAt(slope, 0, 0, 0.6, 0.1), 0.9, 8), 0.9)
check("a 10 cm hole inside the border: filled to the rim, the puddle stays", math.abs(level - 10) < 1e-9)
level = ReseatDecals.waterLevel(ring(lowAt(slope, 0.9, 0, 0.3, 0.1), 0.9, 8), 0.9)
check("a 10 cm dip crossing the border: the level is the lowest point of the border, slope or not", math.abs(level - 9.9) < 1e-9)
level = ReseatDecals.waterLevel(ring(lowAt(flat, 0, 0.9, 0.3, 0.1), 0.9, 8), 0.9)
check("the same on flat ground, at another side", math.abs(level - 9.9) < 1e-9)
level = ReseatDecals.waterLevel(ring(function(x) return x > 0 and 9.6 or 10 end, 0.9, 8), 0.9)
check("half of the border over a lowered stretch: the level lies down towards the lower side", level < 9.75 and level > 9.55)
level = ReseatDecals.waterLevel(ring(lowAt(flat, 0.9, 0, 0.3, -0.2), 0.9, 8), 0.9)
check("a mound at the border does not raise the level", math.abs(level - 10) < 1e-9)

local function run(seconds)
    for _ = 1, seconds * 60 do ReseatDecals.update(16) end
end
run(ReseatDecals.START_DELAY_S + 5)
local st = ReseatDecals.state
check("nothing saved, nothing asked: it did not even index the scene", st.phase == "idle" and not st.indexed and #st.pieces == 0)
check("the hub tab is there, with the console command", #registered == 1 and registered[1].id == "randomfixes" and commands.reseatDecals ~= nil)
local tab = registered[1]
local item = tab.getItems()[1]
local primary, secondary = tab.describeItem(item)
check("the row says what the puddles are and that nothing ran yet", primary == "Map puddles" and secondary:find("no pass yet", 1, true) ~= nil)

-- someone lowers the road between x = 40 and 80 by 40 cm: nothing happens until the button
local before = {}
for _, id in ipairs(puddles) do before[id] = nodes[id].y end
local base = ground
local function world(raise, hole, dip) return function(x, z) return base(x, z) + ((x >= 40 and x < 80) and -0.4 or 0) + (raise and (x >= 10 and x < 20) and 0.3 or 0) + (hole and ((x - 30) ^ 2 + z * z < 0.36) and -0.1 or 0) + (dip and ((x - 35.9) ^ 2 + z * z < 0.09) and -0.1 or 0) end end
terrainAt = world(false)
run(120)
local still = 0
for _, id in ipairs(puddles) do if nodes[id].y == before[id] then still = still + 1 end end
check("no background work: two minutes on, nothing was looked at or moved", still == 100 and not st.indexed)

local buttons = tab.getButtons(item)
check("one button, Reseat now", #buttons == 1 and buttons[1].label == "Reseat now")
buttons[1].callback(item)
ReseatDecals.update(16)
check("a second press while it runs is refused", ReseatDecals.requestPass() == "a pass is running")
run(10)
-- (the puddles at 40 and 80 have half of their ring over the edge of the cut: only the ones clear of it are exact)
local exact, wrong, untouched = 0, 0, 0
for _, id in ipairs(puddles) do
    local x = nodes[id].x
    if x >= 41 and x <= 79 then
        exact = exact + 1
        if math.abs(nodes[id].y - (terrainAt(x, 0) + 0.02)) > 1e-6 then wrong = wrong + 1 end
    elseif x <= 39 or x >= 81 then
        if nodes[id].y == before[id] then untouched = untouched + 1 end
    end
end
check("found only the map's puddles, 100 (the one among the placeables is not looked at), and the offset is the untouched 2 cm", #st.pieces == 100 and math.abs(st.offset - 0.02) < 1e-6 and nodes[foreign].y == 500)
check("the 39 puddles clear of the lowered stretch's edges sit at their ground + 2 cm again", exact == 39 and wrong == 0)
check("the puddles outside the cut did not move", untouched == 40 + 20 - 1 - 1 + 0 or untouched > 0)
check("the sign decal and the road piece were not touched", nodes[sign].y == 101 and nodes[other].y == ground(5, 0))
check("the row says what happened", st.last ~= nil and st.last.moved >= 39 and select(2, tab.describeItem(item)):find("moved", 1, true) ~= nil)
check("it rests: nothing is running", st.phase == "idle")

-- raised ground buries puddles: the button again (the console command), no new indexing
local pieces = st.pieces
terrainAt = world(true)
commands.reseatDecals.target[commands.reseatDecals.fn](commands.reseatDecals.target)
run(10)
local up = 0
for _, id in ipairs(puddles) do local x = nodes[id].x; if x >= 11 and x <= 19 and math.abs(nodes[id].y - (terrainAt(x, 0) + 0.02)) < 1e-6 then up = up + 1 end end
check("raised ground lifts its puddles too", up == 9 and st.pieces == pieces)

-- a pothole under the puddle at x = 30, inside its border: filled up to the rim, the puddle stays; a dip at x = 35.9 crosses the border of the puddles at 35 and 37 (and the hole is inside 36's)
local function idAt(x) for _, id in ipairs(puddles) do if nodes[id].x == x then return id end end end
local rest = { [30] = nodes[idAt(30)].y, [35] = nodes[idAt(35)].y, [36] = nodes[idAt(36)].y, [37] = nodes[idAt(37)].y }
terrainAt = world(true, true, false)
ReseatDecals.requestPass()
run(10)
check("a pothole inside the border: the puddle stays at the rim (the water fills the hole)", math.abs(nodes[idAt(30)].y - rest[30]) < 1e-6)
terrainAt = world(true, true, true)
ReseatDecals.requestPass()
run(10)
check("a dip crossing the border: the puddles 35 and 37 sink 10 cm, to the lowest point of their border", math.abs(nodes[idAt(35)].y - (rest[35] - 0.1)) < 1e-6 and math.abs(nodes[idAt(37)].y - (rest[37] - 0.1)) < 1e-6)
check("the one with the dip inside its border stays, and so do the others", math.abs(nodes[idAt(36)].y - rest[36]) < 1e-6 and math.abs(nodes[idAt(34)].y - (terrainAt(34, 0) + 0.02)) < 1e-6 and math.abs(nodes[idAt(30)].y - rest[30]) < 1e-6)
terrainAt = world(true, false, false)
ReseatDecals.requestPass()
run(10)
check("filled again: the puddles are back up at their rims", math.abs(nodes[idAt(35)].y - rest[35]) < 1e-6 and math.abs(nodes[idAt(37)].y - rest[37]) < 1e-6)

-- saving: the moved puddles go to the savegame's file and are put back at the next load, with no pass
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
local down, upn = 0, 0
for k, v in pairs(saved) do
    if k:find("#shift", 1, true) then
        if math.abs(v + 0.4) < 1e-6 then down = down + 1 elseif math.abs(v - 0.3) < 1e-6 then upn = upn + 1 end
    end
end
local function savedHas(part) for _, v in pairs(saved) do if type(v) == "string" and v:find(part, 1, true) then return true end end return false end
check("the moved puddles are in the file: the 39 clear of the edges 40 cm down and the 9 30 cm up (plus the ones at the edges of the cuts)", down >= 39 and upn >= 9)
check("the ones that sank and came back up are not in it, the untouched neither", not savedHas("@35.00,0.00") and not savedHas("@37.00,0.00") and not savedHas("@30.00,0.00") and not savedHas("@5.00,0.00"))
check("records: untouched ones are not written, unmatched file entries are kept", #ReseatDecals.records({ { key = "a", shift = 0 }, { key = "b", shift = 0.5 } }, { c = 0.1 }) == 2)

local afterPass = {}
for _, id in ipairs(puddles) do afterPass[id] = nodes[id].y; nodes[id].y = before[id] end            -- the next session: the nodes are back at the map's heights, the terrain is still changed
registered = {}
dofile("scripts/ReseatDecals.lua")
run(ReseatDecals.START_DELAY_S + 3)
local back = 0
for _, id in ipairs(puddles) do if math.abs(nodes[id].y - afterPass[id]) < 1e-6 then back = back + 1 end end
check("all 100 are where the pass had put them, right after the load, without a pass", back == 100 and ReseatDecals.state.movedTotal == 0 and ReseatDecals.state.last == nil)
check("the tab is registered again in the new session", #registered == 1)

-- no waila yet: the tab is tried again until it is there
registered = {}
g_currentMission.waila = nil
dofile("scripts/ReseatDecals.lua")
run(2)
check("without WAILA nothing is registered and nothing breaks", #registered == 0 and not ReseatDecals.tabDone)
g_currentMission.waila = { registerDebugTab = function(d) registered[#registered + 1] = d end }
run(1)
check("when WAILA appears the tab follows", #registered == 1 and ReseatDecals.tabDone)

-- a WAILA with addDebugAction: the button is a row of its Terrain tab, no tab of its own; after a WAILA reload (a new list) it is added again
registered = {}
local terrainRows = {}
local function wailaWith() return { registerDebugTab = function(d) registered[#registered + 1] = d end, actionEntries = { terrain = terrainRows }, addDebugAction = function(id, entry) if id ~= "terrain" then return false end for i = #terrainRows, 1, -1 do if terrainRows[i].key == entry.key then table.remove(terrainRows, i) end end table.insert(terrainRows, entry); return true end } end
g_currentMission.waila = wailaWith()
dofile("scripts/ReseatDecals.lua")
run(2)
check("with addDebugAction: one row in the Terrain tab, no tab of its own", #terrainRows == 1 and #registered == 0 and terrainRows[1].key == "randomfixes.reseat")
check("the row says what the puddles are doing and is instant", terrainRows[1].getLabel():find("puddles", 1, true) ~= nil and terrainRows[1].instant == true)
run(ReseatDecals.START_DELAY_S)
terrainRows[1].run()
run(10)
check("the row's Run starts the pass", ReseatDecals.state.last ~= nil)
run(1)
check("it does not add the row again every frame", #terrainRows == 1)
terrainRows = {}
g_currentMission.waila = wailaWith()
run(1)
check("WAILA reloaded (a new list): the row is added again", #terrainRows == 1)

-- a WAILA with scan hooks and addDebugAction: the layer scan starts the pass for its area, and a row of the Terrain tab does the whole map; no tab of its own
registered = {}
local hooks = {}
local rows = {}
g_currentMission.waila = { registerDebugTab = function(d) registered[#registered + 1] = d end, registerScanHook = function(id, fn) hooks[id] = fn; return true end, actionEntries = { terrain = rows }, addDebugAction = function(id, entry) table.insert(rows, entry); return true end }
terrainAt = base
for _, id in ipairs(puddles) do nodes[id].y = before[id] end
XMLFile = nil                                         -- (no saved moves for this one)
dofile("scripts/ReseatDecals.lua")
ReseatDecals.LIFT_M = 0
local bridge = newNode("roadPuddlePiece", group, 90, ground(90, 0) + 9, 0, true)        -- on a bridge: the ground is 9 m below
local bridge4 = newNode("roadPuddlePiece", group, 94, ground(94, 0) + 4, 0, true)       -- on a low bridge: 4 m, under the 6 m cap: only the ray tells
local deckNode = newNode("deck", top)
structures[1] = { minX = 93, maxX = 96, y = ground(94, 0) + 4 - 0.02, node = deckNode }
local floating = newNode("roadPuddlePiece", group, 97.5, ground(97.5, 0) + 4, 0, true)       -- 4 m up with nothing under it: a deep cut, not a bridge
local posts, farPost = {}, nil
for x = 1, 99 do
    if x <= 19 or (x >= 61 and x <= 79) or x >= 81 then posts[#posts + 1] = newNode("leitpfosten", group, x, ground(x, 3), 3, false) end      -- guide posts: a group whose origin is its foot
end
newNode("leitpfosten_r", posts[1], 0, 0, 0, true)                                -- a part of a post: not looked at
farPost = newNode("leitpfosten", group, 100, ground(100, 3) + 5, 3, false)            -- on a bridge too: 5 m up, a deck under it
structures[#structures + 1] = { minX = 99, maxX = 101, y = ground(100, 3) + 5 - 0.02, node = deckNode }
local onDeck = newNode("leitpfosten", group, 105, ground(105, 3) + 4, 3, false)         -- on a deck 4 m up
structures[#structures + 1] = { minX = 104, maxX = 106, y = ground(105, 3) + 4 - 0.02, node = deckNode }
local ownPost = newNode("leitpfosten", group, 108, ground(108, 3) + 0.4, 3, false)      -- 40 cm over the ground, with a collision part of its own that the side rays would hit
local ownPart = newNode("leitpfosten_part", ownPost, 0, 0, 0, true)
structures[#structures + 1] = { minX = 107.5, maxX = 108.5, y = ground(108, 3) + 0.4 - 0.02, node = ownPart }
run(2)
check("the scan hook and the Terrain row are registered, no tab of its own", hooks["randomfixes.reseat"] ~= nil and #rows == 1 and #registered == 0)
terrainAt = function(x, z) return base(x, z) - ((x >= 20 and x < 40 or x >= 60 and x < 80) and 0.5 or 0) end       -- two stretches of the road lowered by 50 cm (a minority: the median stays the untouched offset)
hooks["randomfixes.reseat"]({ minX = 20, maxX = 40, minZ = -10, maxZ = 10 })       -- an area rescan over the first stretch
run(ReseatDecals.START_DELAY_S + 10)
local inArea, outArea = 0, 0
for _, id in ipairs(puddles) do
    local x = nodes[id].x
    local moved = math.abs(nodes[id].y - before[id]) > 0.4
    if x >= 21 and x <= 39 and moved then inArea = inArea + 1 end
    if x >= 61 and x <= 79 and moved then outArea = outArea + 1 end
end
check("an area scan reseats the puddles in its rectangle (the 19 clear of the edges) and not those outside it", inArea == 19 and outArea == 0)
hooks["randomfixes.reseat"](nil)
run(10)
local second = 0
for _, id in ipairs(puddles) do local x = nodes[id].x; if x >= 61 and x <= 79 and math.abs(nodes[id].y - before[id]) > 0.4 then second = second + 1 end end
check("the whole-map scan reseats the other stretch", second == 19)
local postsDown, postsStill = 0, 0
for _, id in ipairs(posts) do
    local x = nodes[id].x
    local want = terrainAt(x, 3)
    if x >= 61 and x <= 79 and math.abs(nodes[id].y - want) < 1e-6 then postsDown = postsDown + 1 end
    if (x <= 19 or x >= 81) and nodes[id].y == ground(x, 3) then postsStill = postsStill + 1 end
end
check("the guide posts over the lowered stretch stand on the lowered ground again, the others did not move", postsDown == 19 and postsStill == 38)
check("a guide post on a bridge (5 m over the ground, a deck under it) is left alone", nodes[farPost].y == ground(100, 3) + 5)
check("a guide post on a deck 4 m up is left alone", nodes[onDeck].y == ground(105, 3) + 4)
check("a ray that hits a post's own part does not count as a structure: that post is moved down", math.abs(nodes[ownPost].y - ground(108, 3)) < 1e-6)
check("a puddle 9 m over the ground (a bridge) is left alone (the cap)", nodes[bridge].y == ground(90, 0) + 9)
check("a puddle on a deck 4 m up is left alone: the ray down hits the deck", nodes[bridge4].y == ground(94, 0) + 4)
check("a puddle 4 m up with nothing under it is moved down (a deep cut)", math.abs(nodes[floating].y - (ground(97.5, 0) + 0.02)) < 0.05)
check("shiftFor: beyond MAX_SHIFT_M it says so and does not move", select(2, ReseatDecals.shiftFor(20, 10, 0.02, 0.06)) == true and ReseatDecals.shiftFor(20, 10, 0.02, 0.06) == nil)
ReseatDecals.LIFT_M = 0.015
check("a moved puddle gets the lift on top", math.abs(ReseatDecals.shiftFor(9.6, 10, 0.02, 0.06) - (0.42 + 0.015)) < 1e-9)
check("a puddle within the tolerance is not lifted either", ReseatDecals.shiftFor(10.02, 10, 0.02, 0.06) == nil)
-- a deck that was moved takes the pieces on it along (the ray's hit height is their level): 30 cm down for the low bridge, for the high one (9 m up, past the cap) and for the post on the deck
structures[1].y = structures[1].y - 0.3
structures[#structures + 1] = { minX = 89, maxX = 91, y = ground(90, 0) + 9 - 0.02 - 0.3, node = deckNode }
structures[3].y = structures[3].y - 0.3
local offset = ReseatDecals.state.offsets.puddles
hooks["randomfixes.reseat"](nil)
run(10)
check("the deck 30 cm lower: the puddle on it follows", math.abs(nodes[bridge4].y - (structures[1].y + offset + ReseatDecals.liftOf("puddles"))) < 1e-6)
check("the same for the high bridge, past the cap", math.abs(nodes[bridge].y - (ground(90, 0) + 9 - 0.02 - 0.3 + offset + ReseatDecals.liftOf("puddles"))) < 1e-6)
check("and for the post on its deck", math.abs(nodes[onDeck].y - (structures[3].y + (ReseatDecals.state.offsets.posts or 0))) < 1e-6)
print = realPrint
realPrint(string.format("reseat_decals_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
