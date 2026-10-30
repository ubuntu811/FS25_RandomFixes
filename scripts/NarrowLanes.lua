--[[
    NarrowLanes.lua -- the steering assist plans its field lanes for the narrowest of the attached implements, not the widest.

    The bug: with two implements on one tractor (a mower in front and a windrower behind, a cultivator and a seeder ...) the
    steering assist plans its field lanes for the WIDEST of them. FieldCourseSettings.generate takes the left-most and right-most
    edge over every attached AI implement and calls the span "implementWidth"; AIAutomaticSteering:getAttacherToolWorkingWidth
    takes the maximum width of any child vehicle. So the lanes only ever suit the widest tool, and everything narrower leaves
    gaps or has to be driven by hand.

    The fix: plan for the NARROWEST. During FieldCourseSettings.generate, and only while the vehicle's AI mode is the steering assist, only the
    narrowest implements (within TOLERANCE metres of the smallest width) are in the list the course is built from. Nothing else about the
    implements is touched: the other callers of getAttachedAIImplements (lowering, turning on ...) see the full list as before, and the AI
    helper (worker mode), which plans its lanes with the same function, gets the game's lanes unchanged.

    What is NOT changed: the turning geometry, headland offsets and tool lengths are now those of the kept implements only.
]]
NarrowLanes = {}

NarrowLanes.ENABLED = true
NarrowLanes.TOLERANCE = 0.05          -- metres: implements this close to the smallest width count as the same

-- The work width of an AI implement (nil when it has none: no work area, nothing to plan lanes for).
function NarrowLanes.widthOf(object)
    if object == nil or object.getAIMarkers == nil then
        return nil
    end
    if object.updateAIMarkerWidth ~= nil then
        object:updateAIMarkerWidth()
    end
    local _, _, _, _, width = object:getAIMarkers()
    if type(width) == "number" and width > 0 then
        return width
    end
    return nil
end

-- implements: the list getAttachedAIImplements returns ({ object = vehicle, ... }). Returns the list to plan lanes from:
-- the narrowest implements, plus any that have no width at all (left as the game would treat them). With fewer than two
-- implements, or none with a width, the list is returned unchanged.
function NarrowLanes.narrowest(implements)
    if implements == nil or #implements < 2 then
        return implements
    end
    local smallest = nil
    local widths = {}
    for i, implement in ipairs(implements) do
        local width = NarrowLanes.widthOf(implement.object)
        widths[i] = width
        if width ~= nil and (smallest == nil or width < smallest) then
            smallest = width
        end
    end
    if smallest == nil then
        return implements
    end
    local kept = {}
    for i, implement in ipairs(implements) do
        if widths[i] == nil or widths[i] <= smallest + NarrowLanes.TOLERANCE then
            kept[#kept + 1] = implement
        end
    end
    return kept
end

-- The narrowest work width among the child vehicles of a rig (for the assist's "has the width changed" check).
function NarrowLanes.narrowestWorkingWidth(rootVehicle)
    local smallest = nil
    for _, vehicle in pairs(rootVehicle.childVehicles or {}) do
        local width = 0
        if vehicle.getAIMarkers ~= nil then
            if vehicle.updateAIMarkerWidth ~= nil then
                vehicle:updateAIMarkerWidth()
            end
            local _, _, _, _, markerWidth = vehicle:getAIMarkers()
            if type(markerWidth) == "number" then
                width = math.max(width, markerWidth)
            end
        end
        if vehicle.getAIWorkAreaWidth ~= nil then
            width = math.max(width, vehicle:getAIWorkAreaWidth())
        end
        if width > 0 and (smallest == nil or width < smallest) then
            smallest = width
        end
    end
    return smallest or 0
end

-- The base game's lane planner, run on the narrowest implements only. For every caller: the steering assist, and the AI helper too (a mower with a
-- windrower behind would otherwise be worked in windrower-wide rows with one narrow strip mowed).

-- The planner returns (settings, implementData); implementData[i] belongs to the i-th implement of the list it was given, and the AI helper's strategy
-- (AIDriveStrategyFieldCourse) indexes it by the vehicle's OWN implement list: a table built from the shortened list would have no entry for a dropped
-- implement and the strategy would fail on every frame (data.isLowered on nil: a flood of errors, then the game dies). So the table is put back in the order
-- of the full list; a dropped implement gets a copy of a kept one's entry, not lowered and without a parent link (the strategy walks those links and
-- raises the parents of a lowered entry: a copy must not lower somebody else's). The strategy sets isLowered of every implement itself, from the
-- implement's own work area, so the dropped one still works when it is over unworked ground.
function NarrowLanes.alignImplementData(data, full, kept)
    if type(data) ~= "table" then
        return data
    end
    local position = {}
    for j, implement in ipairs(kept) do
        position[implement] = j
    end
    local aligned = {}
    local fallback = data[1]
    for i, implement in ipairs(full) do
        local entry = data[position[implement] or 0]
        if entry == nil and fallback ~= nil then
            entry = {}
            for key, value in pairs(fallback) do
                entry[key] = value
            end
            entry.isLowered, entry.wasLowered, entry.parentAIImplement = false, nil, nil
        end
        aligned[i] = entry
    end
    return aligned
end

function NarrowLanes.generate(original, rootVehicle, ...)
    if not NarrowLanes.ENABLED or rootVehicle == nil or rootVehicle.getAttachedAIImplements == nil then
        return original(rootVehicle, ...)
    end
    local getter = rootVehicle.getAttachedAIImplements
    local full = getter(rootVehicle)
    local kept = NarrowLanes.narrowest(full)
    if kept == full or #kept == #full then
        return original(rootVehicle, ...)
    end
    -- for this one synchronous call only, the vehicle reports the kept implements
    rootVehicle.getAttachedAIImplements = function() return kept end
    local results = { pcall(original, rootVehicle, ...) }
    rootVehicle.getAttachedAIImplements = getter
    if not results[1] then
        error(results[2], 0)
    end
    return results[2], NarrowLanes.alignImplementData(results[3], full, kept)
end

-- ===== hooks (the game's classes, patched once when this file loads) =====
if FieldCourseSettings ~= nil and FieldCourseSettings.generate ~= nil and not NarrowLanes.hooked then
    NarrowLanes.hooked = true
    local originalGenerate = FieldCourseSettings.generate
    FieldCourseSettings.generate = function(rootVehicle, ...)
        return NarrowLanes.generate(originalGenerate, rootVehicle, ...)
    end
    print("[RandomFixes] narrow lanes: the field lanes (steering assist and AI helper) are planned for the narrowest attached implement")
end

if AIAutomaticSteering ~= nil and AIAutomaticSteering.getAttacherToolWorkingWidth ~= nil and Utils ~= nil and Utils.overwrittenFunction ~= nil
    and not NarrowLanes.widthHooked then
    NarrowLanes.widthHooked = true
    AIAutomaticSteering.getAttacherToolWorkingWidth = Utils.overwrittenFunction(AIAutomaticSteering.getAttacherToolWorkingWidth,
        function(self, superFunc)
            if not NarrowLanes.ENABLED then
                return superFunc(self)
            end
            return NarrowLanes.narrowestWorkingWidth(self.rootVehicle)
        end)
end
