--[[
    PreparerCrops.lua -- a harvester header with a cutter AND a fruit preparer (a beet / potato header ...) is only offered the crops the PREPARER lists to the AI helper.
    A multi-crop header whose cutter takes more crops than its preparer lists (peas, carrots ... next to beets) can be harvested by hand but the AI helper stops with
    "field not ready for this work or already worked". A second cause, found with a potato field: the preparer's own list loses crops (see missing()). Details and the suggested game fix: docs/PREPARER_CROPS.md.

    The game: FruitPreparer overrides getAllowCutterAIFruitRequirements to false, which switches off the cutter's own list of AI crops (Cutter:onAIImplementStart and the
    update after working); what is left is the list the preparer made from its own fruitTypes.

    Here: once a vehicle has loaded (every specialization has read its XML, whichever mod the vehicle comes from), (1) every crop the preparer lists gets back what FruitPreparer meant to add
    for it and the game's list lost (a preparer with several crops: each crop with a preparing state, potatoes and beets, clears the list before adding its own, so only the last is left), and
    (2) each crop the cutter takes and the preparer does not list is added with the cutter's normal harvest growth states. Nothing is added that is already in the list.
]]
PreparerCrops = {}
PreparerCrops.ENABLED = true
PreparerCrops.logged = {}

local function say(format, ...)
    print(string.format("[RandomFixes] " .. format, ...))
end

local function contains(list, value)
    for _, entry in ipairs(list or {}) do
        if entry == value then
            return true
        end
    end
    return false
end

local function hasRequirement(list, fruitType, minState, maxState)
    for _, requirement in ipairs(list) do
        if requirement.fruitType == fruitType and requirement.minGrowthState == minState and requirement.maxGrowthState == maxState then
            return true
        end
    end
    return false
end

-- What FruitPreparer means to put into the AI list for one crop it lists (its onLoad): a crop with a preparing state (potato haulm, beet leaves) the preparing states, and the prepared state when
-- the AI uses it (aiUsePreparedState, by default when the vehicle also has a cutter); any other crop its harvest states. A list of { min, max }.
function PreparerCrops.preparerWants(vehicle, desc)
    local preparer = vehicle.spec_fruitPreparer
    if desc.minPreparingGrowthState ~= nil and desc.minPreparingGrowthState ~= -1 then
        local wants = { { desc.minPreparingGrowthState, desc.maxPreparingGrowthState } }
        local usePrepared = vehicle.spec_cutter ~= nil
        if vehicle.xmlFile ~= nil and vehicle.xmlFile.getValue ~= nil then
            local ok, value = pcall(vehicle.xmlFile.getValue, vehicle.xmlFile, "vehicle.fruitPreparer#aiUsePreparedState", usePrepared)
            if ok and value ~= nil then
                usePrepared = value
            end
        end
        if usePrepared and desc.preparedGrowthState ~= nil and desc.preparedGrowthState ~= -1 then
            wants[#wants + 1] = { desc.preparedGrowthState, desc.preparedGrowthState }
        end
        return wants
    end
    local minState = preparer.allowsForageGrowthState and desc.minForageGrowthState or desc.minHarvestingGrowthState
    return { { minState, desc.maxHarvestingGrowthState } }
end

-- The AI requirements that are missing: a list of { fruitType = index, min, max }.
--  1. Every crop the PREPARER lists: FruitPreparer calls setAIFruitRequirements for a crop with a preparing state, and that CLEARS the AI list (AIImplement:setAIFruitRequirements = clear + add),
--     so in a preparer with several crops (beets, potatoes ...) only the last such crop is left. Whatever the preparer would have added for a listed crop and is not in the list is put back.
--  2. Every crop the CUTTER takes that the preparer does not list, when the cutter's own AI list is switched off (FruitPreparer:getAllowCutterAIFruitRequirements is false): its harvest states.
function PreparerCrops.missing(vehicle)
    local preparer, cutter = vehicle.spec_fruitPreparer, vehicle.spec_cutter
    if preparer == nil or vehicle.getAIFruitRequirements == nil or vehicle.addAIFruitRequirement == nil or g_fruitTypeManager == nil then
        return {}
    end
    local list = vehicle:getAIFruitRequirements() or {}
    local result = {}
    local function want(index, minState, maxState)
        if minState ~= nil and maxState ~= nil and not hasRequirement(list, index, minState, maxState) and not hasRequirement(result, index, minState, maxState) then
            result[#result + 1] = { fruitType = index, minGrowthState = minState, maxGrowthState = maxState }
        end
    end
    for _, index in ipairs(preparer.fruitTypes or {}) do
        local desc = g_fruitTypeManager:getFruitTypeByIndex(index)
        if desc ~= nil then
            for _, state in ipairs(PreparerCrops.preparerWants(vehicle, desc)) do
                want(index, state[1], state[2])
            end
        end
    end
    -- the cutter manages its own AI crops: nothing to add for it
    if cutter ~= nil and cutter.fruitTypeIndices ~= nil and vehicle.getAllowCutterAIFruitRequirements ~= nil and vehicle:getAllowCutterAIFruitRequirements() == false then
        local known = {}
        for _, requirement in ipairs(list) do
            known[requirement.fruitType] = true
        end
        for _, index in ipairs(cutter.fruitTypeIndices) do
            if not known[index] and not contains(preparer.fruitTypes, index) then
                local desc = g_fruitTypeManager:getFruitTypeByIndex(index)
                if desc ~= nil then
                    -- as the cutter itself does for its crops
                    want(index, cutter.allowsForageGrowthState and desc.minForageGrowthState or desc.minHarvestingGrowthState, desc.maxHarvestingGrowthState)
                end
            end
        end
    end
    return result
end

function PreparerCrops.apply(vehicle)
    if not PreparerCrops.ENABLED or vehicle == nil then
        return
    end
    local added = {}
    for _, requirement in ipairs(PreparerCrops.missing(vehicle)) do
        vehicle:addAIFruitRequirement(requirement.fruitType, requirement.minGrowthState, requirement.maxGrowthState)
        local desc = g_fruitTypeManager:getFruitTypeByIndex(requirement.fruitType)
        added[#added + 1] = string.format("%s %d-%d", string.upper(tostring(desc ~= nil and desc.name or requirement.fruitType)), requirement.minGrowthState, requirement.maxGrowthState)
    end
    if #added > 0 then
        local key = tostring(vehicle.configFileName)
        if not PreparerCrops.logged[key] then
            PreparerCrops.logged[key] = true
            say("AI crops: %s: put into the AI helper's crop list (the game's list lacked them): %s", key, table.concat(added, ", "))
        end
    end
end

-- ===== the probe: console rfAiCrops =====
-- What the AI helper is told to harvest, for every vehicle and implement within 40 m of the player (their AI crop lists, with the growth states they accept), and what the ground under the player is
-- (the crop, its growth state, and whether that is inside the crop's harvest window). To tell a header that does not list a crop from a field that is not ready (or already harvested).
function PreparerCrops.probe()
    local px, pz
    if g_localPlayer ~= nil and g_localPlayer.rootNode ~= nil then
        local x, _, z = getWorldTranslation(g_localPlayer.rootNode)
        px, pz = x, z
    end
    if px == nil then
        return "no player position"
    end
    local out = {}
    local ok, err = pcall(function()
        local state = FieldState.new()
        state:update(px, pz)
        local fruitType = g_fruitTypeManager:getFruitTypeByIndex(state.fruitTypeIndex)
        if fruitType == nil then
            out[#out + 1] = "the ground here: no crop"
        else
            local growth = state.growthState or -1
            local verdict = "in the harvest window"
            if growth < fruitType.minHarvestingGrowthState then
                verdict = "NOT RIPE YET"
            elseif growth > fruitType.maxHarvestingGrowthState then
                verdict = "PAST the harvest window (withered or already harvested)"
            end
            out[#out + 1] = string.format("the ground here: %s, growth state %d, harvest states %d to %d: %s", tostring(fruitType.name), growth, fruitType.minHarvestingGrowthState, fruitType.maxHarvestingGrowthState, verdict)
        end
    end)
    if not ok then
        out[#out + 1] = "the ground here: unreadable (" .. tostring(err) .. ")"
    end
    local vehicles = g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.getAIFruitRequirements ~= nil and vehicle.rootNode ~= nil then
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            if math.sqrt((x - px) ^ 2 + (z - pz) ^ 2) < 40 then
                local crops = {}
                for _, requirement in ipairs(vehicle:getAIFruitRequirements() or {}) do
                    local fruitType = g_fruitTypeManager:getFruitTypeByIndex(requirement.fruitType)
                    crops[#crops + 1] = string.format("%s %s-%s", fruitType ~= nil and tostring(fruitType.name) or "?", tostring(requirement.minGrowthState), tostring(requirement.maxGrowthState))
                end
                local cutterOwn = vehicle.getAllowCutterAIFruitRequirements ~= nil and tostring(vehicle:getAllowCutterAIFruitRequirements()) or "n/a"
                out[#out + 1] = string.format("%s: AI crops: %s (the cutter's own list on: %s)", tostring(vehicle.configFileName), #crops > 0 and table.concat(crops, ", ") or "NONE", cutterOwn)
            end
        end
    end
    print("[RandomFixes] AI crops probe:\n" .. table.concat(out, "\n"))
    return table.concat(out, "\n")
end

function PreparerCrops.consoleProbe()
    return PreparerCrops.probe()
end

if addConsoleCommand ~= nil and not PreparerCrops.commandAdded then
    PreparerCrops.commandAdded = true
    addConsoleCommand("rfAiCrops", "RandomFixes: what the AI helper is told to harvest near you, and the crop state of the ground under you", "consoleProbe", PreparerCrops)
end

-- ===== hooks (the game's class, patched once when this file loads) =====
if AIImplement ~= nil and AIImplement.onPostLoad ~= nil and Utils ~= nil and not PreparerCrops.hooked then
    PreparerCrops.hooked = true
    AIImplement.onPostLoad = Utils.appendedFunction(AIImplement.onPostLoad, function(self)
        local ok, err = pcall(PreparerCrops.apply, self)
        if not ok then
            say("AI crops: skipped (%s)", tostring(err))
        end
    end)
    say("AI crops: the crops of a fruit preparer that the game's AI list lost, and a cutter's crops that its preparer does not list, are put into the AI helper's list")
end
