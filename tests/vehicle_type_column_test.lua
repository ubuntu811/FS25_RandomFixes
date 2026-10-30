-- plain Lua with a fake GUI: the column is added to the header and the row template, the data and the sorting work
local passed, failed = 0, 0
local realPrint = print
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end
local log = {}
print = function(text) log[#log + 1] = text end

-- ===== a fake GUI element (position in normalised units: 1 px = 0.001) =====
local Element = {}
Element.__index = Element
local function newElement(name, x)
    return setmetatable({ name = name, position = { x or 0, 0 }, elements = {}, text = "" }, Element)
end
function Element:addChild(child) self.elements[#self.elements + 1] = child; child.parent = self; return child end
function Element:clone(parent, includeId, suppressOnCreate)
    local copy = newElement(self.name, self.position[1])
    copy.text = self.text
    copy.onClickCallback = self.onClickCallback
    copy.target = self.target
    copy.created = not suppressOnCreate
    for _, child in ipairs(self.elements) do child:clone(copy, includeId, true) end
    if parent ~= nil then parent:addChild(copy) end
    return copy
end
function Element:setPosition(x, y) self.position[1] = x or self.position[1]; self.position[2] = y or self.position[2] end
function Element:setText(text) self.text = text end
function Element:setVisible(visible) self.visible = visible end
function Element:getDescendantByName(name)
    for _, child in ipairs(self.elements) do
        if child.name == name then return child end
        local found = child:getDescendantByName(name)
        if found ~= nil then return found end
    end
    return nil
end

-- ===== the game's classes, as far as the hooks need them =====
Utils = {
    appendedFunction = function(oldFunc, newFunc) return function(...) if oldFunc then oldFunc(...) end newFunc(...) end end,
    prependedFunction = function(oldFunc, newFunc) return function(...) newFunc(...) if oldFunc then oldFunc(...) end end end,
}
g_currentModName = "FS25_RandomFixes"
g_i18n = { getText = function(_, name) return ({ rf_columnType = "Type", rf_typeUnknown = "-" })[name] or name end }
local categories = { TRACTORSM = { title = "Tractors" }, ROLLERS = { title = "Rollers" }, TRAILERS = { title = "$l10n_category_trailers" } }
g_storeManager = {
    getItemByXMLFilename = function(_, file) return ({ ["tractor.xml"] = { categoryNames = { "TRACTORSM" } }, ["roller.xml"] = { categoryNames = { "ROLLERS" } },
        ["trailer.xml"] = { categoryNames = { "TRAILERS" } }, ["nocat.xml"] = { categoryNames = {} } })[file] end,
    getCategoryByName = function(_, name) return categories[name] end,
}
InGameMenuStatisticsFrame = { SORT_ORDER_ASC = 1, SORT_ORDER_DESC = 2 }
function InGameMenuStatisticsFrame.onGuiSetupFinished() end
function InGameMenuStatisticsFrame.onFrameOpen() end
function InGameMenuStatisticsFrame.updateView(self)
    table.sort(self.vehicles, function(a, b)
        local va, vb = a.columns[self.sortByColumn].value, b.columns[self.sortByColumn].value
        if va == vb then va, vb = a.columns[1].value, b.columns[1].value end
        if self.sortOrder == InGameMenuStatisticsFrame.SORT_ORDER_DESC then return vb < va end
        return va < vb
    end)
end
function InGameMenuStatisticsFrame.populateCellForItemInSection(self, list, section, index, cell) self.populatedByGame = (self.populatedByGame or 0) + 1 end
function InGameMenuStatisticsFrame.applySorting(self, column)
    if self.sortByColumn == column then self.sortOrder = self.sortOrder == 1 and 2 or 1 end
    self.sortByColumn = column
    self:updateView()
end

g_i18n.getText = g_i18n.getText
dofile("scripts/VehicleTypeColumn.lua")
local V = VehicleTypeColumn
getmetatable = getmetatable
InGameMenuStatisticsFrame.__index = InGameMenuStatisticsFrame

-- ===== a frame with the vehicles page as the game builds it (positions: 1 px = 0.001) =====
local function px(value) return value / 1000 end
local ORDER = { "licensePlate", "age", "operatingHours", "damage", "leasing", "value" }
local OLD = { licensePlate = 440, age = 620, operatingHours = 800, damage = 980, leasing = 1160, value = 1340 }
local function buildFrame()
    local frame = setmetatable({ vehicles = {}, sortIcons = {}, sortByColumn = 1, sortOrder = 1 }, InGameMenuStatisticsFrame)
    local header = newElement("header")
    header:addChild(newElement("nameButton", 0))
    for _, key in ipairs(ORDER) do
        local container = newElement("container_" .. key, px(OLD[key]))
        local button = container:addChild(newElement("button_" .. key, 0))
        button:addChild(newElement("iconAscending"))
        button:addChild(newElement("iconDescending"))
        header:addChild(container)
    end
    local page = newElement("page")
    page:addChild(header)
    frame.subCategoryPages = { newElement("page1"), page }
    local list = newElement("vehiclesList")
    local template = newElement("rowTemplate")
    template:addChild(newElement("name", 0))
    for _, key in ipairs(ORDER) do template:addChild(newElement(key, px(OLD[key]))) end
    list.cellDatabase = { rowTemplate = template }
    list:addChild(template)
    frame.vehiclesList = list
    return frame, header, template
end

local frame, header, template = buildFrame()
-- a row the list made BEFORE the column was set up (the list clones its cells early)
local earlyRow = template:clone(nil, false, true)
frame:onGuiSetupFinished()
check("the setup runs from onGuiSetupFinished and says it is done", frame.rfTypeColumn == "done")
check("the header has one new container (7 children plus the name button = 8)", #header.elements == 8)
local typeHeader = header.elements[8]
check("... the new header is the age header's copy, made without its own onCreate", typeHeader.created == false and typeHeader.elements[1].text == "Type")
check("... with its click handler and the frame as target", typeHeader.elements[1].onClickCallback == V.onClickSort and typeHeader.elements[1].target == frame)
check("... and its sort arrows registered for the new column", frame.sortIcons[V.COLUMN] ~= nil and frame.sortIcons[V.COLUMN][1] ~= nil and frame.sortIcons[V.COLUMN][2] ~= nil)
local function approx(a, b) return math.abs(a - b) < 1e-9 end
check("... placed exactly where the licence plate header was", approx(typeHeader.position[1], px(440)))
check("the licence plate header is hidden", header:getDescendantByName("container_licensePlate").visible == false)
for _, key in ipairs(ORDER) do
    if key ~= "licensePlate" then
        check("header " .. key .. " did not move", approx(header:getDescendantByName("container_" .. key).position[1], px(OLD[key])) and header:getDescendantByName("container_" .. key).visible ~= false)
    end
end
check("the row template was not touched (same cells, same positions)", #template.elements == 7 and approx(template:getDescendantByName("age").position[1], px(620)))
frame:onFrameOpen()
check("a second setup (frame opens) does nothing more", #header.elements == 8)

-- data and sorting
local function item(name, file, typeName)
    return { vehicle = { configFileName = file, typeName = typeName }, columns = { [1] = { text = name, value = name } } }
end
frame.vehicles = { item("Zetor", "tractor.xml"), item("Rotocare", "roller.xml"), item("Timber", "trailer.xml"), item("Fake bucket", "nocat.xml", "wheelLoaderTool") }
frame:updateView()
check("every item has the type column after the frame's sort", frame.vehicles[1].columns[V.COLUMN] ~= nil and frame.vehicles[4].columns[V.COLUMN] ~= nil)
local types = {}
for _, it in ipairs(frame.vehicles) do types[it.columns[1].text] = it.columns[V.COLUMN].text end
check("the type is the shop category's title", types.Zetor == "Tractors" and types.Rotocare == "Rollers")
check("a title given as $l10n_ text is looked up", types.Timber == "category_trailers")
check("no category: the vehicle type name", types["Fake bucket"] == "wheelLoaderTool")
frame:applySorting(V.COLUMN)
check("sorted by type (ascending, case-insensitive): category_trailers, Rollers, Tractors, wheelLoaderTool", frame.vehicles[1].columns[1].text == "Timber" and frame.vehicles[2].columns[1].text == "Rotocare" and frame.vehicles[3].columns[1].text == "Zetor")
frame:applySorting(V.COLUMN)
check("sorted again: descending", frame.vehicles[1].columns[V.COLUMN].text == "wheelLoaderTool")
-- a row is filled: the licence plate cell shows the type, for a row made before the setup too
local rowCell = template:clone(nil, false, true)
frame:populateCellForItemInSection(frame.vehiclesList, 1, 2, rowCell)
check("the game's own populate still runs and the plate cell shows the type", frame.populatedByGame == 1 and rowCell:getDescendantByName("licensePlate").text == frame.vehicles[2].columns[V.COLUMN].text)
frame:populateCellForItemInSection(frame.vehiclesList, 1, 1, earlyRow)
check("a row the list made before the setup shows it as well (nothing depends on the template)", earlyRow:getDescendantByName("licensePlate").text == frame.vehicles[1].columns[V.COLUMN].text)
local otherList = newElement("handToolsList")
rowCell:getDescendantByName("licensePlate").text = "keep"
frame:populateCellForItemInSection(otherList, 1, 1, rowCell)
check("another list (hand tools) is left alone", rowCell:getDescendantByName("licensePlate").text == "keep")
-- a layout that is not what was expected: no column, no error, the reason in the log
local broken = setmetatable({ vehicles = {}, sortIcons = {}, subCategoryPages = { newElement("a"), newElement("b") } }, InGameMenuStatisticsFrame)
broken:onGuiSetupFinished()
check("an unexpected layout: no column, marked failed, no error", broken.rfTypeColumn == "failed")
local said = false
for _, l in ipairs(log) do if l:find("no type column") then said = true end end
check("... and the log says why", said)
broken.vehicles = { item("X", "tractor.xml") }
broken:updateView()
check("a failed frame is left alone (no column added to its items)", broken.vehicles[1].columns[V.COLUMN] == nil)
check("a vehicle that is nil: the unknown text", V.typeOf(nil) == "-")

print = realPrint
realPrint(string.format("vehicle_type_column_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
