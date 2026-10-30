# The vehicles list does not say what a machine is (fixed by VehicleTypeColumn.lua)

**Status:** fixed in this mod. Offline tests pass (27 checks, a fake GUI); **not yet confirmed in the running game.**
**Game version:** FS25 as installed 2026-10-29.

## Symptom

The menu's vehicles list (Prices / Vehicles / Hand tools / Finances / Statistics, the Vehicles tab) shows brand and model names only: "Quicke Q4M",
"Albutt Pallet Fork", "Volvo Fake Capacity Bucket Volvo 180". Nothing says it is a front loader, a pallet fork or a bucket. The licence plate column,
which says little, takes the space.

## Where

`InGameMenuStatisticsFrame` (`InGameMenuStatisticsFrame.xml` and the script of the same name):

* XML, page 2 (`subCategoryPages[2]`): a header with one container per column at fixed left edges (440, 620, 800, 980, 1160, 1340 px), and a
  `SmoothList id="vehiclesList"` whose `ListItem name="rowTemplate"` has one `Text` per column: `name`, `licensePlate`, `age`, `operatingHours`,
  `damage`, `leasing`, `value`.
* Lua: `updateVehicles` builds one item per vehicle with `item.columns[COLUMN_...] = { text, value }`; `updateView` sorts by
  `columns[sortByColumn].value`; `populateCellForItemInSection` fills the cells; `COLUMN_NAME..COLUMN_VALUE` are 1..6.

## Suggested change for the game

Add a `COLUMN_TYPE` (7):

```lua
local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
local category  = storeItem and g_storeManager:getCategoryByName(storeItem.categoryNames[1])
item.columns[InGameMenuStatisticsFrame.COLUMN_TYPE] = { text = category.title, value = category.title:lower() }
```

plus one more header container (sortable, with the sort arrows like the age header) and one more `Text` in `rowTemplate`. The table is already as wide as
its container: the column pitch (180 px) would need to come down to about 145 px, or the licence plate column would have to go (the mod does the latter).
The shop's own category title is localized already and is the wording players know from the shop.

## What this mod does

`scripts/VehicleTypeColumn.lua` (hooks on the frame class, nothing replaced):

* header: the age header is copied (sortable, with its arrows), given the text "Type" and its own click handler, put where the licence plate header was;
  the plate header is hidden;
* rows: after the game fills the licence plate cell of a row, that cell is given the type text;
* data: a seventh column is added to every item just before `updateView` sorts.

Everything is in a `pcall`: if the layout is not what is expected (a game update, another mod) nothing is changed and the log says why.

## A pitfall worth knowing (cost one failed version)

The first version added a new cell to the row template and moved the other columns. That fails: the `SmoothList` has **already cloned its rows** from the
template by the time the frame opens, so only rows created later had the new layout and the table fell apart. Changing the XML (the upstream way) has no such
problem; for a mod, reusing an existing cell is the robust way.

## Tests

`lua5.1 tests/vehicle_type_column_test.lua`: header copy and placement, nothing else moves, rows made before the setup also work, other lists untouched, sorting by
type, unknown layout leaves everything alone.
