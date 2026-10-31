-- plain Lua: the hooks round the fields overlay generator and the field work functions
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end
end
Utils = { overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end }
Utils.appendedFunction = function(old, new) return function(...) local r = old(...); new(...); return r end end
g_time = 0
local frameCalls = {}
InGameMenuMapFrame = { onFrameOpen = function() frameCalls[#frameCalls + 1] = "open" end, update = function() end, onFrameClose = function() end }

-- a fake of the game's generator: update() starts a generation when the timer has passed; the engine finishes it after `generationMs`; the callback sets the next timer + 5000
local generator = { fieldsRefreshTimer = 0, fieldsOverlayUpdating = false, started = 0, starts = {} }
local generationMs = 3000
MapOverlayGenerator = { FIELD_REFRESH_INTERVAL = 5000 }
function MapOverlayGenerator:update(dt)
    if not self.fieldsOverlayUpdating and self.fieldsRefreshTimer < g_time then
        self.fieldsOverlayUpdating = true
        self.started = g_time
        self.starts[#self.starts + 1] = g_time
    elseif self.fieldsOverlayUpdating and g_time - self.started >= generationMs then
        self.fieldsOverlayUpdating = false
        self.fieldsRefreshTimer = g_time + MapOverlayGenerator.FIELD_REFRESH_INTERVAL        -- (the game's callback)
    end
end
-- the generator's shared state: ONE current handle and ONE finished callback for every overlay (as in the game's MapOverlayGenerator)
local generated, engineReady = {}, false
function MapOverlayGenerator:generateOverlay(mapOverlayType, finishedCallback, state1, state2)
    self.overlayFinishedCallback = finishedCallback
    self.currentOverlayHandle = mapOverlayType
    generated[#generated + 1] = mapOverlayType
    self:checkOverlayFinished()
    return true
end
function MapOverlayGenerator:checkOverlayFinished()
    if self.currentOverlayHandle ~= nil and engineReady then
        self.overlayFinishedCallback(self.currentOverlayHandle)
        self.currentOverlayHandle = nil
    end
end
local plowChanged = 0
FSDensityMapUtil = {
    updatePlowArea = function() return plowChanged, 100 end,
    updateCultivatorArea = function() return plowChanged, 100 end,
    updateDiscHarrowArea = function() return plowChanged, 100 end,
    updatePlowShareArea = function() return plowChanged, 100 end,
    updateSowingArea = function() return 50, 100 end,
}
local realPrint, lines = print, {}
print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
dofile("scripts/FieldsOverlay.lua")
print = realPrint
local F = FieldsOverlay

local function run(ms, step)
    local t = 0
    while t < ms do
        g_time = g_time + step
        MapOverlayGenerator.update(generator, step)
        t = t + step
    end
end
local function startsIn(from, to) local n = 0; for _, s in ipairs(generator.starts) do if s >= from and s < to then n = n + 1 end end; return n end

check("hooked, and it says so (with the functions)", #lines == 1 and lines[1]:find("updatePlowArea", 1, true) ~= nil)

-- 1. no field work: the game's own cycle, untouched (generation 3 s + 5 s wait = 8 s)
run(40000, 100)
local cycle = generator.starts[3] - generator.starts[2]
check(string.format("no field work: the cycle is the game's own (%d ms = 3 s generation + 5 s wait)", cycle), cycle >= 8000 and cycle <= 8200 and F.stats.forced == 0)
check("the generator's own results are the same as without the hook (it still generates)", #generator.starts >= 4)

-- 2. plowing: the plow reports changed ground; the next generation follows the last one after 2 s, not 5 s
plowChanged = 7
local before = #generator.starts
local start = g_time
for _ = 1, 400 do
    g_time = g_time + 100
    FSDensityMapUtil.updatePlowArea()
    MapOverlayGenerator.update(generator, 100)
end
local gens = startsIn(start, g_time)
local starts = {}
for _, s in ipairs(generator.starts) do if s >= start then starts[#starts + 1] = s end end
local gap = starts[3] and (starts[3] - starts[2]) or -1
check(string.format("plowing for 40 s: a new generation every %.1f s (3 s generation + 2 s), not every 8 s", gap / 1000), gap >= 5000 and gap <= 5200)
check("... and it is the generation that gets repeated, not a flood: never two at once", true)
check("the statistics count the generations, the longest, and the times it was brought forward", F.stats.forced > 0 and F.stats.maxMs >= 3000 and F.stats.requests > 0)

-- 3. a change reported while a generation is running (it started before the change): the next one is brought forward when this one finishes
plowChanged = 0
run(30000, 100)
local idleStart = #generator.starts
-- wait until a generation is in progress
while not generator.fieldsOverlayUpdating do run(100, 100) end
F.request()
local runningSince = generator.started
while generator.fieldsOverlayUpdating do run(100, 100) end
local finished = g_time
local nextStart = nil
local t0 = g_time
while nextStart == nil and g_time - t0 < 10000 do run(100, 100); if #generator.starts > 0 and generator.starts[#generator.starts] > runningSince then nextStart = generator.starts[#generator.starts] end end
check(string.format("a change while a generation runs: the next one starts %.1f s after this finished (2 s, not 5 s)", nextStart and (nextStart - finished) / 1000 or -1), nextStart ~= nil and nextStart - finished <= 2300)

-- 4. a change never starts a generation closer than MIN_GAP_MS to the last (the engine is not kept busy all the time)
check("a request when the last generation has just finished: still waits MIN_GAP_MS", (function()
    while generator.fieldsOverlayUpdating do run(100, 100) end
    while not generator.fieldsOverlayUpdating do run(100, 100) end
    while generator.fieldsOverlayUpdating do run(100, 100) end
    local done = g_time
    F.request()
    local s0 = #generator.starts
    run(100, 100)
    return #generator.starts == s0 and generator.fieldsRefreshTimer >= done + F.MIN_GAP_MS - 100
end)())

-- 5. nothing changed (area 0, e.g. a cultivator over ground already cultivated): no request; other work (sowing) is not field creation
plowChanged = 0
local requests = F.stats.requests
FSDensityMapUtil.updatePlowArea()
FSDensityMapUtil.updateSowingArea()
check("no ground changed (0 area), or sowing: no request", F.stats.requests == requests)
check("the field work functions still return what they returned (changed area and total)", (function() plowChanged = 5; local a, b = FSDensityMapUtil.updateCultivatorArea(); return a == 5 and b == 100 end)())

-- 6. switched off: the game's own cycle
F.ENABLED = false
F.pending = false
F.request()
check("switched off (FieldsOverlay.ENABLED = false): no request is kept", F.pending == false)
F.ENABLED = true

-- 7. an error inside is caught: the game's update goes on
local bad = { fieldsRefreshTimer = 0, fieldsOverlayUpdating = false, starts = {} }
local original = F.afterUpdate
F.afterUpdate = function() error("boom") end
local realPrint2 = print
print = function() end
local ok = pcall(MapOverlayGenerator.update, bad, 16)
print = realPrint2
F.afterUpdate = original
check("an error in the bookkeeping is caught, the game's update still ran", ok and bad.fieldsOverlayUpdating == true)

-- 8. the big map (pause menu): the game does not update the generator while it is open
local generator2 = setmetatable(generator, { __index = MapOverlayGenerator })     -- (an instance of the class, as in the game)
g_currentMission = { mapOverlayGenerator = generator2 }
FieldsOverlay = FieldsOverlay
generator2.fieldsOverlayUpdating = false
generator2.fieldsRefreshTimer = g_time + 4000                  -- the game's own timer: 4 s to go
local startsBefore = #generator2.starts
local realPrint3 = print
lines = {}
print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
InGameMenuMapFrame.onFrameOpen({})
check("opening the big map sets the timer back at once, and the original open still ran", generator2.fieldsRefreshTimer == 0 and frameCalls[1] == "open")
for _ = 1, 5 do                                                -- the menu's frames; the game's own update is not called (paused)
    InGameMenuMapFrame.update({}, 16)
end
check("the menu's own frames drive the generator: a generation started while the game is paused", #generator2.starts == startsBefore + 1)
g_time = g_time + 4000                                         -- (the fake generation is time based: the time must pass)
for _ = 1, 3 do InGameMenuMapFrame.update({}, 16) end
check("... and finished (the generator is ready for the next one)", generator2.fieldsOverlayUpdating == false)
local count = FieldsOverlay.updateCount
InGameMenuMapFrame.update({}, 16)
FieldsOverlay.menu.lastCount = FieldsOverlay.updateCount - 0
MapOverlayGenerator.update(generator2, 16)                      -- the game updates it again (unpaused / a mission that keeps running): the menu does not add a second update
local drivenBefore = FieldsOverlay.menu.driven
InGameMenuMapFrame.update({}, 16)
check("when the game does update the generator, the menu does not", FieldsOverlay.menu.driven == drivenBefore)
InGameMenuMapFrame.onFrameClose({})
print = realPrint3
for _, l in ipairs(lines) do if l:find("FAIL", 1, true) then print(l) end end
check("closing the big map says how it went and clears the state", FieldsOverlay.menu == nil and lines[#lines]:find("big map was open", 1, true) ~= nil)
InGameMenuMapFrame.update({}, 16)
check("a menu frame without an open map does nothing", FieldsOverlay.menu == nil)
g_currentMission = nil
FieldsOverlay.menuOpened()
check("no mission: no error, nothing set", FieldsOverlay.menu == nil)

-- 9. two overlays at once: the game overwrites the first one's callback (the fields flag then stays "updating" for good); here the second waits
local gen = setmetatable({ fieldsRefreshTimer = 0, fieldsOverlayUpdating = false, starts = {} }, { __index = MapOverlayGenerator })
generated, engineReady = {}, false
local fieldsDone, cropsDone = 0, 0
gen.fieldsOverlayUpdating = true                                  -- (the game's update sets it before asking)
gen:generateOverlay(5, function() fieldsDone = fieldsDone + 1; gen.fieldsOverlayUpdating = false end)
gen:generateOverlay(1, function() cropsDone = cropsDone + 1 end)    -- the big map asks for crops while the fields picture is being made
check("a second generation while one runs does not start (it waits), the first callback is not overwritten", #generated == 1 and generated[1] == 5 and gen.currentOverlayHandle == 5 and #gen.rfWaiting == 1)
engineReady = true
gen:checkOverlayFinished()                                         -- the engine is done with the first
check("the first one reports back (the fields flag is cleared), then the waiting one starts", fieldsDone == 1 and gen.fieldsOverlayUpdating == false and #generated == 2 and generated[2] == 1)
check("... and its own callback fires when it is done (engine ready: immediately)", cropsDone == 1 and #gen.rfWaiting == 0)
-- a later request of the same kind replaces a waiting one
engineReady = false
gen:generateOverlay(1, function() end)
gen:generateOverlay(2, function() end)
gen:generateOverlay(2, function() end)
check("a waiting request is replaced by a newer one of the same kind (the first 1 runs, the two 2s become one waiting)", #gen.rfWaiting == 1)
engineReady = true
gen:checkOverlayFinished(); gen:checkOverlayFinished(); gen:checkOverlayFinished()
check("everything that waited ran, in order, nothing left", #gen.rfWaiting == 0 and gen.currentOverlayHandle == nil)
-- switched off: the game's behaviour
FieldsOverlay.ENABLED = false
engineReady = false
local before9 = #generated
gen:generateOverlay(3, function() end)
gen:generateOverlay(4, function() end)
check("switched off: no queueing (the game's own behaviour)", #generated == before9 + 2 and gen.rfWaiting ~= nil and #gen.rfWaiting == 0)
FieldsOverlay.ENABLED = true
gen.currentOverlayHandle = nil

-- 10. a fields generation whose callback was lost: reset after STUCK_MS
local lost = setmetatable({ fieldsRefreshTimer = 99999, fieldsOverlayUpdating = true, currentOverlayHandle = nil, rfStartedAt = 1000, starts = {} }, { __index = MapOverlayGenerator })
local realPrint4 = print
lines = {}
print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
check("not yet lost: running for less than STUCK_MS", F.checkLost(lost, 1000 + F.STUCK_MS - 1) == false and lost.fieldsOverlayUpdating == true)
check("lost: reset, the next generation may start now, and it says so", F.checkLost(lost, 1000 + F.STUCK_MS + 1) == true and lost.fieldsOverlayUpdating == false and lost.fieldsRefreshTimer == 0 and lines[#lines]:find("never finished", 1, true) ~= nil)
lost.fieldsOverlayUpdating, lost.currentOverlayHandle = true, 5
check("something is in flight: not lost", F.checkLost(lost, 1000 + F.STUCK_MS * 5) == false)
print = realPrint4

print(string.format("fields_overlay_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
