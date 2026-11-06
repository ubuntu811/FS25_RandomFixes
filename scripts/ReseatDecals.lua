--[[
    ReseatDecals.lua -- the map's puddles stay on the ground when the ground is lowered or raised under them.

    The puddles of a map (CreativeHorizon: ~2,330 "roadPuddlePiece" shapes in the group "wetnessPieces", plus "intersectionPuddles") are ordinary meshes at the height they were made at. The road under them is
    baked into the terrain's surface (terrainDecal), so it follows a cut or a fill, and the puddles are left floating (or buried). The map's other decals are baked into the terrain too (nonRenderable terrainDecal:
    road pieces, centre lines, parking lines, manholes, tyre tracks) and need nothing.

    How: once, a little after the mission starts, the scene is walked in small slices (a time budget per frame) and every shape whose name holds PATTERNS is remembered. Each one's height above the ground
    (the world bounding sphere's centre against the terrain at that spot) is measured; the MEDIAN of those is the normal offset of a puddle over its ground (nearly all of them are untouched, so the median is
    the untouched value). After that a pass over all of them runs, again in slices, a moment after every terrain edit (the queue's queueJob and TerrainDeformation.apply are wrapped to notice one; nothing runs between edits): a puddle whose height over the ground is off the offset by more than TOLERANCE is moved, as a whole,
    up or down by the difference. A bowl cannot be followed (a mesh does not bend), a lowered or raised stretch can.

    The log says how many were found, the offset, how far off the pieces are (percentiles) and how many were moved ("[RandomFixes] puddles: ...").
]]
ReseatDecals = { PATTERNS = { "puddle" }, TOLERANCE = 0.06, BUDGET_MS = 0.25, START_DELAY_S = 8, MAX_NODES_PER_SLICE = 4000 }

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
function ReseatDecals.shiftFor(sphereY, groundY, offset, tolerance)
    local delta = groundY + offset - sphereY
    if math.abs(delta) > tolerance then
        return delta
    end
    return nil
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
            if getHasClassId(node, ClassIds.SHAPE) and ReseatDecals.matches(getName(node)) then
                state.pieces[#state.pieces + 1] = { node = node }
            end
            top.count = getNumOfChildren(node)
        end
        if top.index < top.count then
            local child = getChildAt(top.node, top.index)
            top.index = top.index + 1
            state.stack[#state.stack + 1] = { node = child, index = 0, count = 0 }
        else
            state.stack[#state.stack] = nil
        end
        steps = steps + 1
        if steps >= ReseatDecals.MAX_NODES_PER_SLICE or (steps % 64 == 0 and now() - t0 > budgetMs) then
            return false
        end
    end
    return true
end

local function height(piece)
    local cx, cy, cz = getShapeWorldBoundingSphere(piece.node)
    return cy, getTerrainHeightAtWorldPos(g_terrainNode, cx, 0, cz)
end

-- phase 2: the offset of an untouched puddle over its ground (the median), and how scattered they are
local function measure(state, budgetMs)
    local t0 = now()
    while state.cursor <= #state.pieces do
        local piece = state.pieces[state.cursor]
        local y, ground = height(piece)
        state.devs[state.cursor] = y - ground
        state.cursor = state.cursor + 1
        if now() - t0 > budgetMs then
            return false
        end
    end
    return true
end

local function sweep(state, budgetMs)
    local t0 = now()
    while state.cursor <= #state.pieces do
        local piece = state.pieces[state.cursor]
        local y, ground = height(piece)
        local delta = ReseatDecals.shiftFor(y, ground, state.offset, ReseatDecals.TOLERANCE)
        if delta ~= nil then
            local x, wy, z = getWorldTranslation(piece.node)
            setWorldTranslation(piece.node, x, wy + delta, z)
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

-- A terrain edit goes through g_terrainDeformationQueue:queueJob (construction, levelling placeables) or deformation:apply (TerraFarm): both are wrapped to note that something changed; nothing runs
-- between edits. SETTLE_S after the last edit a pass runs (the job is applied over the next frames), and one more LATE_S later for the slow ones. If neither hook could be installed, the pass runs every FALLBACK_S.
ReseatDecals.SETTLE_S, ReseatDecals.LATE_S, ReseatDecals.FALLBACK_S = 2, 6, 30

function ReseatDecals.markDirty(label)
    local state = ReseatDecals.state
    if state == nil then
        return
    end
    state.due = state.clock + ReseatDecals.SETTLE_S
    state.second = true
    state.edits = (state.edits or 0) + 1
    if state.edits <= 3 then
        say("puddles: terrain edit seen (%s)", label)
    end
end

local function wrap(owner, key, label)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then
        return false
    end
    local original = owner[key]
    owner[key] = function(...)
        ReseatDecals.markDirty(label)
        return original(...)
    end
    return true
end

function ReseatDecals.installHooks()
    local ok1, r1 = pcall(wrap, g_terrainDeformationQueue, "queueJob", "queueJob")
    local ok2, r2 = pcall(wrap, TerrainDeformation, "apply", "apply")
    ReseatDecals.hookCount = ((ok1 and r1) and 1 or 0) + ((ok2 and r2) and 1 or 0)
    say("puddles: terrain edit hooks: queueJob %s, apply %s", (ok1 and r1) and "yes" or "no", (ok2 and r2) and "yes" or "no")
end

function ReseatDecals.update(dt)
    if g_currentMission == nil or g_terrainNode == nil or g_client == nil then
        return
    end
    local state = ReseatDecals.state
    if state == nil then
        state = { phase = "wait", waited = 0, clock = 0, stack = {}, pieces = {}, devs = {}, cursor = 1, moved = 0, movedTotal = 0 }
        ReseatDecals.state = state
        ReseatDecals.installHooks()
    end
    state.clock = state.clock + dt / 1000
    local budget = ReseatDecals.BUDGET_MS
    if state.phase == "wait" then
        state.waited = state.waited + dt / 1000
        if state.waited >= ReseatDecals.START_DELAY_S then
            state.stack = { { node = getRootNode(), index = 0, count = 0 } }
            state.phase = "collect"
            state.startedAt = now()
        end
    elseif state.phase == "collect" then
        if collect(state, budget) then
            state.phase = "measure"
            state.cursor = 1
            say("puddles: %d found in %.0f ms of slices", #state.pieces, now() - state.startedAt)
        end
    elseif state.phase == "measure" then
        if measure(state, budget) then
            state.offset = ReseatDecals.median(state.devs) or 0
            local beyond = 0
            for _, d in ipairs(state.devs) do
                if math.abs(d - state.offset) > ReseatDecals.TOLERANCE then
                    beyond = beyond + 1
                end
            end
            say("puddles: %.1f cm over the ground at the median; deviation p50 %.1f / p90 %.1f / p99 %.1f cm; %d of %d are beyond the %.0f cm tolerance (they are moved)", state.offset * 100,
                ReseatDecals.percentile(state.devs, state.offset, 0.5) * 100, ReseatDecals.percentile(state.devs, state.offset, 0.9) * 100, ReseatDecals.percentile(state.devs, state.offset, 0.99) * 100,
                beyond, #state.pieces, ReseatDecals.TOLERANCE * 100)
            state.devs = nil
            state.phase = "sweep"
            state.cursor = 1
        end
    elseif state.phase == "sweep" then
        if #state.pieces == 0 then
            state.phase = "none"
            return
        end
        if sweep(state, budget) then
            if state.moved > 0 then
                say("puddles: %d moved back to the ground in this pass (%d in all)", state.moved, state.movedTotal)
            end
            state.moved = 0
            state.cursor = 1
            state.phase = "idle"
            if state.second then                       -- one more pass a little later for an edit that was still being applied
                state.second = false
                state.due = state.clock + ReseatDecals.LATE_S
            elseif ReseatDecals.hookCount == 0 then
                state.due = state.clock + ReseatDecals.FALLBACK_S
            else
                state.due = nil
            end
        end
    elseif state.phase == "idle" then
        if state.due ~= nil and state.clock >= state.due then
            state.due = nil
            state.phase = "sweep"
        end
    end
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
