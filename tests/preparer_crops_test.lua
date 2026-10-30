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
AIImplement.onPostLoad(v)
check("the preparer lists everything: nothing added", #v.requirements == 1)

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

PreparerCrops.ENABLED = false
v = header({ 1, 2, 3 }, { 1 }, false)
AIImplement.onPostLoad(v)
check("switched off: nothing", #v.requirements == 1)
PreparerCrops.ENABLED = true

v = header({ 1, 2, 3 }, { 1 }, false)
v.addAIFruitRequirement = function() error("boom") end
local ok = pcall(AIImplement.onPostLoad, v)
check("an error inside is caught: the vehicle still loads", ok)

print(string.format("preparer_crops_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
