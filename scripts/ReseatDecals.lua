--[[
    ReseatDecals.lua -- the map's puddles stay on the ground when the ground is lowered or raised under them.

    The puddles of a map (CreativeHorizon: ~2,330 "roadPuddlePiece" shapes in the group "wetnessPieces", plus "intersectionPuddles") are ordinary meshes at the height they were made at. The road under them is
    baked into the terrain's surface (terrainDecal), so it follows a cut or a fill, and the puddles are left floating (or buried). The map's other decals are baked into the terrain too (nonRenderable terrainDecal:
    road pieces, centre lines, parking lines, manholes, tyre tracks) and need nothing.

    How: on demand, no hooks and nothing in the background (nobody deforms the terrain every day). The button "Reseat now" of the "Map fixes" tab of WAILA's debug hub (or the console command reseatDecals) walks
    the scene in small slices (a time budget per frame) and remembers every shape whose name holds PATTERNS, measures each one's height above the ground (the world bounding sphere's centre against the terrain at
    that spot), takes the MEDIAN as the normal offset of a puddle over its ground (nearly all are untouched), and moves any puddle that is off by more than TOLERANCE, as a whole, up or down by the difference.
    A bowl cannot be followed, a lowered or raised stretch can. The moves are saved in the savegame (reseatDecals.xml, like MovePlaceablesAdvanced's own file) and put back at the next load, so the button is
    pressed once per edit, not once per session.

    The log says how many were found, the offset, how far off the pieces are (percentiles) and how many were moved ("[RandomFixes] puddles: ...").
]]
ReseatDecals = { PATTERNS = { "puddle" }, TOLERANCE = 0.06, BUDGET_MS = 0.25, START_DELAY_S = 3, MAX_NODES_PER_SLICE = 4000, FILE = "reseatDecals.xml", MIN_SAVED_M = 0.01 }

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

-- a puddle has no id (the map file's nodes sit at the origin, the vertices carry the world position): its name and where its bounding sphere's centre is in x / z (a height shift leaves that alone) are its key
function ReseatDecals.keyOf(name, cx, cz)
    return string.format("%s@%.2f,%.2f", name, cx, cz)
end

-- what is worth saving: every piece that was moved, by key, with how far (metres, + up); entries of the file that nothing matched yet are kept
function ReseatDecals.records(pieces, saved)
    local list, seen = {}, {}
    for _, piece in ipairs(pieces or {}) do
        seen[piece.key] = true
        if math.abs(piece.shift or 0) >= ReseatDecals.MIN_SAVED_M then
            list[#list + 1] = { key = piece.key, shift = piece.shift }
        end
    end
    for key, shift in pairs(saved or {}) do
        if not seen[key] then
            list[#list + 1] = { key = key, shift = shift }
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
    local saved, path = {}, savePath()
    if path == nil or XMLFile == nil then
        return saved
    end
    local xml = XMLFile.loadIfExists ~= nil and XMLFile.loadIfExists("ReseatDecals", path) or nil
    if xml == nil then
        return saved
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
        end
        i = i + 1
    end
    xml:delete()
    return saved
end

function ReseatDecals.save()
    local path = savePath()
    if path == nil or XMLFile == nil then
        return
    end
    local state = ReseatDecals.state
    local records = ReseatDecals.records(state ~= nil and state.pieces or {}, state ~= nil and state.saved or ReseatDecals.readFile())
    local xml = XMLFile.create("ReseatDecals", path, "reseatDecals")
    if xml == nil then
        say("puddles: could not write %s", path)
        return
    end
    for i, record in ipairs(records) do
        local key = string.format("reseatDecals.piece(%d)", i - 1)
        xml:setString(key .. "#key", record.key)
        xml:setFloat(key .. "#shift", record.shift)
    end
    xml:save()
    xml:delete()
    say("puddles: %d moved puddle(s) written to %s", #records, ReseatDecals.FILE)
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
                local cx, _, cz = getShapeWorldBoundingSphere(node)
                state.pieces[#state.pieces + 1] = { node = node, key = ReseatDecals.keyOf(getName(node), cx, cz), shift = 0 }
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
    return { phase = "wait", waited = 0, stack = {}, pieces = {}, devs = {}, cursor = 1, moved = 0, movedTotal = 0, saved = ReseatDecals.readFile(), indexed = false, purpose = nil, wantPass = false }
end

local function startCollect(state, purpose)
    state.stack = { { node = getRootNode(), index = 0, count = 0 } }
    state.pieces = {}
    state.purpose = purpose
    state.phase = "collect"
    state.startedAt = now()
end

-- asks for a pass: returns a line for the screen / console
function ReseatDecals.requestPass()
    local state = ReseatDecals.state
    if state == nil or g_currentMission == nil then
        return "not ready yet"
    end
    if state.phase == "collect" or state.phase == "measure" or state.phase == "sweep" then
        return "a pass is running"
    end
    state.wantPass = true
    return "reseating the map puddles"
end

function ReseatDecals.status()
    local state = ReseatDecals.state
    if state == nil then
        return "not started"
    end
    if state.phase == "collect" or state.phase == "measure" or state.phase == "sweep" then
        return "running: " .. state.phase
    end
    if state.last ~= nil then
        return string.format("last pass: %d puddles, %d moved (%d in all), %.1f cm over the ground", state.last.found, state.last.moved, state.movedTotal, state.last.offset * 100)
    end
    return state.indexed and "found " .. #state.pieces .. " puddles, no pass yet" or "no pass yet this session"
end

function ReseatDecals.update(dt)
    if g_currentMission == nil or g_terrainNode == nil or g_client == nil then
        return
    end
    if not ReseatDecals.tabDone then
        ReseatDecals.registerTab()
    end
    local state = ReseatDecals.state
    if state == nil then
        state = newState()
        ReseatDecals.state = state
    end
    local budget = ReseatDecals.BUDGET_MS
    if state.phase == "wait" then
        state.waited = state.waited + dt / 1000
        if state.waited >= ReseatDecals.START_DELAY_S then
            if next(state.saved) ~= nil then
                startCollect(state, "restore")
            else
                state.phase = "idle"
            end
        end
    elseif state.phase == "collect" then
        if collect(state, budget) then
            local restored = 0
            for _, piece in ipairs(state.pieces) do
                local shift = state.saved[piece.key]
                if shift ~= nil then
                    local x, wy, z = getWorldTranslation(piece.node)
                    setWorldTranslation(piece.node, x, wy + shift, z)
                    piece.shift = shift
                    restored = restored + 1
                end
            end
            state.indexed = true
            say("puddles: %d found in %.0f ms of slices, %d put back from %s", #state.pieces, now() - state.startedAt, restored, ReseatDecals.FILE)
            if state.purpose == "pass" then
                state.phase = "measure"
                state.cursor = 1
            else
                state.phase = "idle"
            end
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
            state.devs = {}
            state.phase = "sweep"
            state.cursor = 1
            state.moved = 0
        end
    elseif state.phase == "sweep" then
        if sweep(state, budget) then
            say("puddles: %d moved back to the ground (%d in all)", state.moved, state.movedTotal)
            state.last = { found = #state.pieces, moved = state.moved, offset = state.offset }
            state.moved = 0
            state.phase = "idle"
        end
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
            end
        end
    end
end

-- the button, as a tab of WAILA's debug hub (WAILA may load after this mod: tried every frame until it is there)
function ReseatDecals.registerTab()
    local waila = g_currentMission ~= nil and g_currentMission.waila or nil
    if waila == nil or waila.registerDebugTab == nil then
        return
    end
    ReseatDecals.tabDone = true
    if waila.unregisterDebugTab ~= nil then
        waila.unregisterDebugTab("randomfixes")
    end
    waila.registerDebugTab({
        id = "randomfixes",
        label = "Map fixes",
        getItems = function() return { { wailaID = "puddles", name = "Map puddles" } } end,
        describeItem = function(item) return item.name, ReseatDecals.status() end,
        getButtons = function(item)
            return { { label = "Reseat now", callback = function() say("%s", ReseatDecals.requestPass()) end } }
        end,
    })
end

if addConsoleCommand ~= nil and not ReseatDecals.commandAdded then
    ReseatDecals.commandAdded = true
    addConsoleCommand("reseatDecals", "reseatDecals: put the map's puddles back on the ground (after the terrain was lowered or raised under them)", "consoleReseat", ReseatDecals)
    function ReseatDecals:consoleReseat() return ReseatDecals.requestPass() end
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
