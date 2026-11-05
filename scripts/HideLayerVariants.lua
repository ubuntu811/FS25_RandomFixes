--[[
    HideLayerVariants.lua -- the Painting menu of the construction screen stops listing the damage variants of ground textures (COBBLESTONE03_CRACKED1, _MISSING2, _WORN ...).

    The menu lists the map's ground types (g_groundTypeManager.groundTypeMappings); the mod "All The Ground Textures" adds every ALL-CAPS terrain layer to them, and the damage variants made for
    Immersive Weathering (tools/damage_builder.py) are ALL-CAPS layers too: five to seven more tiles per texture, which buries the real ones. The variants are not meant to be painted by hand
    (a set's "matching details" lays them), so they are taken out of the mappings just before the screen builds its paint brushes. It does not matter which mod added them or in which order the
    mods loaded: the filter runs at the last moment.

    A variant is a layer named <another layer of the map>_<something with a damage word> (crack, missing, worn, damage, broken, chip, pothole, hole), so DIRT_ROAD or STONY_DIRT stay.
]]
HideLayerVariants = {}
HideLayerVariants.WORDS = { "crack", "missing", "worn", "damage", "broken", "chip", "pothole", "hole" }

local function say(format, ...)
    print(string.format("[RandomFixes] " .. format, ...))
end

-- known: a set of lower-case layer names of the map.
function HideLayerVariants.isVariant(name, known)
    local lower = string.lower(name)
    local from = 1
    while true do
        local at = lower:find("_", from, true)
        if at == nil then
            return false
        end
        if known[lower:sub(1, at - 1)] then
            local rest = lower:sub(at + 1)
            for _, word in ipairs(HideLayerVariants.WORDS) do
                if rest:find(word, 1, true) then
                    return true
                end
            end
        end
        from = at + 1
    end
end

-- Removes the variants from the manager's mappings (typeName -> { layerName }). Returns how many.
function HideLayerVariants.prune(manager, layerNames)
    local known = {}
    for _, name in ipairs(layerNames) do
        known[string.lower(name)] = true
    end
    local remove = {}
    for typeName, mapping in pairs(manager.groundTypeMappings or {}) do
        if mapping.layerName ~= nil and HideLayerVariants.isVariant(mapping.layerName, known) then
            remove[#remove + 1] = typeName
        end
    end
    for _, typeName in ipairs(remove) do
        manager.groundTypeMappings[typeName] = nil
    end
    return #remove
end

local function terrainLayerNames()
    local names = {}
    for i = 0, getTerrainNumOfLayers(g_terrainNode) - 1 do
        names[#names + 1] = getTerrainLayerName(g_terrainNode, i)
    end
    return names
end

if ConstructionScreen ~= nil and not HideLayerVariants.hooked then
    HideLayerVariants.hooked = true
    ConstructionScreen.buildTerrainPaintBrushes = Utils.prependedFunction(ConstructionScreen.buildTerrainPaintBrushes, function()
        local ok, removed = pcall(function() return HideLayerVariants.prune(g_groundTypeManager, terrainLayerNames()) end)
        if not ok then
            say("painting menu: the damage variants could not be hidden (%s)", tostring(removed))
        elseif removed > 0 then
            say("painting menu: %d damage variant(s) of ground textures left out", removed)
        end
    end)
end
