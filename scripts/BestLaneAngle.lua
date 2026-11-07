--[[
    BestLaneAngle.lua -- the AI worker's "Automatic" work direction takes the longest side of the field, not the first angle that ties.

    The game (BoundaryLineGenerationTask.getOptimalBoundaryAngle, read from the decompiled 1.25.1.0 scripts) tries 16 angles from 0 to 180 degrees and keeps the one with the FEWEST LINES, but it counts the
    boundary crossings of ONE scan line (getNumLinesByAngle: a loop that breaks after its first round, and a second loop that does nothing). For a field without notches that is 1 at every angle: all
    tie, the comparison is strict, and the first angle, 0 (north to south), always wins, whatever the shape of the field. The function even gets the field's extent across the lanes
    (getFurthestPointToLine) and throws it away.

    Here (RULE "side", the default): the lanes run parallel to the LONGEST SIDE of the field. A side is a run of consecutive boundary edges that bend only a little (MERGE_DEG per corner, MAX_BEND_DEG
    in all: a hand-driven outline comes out of the game's simplification as several short edges along one side); its direction is the chord from the start to the end of the run. A boundary with no sharp
    corner at all (a round field) has no sides and falls back to the extent rule. RULE "extent": the angle is the one with the smallest EXTENT ACROSS THE LANES (the number of passes is the extent divided by the working width, so the lanes run along the longest dimension: the fewest turns).
    For a convex field the best direction is parallel to one of its edges, so the candidates are the game's 16 angles plus the directions of the CANDIDATE_EDGES longest edges (at least MIN_EDGE_M long);
    ties go to the first candidate. Notches in a field are the game's own business (its lane generation handles them); the extent is a good guide for the field as a whole.
]]
BestLaneAngle = { ENABLED = true, RULE = "side", MERGE_DEG = 14, SHARP_DEG = 35, CANDIDATE_EDGES = 24, MIN_EDGE_M = 5, LOG_FIRST = 6, logged = 0 }

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

-- The longest side: runs of consecutive edges that stay within MERGE_DEG of the run's own direction so far, started at a corner of more than SHARP_DEG. Returns the unit direction of the longest run's chord, its
-- length (the chord's), and the number of sides; nil when the boundary has no sharp corner to start a run at (a round field) or is degenerate.
function BestLaneAngle.longestSide(boundary)
    local points = {}
    for i, p in ipairs(boundary) do
        points[i] = p
    end
    local n = #points
    if n >= 2 and math.abs(points[n][1] - points[1][1]) < 1e-6 and math.abs(points[n][2] - points[1][2]) < 1e-6 then
        points[n] = nil                                     -- (a closed line repeats its first point)
        n = n - 1
    end
    if n < 3 then
        return nil
    end
    local edges = {}
    for i = 1, n do
        local a, b = points[i], points[i % n + 1]
        local dx, dz = b[1] - a[1], b[2] - a[2]
        local length = math.sqrt(dx * dx + dz * dz)
        if length < 1e-9 then
            return nil
        end
        edges[i] = { dx, dz, length }
    end
    local function turnDeg(e1, e2)
        local cross = e1[1] * e2[2] - e1[2] * e2[1]
        local dot = e1[1] * e2[1] + e1[2] * e2[2]
        return math.abs(math.deg(math.atan2(cross, dot)))
    end
    -- start the walk at a corner that is sharp, so that a side is never cut in two by the start of the list
    local start
    for i = 1, n do
        if turnDeg(edges[i], edges[i % n + 1]) > BestLaneAngle.SHARP_DEG then
            start = i % n + 1
            break
        end
    end
    if start == nil then
        return nil
    end
    local best, bestLength, sides = nil, -1, 0
    local i, walked = start, 0
    while walked < n do
        local sx, sz = edges[i][1], edges[i][2]
        local count = 1
        local j = i % n + 1
        while count + walked < n and turnDeg({ sx, sz }, edges[j]) <= BestLaneAngle.MERGE_DEG do
            sx, sz = sx + edges[j][1], sz + edges[j][2]
            count = count + 1
            j = j % n + 1
        end
        local length = math.sqrt(sx * sx + sz * sz)
        sides = sides + 1
        if length > bestLength then
            best, bestLength = { sx / length, sz / length }, length
        end
        walked = walked + count
        i = j
    end
    return best[1], best[2], bestLength, sides
end

-- The direction to use, by RULE: returns dirX, dirZ, the extent across the lanes in it, and the extent at angle 0 (the game's choice).
function BestLaneAngle.choose(boundary, steps)
    local ex, ez, e0
    if BestLaneAngle.RULE == "side" then
        local dx, dz = BestLaneAngle.longestSide(boundary)
        if dx ~= nil then
            return dx, dz, BestLaneAngle.extent(boundary, dx, dz), BestLaneAngle.extent(boundary, 0, 1)
        end
    end
    return BestLaneAngle.best(boundary, steps)
end

if BoundaryLineGenerationTask ~= nil and BoundaryLineGenerationTask.getOptimalBoundaryAngle ~= nil and Utils ~= nil and not BestLaneAngle.hooked then
    BestLaneAngle.hooked = true
    BoundaryLineGenerationTask.getOptimalBoundaryAngle = Utils.overwrittenFunction(BoundaryLineGenerationTask.getOptimalBoundaryAngle, function(self, superFunc, centerX, centerZ, boundary, steps)
        if not BestLaneAngle.ENABLED or boundary == nil or #boundary < 3 then
            return superFunc(self, centerX, centerZ, boundary, steps)
        end
        local ok, dirX, dirZ, extent, firstExtent = pcall(BestLaneAngle.choose, boundary, steps or 16)
        if not ok or dirX == nil then
            return superFunc(self, centerX, centerZ, boundary, steps)
        end
        local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
        angle = angle % math.pi                                      -- (a lane has no direction: 0 .. 180 degrees, as the game's own)
        if BestLaneAngle.logged < BestLaneAngle.LOG_FIRST and extent < (firstExtent or extent) - 1 then
            BestLaneAngle.logged = BestLaneAngle.logged + 1
            say("lane angle (%s): %.0f degrees (the lanes are %.0f m across, the game's first angle 0 would make it %.0f m)", BestLaneAngle.RULE, math.deg(angle), extent, firstExtent)
        end
        return angle
    end)
end

if addConsoleCommand ~= nil and not BestLaneAngle.commandAdded then
    BestLaneAngle.commandAdded = true
    addConsoleCommand("rfLaneAngle", "rfLaneAngle [side|extent|off]: the automatic work direction: along the longest side of the field (side), or the smallest extent across the lanes (extent); off: the game's own (always 0 degrees on a plain field)", "consoleSwitch", BestLaneAngle)
    function BestLaneAngle:consoleSwitch(what)
        if what == "off" then
            BestLaneAngle.ENABLED = false
        elseif what == "side" or what == "extent" then
            BestLaneAngle.ENABLED, BestLaneAngle.RULE = true, what
        end
        return "lane angle fix: " .. (BestLaneAngle.ENABLED and ("on, rule " .. BestLaneAngle.RULE) or "off")
    end
end
