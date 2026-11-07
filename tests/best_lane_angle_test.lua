-- plain Lua: the lane direction with the smallest extent across the lanes, and the override of the game's getOptimalBoundaryAngle
local passed, failed = 0, 0
local realPrint = print

local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end
local log = {}
print = function(text) log[#log + 1] = text end
Utils = { overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end }
MathUtil = { getYRotationFromDirection = function(dx, dz) return math.atan2(dx, dz) end, getDirectionFromYRotation = function(a) return math.sin(a), math.cos(a) end }
BoundaryLineGenerationTask = { getOptimalBoundaryAngle = function() return 0 end }       -- (the game's: always 0 on a plain field)
dofile("scripts/BestLaneAngle.lua")

local function rect(w, h, rot)
    local pts = { { 0, 0 }, { w, 0 }, { w, h }, { 0, h }, { 0, 0 } }
    local c, s = math.cos(rot or 0), math.sin(rot or 0)
    for i, p in ipairs(pts) do pts[i] = { p[1] * c - p[2] * s + 1000, p[1] * s + p[2] * c - 500 } end
    return pts
end

-- the extent across the lanes
local r = rect(200, 100)
check("a 200 x 100 field: lanes along the long side are 100 m across", math.abs(BestLaneAngle.extent(r, 1, 0) - 100) < 1e-9)
check("lanes along the short side are 200 m across", math.abs(BestLaneAngle.extent(r, 0, 1) - 200) < 1e-9)

-- the best direction
local dx, dz, extent, first = BestLaneAngle.best(r, 16)
check("the long side (x): direction (1, 0), 100 m across, where the game's angle 0 (z) would be 200", math.abs(dx) > 0.999999 and math.abs(dz) < 1e-6 and math.abs(extent - 100) < 1e-9 and math.abs(first - 200) < 1e-9)
local tall = rect(100, 200)
dx, dz, extent = BestLaneAngle.best(tall, 16)
check("a field that is long north to south: angle 0 stays", math.abs(dx) < 1e-6 and math.abs(dz) > 0.999999 and math.abs(extent - 100) < 1e-9)
local turned = rect(300, 120, math.rad(33))
dx, dz, extent = BestLaneAngle.best(turned, 16)
check("a field turned by 33 degrees: the lanes follow its long edge exactly (not just the nearest 11.25 degree step), 120 m across", math.abs(extent - 120) < 1e-6)

-- the user's kind of field: a convex quadrilateral; against a brute force over a fine angle grid
local quad = { { 0, 0 }, { 380, -30 }, { 420, 190 }, { 40, 260 }, { 0, 0 } }
local bx, bz, bExtent = BestLaneAngle.best(quad, 16)
local brute = math.huge
for deg = 0, 179.9, 0.1 do
    local a = math.rad(deg)
    brute = math.min(brute, BestLaneAngle.extent(quad, math.sin(a), math.cos(a)))
end
check("a convex field: no angle of a 0.1 degree grid is better than the best candidate", bExtent <= brute + 1e-6)
check("and it is better than the game's angle 0", bExtent < BestLaneAngle.extent(quad, 0, 1) - 1)


-- the longest side (the default rule)
local function deg(dx, dz) return (math.deg(math.atan2(dx, dz)) % 180) end
local sx, sz, slen, sides = BestLaneAngle.longestSide(rect(200, 100))
check("a rectangle: the long side, 200 m, 4 sides", math.abs(deg(sx, sz) - 90) < 1e-6 and math.abs(slen - 200) < 1e-6 and sides == 4)
sx, sz = BestLaneAngle.longestSide(rect(300, 120, math.rad(33)))
check("a rectangle turned by 33 degrees: that angle exactly (the side runs 33 degrees from east: direction angle 57)", math.abs(deg(sx, sz) - 57) < 1e-6)
-- a side that came out of the simplification as three edges that bend 5 degrees each is one side
local bent = { { 0, 0 }, { 120, 5 }, { 240, 15 }, { 360, 30 }, { 380, 200 }, { 100, 210 }, { 0, 0 } }
sx, sz, slen, sides = BestLaneAngle.longestSide(bent)
check("three slightly bent edges are one side, longer than the others", sides < 6 and slen > 340)
-- a hand-driven outline: every side wobbles by up to 2 m, the long side is cut into many pieces
local wobbly = {}
local function add2(x, z) wobbly[#wobbly + 1] = { x, z } end
for k = 0, 20 do add2(k * 20, (k % 3 - 1) * 1.5) end                       -- the south side, 400 m, as 21 points
for k = 1, 8 do add2(400 + (k % 2) * 1.2, k * 12) end                       -- the east side, 96 m
for k = 0, 20 do add2(400 - k * 20, 96 + (k % 3 - 1) * 1.5) end             -- the north side
for k = 1, 7 do add2((k % 2) * 1.2, 96 - k * 12) end                        -- the west side
add2(wobbly[1][1], wobbly[1][2])
sx, sz = BestLaneAngle.longestSide(wobbly)
check("a wobbly hand-driven outline: the lanes still follow the long (east-west) side within 3 degrees", math.abs(deg(sx, sz) - 90) < 3)
-- a round field has no side
local circle = {}
for k = 0, 35 do local a = math.rad(k * 10); circle[#circle + 1] = { 100 * math.cos(a), 100 * math.sin(a) } end
circle[#circle + 1] = { circle[1][1], circle[1][2] }
check("a round field has no sharp corner: no side, the extent rule takes over", BestLaneAngle.longestSide(circle) == nil)
-- the choice: by RULE
local cx, cz, cext, c0 = BestLaneAngle.choose(rect(200, 100), 16)
check("the default rule takes the long side: 100 m across, the game's angle 0 would make it 200", BestLaneAngle.RULE == "side" and math.abs(cext - 100) < 1e-9 and math.abs(c0 - 200) < 1e-9)
BestLaneAngle.RULE = "extent"
cx, cz, cext = BestLaneAngle.choose(rect(200, 100), 16)
check("rule extent: the same for a rectangle", math.abs(cext - 100) < 1e-9)
BestLaneAngle.RULE = "side"
cx, cz, cext = BestLaneAngle.choose(circle, 16)
check("a circle with the side rule: the extent rule answers (a 36-gon is about 199 m across in every direction)", cx ~= nil and cext > 198 and cext < 200.01)

-- the override
local angle = BoundaryLineGenerationTask.getOptimalBoundaryAngle(0, 0, r, 16)
check("the override returns the angle of the long side (east-west lanes: 90 degrees), in 0 .. 180", math.abs(angle - math.pi / 2) < 1e-6 and angle >= 0 and angle < math.pi)
angle = BoundaryLineGenerationTask.getOptimalBoundaryAngle(0, 0, tall, 16)
check("a field long north to south: 0 as before", math.abs(angle) < 1e-6 or math.abs(angle - math.pi) < 1e-6)
check("the lines are as the game computes them from that angle: direction (sin, cos)", (function() local a = BoundaryLineGenerationTask.getOptimalBoundaryAngle(0, 0, turned, 16); local x, z = MathUtil.getDirectionFromYRotation(a); return math.abs(BestLaneAngle.extent(turned, x, z) - 120) < 1e-6 end)())
check("it said so (once per call, the first few)", #log >= 1 and tostring(log[1]):find("lane angle", 1, true) ~= nil)
BestLaneAngle.ENABLED = false
check("switched off: the game's own answer", BoundaryLineGenerationTask.getOptimalBoundaryAngle(0, 0, r, 16) == 0)
BestLaneAngle.ENABLED = true
check("a degenerate boundary: the game's own answer", BoundaryLineGenerationTask.getOptimalBoundaryAngle(0, 0, { { 0, 0 }, { 1, 1 } }, 16) == 0)
print = realPrint
-- the hook body, whichever way Utils.overwrittenFunction hands the arguments over
do
    local square = { { 0, 0 }, { 100, 0 }, { 100, 30 }, { 0, 30 } }
    local seen = nil
    local function super(...) seen = { ... }; return "super" end
    local a1, a2, a3 = BestLaneAngle.wrap(5, super, 7, square, 16), BestLaneAngle.wrap(super, 5, 7, square, 16), BestLaneAngle.wrap(nil, super, 5, 7, square, 16)
    check("the hook sorts the arguments in all three orders and answers the same angle, not the game's", type(a1) == "number" and a1 == a2 and a2 == a3)
    seen = nil
    BestLaneAngle.wrap(5, super, 7, 16, nil)
    check("a boundary that is no table goes to the game's own function with the right arguments", seen ~= nil and seen[1] == 5 and seen[2] == 7 and seen[3] == 16)
end
realPrint(string.format("best_lane_angle_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
