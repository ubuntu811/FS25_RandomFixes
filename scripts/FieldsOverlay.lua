--[[
    FieldsOverlay.lua -- the minimap's field picture shows a freshly plowed meadow (a new field) only much later. Details and the suggested game fix: docs/FIELDS_OVERLAY.md.

    The game: the fields overlay of the map (MapOverlayGenerator, drawn by IngameMap:drawFields) is a picture of the ground type map, regenerated in the background by the engine,
    all of it, on a timer: when a generation has finished, the next one starts FIELD_REFRESH_INTERVAL (5 s) later. Nothing starts a regeneration because the ground changed. So a
    patch plowed just after a generation began waits for the rest of that generation, the 5 s, and one whole generation more.

    Here: the functions that change the ground type of a field (plow, cultivator, disc harrow, plow share: FSDensityMapUtil.update...Area, which return the area they changed)
    note when they changed something, and the overlay is asked to start its next generation MIN_GAP_MS after the last one finished, instead of the full interval. That makes the
    wait one generation plus 2 s while field work goes on, and nothing else changes (no field work: no request, the game's own 5 s timer as before). The engine's generation is all
    or nothing for the whole map; how long it takes decides how much this helps, so the time of every generation is logged (once a minute, with the longest).
]]
FieldsOverlay = {}
FieldsOverlay.ENABLED = true
FieldsOverlay.MIN_GAP_MS = 2000             -- the next generation starts this long after the last one finished, while there is field work (the game's own wait is 5000)
FieldsOverlay.LOG_EVERY_MS = 60000
FieldsOverlay.FUNCTIONS = { "updatePlowArea", "updateCultivatorArea", "updateDiscHarrowArea", "updatePlowShareArea" }
FieldsOverlay.pending = false
FieldsOverlay.updateCount = 0               -- how many times the generator has been updated (by the game or by the menu hook below)
FieldsOverlay.menu = nil                    -- set while the big map (pause menu) is open
FieldsOverlay.stats = { generations = 0, totalMs = 0, maxMs = 0, forced = 0, requests = 0, logAt = nil }

local function say(format, ...)
    print(string.format("[RandomFixes] " .. format, ...))
end

-- Some ground has been changed: the next generation should not wait the full interval.
function FieldsOverlay.request()
    if FieldsOverlay.ENABLED then
        FieldsOverlay.pending = true
        FieldsOverlay.stats.requests = FieldsOverlay.stats.requests + 1
    end
end

-- Called after every update of the overlay generator: sees a generation start and finish (self.fieldsOverlayUpdating), times it, and brings the next one forward when a change
-- is waiting.
function FieldsOverlay.afterUpdate(generator, wasUpdating)
    local now = g_time or 0
    local updating = generator.fieldsOverlayUpdating == true
    local stats = FieldsOverlay.stats
    if updating and not wasUpdating then
        generator.rfStartedAt = now
    elseif wasUpdating and not updating then
        local took = now - (generator.rfStartedAt or now)
        stats.generations, stats.totalMs, stats.maxMs = stats.generations + 1, stats.totalMs + took, math.max(stats.maxMs, took)
        generator.rfFinishedAt = now
    end
    if FieldsOverlay.ENABLED and FieldsOverlay.checkLost(generator, now) then
        updating = false
    end
    if FieldsOverlay.ENABLED and FieldsOverlay.pending and not updating then
        -- idle, waiting for the timer (or a generation has just finished): a change is waiting, so the timer is brought forward, but not closer than MIN_GAP_MS after the
        -- last generation finished
        FieldsOverlay.pending = false
        local earliest = math.max(now, (generator.rfFinishedAt or 0) + FieldsOverlay.MIN_GAP_MS)
        if generator.fieldsRefreshTimer ~= nil and generator.fieldsRefreshTimer > earliest then
            generator.fieldsRefreshTimer = earliest
            stats.forced = stats.forced + 1
        end
    end
    if stats.logAt == nil then
        stats.logAt = now
    elseif now - stats.logAt >= FieldsOverlay.LOG_EVERY_MS then
        if stats.generations > 0 then
            say("fields overlay: %d generation(s) in the last minute, %.0f ms each on average (longest %.0f ms); brought forward %d time(s) by field work (%d change reports)",
                stats.generations, stats.totalMs / stats.generations, stats.maxMs, stats.forced, stats.requests)
        end
        stats.generations, stats.totalMs, stats.maxMs, stats.forced, stats.requests, stats.logAt = 0, 0, 0, 0, 0, now
    end
end

-- The big map (InGameMenuMapFrame -> its IngameMap) draws the SAME picture, but the pause menu stops the game's update, and MapOverlayGenerator:update is called from the mission's
-- update: while the menu is open the picture is never regenerated, so it shows the ground as it was up to a cycle before the menu was opened (and a patch plowed in the last seconds not at all).
-- On opening: a generation is asked for at once (the timer is set back; if one is running, a follow-up is asked for). While the menu is open: if the game has not updated the generator since
-- the last frame of the menu, the menu's own update calls it (a generation is the engine's job, started and polled from that update, so nothing else is needed).
function FieldsOverlay.menuOpened()
    local generator = g_currentMission ~= nil and g_currentMission.mapOverlayGenerator or nil
    if not FieldsOverlay.ENABLED or generator == nil then
        return
    end
    local now = g_time or 0
    FieldsOverlay.menu = { lastCount = FieldsOverlay.updateCount, driven = 0, frames = 0, ageMs = now - (generator.rfFinishedAt or now) }
    if generator.fieldsOverlayUpdating then
        FieldsOverlay.pending = true
    else
        generator.fieldsRefreshTimer = 0
    end
end

function FieldsOverlay.menuUpdate(dt)
    local menu = FieldsOverlay.menu
    local generator = g_currentMission ~= nil and g_currentMission.mapOverlayGenerator or nil
    if menu == nil or generator == nil or not FieldsOverlay.ENABLED then
        return
    end
    menu.frames = menu.frames + 1
    if FieldsOverlay.updateCount == menu.lastCount then
        menu.driven = menu.driven + 1
        generator:update(dt)                                  -- (the wrapped update: counted, timed)
    end
    menu.lastCount = FieldsOverlay.updateCount
end

function FieldsOverlay.menuClosed()
    local menu = FieldsOverlay.menu
    FieldsOverlay.menu = nil
    if menu ~= nil then
        say("fields overlay: big map was open for %d frame(s); the game updated the generator in %d of them (%d updated by this mod); the picture was %.1f s old when it opened",
            menu.frames, menu.frames - menu.driven, menu.driven, menu.ageMs / 1000)
    end
end

-- The generator builds every overlay (fields, crops, growth, soil, farmlands) with ONE currentOverlayHandle and ONE overlayFinishedCallback (MapOverlayGenerator:generateOverlay). When a
-- second generation is started while one is running (the big map starts its own the moment it opens; the fields one starts on its 5 s timer), the first one's callback is overwritten
-- and never called: for the fields overlay that leaves fieldsOverlayUpdating true for good, and the picture of the fields is never regenerated again (until the game is restarted).
-- Here a request that comes while another generation is running waits and starts when that one has finished (a later request of the same kind replaces an earlier waiting one),
-- and a fields generation that has been "running" for STUCK_MS without anything in flight is declared lost: the flag is reset and the next one starts.
FieldsOverlay.STUCK_MS = 10000
FieldsOverlay.lostCount = 0

function FieldsOverlay.generateOverlay(generator, superFunc, mapOverlayType, finishedCallback, state1, state2)
    if generator.currentOverlayHandle ~= nil then
        generator.rfWaiting = generator.rfWaiting or {}
        for i = #generator.rfWaiting, 1, -1 do
            if generator.rfWaiting[i].type == mapOverlayType and mapOverlayType ~= nil then
                table.remove(generator.rfWaiting, i)
            end
        end
        generator.rfWaiting[#generator.rfWaiting + 1] = { type = mapOverlayType, callback = finishedCallback, state1 = state1, state2 = state2 }
        FieldsOverlay.stats.queued = (FieldsOverlay.stats.queued or 0) + 1
        return true
    end
    return superFunc(generator, mapOverlayType, finishedCallback, state1, state2)
end

-- After the game's own check: when nothing is running any more, the next waiting request starts.
function FieldsOverlay.afterCheck(generator, superGenerate)
    local waiting = generator.rfWaiting
    if generator.currentOverlayHandle == nil and waiting ~= nil and #waiting > 0 then
        local request = table.remove(waiting, 1)
        superGenerate(generator, request.type, request.callback, request.state1, request.state2)
    end
end

-- A fields generation that never reported back (its callback was lost): reset the game's flag so the next one can start.
function FieldsOverlay.checkLost(generator, now)
    if generator.fieldsOverlayUpdating == true and generator.currentOverlayHandle == nil and (generator.rfWaiting == nil or #generator.rfWaiting == 0)
        and generator.rfStartedAt ~= nil and now - generator.rfStartedAt > FieldsOverlay.STUCK_MS then
        generator.fieldsOverlayUpdating = false
        generator.fieldsRefreshTimer = 0
        FieldsOverlay.lostCount = FieldsOverlay.lostCount + 1
        say("fields overlay: a generation of the fields picture never finished (its callback was lost to another overlay's generation); reset, the next one starts now (%d so far)", FieldsOverlay.lostCount)
        return true
    end
    return false
end

-- ===== hooks (the game's classes, patched once when this file loads) =====
if MapOverlayGenerator ~= nil and MapOverlayGenerator.update ~= nil and Utils ~= nil and not FieldsOverlay.hooked then
    FieldsOverlay.hooked = true
    MapOverlayGenerator.update = Utils.overwrittenFunction(MapOverlayGenerator.update, function(self, superFunc, dt)
        local wasUpdating = self.fieldsOverlayUpdating == true
        FieldsOverlay.updateCount = FieldsOverlay.updateCount + 1
        superFunc(self, dt)
        local ok, err = pcall(FieldsOverlay.afterUpdate, self, wasUpdating)
        if not ok and not FieldsOverlay.failed then
            FieldsOverlay.failed = true
            say("fields overlay: skipped (%s)", tostring(err))
        end
    end)
    local originalGenerate = MapOverlayGenerator.generateOverlay
    if originalGenerate ~= nil and MapOverlayGenerator.checkOverlayFinished ~= nil then
        MapOverlayGenerator.generateOverlay = function(self, mapOverlayType, finishedCallback, state1, state2)
            if not FieldsOverlay.ENABLED then
                return originalGenerate(self, mapOverlayType, finishedCallback, state1, state2)
            end
            return FieldsOverlay.generateOverlay(self, originalGenerate, mapOverlayType, finishedCallback, state1, state2)
        end
        MapOverlayGenerator.checkOverlayFinished = Utils.overwrittenFunction(MapOverlayGenerator.checkOverlayFinished, function(self, superFunc)
            superFunc(self)
            if FieldsOverlay.ENABLED then
                local ok, err = pcall(FieldsOverlay.afterCheck, self, originalGenerate)
                if not ok and not FieldsOverlay.failed then
                    FieldsOverlay.failed = true
                    say("fields overlay: queue skipped (%s)", tostring(err))
                end
            end
        end)
    end
    local hooked = {}
    if FSDensityMapUtil ~= nil then
        for _, name in ipairs(FieldsOverlay.FUNCTIONS) do
            local original = FSDensityMapUtil[name]
            if original ~= nil then
                FSDensityMapUtil[name] = function(...)
                    local changed, total = original(...)
                    if type(changed) == "number" and changed > 0 then
                        FieldsOverlay.request()
                    end
                    return changed, total
                end
                hooked[#hooked + 1] = name
            end
        end
    end
    say("fields overlay: the minimap's field picture is asked to refresh %d ms after the last one when ground is plowed / cultivated (%s)", FieldsOverlay.MIN_GAP_MS, table.concat(hooked, ", "))
end

if InGameMenuMapFrame ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil and not FieldsOverlay.menuHooked then
    FieldsOverlay.menuHooked = true
    local function guarded(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok and not FieldsOverlay.menuFailed then
                FieldsOverlay.menuFailed = true
                say("fields overlay: big map hook skipped (%s)", tostring(err))
            end
        end
    end
    if InGameMenuMapFrame.onFrameOpen ~= nil then
        InGameMenuMapFrame.onFrameOpen = Utils.appendedFunction(InGameMenuMapFrame.onFrameOpen, guarded(function() FieldsOverlay.menuOpened() end))
    end
    if InGameMenuMapFrame.update ~= nil then
        InGameMenuMapFrame.update = Utils.appendedFunction(InGameMenuMapFrame.update, guarded(function(_, dt) FieldsOverlay.menuUpdate(dt) end))
    end
    if InGameMenuMapFrame.onFrameClose ~= nil then
        InGameMenuMapFrame.onFrameClose = Utils.appendedFunction(InGameMenuMapFrame.onFrameClose, guarded(function() FieldsOverlay.menuClosed() end))
    end
end

-- A switch for a test without a restart (field work with AI workers makes the engine regenerate the whole map's field picture more often than the game's 5 s: is that what costs frames?):
-- rfFieldsOverlay off | on | gap <ms>
if addConsoleCommand ~= nil and not FieldsOverlay.commandAdded then
    FieldsOverlay.commandAdded = true
    addConsoleCommand("rfFieldsOverlay", "rfFieldsOverlay [off|on|gap <ms>]: the faster refresh of the minimap's field picture while there is field work (off = the game's own 5 s timer)", "consoleSwitch", FieldsOverlay)
    function FieldsOverlay:consoleSwitch(what, value)
        if what == "off" then
            FieldsOverlay.ENABLED = false
        elseif what == "on" then
            FieldsOverlay.ENABLED = true
        elseif what == "gap" and tonumber(value) ~= nil then
            FieldsOverlay.MIN_GAP_MS = math.max(500, tonumber(value))
        elseif what ~= nil then
            return "usage: rfFieldsOverlay [off|on|gap <ms>]"
        end
        return string.format("fields overlay: %s, next generation %d ms after the last one while there is field work (the game's own wait is 5000)", FieldsOverlay.ENABLED and "on" or "off", FieldsOverlay.MIN_GAP_MS)
    end
end
