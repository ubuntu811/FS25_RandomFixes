-- plain Lua with a fake ground type manager: the damage variants of ground textures are left out of the construction screen's paint list
local passed, failed = 0, 0
local realPrint = print
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end
local log = {}
print = function(text) log[#log + 1] = text end
Utils = { prependedFunction = function(old, new) return function(...) new(...); return old(...) end end }

local layers = { "DIRT", "DIRT_ROAD", "STONY_DIRT", "COBBLESTONE03", "COBBLESTONE03_CRACKED1", "COBBLESTONE03_CRACKED3", "COBBLESTONE03_MISSING2", "COBBLESTONE03_WORN", "COBBLESTONE03_DAMAGED", "GHOST_CRACKED", "cobblestone03", "cobblestone03_cracked1" }
g_terrainNode = 1
getTerrainNumOfLayers = function() return #layers end
getTerrainLayerName = function(_, i) return layers[i + 1] end
g_groundTypeManager = { groundTypeMappings = {} }
for _, name in ipairs(layers) do g_groundTypeManager.groundTypeMappings[name] = { typeName = name, layerName = name, title = name } end
g_groundTypeManager.groundTypeMappings.tiles08 = { typeName = "tiles08", layerName = "COBBLESTONE03", title = "Cobblestones" }

local built
ConstructionScreen = { buildTerrainPaintBrushes = function(self, n) built = {}; for k in pairs(g_groundTypeManager.groundTypeMappings or {}) do built[k] = true end; return n + 1 end }
dofile("scripts/HideLayerVariants.lua")

local known = {}
for _, n in ipairs(layers) do known[n:lower()] = true end
check("a damage variant of a layer that exists is a variant", HideLayerVariants.isVariant("COBBLESTONE03_CRACKED1", known) and HideLayerVariants.isVariant("COBBLESTONE03_WORN", known) and HideLayerVariants.isVariant("cobblestone03_cracked1", known))
check("real layers with an underscore, and a name whose base layer does not exist, are not", not HideLayerVariants.isVariant("DIRT_ROAD", known) and not HideLayerVariants.isVariant("STONY_DIRT", known) and not HideLayerVariants.isVariant("GHOST_CRACKED", known) and not HideLayerVariants.isVariant("COBBLESTONE03", known))

local result = ConstructionScreen:buildTerrainPaintBrushes(41)
check("the screen builds its brushes as before (the original runs, its result is kept)", result == 42)
check("the variants are gone from the list the screen builds from", built["COBBLESTONE03_CRACKED1"] == nil and built["COBBLESTONE03_CRACKED3"] == nil and built["COBBLESTONE03_MISSING2"] == nil and built["COBBLESTONE03_WORN"] == nil and built["cobblestone03_cracked1"] == nil)
check("... and everything else stays (the base layers, the road and stony dirt, the mapped type)", built["DIRT"] and built["DIRT_ROAD"] and built["STONY_DIRT"] and built["COBBLESTONE03"] and built["cobblestone03"] and built["GHOST_CRACKED"] and built.tiles08)
check("... and the _DAMAGED mix stays: the one entry per texture for painting damage in places", built["COBBLESTONE03_DAMAGED"] == true)
check("one line says how many were left out (5: cracked1, cracked3, missing2, worn and the lower-case cracked1)", #log == 1 and log[1]:find("5 damage variant", 1, true) ~= nil)

-- a second build: nothing left to remove, no line
log = {}
ConstructionScreen:buildTerrainPaintBrushes(0)
check("a second build removes nothing and says nothing", #log == 0)

-- a failure leaves the game's list alone
g_groundTypeManager = { groundTypeMappings = nil }
getTerrainNumOfLayers = function() error("boom") end
log = {}
check("a failure inside ours: one line, the screen still builds", ConstructionScreen:buildTerrainPaintBrushes(1) == 2 and #log == 1 and log[1]:find("could not be hidden", 1, true) ~= nil)

print = realPrint
print(string.format("hide_layer_variants_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
