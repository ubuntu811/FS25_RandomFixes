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

-- the override
local angle = BoundaryLineGenerationTask:getOptimalBoundaryAngle(0, 0, r, 16)
check("the override returns the angle of the long side (east-west lanes: 90 degrees), in 0 .. 180", math.abs(angle - math.pi / 2) < 1e-6 and angle >= 0 and angle < math.pi)
angle = BoundaryLineGenerationTask:getOptimalBoundaryAngle(0, 0, tall, 16)
check("a field long north to south: 0 as before", math.abs(angle) < 1e-6 or math.abs(angle - math.pi) < 1e-6)
check("the lines are as the game computes them from that angle: direction (sin, cos)", (function() local a = BoundaryLineGenerationTask:getOptimalBoundaryAngle(0, 0, turned, 16); local x, z = MathUtil.getDirectionFromYRotation(a); return math.abs(BestLaneAngle.extent(turned, x, z) - 120) < 1e-6 end)())
check("it said so (once per call, the first few)", #log >= 1 and tostring(log[1]):find("lane angle", 1, true) ~= nil)
BestLaneAngle.ENABLED = false
check("switched off: the game's own answer", BoundaryLineGenerationTask:getOptimalBoundaryAngle(0, 0, r, 16) == 0)
BestLaneAngle.ENABLED = true
check("a degenerate boundary: the game's own answer", BoundaryLineGenerationTask:getOptimalBoundaryAngle(0, 0, { { 0, 0 }, { 1, 1 } }, 16) == 0)
print = realPrint
realPrint(string.format("best_lane_angle_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
