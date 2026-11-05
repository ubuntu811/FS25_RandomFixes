-- plain Lua with a fake store: the shop search also finds items by their category titles, brand and name words
local passed, failed = 0, 0
local realPrint = print
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end
local log = {}
print = function(text) log[#log + 1] = text end

Utils = { prependedFunction = function(old, new) return function(...) new(...); return old(...) end end }
StoreSpecies = { VEHICLE = "vehicle", HANDTOOL = "handtool", PLACEABLE = "placeable" }
g_i18n = { getText = function(_, key) return "<" .. key .. ">" end }

local categories = {
    COTTONHARVESTERS = { title = "Cotton Harvesters" },
    TRACTORSL = { title = "Large Tractors" },
    PACKS = { title = "Packs" },
    LOCALIZED = { title = "$l10n_category_forageHarvesters" },
}
local brands = { [1] = { name = "CASE", title = "Case IH" }, [2] = { name = "DEERE", title = "John Deere" }, [3] = { name = "NONE", title = "" } }
local function item(name, brandIndex, cats, extra)
    local t = { name = name, brandIndex = brandIndex, categoryNames = cats, showInStore = true, species = StoreSpecies.VEHICLE }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
local express = item("Module Express 635", 1, { "COTTONHARVESTERS", "PACKS" })
local cp690 = item("CP690", 2, { "COTTONHARVESTERS" })
local grab = item("Cotton Wheelie Grab", 3, { "PACKS" })
local axion = item("Axion 960", 1, { "TRACTORSL" })
local forage = item("Jaguar", 3, { "LOCALIZED" })
local hidden = item("Secret Cotton Thing", 1, { "COTTONHARVESTERS" }, { showInStore = false })
local bundle = item("Bundle Cotton", 1, { "COTTONHARVESTERS" }, { isBundleItem = true })
local house = item("Cotton House", 3, { "COTTONHARVESTERS" }, { species = StoreSpecies.PLACEABLE })
local locked = item("Locked Cotton", 1, { "COTTONHARVESTERS" }, { extraContentId = "dlc_locked" })
g_extraContentSystem = { getIsItemIdUnlocked = function(_, id) return id ~= "dlc_locked" end }
local items = { express, cp690, grab, axion, forage, hidden, bundle, house, locked }

local engineCalls
g_storeManager = {
    getItems = function() return items end,
    getCategoryByName = function(_, name) return categories[name] end,
    search = function(self, text, callback)
        engineCalls = (engineCalls or 0) + 1
        local results = {}
        for _, it in ipairs(items) do          -- (the game's own: the name only)
            if it.showInStore and it.extraContentId == nil and it.name:lower():find(text:lower(), 1, true) and it.species == StoreSpecies.VEHICLE and not it.isBundleItem then results[#results + 1] = { ref = it } end
        end
        callback(results)
        return true
    end,
}
g_brandManager = { getBrandByIndex = function(_, index) return brands[index] end }
ShopMenu = { onSearchTextEntered = function() end }
dofile("scripts/SmartShopSearch.lua")

local function search(text)
    local out
    local ok = g_storeManager:search(text, function(results) out = results end)
    return out, ok
end
local function names(results)
    local list = {}
    for _, data in ipairs(results or {}) do list[#list + 1] = data.ref.name end
    return table.concat(list, ", ")
end

check("the words of a query: lower case, split at spaces", table.concat(SmartShopSearch.words("  Cotton   HARVESTER "), "|") == "cotton|harvester" and #SmartShopSearch.words("   ") == 0)

-- before the shop's search is used the store manager is untouched
local untouched = g_storeManager.search
ShopMenu.onSearchTextEntered({}, "cotton", true)
check("the first use of the shop's search puts the wrapper on the store manager (once)", g_storeManager.search ~= untouched)
local wrapped = g_storeManager.search
ShopMenu.onSearchTextEntered({}, "cotton", true)
check("... and not again on the second use", g_storeManager.search == wrapped)

local results, ok = search("cotton")
check("cotton finds the machines of the Cotton Harvesters category by their category, not only the ones named cotton", names(results) == "Cotton Wheelie Grab, Module Express 635, CP690")
check("... the game's results first, ours after", results[1].ref == grab and results[2].ref == express and results[3].ref == cp690 and ok == true)
check("... never an item the shop does not show (not in the store, a bundle part, a placeable, a locked one)", not names(results):find("Secret") and not names(results):find("Bundle") and not names(results):find("House") and not names(results):find("Locked"))
check("a word of the brand and one of the category together: case ih cotton", names((search("case cotton"))) == "Module Express 635")
check("any order, any case: HARVESTERS cotton", names((search("HARVESTERS cotton"))) == "Module Express 635, CP690")
check("the category title of a localised category is looked up", names((search("forage"))) == "Jaguar")
check("tractor finds the tractors by their category (Large Tractors)", names((search("tractors"))) == "Axion 960")
check("nobody twice: an item the game found by name and by category is in once", names((search("module"))) == "Module Express 635")
check("a word nothing has: nothing, and the game's search ran", names((search("zzz"))) == "" and engineCalls ~= nil)

-- the game's search could not start: ours still answers
local realSearch = wrapped
local calls = 0
g_storeManager.search = nil
g_storeManager = nil
g_storeManager = {
    getItems = function() return items end,
    getCategoryByName = function(_, name) return categories[name] end,
    search = function() return false end,
}
SmartShopSearch.installedOn = nil
SmartShopSearch.install()
local out
local started = g_storeManager:search("cotton", function(r) calls = calls + 1; out = r end)
check("the game's search refusing to start (false): the category results come back all the same, once", started == true and calls == 1 and names(out) == "Module Express 635, CP690, Cotton Wheelie Grab")
started = g_storeManager:search("zzz", function() end)
check("... and with nothing found either way it says false, like the game", started == false)

-- a failure inside ours leaves the game's search alone
g_storeManager.getItems = function() error("boom") end
local plain = { ran = false }
g_storeManager.search = nil
check("a failing category search does not break the game's (one line says so)", (function()
    SmartShopSearch.installedOn = nil
    local base = function(self, text, callback) plain.ran = true; callback({}); return true end
    g_storeManager.search = base
    SmartShopSearch.install()
    log = {}
    local got
    local success = g_storeManager:search("cotton", function(r) got = r end)
    return success == true and plain.ran and #got == 0 and #log == 1 and log[1]:find("failed", 1, true) ~= nil
end)())

-- no search function at all
g_storeManager = { getItems = function() return {} end }
SmartShopSearch.installedOn = nil
log = {}
SmartShopSearch.install()
check("a store manager without a search function: nothing is changed and a line says so", g_storeManager.search == nil and #log == 1)

print = realPrint
print(string.format("smart_shop_search_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
