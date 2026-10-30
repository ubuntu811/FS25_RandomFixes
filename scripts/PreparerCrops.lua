--[[
    PreparerCrops.lua -- a harvester header with a cutter AND a fruit preparer (a beet / potato header ...) is only offered the crops the PREPARER lists to the AI helper.
    A multi-crop header whose cutter takes more crops than its preparer lists (peas, carrots ... next to beets) can be harvested by hand but the AI helper stops with
    "field not ready for this work or already worked". Details and the suggested game fix: docs/PREPARER_CROPS.md.

    The game: FruitPreparer overrides getAllowCutterAIFruitRequirements to false, which switches off the cutter's own list of AI crops (Cutter:onAIImplementStart and the
    update after working); what is left is the list the preparer made from its own fruitTypes.

    Here: once a vehicle has loaded (every specialization has read its XML, whichever mod the vehicle comes from), each crop the cutter takes and the preparer does not list
    is added to the AI's crops with the cutter's normal harvest growth states. Nothing is changed for a vehicle where the cutter's own list is on, or where the preparer
    already lists everything.
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

-- The crops (fruit type indices) the cutter takes that neither the preparer lists nor the AI already has, in the cutter's order.
function PreparerCrops.missing(vehicle)
    local cutter, preparer = vehicle.spec_cutter, vehicle.spec_fruitPreparer
    if cutter == nil or preparer == nil or cutter.fruitTypeIndices == nil or vehicle.getAIFruitRequirements == nil or vehicle.addAIFruitRequirement == nil then
        return {}
    end
    -- the cutter manages its own AI crops: nothing to add
    if vehicle.getAllowCutterAIFruitRequirements == nil or vehicle:getAllowCutterAIFruitRequirements() ~= false then
        return {}
    end
    local known = {}
    for _, requirement in ipairs(vehicle:getAIFruitRequirements() or {}) do
        known[requirement.fruitType] = true
    end
    local result = {}
    for _, index in ipairs(cutter.fruitTypeIndices) do
        if not known[index] and not contains(preparer.fruitTypes, index) then
            result[#result + 1] = index
        end
    end
    return result
end

function PreparerCrops.apply(vehicle)
    if not PreparerCrops.ENABLED or vehicle == nil then
        return
    end
    local added = {}
    for _, index in ipairs(PreparerCrops.missing(vehicle)) do
        local fruitType = g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByIndex(index) or nil
        if fruitType ~= nil then
            -- as the cutter itself does for its crops
            local minState = vehicle.spec_cutter.allowsForageGrowthState and fruitType.minForageGrowthState or fruitType.minHarvestingGrowthState
            vehicle:addAIFruitRequirement(fruitType.index, minState, fruitType.maxHarvestingGrowthState)
            added[#added + 1] = tostring(fruitType.name)
        end
    end
    if #added > 0 then
        local key = tostring(vehicle.configFileName)
        if not PreparerCrops.logged[key] then
            PreparerCrops.logged[key] = true
            say("AI crops: %s: the cutter's crops missing in the preparer's list added for the AI helper: %s", key, table.concat(added, " "))
        end
    end
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
    say("AI crops: a cutter's crops that its fruit preparer does not list are offered to the AI helper")
end
