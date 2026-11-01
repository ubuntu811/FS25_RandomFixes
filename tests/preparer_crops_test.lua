-- plain Lua: the AI crop list of a header with a cutter and a fruit preparer
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end
end

Utils = { appendedFunction = function(old, new) return function(...) local r = old(...); new(...); return r end end }
local types = {
    { index = 1, name = "sugarBeet", minHarvestingGrowthState = 8, maxHarvestingGrowthState = 9, minForageGrowthState = 3 },
    { index = 2, name = "pea", minHarvestingGrowthState = 7, maxHarvestingGrowthState = 8, minForageGrowthState = 4 },
    { index = 3, name = "carrot", minHarvestingGrowthState = 6, maxHarvestingGrowthState = 7, minForageGrowthState = 2 },
    { index = 4, name = "potato", minHarvestingGrowthState = 7, maxHarvestingGrowthState = 7, minPreparingGrowthState = 6, maxPreparingGrowthState = 6, preparedGrowthState = 7 },
    { index = 5, name = "beetroot", minHarvestingGrowthState = 7, maxHarvestingGrowthState = 7, minPreparingGrowthState = 5, maxPreparingGrowthState = 6, preparedGrowthState = 7 },
}
g_fruitTypeManager = { getFruitTypeByIndex = function(_, i) return types[i] end }
local loaded = 0
AIImplement = { onPostLoad = function(self) loaded = loaded + 1 end }
dofile("scripts/PreparerCrops.lua")
local P = PreparerCrops

-- a vehicle: preparer listed sugar beet (index 1), which put its own requirement into the AI list
local function header(cutterTypes, preparerTypes, allowCutter)
    local v = { configFileName = "multi.xml", requirements = { { fruitType = 1, minGrowthState = 8, maxGrowthState = 9 } } }
    v.spec_cutter = { fruitTypeIndices = cutterTypes }
    v.spec_fruitPreparer = { fruitTypes = preparerTypes }
    v.getAIFruitRequirements = function(self) return self.requirements end
    v.addAIFruitRequirement = function(self, fruitType, min, max) self.requirements[#self.requirements + 1] = { fruitType = fruitType, minGrowthState = min, maxGrowthState = max } end
    v.getAllowCutterAIFruitRequirements = function() return allowCutter end
    return v
end

local v = header({ 1, 2, 3 }, { 1 }, false)
AIImplement.onPostLoad(v)
check("the base onPostLoad still runs", loaded == 1)
check("the crops of the cutter that the preparer lacks are added (pea, carrot)", #v.requirements == 3 and v.requirements[2].fruitType == 2 and v.requirements[3].fruitType == 3)
check("... with the harvest growth states of the crop", v.requirements[2].minGrowthState == 7 and v.requirements[2].maxGrowthState == 8 and v.requirements[3].minGrowthState == 6)
check("... the preparer's own requirement is untouched", v.requirements[1].fruitType == 1 and v.requirements[1].minGrowthState == 8)

AIImplement.onPostLoad(v)
check("a second run adds nothing (no duplicates)", #v.requirements == 3)

v = header({ 1, 2, 3 }, { 1, 2, 3 }, false)
v.requirements = { { fruitType = 1, minGrowthState = 8, maxGrowthState = 9 }, { fruitType = 2, minGrowthState = 7, maxGrowthState = 8 }, { fruitType = 3, minGrowthState = 6, maxGrowthState = 7 } }
AIImplement.onPostLoad(v)
check("the preparer lists everything and the AI list has it all: nothing added", #v.requirements == 3)

v = header({ 1, 2, 3 }, { 1 }, true)
AIImplement.onPostLoad(v)
check("the cutter's own AI list is on (it fills the crops itself): nothing added", #v.requirements == 1)

v = header({ 1, 2, 3 }, { 1 }, false)
v.spec_cutter.allowsForageGrowthState = true
AIImplement.onPostLoad(v)
check("a forage cutter uses the forage growth states, as the cutter does", v.requirements[2].minGrowthState == 4 and v.requirements[3].minGrowthState == 2)

v = header({ 1, 2 }, { 1 }, false)
v.spec_fruitPreparer = nil
AIImplement.onPostLoad(v)
check("no preparer: not this fix's business", #v.requirements == 1)
v = header({ 1, 2 }, { 1 }, false)
v.spec_cutter = nil
AIImplement.onPostLoad(v)
check("no cutter: nothing", #v.requirements == 1)
v = header({ 1, 2 }, { 1 }, false)
v.getAllowCutterAIFruitRequirements = nil
AIImplement.onPostLoad(v)
check("a game update removed the function: nothing changed, no error", #v.requirements == 1)

v = header({ 1, 2, 99 }, { 1 }, false)
AIImplement.onPostLoad(v)
check("a crop the game does not know is skipped", #v.requirements == 2 and v.requirements[2].fruitType == 2)

-- the game's list loses crops: FruitPreparer calls setAIFruitRequirements (clear + add) for every crop with a preparing state, so only the last one is left
-- a preparer listing potato (4) and beetroot (5): the list holds beetroot only (its preparing states 5-6 and the prepared state 7)
local function lostList()
    local lost = header({ 4, 5 }, { 4, 5 }, false)
    lost.requirements = { { fruitType = 5, minGrowthState = 5, maxGrowthState = 6 }, { fruitType = 5, minGrowthState = 7, maxGrowthState = 7 } }
    return lost
end
v = lostList()
AIImplement.onPostLoad(v)
local function has(list, fruitType, minState, maxState)
    for _, r in ipairs(list) do if r.fruitType == fruitType and r.minGrowthState == minState and r.maxGrowthState == maxState then return true end end
    return false
end
check("a crop the game's list lost is put back: potato gets its preparing states (6-6) and the prepared state (7-7), as FruitPreparer meant", has(v.requirements, 4, 6, 6) and has(v.requirements, 4, 7, 7))
check("... the crop the list kept is untouched and not doubled", #v.requirements == 4 and has(v.requirements, 5, 5, 6) and has(v.requirements, 5, 7, 7))
AIImplement.onPostLoad(v)
check("... a second run adds nothing", #v.requirements == 4)
v = lostList()
v.xmlFile = { getValue = function(_, key, default) if key:find("aiUsePreparedState", 1, true) then return false end return default end }
AIImplement.onPostLoad(v)
check("aiUsePreparedState=false in the vehicle's xml: only the preparing states are put back", has(v.requirements, 4, 6, 6) and not has(v.requirements, 4, 7, 7))
v = lostList()
v.spec_cutter, v.getAllowCutterAIFruitRequirements = nil, nil
AIImplement.onPostLoad(v)
check("a preparer without a cutter (no prepared state by default) loses crops the same way: the preparing states are put back, not the prepared one", has(v.requirements, 4, 6, 6) and not has(v.requirements, 4, 7, 7))
v = header({ 1, 4 }, { 1, 4 }, false)
v.requirements = { { fruitType = 4, minGrowthState = 6, maxGrowthState = 6 }, { fruitType = 4, minGrowthState = 7, maxGrowthState = 7 } }
AIImplement.onPostLoad(v)
check("sugar beet (no preparing state in this fixture) falls back to its harvest states, and potato already there is left alone", has(v.requirements, 1, 8, 9) and #v.requirements == 3)

PreparerCrops.ENABLED = false
v = header({ 1, 2, 3 }, { 1 }, false)
AIImplement.onPostLoad(v)
check("switched off: nothing", #v.requirements == 1)
PreparerCrops.ENABLED = true

v = header({ 1, 2, 3 }, { 1 }, false)
v.addAIFruitRequirement = function() error("boom") end
local ok = pcall(AIImplement.onPostLoad, v)
check("an error inside is caught: the vehicle still loads", ok)

-- the probe: the crop under the player and the AI crop lists of the vehicles near him
local printed = {}
local realPrint = print
print = function(text) printed[#printed + 1] = text end
g_localPlayer = { rootNode = 1 }
local position = { [1] = { 100, 0, 100 }, [2] = { 110, 0, 100 }, [3] = { 500, 0, 500 } }
getWorldTranslation = function(node) return position[node][1], position[node][2], position[node][3] end
local state = { growthState = 8 }
FieldState = { new = function() return setmetatable({}, { __index = { update = function(self) self.fruitTypeIndex, self.growthState = 1, state.growthState end } }) end }
local near, far = header({ 1, 2, 3 }, { 1 }, false), header({ 1 }, { 1 }, true)
near.rootNode, far.rootNode = 2, 3
g_currentMission = { vehicleSystem = { vehicles = { near, far } } }
local text = P.probe()
check("probe: the ground is named with its growth state and the verdict", text:find("sugarBeet, growth state 8, harvest states 8 to 9: in the harvest window", 1, true) ~= nil)
check("probe: a vehicle near lists its AI crops and whether its cutter's own list is on; one far away is left out", text:find("multi.xml: AI crops: sugarBeet 8-9", 1, true) ~= nil and select(2, text:gsub("multi.xml", "")) == 1)
state.growthState = 3
check("probe: a crop that is not ripe says so", P.probe():find("NOT RIPE YET", 1, true) ~= nil)
state.growthState = 11
check("probe: a crop past its window says so", P.probe():find("PAST the harvest window", 1, true) ~= nil)
near.requirements = {}
check("probe: a vehicle whose AI list is empty says NONE", P.probe():find("AI crops: NONE", 1, true) ~= nil)
print = realPrint

print(string.format("preparer_crops_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
