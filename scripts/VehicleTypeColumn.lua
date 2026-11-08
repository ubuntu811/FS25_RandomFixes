--[[
    VehicleTypeColumn.lua -- the vehicles list of the menu (Vehicles tab, next to Prices, Hand tools ...) shows what each machine is
    (Tractor, Roller, Trailer ...) where the licence plate used to be, sortable like the other columns.

    The type comes from the machine's shop category, so nobody has to know every brand name. The licence plate column is replaced
    (nobody reads them); nothing else moves, so the table keeps its layout.

    How it is done (read from the game's own InGameMenuStatisticsFrame and its XML, nothing is replaced):
      * header: the age header (a sortable column, with sort arrows) is copied, given the text "Type" and our own click handler, and
        put where the licence plate header was; that one is hidden.
      * rows: the frame fills the licence plate cell of every row; just after, the same cell is given the type text. The cells already
        exist when the list is built, so nothing has to be added to them (an earlier version added a cell to the row template: rows
        the list had already made kept the old layout).
      * data: the frame keeps one item per vehicle with columns[...] = { text, value } and sorts by columns[sortByColumn].value:
        a seventh column is added to every item just before the frame sorts (updateView).
    Everything in a pcall: if the layout is not what this expects (a game update, another mod's own changes) nothing is changed and a
    line says why.
]]
VehicleTypeColumn = {}

VehicleTypeColumn.COLUMN = 7
VehicleTypeColumn.LOG_FIRST = 16                    -- rows logged (one line each) until the game restarts: what the game wrote and what we put there
VehicleTypeColumn.modName = g_currentModName

local function say(format, ...)
    print(string.format("[RandomFixes] " .. format, ...))
end

-- The category title of a vehicle's shop entry ("Tractors", "Rollers" ...), or its vehicle type name when it has none.
function VehicleTypeColumn.typeOf(vehicle)
    local unknown = g_i18n ~= nil and g_i18n:getText("rf_typeUnknown", VehicleTypeColumn.modName) or "-"
    if vehicle == nil then
        return unknown
    end
    local storeItem = g_storeManager ~= nil and vehicle.configFileName ~= nil and g_storeManager:getItemByXMLFilename(vehicle.configFileName) or nil
    if storeItem ~= nil then
        local name = storeItem.categoryNames ~= nil and storeItem.categoryNames[1] or storeItem.categoryName
        local category = name ~= nil and g_storeManager:getCategoryByName(name) or nil
        local title = category ~= nil and category.title or nil
        if type(title) == "string" and title ~= "" then
            if title:sub(1, 6) == "$l10n_" then
                title = g_i18n:getText(title:sub(7))
            end
            return title
        end
    end
    if type(vehicle.typeName) == "string" and vehicle.typeName ~= "" then
        return vehicle.typeName
    end
    return unknown
end

-- before the frame sorts: every vehicle item gets the type column
function VehicleTypeColumn.ensureColumns(frame)
    for _, item in ipairs(frame.vehicles or {}) do
        if item.columns ~= nil and item.columns[VehicleTypeColumn.COLUMN] == nil then
            local text = VehicleTypeColumn.typeOf(item.vehicle)
            item.columns[VehicleTypeColumn.COLUMN] = { text = text, value = string.lower(text) }
        end
    end
end

-- after the frame has filled a row: the licence plate cell shows the type
function VehicleTypeColumn.populate(frame, list, section, index, cell)
    if list ~= frame.vehiclesList or cell == nil or frame.vehicles == nil then
        return
    end
    local element = cell:getDescendantByName("licensePlate")
    local item = frame.vehicles[index]
    if element ~= nil and item ~= nil then
        local column = item.columns ~= nil and item.columns[VehicleTypeColumn.COLUMN] or nil
        local before = element.getText ~= nil and element:getText() or nil
        element:setText(column ~= nil and column.text or "-")
        if (VehicleTypeColumn.logged or 0) < VehicleTypeColumn.LOG_FIRST then
            VehicleTypeColumn.logged = (VehicleTypeColumn.logged or 0) + 1
            local sameElement = cell.getAttribute ~= nil and cell:getAttribute("licensePlate") == element
            say("type column row %d: shows '%s' (the game had written '%s'), the game's licensePlate element is ours: %s", index, tostring(column ~= nil and column.text or "-"), tostring(before), tostring(sameElement))
        end
    end
end

function VehicleTypeColumn.onClickSort(frame)
    frame:applySorting(VehicleTypeColumn.COLUMN)
end

local function setupHeader(frame)
    local page = frame.subCategoryPages ~= nil and frame.subCategoryPages[2] or nil
    local header = page ~= nil and page.elements ~= nil and page.elements[1] or nil
    if header == nil or header.elements == nil or #header.elements < 7 then
        error("the header of the vehicles page is not what was expected")
    end
    local plate = header.elements[2]               -- (the first child is the vehicle name button; then plate, age, hours, ...)
    local age = header.elements[3]
    if plate == nil or age == nil or age.elements == nil or age.elements[1] == nil then
        error("the licence plate / age headers are not what was expected")
    end
    -- the new header: a copy of the age one (sortable, with its sort arrows), made without its own onCreate (that would register it as "age")
    local clone = age:clone(header, false, true)
    clone:setPosition(plate.position[1], clone.position[2])
    local button = clone.elements[1]
    button:setText(g_i18n:getText("rf_columnType", VehicleTypeColumn.modName))
    button.onClickCallback = VehicleTypeColumn.onClickSort
    button.target = frame
    local ascending = button:getDescendantByName("iconAscending")
    local descending = button:getDescendantByName("iconDescending")
    if ascending ~= nil and descending ~= nil and frame.sortIcons ~= nil then
        frame.sortIcons[VehicleTypeColumn.COLUMN] = { [InGameMenuStatisticsFrame.SORT_ORDER_ASC] = ascending, [InGameMenuStatisticsFrame.SORT_ORDER_DESC] = descending }
    end
    plate:setVisible(false)
end

-- Called when the frame's GUI is set up and again when it opens (in case the header was not there the first time).
function VehicleTypeColumn.setup(frame)
    if frame.rfTypeColumn ~= nil then
        return
    end
    local ok, err = pcall(setupHeader, frame)
    if ok then
        frame.rfTypeColumn = "done"
        say("vehicles list: Type column in place of the licence plate")
    else
        frame.rfTypeColumn = "failed"
        say("no type column (%s)", tostring(err))
    end
end

-- ===== hooks (the game's frame class, patched once when this file loads) =====
if InGameMenuStatisticsFrame ~= nil and not VehicleTypeColumn.hooked then
    VehicleTypeColumn.hooked = true
    InGameMenuStatisticsFrame.onGuiSetupFinished = Utils.appendedFunction(InGameMenuStatisticsFrame.onGuiSetupFinished, function(self)
        VehicleTypeColumn.setup(self)
    end)
    InGameMenuStatisticsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuStatisticsFrame.onFrameOpen, function(self)
        VehicleTypeColumn.setup(self)
    end)
    InGameMenuStatisticsFrame.updateView = Utils.prependedFunction(InGameMenuStatisticsFrame.updateView, function(self)
        if self.rfTypeColumn ~= "failed" then
            VehicleTypeColumn.ensureColumns(self)
        end
    end)
    InGameMenuStatisticsFrame.populateCellForItemInSection = Utils.appendedFunction(InGameMenuStatisticsFrame.populateCellForItemInSection, function(self, list, section, index, cell)
        if self.rfTypeColumn == "done" then
            VehicleTypeColumn.populate(self, list, section, index, cell)
        end
    end)
end
