--[[
    SmartShopSearch.lua -- the shop's search also finds what a machine IS, not only what it is called: "cotton" finds the machines of the
    shop category "Cotton Harvesters" whatever their name is ("CP690", "Module Express 635"), "forage" the forage harvesters, "tractor" the tractors.

    The game's own search (StoreManager.indexedSearch) knows four fields of an item only: its title, brand, author and DLC title. The category
    title is not one of them, though the shop shows it everywhere. Here the search runs as before; the results the game gives back are then
    extended by the items whose category titles, brand and name together contain every word typed (any order, any case). The game's results come
    first, ours after, nobody twice. Same items as the game's own index holds: vehicles and hand tools that are shown in the store and unlocked.

    The wrapper is put on the store manager the first time the shop's search is used (ShopMenu:onSearchTextEntered). Everything in a pcall: if it
    does not fit, the game's search runs alone and a line says why.
]]
SmartShopSearch = {}

local function say(format, ...)
    print(string.format("[RandomFixes] " .. format, ...))
end

local function localized(text)
    if type(text) ~= "string" then
        return ""
    end
    if text:sub(1, 6) == "$l10n_" and g_i18n ~= nil then
        return g_i18n:getText(text:sub(7))
    end
    return text
end

-- The words of a query: lower case, split at spaces. Nothing for an empty query.
function SmartShopSearch.words(text)
    local words = {}
    for word in string.gmatch(string.lower(text or ""), "%S+") do
        words[#words + 1] = word
    end
    return words
end

-- What a store item can be found by: its name, its brand and the titles of all its categories, lower case.
function SmartShopSearch.haystack(storeItem)
    local parts = { localized(storeItem.name) }
    local brand = g_brandManager ~= nil and g_brandManager:getBrandByIndex(storeItem.brandIndex) or nil
    if brand ~= nil and brand.name ~= "NONE" then
        parts[#parts + 1] = localized(brand.title)
    elseif storeItem.brandNameRaw ~= nil then
        parts[#parts + 1] = storeItem.brandNameRaw
    end
    for _, name in ipairs(storeItem.categoryNames or {}) do
        local category = g_storeManager:getCategoryByName(name)
        if category ~= nil then
            parts[#parts + 1] = localized(category.title)
        end
    end
    return string.lower(table.concat(parts, " "))
end

function SmartShopSearch.matches(storeItem, words)
    if #words == 0 then
        return false
    end
    local haystack = SmartShopSearch.haystack(storeItem)
    for _, word in ipairs(words) do
        if not haystack:find(word, 1, true) then
            return false
        end
    end
    return true
end

-- The items of the shop (what the game's own index holds) that match every word.
function SmartShopSearch.find(text)
    local words = SmartShopSearch.words(text)
    local found = {}
    if #words == 0 then
        return found
    end
    for _, storeItem in ipairs(g_storeManager:getItems()) do
        local unlocked = storeItem.extraContentId == nil or g_extraContentSystem == nil or g_extraContentSystem:getIsItemIdUnlocked(storeItem.extraContentId)
        if not storeItem.isBundleItem and unlocked and storeItem.showInStore
            and (storeItem.species == StoreSpecies.VEHICLE or storeItem.species == StoreSpecies.HANDTOOL)
            and SmartShopSearch.matches(storeItem, words) then
            found[#found + 1] = storeItem
        end
    end
    return found
end

-- The game's results (a list of { ref = storeItem }) and ours, nobody twice.
function SmartShopSearch.merge(results, extras)
    local merged, seen = {}, {}
    for _, data in ipairs(results or {}) do
        merged[#merged + 1] = data
        seen[data.ref] = true
    end
    for _, storeItem in ipairs(extras) do
        if not seen[storeItem] then
            seen[storeItem] = true
            merged[#merged + 1] = { ref = storeItem }
        end
    end
    return merged
end

-- g_storeManager:search(text, callback) -> success; the callback gets the results, maybe later.
function SmartShopSearch.install()
    local manager = g_storeManager
    if manager == nil or SmartShopSearch.installedOn == manager then
        return
    end
    local original = manager.search
    if type(original) ~= "function" then
        SmartShopSearch.installedOn = manager
        say("no smart shop search (the store manager has no search function)")
        return
    end
    SmartShopSearch.installedOn = manager
    manager.search = function(self, text, callback, ...)
        local ok, extras = pcall(SmartShopSearch.find, text)
        if not ok then
            say("shop search: the category search failed (%s), the game's search runs alone", tostring(extras))
            return original(self, text, callback, ...)
        end
        if #extras == 0 then
            return original(self, text, callback, ...)
        end
        local success = original(self, text, function(results)
            callback(SmartShopSearch.merge(results, extras))
        end, ...)
        if not success then
            callback(SmartShopSearch.merge({}, extras))                -- (the game's search had nothing to start: ours still has)
            return true
        end
        return success
    end
    say("shop search: also finds items by their category, brand and name words")
end

if ShopMenu ~= nil and not SmartShopSearch.hooked then
    SmartShopSearch.hooked = true
    ShopMenu.onSearchTextEntered = Utils.prependedFunction(ShopMenu.onSearchTextEntered, function()
        local ok, err = pcall(SmartShopSearch.install)
        if not ok then
            say("no smart shop search (%s)", tostring(err))
        end
    end)
end
