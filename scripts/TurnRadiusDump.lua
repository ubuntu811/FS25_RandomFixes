--[[
    TurnRadiusDump.lua -- console command rfTurnRadius: where the AI's minimum turn radius of the rig you sit in comes from. Reads the live values (the vehicle XMLs of DLC packs cannot be read offline) and
    prints, per vehicle in the chain: whether the game counts it as an AI implement, what it declares (radius, rotation joint, wheels) and the radius the game works out for it, then the final number
    the way FieldCourseSettings combines it: max(tractor steering * 1.1, root's own minimum, worst tool radius, 2.5).
]]
TurnRadiusDump = {}

local function say(format, ...)
    print(string.format("[RandomFixes] " .. format, ...))
end

-- The planner's rule (FieldCourseSettings): the largest of the four.
function TurnRadiusDump.combine(rootMaxTurningRadius, rootAIMin, toolRadii)
    local radius = (rootMaxTurningRadius or 0) * 1.1
    if rootAIMin ~= nil then
        radius = math.max(radius, rootAIMin)
    end
    for _, r in ipairs(toolRadii) do
        radius = math.max(radius, r)
    end
    return math.max(radius, 2.5)
end

local function nameOf(object)
    return object.getFullName ~= nil and object:getFullName() or tostring(object.configFileName)
end

local function describe(object, depth, counted, toolRadii)
    local line = string.format("%s%s", string.rep("  ", depth), nameOf(object))
    local isAI = object.getCanImplementBeUsedForAI ~= nil and object:getCanImplementBeUsedForAI() == true
    line = line .. string.format(" | counted as AI implement: %s", tostring(counted[object] == true))
    if object.getAITurnRadiusLimitation ~= nil then
        local radius, joint, wheels, factor, initial = object:getAITurnRadiusLimitation()
        line = line .. string.format(" | declares radius %s, rotation joint %s, wheels %d, rotLimitFactor %s, initial factor %s",
            tostring(radius), joint ~= nil and getName(joint) or "none", wheels ~= nil and #wheels or 0, tostring(factor), tostring(initial))
        if counted[object] then
            local ok, result = pcall(AIVehicleUtil.getMaxToolRadius, { object = object })
            line = line .. string.format(" | game's tool radius %s", ok and string.format("%.2f m", result) or ("failed: " .. tostring(result)))
            if ok then
                toolRadii[#toolRadii + 1] = result
            end
        end
    else
        line = line .. " | no AI implement setup at all"
    end
    if object.getAIMinTurningRadius ~= nil and object:getAIMinTurningRadius() ~= nil then
        line = line .. string.format(" | own minimum %.2f m", object:getAIMinTurningRadius())
    end
    if object.maxTurningRadius ~= nil then
        line = line .. string.format(" | steering radius %.2f m", object.maxTurningRadius)
    end
    say("%s", line)
    if object.getAttachedImplements ~= nil then
        for _, implement in ipairs(object:getAttachedImplements()) do
            if implement.object ~= nil then
                describe(implement.object, depth + 1, counted, toolRadii)
            end
        end
    end
end

function TurnRadiusDump.run()
    local vehicle = g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() or nil
    local root = vehicle ~= nil and vehicle.rootVehicle or nil
    if root == nil then
        return "rfTurnRadius: sit in the tractor first"
    end
    local counted = {}
    for _, implement in ipairs(root.getAttachedAIImplements ~= nil and root:getAttachedAIImplements() or {}) do
        counted[implement.object] = true
    end
    local toolRadii = {}
    say("turn radius of %s:", nameOf(root))
    describe(root, 0, counted, toolRadii)
    local aiMin = root.getAIMinTurningRadius ~= nil and root:getAIMinTurningRadius() or nil
    local result = TurnRadiusDump.combine(root.maxTurningRadius, aiMin, toolRadii)
    say("the planner's minimum turn radius: %.2f m (tractor steering %.2f x 1.1, root minimum %s, %d counted tool(s), floor 2.5)",
        result, root.maxTurningRadius or 0, tostring(aiMin), #toolRadii)
    return string.format("rfTurnRadius: %.2f m, details in the log", result)
end

if addConsoleCommand ~= nil and not TurnRadiusDump.commandAdded then
    TurnRadiusDump.commandAdded = true
    addConsoleCommand("rfTurnRadius", "rfTurnRadius: where the AI's minimum turn radius of the rig you sit in comes from (to the log)", "run", TurnRadiusDump)
end
