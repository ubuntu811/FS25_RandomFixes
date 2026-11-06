--[[
    ReseatDecals.lua -- the map's puddles stay on the ground when the ground is lowered or raised under them.

    The puddles of a map (CreativeHorizon: ~2,330 "roadPuddlePiece" shapes in the group "wetnessPieces", plus "intersectionPuddles") are ordinary meshes at the height they were made at. The road under them is
    baked into the terrain's surface (terrainDecal), so it follows a cut or a fill, and the puddles are left floating (or buried). The map's other decals are baked into the terrain too (nonRenderable terrainDecal:
    road pieces, centre lines, parking lines, manholes, tyre tracks) and need nothing.

    How: on demand, no hooks and nothing in the background (nobody deforms the terrain every day). The button "Reseat now" of the "Map fixes" tab of WAILA's debug hub (or the console command reseatDecals) walks
    the map file's nodes (the terrain's parent, not the whole mission scene) in small slices (a time budget per frame: 8 ms for a pass somebody asked for, 1.5 ms for putting the saved moves back at the start); measuring and moving the puddles is one go and remembers every shape whose name holds PATTERNS, measures each one's height above its water level (the world bounding sphere's centre against the level),
    takes the MEDIAN as the normal offset of a puddle over its level (nearly all are untouched), and moves any puddle that is off by more than TOLERANCE, as a whole, up or down by the difference.
    The level is the lowest ground height on the puddle's BORDER (a ring of samples, the ground's slope taken out; see waterLevel): a lowered or raised stretch moves puddles with it; a pothole INSIDE the border
    leaves the puddle at the rim, the water fills the hole; a dip that crosses the border lets the water down to the lowest point there, the terrain covers the part of the mesh over higher ground. Fill the dip and
    press the button again: the level comes back up. The moves are saved in the savegame (reseatDecals.xml, like MovePlaceablesAdvanced's own file) and put back at the next load, so the button is pressed once
    per edit, not once per session.

    The log says how many were found, the offset, how far off the pieces are (percentiles) and how many were moved ("[RandomFixes] puddles: ...").
]]
ReseatDecals = { PATTERNS = { "puddle" }, POST_NAMES = { "leitpfosten_r", "leitpfosten_l" }, POST_MAX_SHARE = nil, POST_MAX_MIN = 8, MIN_MEMBERS = 20, DEFAULT_OFFSET = { puddles = 0.002, posts = 0 }, TOLERANCE = 0.06, BUDGET_REQUEST_MS = 8, BUDGET_RESTORE_MS = 6, START_DELAY_S = 2, MAX_NODES_PER_SLICE = 4000, FILE = "reseatDecals.xml", MIN_SAVED_M = 0.01, RING_SAMPLES = 8, RING_PART = 0.9, MAX_RING_M = 3, MAX_SHIFT_M = 6, LIFT_M = 0.015, RAY_UP_M = 0.3, RAY_LEN_M = 0.7, POST_SIDE_M = 0.3 }

local function say(format, ...)
    print(string.format("[RandomFixes] " .. format, ...))
end

function ReseatDecals.matches(name)
    local lower = string.lower(name or "")
    for _, pattern in ipairs(ReseatDecals.PATTERNS) do
        if lower:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

-- What gets reseated: "puddles" are shapes whose name holds PATTERNS (their level is the lowest point of their border, they get the LIFT_M on top). "posts" are the roadside guide posts: the nodes named exactly
-- as POST_NAMES ("leitpfosten_r" / "leitpfosten_l"), each with its own height; their level is the ground at that spot. Both are MOVED as a whole, up or down. A post is a dynamic body on a breakable joint, and
-- moving its node moves its collision body with it (measured with reseatPostTest: node and "coli" +0.30 m together, and it stayed there). Safeguards, after a first version moved the "Leitpfosten" CONTAINER
-- groups (one sits at the world origin) and took every post of the map with it: only nodes that have a "joint" child are taken, never the containers; a post with a structure under it is left alone or follows
-- it; and, only when POST_MAX_SHARE is set (it is off: nil; e.g. 0.10 = at most 10% of all the posts, at least POST_MAX_MIN, per pass), a pass that would move more is refused.
ReseatDecals.CLASS_LIST = { "puddles", "posts" }
function ReseatDecals.classOf(node, name)
    local lower = string.lower(name or "")
    for _, post in ipairs(ReseatDecals.POST_NAMES) do
        if lower == post then
            local joint = getChild(node, "joint")
            if joint ~= nil and joint ~= 0 then
                return "posts"
            end
            return nil
        end
    end
    if ReseatDecals.matches(name) and getHasClassId(node, ClassIds.SHAPE) then
        return "puddles"
    end
    return nil
end

-- The normal offset of a class over its level: the median of its members when there are enough of them (nearly all of them untouched), a fixed default when there are not (a map with two posts, one of them in the
-- air: the median of two would be half way and move the good one too). Returns the offset and whether it is the default.
function ReseatDecals.offsetFor(class, list)
    if #list >= ReseatDecals.MIN_MEMBERS then
        return ReseatDecals.median(list) or 0, false
    end
    return ReseatDecals.DEFAULT_OFFSET[class] or 0, true
end

function ReseatDecals.liftOf(class)
    return class == "puddles" and ReseatDecals.LIFT_M or 0
end

function ReseatDecals.median(list)
    local n = #list
    if n == 0 then
        return nil
    end
    local sorted = {}
    for i = 1, n do
        sorted[i] = list[i]
    end
    table.sort(sorted)
    if n % 2 == 1 then
        return sorted[(n + 1) / 2]
    end
    return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

-- p in 0..1 of the absolute deviations from the offset (for the log)
function ReseatDecals.percentile(devs, offset, p)
    local absolute = {}
    for i, d in ipairs(devs) do
        absolute[i] = math.abs(d - offset)
    end
    table.sort(absolute)
    if #absolute == 0 then
        return 0
    end
    return absolute[math.max(1, math.min(#absolute, math.ceil(p * #absolute)))]
end

-- how far to move a piece (metres, + up) so that it is back at the ground's height plus the offset; nil when it is within the tolerance
-- A puddle that is farther off than MAX_SHIFT_M is not over a cut road but on something else (a bridge, a ramp, a tunnel: the ground is far below it): it is left alone (second return value true).
-- A puddle that is moved gets LIFT_M on top, so the ground's 1 m triangles do not poke through it.
function ReseatDecals.shiftFor(sphereY, groundY, offset, tolerance, lift)
    local delta = groundY + offset - sphereY
    if math.abs(delta) > ReseatDecals.MAX_SHIFT_M then
        return nil, true
    end
    if math.abs(delta) > tolerance then
        return delta + (lift or ReseatDecals.LIFT_M)
    end
    return nil
end

-- a puddle has no id (the map file's nodes sit at the origin, the vertices carry the world position): its name and where its bounding sphere's centre is in x / z (a height shift leaves that alone) are its key
function ReseatDecals.keyOf(name, cx, cz)
    return string.format("%s@%.2f,%.2f", name, cx, cz)
end

-- what is worth saving: every piece that was moved, by key, with how far (metres, + up); entries of the file that nothing matched are kept only while the scene is not indexed (a save right after loading must
-- not lose them), once it is they are dropped (a piece that is no longer reseated, like the guide posts, must not stay in the file)
function ReseatDecals.records(pieces, saved, indexed, savedPaths)
    local list, seen = {}, {}
    for _, piece in ipairs(pieces or {}) do
        seen[piece.key] = true
        if math.abs(piece.shift or 0) >= ReseatDecals.MIN_SAVED_M then
            list[#list + 1] = { key = piece.key, shift = piece.shift, path = piece.path and table.concat(piece.path, ",") or nil }
        end
    end
    for key, shift in pairs(saved or {}) do
        if not seen[key] and not indexed then
            list[#list + 1] = { key = key, shift = shift, path = savedPaths and savedPaths[key] or nil }
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

local function savePath()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if info == nil or info.savegameDirectory == nil then
        return nil
    end
    return info.savegameDirectory .. "/" .. ReseatDecals.FILE
end

function ReseatDecals.readFile()
    local saved, paths, path = {}, {}, savePath()
    if path == nil or XMLFile == nil then
        return saved, paths
    end
    local xml = XMLFile.loadIfExists ~= nil and XMLFile.loadIfExists("ReseatDecals", path) or nil
    if xml == nil then
        return saved, paths
    end
    local i = 0
    while true do
        local key = string.format("reseatDecals.piece(%d)", i)
        if not xml:hasProperty(key) then
            break
        end
        local id, shift = xml:getString(key .. "#key"), xml:getFloat(key .. "#shift")
        if id ~= nil and shift ~= nil then
            saved[id] = shift
            paths[id] = xml:getString(key .. "#path")
        end
        i = i + 1
    end
    xml:delete()
    return saved, paths
end

function ReseatDecals.save()
    local path = savePath()
    if path == nil or XMLFile == nil then
        return
    end
    local state = ReseatDecals.state
    local fileSaved, filePaths
    if state == nil then
        fileSaved, filePaths = ReseatDecals.readFile()
    end
    local records = ReseatDecals.records(state ~= nil and state.pieces or {}, state ~= nil and state.saved or fileSaved, state ~= nil and state.indexed, state ~= nil and state.savedPaths or filePaths)
    local xml = XMLFile.create("ReseatDecals", path, "reseatDecals")
    if xml == nil then
        say("puddles: could not write %s", path)
        return
    end
    for i, record in ipairs(records) do
        local key = string.format("reseatDecals.piece(%d)", i - 1)
        xml:setString(key .. "#key", record.key)
        xml:setFloat(key .. "#shift", record.shift)
        if record.path ~= nil and record.path ~= "" then
            xml:setString(key .. "#path", record.path)
        end
    end
    xml:save()
    xml:delete()
    say("puddles: %d moved puddle(s) written to %s", #records, ReseatDecals.FILE)
end

-- The water level of a piece: where its flat surface stands. A hole inside the piece's border is filled up to the rim (the mesh stays at the rim, over the hole); only ground that is lower AT the border lets
-- the water out: the level is the lowest point of the border, with the ground's slope taken out (an untouched puddle on a slope keeps its own level). ring: n ground heights evenly round the piece at
-- ringRadius, the first one towards +x. The slope comes from a plane fitted through them without the ones that sit clearly off it (a dip or a mound at the border must not tilt it). Returns the level and the
-- plane's height at the centre (the rim).
local function fitPlane(points)
    local n, sx, sz, sxx, sxz, szz, sh, sxh, szh = 0, 0, 0, 0, 0, 0, 0, 0, 0
    for _, p in ipairs(points) do
        n = n + 1
        sx, sz, sxx, sxz, szz = sx + p.x, sz + p.z, sxx + p.x * p.x, sxz + p.x * p.z, szz + p.z * p.z
        sh, sxh, szh = sh + p.h, sxh + p.x * p.h, szh + p.z * p.h
    end
    -- h = a + b x + c z: the normal equations by Cramer's rule
    local function det(m) return m[1] * (m[5] * m[9] - m[6] * m[8]) - m[2] * (m[4] * m[9] - m[6] * m[7]) + m[3] * (m[4] * m[8] - m[5] * m[7]) end
    local d = det({ n, sx, sz, sx, sxx, sxz, sz, sxz, szz })
    if math.abs(d) < 1e-12 then
        return sh / math.max(n, 1), 0, 0
    end
    return det({ sh, sx, sz, sxh, sxx, sxz, szh, sxz, szz }) / d, det({ n, sh, sz, sx, sxh, sxz, sz, szh, szz }) / d, det({ n, sx, sh, sx, sxx, sxh, sz, sxz, szh }) / d
end

function ReseatDecals.waterLevel(ringHeights, ringRadius)
    local n = #ringHeights
    local all = {}
    for i, h in ipairs(ringHeights) do
        local a = 2 * math.pi * (i - 1) / n
        all[i] = { x = ringRadius * math.cos(a), z = ringRadius * math.sin(a), h = h }
    end
    local a, b, c = fitPlane(all)
    -- the ones far off the first fit are left out and the plane is fitted again: a dip or a mound at the border must not tilt it (the good ones are only slightly off, the odd one a lot)
    local worst = 0
    for _, p in ipairs(all) do
        worst = math.max(worst, math.abs(p.h - (a + b * p.x + c * p.z)))
    end
    if worst > 0.01 then
        local keep = {}
        for _, p in ipairs(all) do
            if math.abs(p.h - (a + b * p.x + c * p.z)) <= 0.5 * worst then
                keep[#keep + 1] = p
            end
        end
        if #keep >= 4 and #keep < n then
            a, b, c = fitPlane(keep)
        end
    end
    local level = math.huge
    for _, p in ipairs(all) do
        level = math.min(level, p.h - b * p.x - c * p.z)
    end
    return math.min(level, a), a
end

-- The surface a piece rests on when that is a structure (a bridge deck, a slab, a placeable): a ray straight down from just above it, against static objects, buildings and road colliders (not the terrain),
-- and the height where it hits is the true surface height there. A puddle has no collision of its own, so its own spot is cast; a post has (its parts are ignored), so four spots 30 cm to its sides are (the
-- highest hit counts). nil when nothing is under it: the ground is the terrain then. Only asked for pieces that are about to move.
local function structureMask()
    local mask = 0
    for _, name in ipairs({ "STATIC_OBJECT", "BUILDING", "ROAD" }) do
        if CollisionFlag ~= nil and CollisionFlag[name] ~= nil then
            mask = mask + CollisionFlag[name]
        end
    end
    return mask
end

local function insideNode(hit, root)
    local node, depth = hit, 0
    while node ~= nil and node ~= 0 and depth < 10 do
        if node == root then
            return true
        end
        node = getParent(node)
        depth = depth + 1
    end
    return false
end

function ReseatDecals.structureSurface(piece, y)
    if raycastClosest == nil then
        return nil
    end
    local mask = structureMask()
    if mask == 0 then
        return nil
    end
    local hitNode, hitY
    local target = { onHit = function(_, nodeId, _, hy) hitNode, hitY = nodeId, hy; return false end }
    local spots
    if piece.class == "posts" then
        local d = ReseatDecals.POST_SIDE_M
        spots = { { piece.cx + d, piece.cz }, { piece.cx - d, piece.cz }, { piece.cx, piece.cz + d }, { piece.cx, piece.cz - d } }
    else
        spots = { { piece.cx, piece.cz } }
    end
    local best
    for _, spot in ipairs(spots) do
        hitNode, hitY = nil, nil
        raycastClosest(spot[1], y + ReseatDecals.RAY_UP_M, spot[2], 0, -1, 0, ReseatDecals.RAY_LEN_M, "onHit", target, mask)
        if hitNode ~= nil and hitY ~= nil and not insideNode(hitNode, piece.node) and (best == nil or hitY > best) then
            best = hitY
        end
    end
    return best
end

local function now() return getTimeSec() * 1000 end

-- phase 1: the scene walked in slices; every matching shape is remembered
local function collect(state, budgetMs)
    local t0 = now()
    local steps = 0
    while #state.stack > 0 do
        local top = state.stack[#state.stack]
        if top.index == 0 then
            local node = top.node
            local name = getName(node)
            local class = ReseatDecals.classOf(node, name)
            if class ~= nil then
                local cx, cz
                if class == "puddles" then
                    local sx, _, sz = getShapeWorldBoundingSphere(node)
                    cx, cz = sx, sz
                else
                    local px, _, pz = getWorldTranslation(node)
                    cx, cz = px, pz
                end
                local path = {}
                for i = 2, #state.stack do
                    path[#path + 1] = state.stack[i].pos
                end
                state.pieces[#state.pieces + 1] = { node = node, class = class, key = ReseatDecals.keyOf(name, cx, cz), shift = 0, cx = cx, cz = cz, path = path }
            end
            top.count = class == "posts" and 0 or getNumOfChildren(node)       -- (the parts of a post are not looked at)
        end
        if top.index < top.count then
            local child = getChildAt(top.node, top.index)
            top.index = top.index + 1
            state.stack[#state.stack + 1] = { node = child, index = 0, count = 0, pos = top.index - 1 }
        else
            state.stack[#state.stack] = nil
        end
        steps = steps + 1
        state.visited = (state.visited or 0) + 1
        if steps >= ReseatDecals.MAX_NODES_PER_SLICE or (steps % 64 == 0 and now() - t0 > budgetMs) then
            return false
        end
    end
    return true
end

local function height(piece)
    if piece.class == "posts" then
        local x, y, z = getWorldTranslation(piece.node)
        local ground = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
        return y, ground, ground
    end
    local cx, cy, cz, radius = getShapeWorldBoundingSphere(piece.node)
    local ringRadius = ReseatDecals.RING_PART * math.min(radius or 1, ReseatDecals.MAX_RING_M)
    local ring = {}
    local n = ReseatDecals.RING_SAMPLES
    for i = 1, n do
        local a = 2 * math.pi * (i - 1) / n
        ring[i] = getTerrainHeightAtWorldPos(g_terrainNode, cx + math.cos(a) * ringRadius, 0, cz + math.sin(a) * ringRadius)
    end
    local level, rim = ReseatDecals.waterLevel(ring, ringRadius)
    return cy, level, rim
end

-- phase 2: the offset of an untouched piece over its level (the median of its class), and how scattered they are
local function measure(state, budgetMs)
    local t0 = now()
    while state.cursor <= #state.pieces do
        local piece = state.pieces[state.cursor]
        local y, ground, rim = height(piece)
        state.devs[state.cursor] = y - ground
        if state.pieces[state.cursor].class == "puddles" and rim - ground > 0.02 then
            state.bowls = (state.bowls or 0) + 1
        end
        state.cursor = state.cursor + 1
        if now() - t0 > budgetMs then
            return false
        end
    end
    return true
end

local function sweep(state, budgetMs)
    local t0 = now()
    local rect = state.rect
    while state.cursor <= #state.pieces do
        local piece = state.pieces[state.cursor]
        local inside = rect == nil or (piece.cx >= rect.minX and piece.cx < rect.maxX and piece.cz >= rect.minZ and piece.cz < rect.maxZ)
        local y, ground
        local delta = nil
        if inside then
            y, ground = height(piece)
            local far
            delta, far = ReseatDecals.shiftFor(y, ground, state.offsets[piece.class] or 0, ReseatDecals.TOLERANCE, ReseatDecals.liftOf(piece.class))
            if delta ~= nil or far then
                -- about to move, or too far off to move: is there a structure under it? Its surface is the level then (the ray's hit height), the terrain is not
                local surface = ReseatDecals.structureSurface(piece, y)
                if surface ~= nil then
                    state.onStructure = (state.onStructure or 0) + 1
                    local toSurface = surface + (state.offsets[piece.class] or 0) + ReseatDecals.liftOf(piece.class) - y
                    delta = math.abs(toSurface) > ReseatDecals.TOLERANCE and toSurface or nil     -- (a deck that was moved takes it along; one that was not leaves it where it is)
                elseif far then
                    state.farOff = (state.farOff or 0) + 1
                    delta = nil
                end
            end
        end
        if delta ~= nil and piece.class == "posts" then
            state.postMoves[#state.postMoves + 1] = { piece = piece, delta = delta }
            delta = nil
        end
        if delta ~= nil then
            local x, wy, z = getWorldTranslation(piece.node)
            setWorldTranslation(piece.node, x, wy + delta, z)
            piece.shift = (piece.shift or 0) + delta
            state.moved = state.moved + 1
            state.movedTotal = state.movedTotal + 1
        end
        state.cursor = state.cursor + 1
        if now() - t0 > budgetMs then
            return false
        end
    end
    return true
end

-- On demand: nothing runs in the background. At the start of a mission the saved moves are put back (only when the savegame has any); a pass (find, measure, move the ones that are off) runs when asked for:
-- the button of the "Map fixes" tab in WAILA's hub (ReseatDecals.requestPass), or the console command reseatDecals.
local function newState()
    local saved, savedPaths = ReseatDecals.readFile()
    return { phase = "wait", waited = 0, stack = {}, pieces = {}, devs = {}, cursor = 1, moved = 0, movedTotal = 0, postMoves = {}, saved = saved, savedPaths = savedPaths, fastKeys = {}, indexed = false, purpose = nil, wantPass = false }
end

-- the walk starts at the map file's own nodes (the terrain's parent: the map's top-level groups hang there), not at the root of the whole mission scene with every placeable and vehicle in it
local function searchRoot()
    local terrain = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
    local parent = terrain ~= nil and terrain ~= 0 and getParent ~= nil and getParent(terrain) or nil
    if parent ~= nil and parent ~= 0 then
        return parent
    end
    return getRootNode()
end

local function startCollect(state, purpose)
    state.stack = { { node = searchRoot(), index = 0, count = 0 } }
    state.pieces = {}
    state.purpose = purpose
    state.phase = "collect"
    state.startedAt = now()
end

-- asks for a pass: returns a line for the screen / console
function ReseatDecals.requestPass(rect)
    local state = ReseatDecals.state
    if state == nil or g_currentMission == nil then
        return "not ready yet"
    end
    if state.phase == "collect" or state.phase == "measure" or state.phase == "sweep" then
        return "a pass is running"
    end
    state.wantPass = true
    state.rect = rect
    return rect == nil and "reseating the map puddles" or "reseating the map puddles in the scanned area"
end

-- for the hub's Run button: a pass that is asked for or running makes the row busy ("Running ..." instead of Run), so nobody starts it twice
function ReseatDecals.isBusy()
    local state = ReseatDecals.state
    return state ~= nil and (state.wantPass == true or state.phase == "collect" or state.phase == "measure" or state.phase == "sweep")
end

function ReseatDecals.status()
    local state = ReseatDecals.state
    if state == nil then
        return "not started"
    end
    if state.wantPass then
        return "starting ..."
    end
    if state.phase == "collect" then
        return "running: finding the puddles and posts"
    elseif state.phase == "measure" or state.phase == "sweep" then
        return "running: moving them"
    end
    if state.last ~= nil then
        return string.format("done: %d pieces, %d moved (%d in all)", state.last.found, state.last.moved, state.movedTotal)
    end
    return "no pass yet this session"
end

-- a row of WAILA's hub shows the status: when it changes by itself (the pass finishes some frames after the click) the hub is told to reload its rows
local function refreshHub()
    local waila = g_currentMission ~= nil and g_currentMission.waila or nil
    if waila == nil then
        return
    end
    local refresh = waila.refreshDebugHubKeepSelection or waila.refreshDebugHub
    if refresh ~= nil then
        pcall(refresh)
    end
end

-- the guide posts that are to be moved are applied together, unless that is more than a mistake can explain
local function applyPostMoves(state)
    local moves = state.postMoves
    state.postMoves = {}
    if #moves == 0 then
        return
    end
    local total = 0
    for _, piece in ipairs(state.pieces) do
        if piece.class == "posts" then
            total = total + 1
        end
    end
    if ReseatDecals.POST_MAX_SHARE ~= nil and #moves > math.max(ReseatDecals.POST_MAX_MIN, ReseatDecals.POST_MAX_SHARE * total) then
        say("guide posts: %d of %d would be moved: refused, that is far more than an edit does (nothing was moved)", #moves, total)
        return
    end
    for _, move in ipairs(moves) do
        local x, wy, z = getWorldTranslation(move.piece.node)
        setWorldTranslation(move.piece.node, x, wy + move.delta, z)
        move.piece.shift = (move.piece.shift or 0) + move.delta
        state.moved = state.moved + 1
        state.movedTotal = state.movedTotal + 1
    end
    say("guide posts: %d moved to the ground at their own spots (of %d)", #moves, total)
end

local function doSweep(state, budget)
    if sweep(state, budget) then
        applyPostMoves(state)
        say("%d moved back to the ground (%d in all); %d of the pieces about to move rest on a structure (a ray down hit a bridge, a slab, a building: they stay or follow it), %d left alone for being more than %.0f m off", state.moved, state.movedTotal, state.onStructure or 0, state.farOff or 0, ReseatDecals.MAX_SHIFT_M)
        state.onStructure, state.farOff = 0, 0
        state.last = { found = #state.pieces, moved = state.moved, offset = state.offset }
        state.moved = 0
        state.phase = "idle"
        refreshHub()
    end
end

-- Putting the saved moves back without walking the scene: a record that has the piece's child-index path from the search root is resolved directly (a few calls each), checked (the name, and the position the
-- key says), and moved. Returns how many were put back and how many could not be resolved (those need the walk).
local function positionOf(class, node)
    if class == "puddles" then
        local x, _, z = getShapeWorldBoundingSphere(node)
        return x, z
    end
    local x, _, z = getWorldTranslation(node)
    return x, z
end

local function fastRestore(state)
    local restored, failed = 0, 0
    local root = searchRoot()
    for key, shift in pairs(state.saved) do
        local ok = false
        local pathText = state.savedPaths ~= nil and state.savedPaths[key] or nil
        if math.abs(shift) > ReseatDecals.MAX_SHIFT_M then
            ok = true                                                     -- (a move that big is ignored, not looked for)
        elseif pathText ~= nil and pathText ~= "" then
            local node = root
            for index in string.gmatch(pathText, "[^,]+") do
                node = node ~= nil and node ~= 0 and getChildAt(node, tonumber(index)) or nil
            end
            if node ~= nil and node ~= 0 then
                local name = getName(node)
                local class = ReseatDecals.classOf(node, name)
                if class ~= nil then
                    local cx, cz = positionOf(class, node)
                    if ReseatDecals.keyOf(name, cx, cz) == key then
                        local x, wy, z = getWorldTranslation(node)
                        setWorldTranslation(node, x, wy + shift, z)
                        state.pieces[#state.pieces + 1] = { node = node, class = class, key = key, shift = shift, cx = cx, cz = cz, path = ReseatDecals.parsePath(pathText) }
                        state.fastKeys[key] = true
                        ok = true
                    end
                end
            end
        end
        if ok then
            if math.abs(shift) <= ReseatDecals.MAX_SHIFT_M then
                restored = restored + 1
            end
        else
            failed = failed + 1
        end
    end
    return restored, failed
end

function ReseatDecals.parsePath(text)
    local path = {}
    for index in string.gmatch(text or "", "[^,]+") do
        path[#path + 1] = tonumber(index)
    end
    return path
end

function ReseatDecals.update(dt)
    if g_currentMission == nil or g_terrainNode == nil or g_client == nil then
        return
    end
    local waila = g_currentMission.waila
    if not ReseatDecals.tabDone or (ReseatDecals.addedTo ~= nil and waila ~= nil and waila.actionEntries ~= nil and waila.actionEntries.terrain ~= ReseatDecals.addedTo) then
        ReseatDecals.registerTab()
    end
    local state = ReseatDecals.state
    if state == nil then
        state = newState()
        ReseatDecals.state = state
    end
    -- a pass somebody asked for runs at once: the walk of the map's nodes in 8 ms slices (about half a second, the first time only), then every new height is worked out and set in one go (a few thousand
    -- ground lookups, tens of milliseconds, once); putting the saved moves back at the start stays gentle
    local budget = state.purpose == "pass" and ReseatDecals.BUDGET_REQUEST_MS or ReseatDecals.BUDGET_RESTORE_MS
    if state.phase == "wait" then
        state.waited = state.waited + dt / 1000
        if state.waited >= ReseatDecals.START_DELAY_S then
            if next(state.saved) ~= nil then
                local restored, failed = fastRestore(state)
                say("puddles: %d put back from %s by their saved places in the scene%s", restored, ReseatDecals.FILE, failed > 0 and string.format(", %d could not be found that way: walking the scene for them", failed) or "")
                if failed > 0 then
                    startCollect(state, "restore")
                else
                    state.phase = "idle"
                end
            else
                state.phase = "idle"
            end
        end
    elseif state.phase == "collect" then
        if collect(state, budget) then
            local restored = 0
            for _, piece in ipairs(state.pieces) do
                local shift = state.saved[piece.key]
                if shift ~= nil and math.abs(shift) <= ReseatDecals.MAX_SHIFT_M then
                    if not state.fastKeys[piece.key] then              -- (the ones the fast restore put back are already where they belong: only remembered)
                        local x, wy, z = getWorldTranslation(piece.node)
                        setWorldTranslation(piece.node, x, wy + shift, z)
                        restored = restored + 1
                    end
                    piece.shift = shift
                end
            end
            state.indexed = true
            say("puddles: %d found among %d nodes walked in %.0f ms, %d put back from %s", #state.pieces, state.visited or 0, now() - state.startedAt, restored, ReseatDecals.FILE)
            if state.purpose == "pass" then
                state.phase = "measure"
                state.cursor = 1
            else
                state.phase = "idle"
            end
        end
    elseif state.phase == "measure" then
        if measure(state, state.purpose == "pass" and math.huge or budget) then
            local byClass = {}
            for i, d in ipairs(state.devs) do
                local c = state.pieces[i].class
                byClass[c] = byClass[c] or {}
                byClass[c][#byClass[c] + 1] = d
            end
            state.offsets = {}
            for _, c in ipairs(ReseatDecals.CLASS_LIST) do
                local list = byClass[c]
                if list ~= nil then
                    local offset, isDefault = ReseatDecals.offsetFor(c, list)
                    state.offsets[c] = offset
                    local beyond = 0
                    for _, d in ipairs(list) do
                        if math.abs(d - offset) > ReseatDecals.TOLERANCE then
                            beyond = beyond + 1
                        end
                    end
                    say("%s: %.1f cm over the ground (%s); deviation p50 %.1f / p90 %.1f / p99 %.1f cm; %d of %d are beyond the %.0f cm tolerance (they are moved)", c, offset * 100, isDefault and string.format("the default: only %d of them, fewer than %d for a median", #list, ReseatDecals.MIN_MEMBERS) or "the median",
                        ReseatDecals.percentile(list, offset, 0.5) * 100, ReseatDecals.percentile(list, offset, 0.9) * 100, ReseatDecals.percentile(list, offset, 0.99) * 100,
                        beyond, #list, ReseatDecals.TOLERANCE * 100)
                end
            end
            state.offset = state.offsets.puddles or 0
            say("puddles: %d of them have ground lower at their border than the rest of it (the water level is the lowest point there)", state.bowls or 0)
            state.bowls = 0
            state.devs = {}
            state.phase = "sweep"
            state.cursor = 1
            state.moved = 0
            if state.purpose == "pass" then
                doSweep(state, math.huge)
            end
        end
    elseif state.phase == "sweep" then
        doSweep(state, budget)
    elseif state.phase == "idle" then
        if state.wantPass then
            state.wantPass = false
            state.purpose = "pass"
            if state.indexed then
                state.phase = "measure"
                state.cursor = 1
                state.devs = {}
            else
                startCollect(state, "pass")
                refreshHub()
            end
        end
    end
end

-- the triggers: WAILA's layer scan (Waila.registerScanHook: called when a whole-map or area scan starts) and a row of its Terrain tab (Waila.addDebugAction); a WAILA with neither gets a tab of its own; WAILA may load after this mod: tried every frame until it is there,
-- and again if WAILA is reloaded (its Terrain tab's list is then a new table)
function ReseatDecals.registerTab()
    local waila = g_currentMission ~= nil and g_currentMission.waila or nil
    if waila == nil or waila.registerDebugTab == nil then
        return
    end
    local function run() print(string.format("[RandomFixes] %s", ReseatDecals.requestPass())) end
    -- the layer scan (the whole map or "rescan around me") starts the pass for the area it covers ...
    if waila.registerScanHook ~= nil then
        waila.registerScanHook("randomfixes.reseat", function(rect) print(string.format("[RandomFixes] %s", ReseatDecals.requestPass(rect))) end)
    end
    -- ... and a row of the Terrain tab does it for the whole map on its own, without the layer scan
    if waila.addDebugAction ~= nil and waila.addDebugAction("terrain", {
        key = "randomfixes.reseat",
        getLabel = function() return "Reseat the map's puddles and guide posts on the ground (" .. ReseatDecals.status() .. ")" end,
        instant = true,
        isBusy = function() return ReseatDecals.isBusy() end,
        run = run,
    }) then
        ReseatDecals.tabDone = true
        ReseatDecals.addedTo = waila.actionEntries ~= nil and waila.actionEntries.terrain or nil
        return
    end
    if waila.registerScanHook ~= nil then
        ReseatDecals.tabDone = true
        ReseatDecals.addedTo = nil
        return
    end
    ReseatDecals.tabDone = true
    ReseatDecals.addedTo = nil
    if waila.unregisterDebugTab ~= nil then
        waila.unregisterDebugTab("randomfixes")
    end
    waila.registerDebugTab({
        id = "randomfixes",
        label = "Map fixes",
        getItems = function() return { { wailaID = "puddles", name = "Map puddles" } } end,
        describeItem = function(item) return item.name, ReseatDecals.status() end,
        getButtons = function(item)
            return { { label = "Reseat now", callback = run } }
        end,
    })
end

if addConsoleCommand ~= nil and not ReseatDecals.commandAdded then
    ReseatDecals.commandAdded = true
    addConsoleCommand("reseatDecals", "reseatDecals: put the map's puddles back on the ground (after the terrain was lowered or raised under them)", "consoleReseat", ReseatDecals)
    function ReseatDecals:consoleReseat() return ReseatDecals.requestPass() end
end

-- An experiment, one post at a time: reseatPostTest [dy] moves the guide post nearest to you (a "leitpfosten_r" / "leitpfosten_l": the node that carries the breakable joint, its own height) up by dy metres
-- (default 0.3) with setWorldTranslation, and prints where the node and its collision body ("coli") were before and are after, and the body type. The posts are dynamic bodies on breakable joints: whether moving
-- the node moves the body (and its collision) or only the picture is not known; look at it, and walk or drive into it. reseatPostTest 0 only prints. Nothing is saved.
local function nearestPost(px, pz)
    local best, bestD
    local stack = { { node = searchRoot(), index = 0 } }
    while #stack > 0 do
        local top = stack[#stack]
        if top.index == 0 then
            local lower = string.lower(getName(top.node) or "")
            if lower == "leitpfosten_r" or lower == "leitpfosten_l" then
                local x, _, z = getWorldTranslation(top.node)
                local d = (x - px) ^ 2 + (z - pz) ^ 2
                if bestD == nil or d < bestD then
                    best, bestD = top.node, d
                end
                top.count = 0
            else
                top.count = getNumOfChildren(top.node)
            end
        end
        if top.index < top.count then
            local child = getChildAt(top.node, top.index)
            top.index = top.index + 1
            stack[#stack + 1] = { node = child, index = 0 }
        else
            stack[#stack] = nil
        end
    end
    return best, bestD and math.sqrt(bestD) or nil
end

function ReseatDecals.postTest(dy)
    dy = tonumber(dy) or 0.3
    local px, pz
    if g_localPlayer ~= nil and g_localPlayer.rootNode ~= nil then
        local x, _, z = getWorldTranslation(g_localPlayer.rootNode)
        px, pz = x, z
    elseif getCamera ~= nil then
        local x, _, z = getWorldTranslation(getCamera())
        px, pz = x, z
    end
    if px == nil then
        return "no player"
    end
    local post, distance = nearestPost(px, pz)
    if post == nil then
        return "no guide post found"
    end
    local joint = getChild(post, "joint")
    local coli = joint ~= nil and joint ~= 0 and getChild(joint, "coli") or nil
    local function where(label)
        local x, y, z = getWorldTranslation(post)
        local line = string.format("%s: node %.3f %.3f %.3f", label, x, y, z)
        if coli ~= nil and coli ~= 0 then
            local cx, cy, cz = getWorldTranslation(coli)
            line = line .. string.format(", coli %.3f %.3f %.3f", cx, cy, cz)
            if getRigidBodyType ~= nil then
                line = line .. ", body type " .. tostring(getRigidBodyType(coli))
            end
        else
            line = line .. ", no coli found under joint"
        end
        return line
    end
    local before = where("before")
    if dy ~= 0 then
        local x, y, z = getWorldTranslation(post)
        setWorldTranslation(post, x, y + dy, z)
    end
    local after = where("after")
    local text = string.format("[RandomFixes] reseatPostTest: %s, %.1f m from you, moved %+.2f m\n  %s\n  %s", getName(post), distance, dy, before, after)
    print(text)
    return text
end

if addConsoleCommand ~= nil and not ReseatDecals.postTestAdded then
    ReseatDecals.postTestAdded = true
    addConsoleCommand("reseatPostTest", "reseatPostTest [dy]: experiment: move the guide post nearest to you up by dy metres (default 0.3) and print where its node and collision body end up", "consolePostTest", ReseatDecals)
    function ReseatDecals:consolePostTest(dy)
        local ok, result = pcall(ReseatDecals.postTest, dy)
        return ok and result or ("failed: " .. tostring(result))
    end
end

if FSCareerMissionInfo ~= nil and not ReseatDecals.saveHooked then
    ReseatDecals.saveHooked = true
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
        local ok, err = pcall(ReseatDecals.save)
        if not ok then
            say("puddles: not saved (%s)", tostring(err))
        end
    end)
end

if FSBaseMission ~= nil and not ReseatDecals.hooked then
    ReseatDecals.hooked = true
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(_, dt)
        local ok, err = pcall(ReseatDecals.update, dt)
        if not ok and not ReseatDecals.failed then
            ReseatDecals.failed = true
            say("puddles: stopped (%s)", tostring(err))
            ReseatDecals.update = function() end
        end
    end)
end
