--[[
    BestLaneAngle.lua -- the AI worker's "Automatic" work direction takes the longest side of the field, not the first angle that ties.

    The game (BoundaryLineGenerationTask.getOptimalBoundaryAngle, read from the decompiled 1.25.1.0 scripts) tries 16 angles from 0 to 180 degrees and keeps the one with the FEWEST LINES, but it counts the
    boundary crossings of ONE scan line (getNumLinesByAngle: a loop that breaks after its first round, and a second loop that does nothing). For a field without notches that is 1 at every angle: all
    tie, the comparison is strict, and the first angle, 0 (north to south), always wins, whatever the shape of the field. The function even gets the field's extent across the lanes
    (getFurthestPointToLine) and throws it away.

    Here: the angle is the one with the smallest EXTENT ACROSS THE LANES (the number of passes is the extent divided by the working width, so the lanes run along the longest dimension: the fewest turns).
    For a convex field the best direction is parallel to one of its edges, so the candidates are the game's 16 angles plus the directions of the CANDIDATE_EDGES longest edges (at least MIN_EDGE_M long);
    ties go to the first candidate. Notches in a field are the game's own business (its lane generation handles them); the extent is a good guide for the field as a whole.
]]
BestLaneAngle = { ENABLED = true, CANDIDATE_EDGES = 24, MIN_EDGE_M = 5, LOG_FIRST = 6, logged = 0 }

local function say(format, ...)
    print(string.format("[RandomFixes] " .. format, ...))
end

-- The extent of the boundary across lanes that run in direction (dirX, dirZ): the spread of its points along the normal (metres).
function BestLaneAngle.extent(boundary, dirX, dirZ)
    local nx, nz = -dirZ, dirX
    local lo, hi = math.huge, -math.huge
    for _, p in ipairs(boundary) do
        local d = p[1] * nx + p[2] * nz
        if d < lo then lo = d end
        if d > hi then hi = d end
    end
    if lo == math.huge then
        return math.huge
    end
    return hi - lo
end

-- The candidate directions: the 16 angles of the game (0 .. 180 degrees; direction = (sin a, cos a) as the game's getDirectionFromYRotation) and the directions of the longest edges.
function BestLaneAngle.candidates(boundary, steps)
    local list = {}
    for k = 0, steps - 1 do
        local a = k * math.pi / steps
        list[#list + 1] = { math.sin(a), math.cos(a) }
    end
    local edges = {}
    for i = 1, #boundary - 1 do
        local dx, dz = boundary[i + 1][1] - boundary[i][1], boundary[i + 1][2] - boundary[i][2]
        local length = math.sqrt(dx * dx + dz * dz)
        if length >= BestLaneAngle.MIN_EDGE_M then
            edges[#edges + 1] = { dx / length, dz / length, length }
        end
    end
    table.sort(edges, function(a, b) return a[3] > b[3] end)
    for i = 1, math.min(#edges, BestLaneAngle.CANDIDATE_EDGES) do
        list[#list + 1] = { edges[i][1], edges[i][2] }
    end
    return list
end

-- The direction with the smallest extent across the lanes; returns dirX, dirZ, the extent, and the extent at the first candidate (the game's choice, angle 0).
function BestLaneAngle.best(boundary, steps)
    local best, bestExtent, firstExtent
    for _, dir in ipairs(BestLaneAngle.candidates(boundary, steps)) do
        local e = BestLaneAngle.extent(boundary, dir[1], dir[2])
        firstExtent = firstExtent or e
        if bestExtent == nil or e < bestExtent - 1e-6 then
            best, bestExtent = dir, e
        end
    end
    if best == nil then
        return nil
    end
    return best[1], best[2], bestExtent, firstExtent
end

if BoundaryLineGenerationTask ~= nil and BoundaryLineGenerationTask.getOptimalBoundaryAngle ~= nil and Utils ~= nil and not BestLaneAngle.hooked then
    BestLaneAngle.hooked = true
    BoundaryLineGenerationTask.getOptimalBoundaryAngle = Utils.overwrittenFunction(BoundaryLineGenerationTask.getOptimalBoundaryAngle, function(self, superFunc, centerX, centerZ, boundary, steps)
        if not BestLaneAngle.ENABLED or boundary == nil or #boundary < 3 then
            return superFunc(self, centerX, centerZ, boundary, steps)
        end
        local ok, dirX, dirZ, extent, firstExtent = pcall(BestLaneAngle.best, boundary, steps or 16)
        if not ok or dirX == nil then
            return superFunc(self, centerX, centerZ, boundary, steps)
        end
        local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
        angle = angle % math.pi                                      -- (a lane has no direction: 0 .. 180 degrees, as the game's own)
        if BestLaneAngle.logged < BestLaneAngle.LOG_FIRST and extent < (firstExtent or extent) - 1 then
            BestLaneAngle.logged = BestLaneAngle.logged + 1
            say("lane angle: %.0f degrees (the lanes are %.0f m across, the game's first angle 0 would make it %.0f m)", math.deg(angle), extent, firstExtent)
        end
        return angle
    end)
end

if addConsoleCommand ~= nil and not BestLaneAngle.commandAdded then
    BestLaneAngle.commandAdded = true
    addConsoleCommand("rfLaneAngle", "rfLaneAngle [on|off]: the automatic work direction along the longest side of the field (off: the game's own, always 0 degrees on a plain field)", "consoleSwitch", BestLaneAngle)
    function BestLaneAngle:consoleSwitch(what)
        if what == "on" then
            BestLaneAngle.ENABLED = true
        elseif what == "off" then
            BestLaneAngle.ENABLED = false
        end
        return "lane angle fix: " .. (BestLaneAngle.ENABLED and "on" or "off")
    end
end
