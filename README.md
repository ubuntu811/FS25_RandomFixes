# RandomFixes

A collection of small base game fixes and conveniences that are too small for a mod of their own.

## Vehicles list: a Type column where the licence plate was

The menu's vehicles list (Vehicles tab) shows **what each machine is** (Tractors, Rollers, Trailers ...) in the licence plate column, taken from its shop category, so nobody has to
know every brand name to tell what a "Quicke Q4M" is. The header sorts by it like the other columns. Nothing else moves.

Done without replacing any base game file: the header gets a copy of the age header (sortable, with its arrows) in the licence plate header's place, and the licence plate
cell of each row is given the type text just after the game has filled the row. If the layout is not what it expects (a game update, another mod that rebuilds the list)
it changes nothing and the log says why (`[RandomFixes] no type column (...)`).

(An earlier version added a new column and moved the others; rows the list had already built kept the old layout and the table fell apart. Replacing the plate cell has no such
problem.)

Test: `lua5.1 tests/vehicle_type_column_test.lua` (a fake GUI, 27 checks).

## Vehicles list: it opens on the machine you are sitting in

The same list used to open on the first row of the alphabet (an AGCO mower, whatever you were driving). It now opens with **your own vehicle selected and scrolled to**. On foot,
or in something the list does not show, it stays as it was.

Test: `lua5.1 tests/select_own_vehicle_test.lua` (a fake frame, 5 checks).

## Steering assist: lanes for the narrowest implement

With two implements on one tractor (a mower and a windrower, a cultivator and a seeder) the game's steering assist plans its field lanes for the WIDEST of them: its lane
planner takes the left-most and right-most edge over every attached implement as the width, so the narrower tool leaves gaps or has to be driven by hand. This plans the
lanes for the NARROWEST attached implement instead, whether the implements are lowered or not (the field is mapped before anything starts, so there is nothing to lower
first). It applies to the AI helper as well (that is where it matters: a mower with a windrower behind it is not worked in windrower-wide rows with one narrow strip mowed). Turning geometry and
headland offsets come from the implements that are kept.

Needs the mod on every client in multiplayer (each client generates its course). `NarrowLanes.ENABLED = false` in `scripts/NarrowLanes.lua` switches it off.
Test: `lua5.1 tests/narrow_lanes_test.lua`.

## Quitting a savegame with an inline bale

Leaving a savegame that contains an inline bale (a string of bales) could fail with `invalid key to 'next'` in `NetworkNode:delete` and hang until the game was force-closed,
on some days and not on others (it depends on how many objects exist). While the session is being deleted, an inline bale no longer tries to re-link its chain. See
[docs/INLINE_BALE_SHUTDOWN.md](docs/INLINE_BALE_SHUTDOWN.md). Test: `lua5.1 tests/inline_bale_shutdown_test.lua`.

## AI helper and multi-crop harvester headers

A harvester header that has a cutter AND a fruit preparer (beet / potato headers) is only offered the crops the PREPARER lists to the AI helper: the game switches the cutter's own list
off. On a multi-crop header (peas, carrots ... next to beets) the AI helper then stops with "field not ready for this work or already worked" on those crops, while harvesting by hand
works. Once a vehicle has loaded, the crops the cutter takes and the preparer does not list are added for the AI helper (normal harvest growth states). See
[docs/PREPARER_CROPS.md](docs/PREPARER_CROPS.md). Test: `lua5.1 tests/preparer_crops_test.lua`. `PreparerCrops.ENABLED = false` switches it off.

## Minimap: a newly plowed field shows up late

The minimap's field picture is regenerated in the background by the engine, all of it, on a timer: the next generation starts 5 s after the last one finished, and nothing starts one
because the ground changed. A meadow plowed just after a generation began therefore waits for the rest of it, the 5 s, and a whole generation more. While you plow or cultivate, the
picture is now asked to start its next generation 2 s after the last one (instead of 5 s), and the time of every generation is logged once a minute, so we can see how much of the wait is
the engine's generation itself. See [docs/FIELDS_OVERLAY.md](docs/FIELDS_OVERLAY.md). Test: `lua5.1 tests/fields_overlay_test.lua`. `FieldsOverlay.ENABLED = false` switches it off.

## AI worker on the outline of a new field

Plow only the OUTLINE of a new field on a meadow (a closed ring of a pass or two) and the AI worker, and the steering assist's lanes, only worked that ring: the meadow inside is an
"island" of the field (a hole, like a pond), and the course generator keeps its lanes out of islands. With the permission to create fields, the game's own island list is now filtered
before the course is made: an island that is big (a quarter of the field or more) and lies within 25 m of the field's boundary all the way round is the inside of a plowed outline, and
goes: bare meadow of a quarter of a hectare or more, solid, with no water, buildings or trees on it (checked with rays from above, so it works on a part plowed field too, where what is left is no ring any more); ponds, farmyards and small islands stay. A helper job restored after a game restart still creates the field: the switch looks at what the course covers, not at a mark. The plow, cultivator and disc harrow also count "not a field yet" ground as workable for the AI (the plow creates the field as it
works), kept when the game rebuilds their requirements. Water, forest and buildings inside the inside become islands of their own (the lanes go round them, the rest is plowed); a hole that is mostly such things stays an island. The helper, or the AI settings preview, can be started on the plowed ring or on the grass inside it. See [docs/OUTLINE_FIELDS.md](docs/OUTLINE_FIELDS.md). Test:
`lua5.1 tests/outline_fields_test.lua`. The console command `rfOutlineFields on|off` switches it (a plowed frame with a meadow deliberately left in the middle looks exactly like an outline: with it off that inside is driven by hand).

## For the game: write-ups of what is wrong and how it could be fixed

Each fix has its own document in `docs/` with the symptom, how to reproduce it, the cause in the game's scripts (functions and the lines of reasoning), a suggested change in game terms,
what this mod does instead, and an honest verification status. They are written so that GIANTS (or another modder) can pick the fix up without this mod.

| Document | What | Status |
|---|---|---|
| [docs/NARROW_LANES.md](docs/NARROW_LANES.md) | steering assist lanes use the widest of several implements | fixed here; **confirmed in game** (first version, in TaskMap); the AI helper with the aligned `implementData` is offline-tested only |
| [docs/VEHICLE_TYPE_COLUMN.md](docs/VEHICLE_TYPE_COLUMN.md) | vehicles list does not say what a machine is | fixed here; offline tests; not yet confirmed in game |
| [docs/INLINE_BALE_SHUTDOWN.md](docs/INLINE_BALE_SHUTDOWN.md) | quitting a savegame with an inline bale fails with `invalid key to 'next'` and hangs | diagnosed from three logs; fixed here; offline tests; not yet confirmed in game |
| [docs/PREPARER_CROPS.md](docs/PREPARER_CROPS.md) | AI helper only knows the preparer's crops on a header with cutter and preparer | diagnosed from the scripts and a mod's XML; fixed here; **confirmed in game** |
| [docs/FIELDS_OVERLAY.md](docs/FIELDS_OVERLAY.md) | a newly plowed meadow shows on the minimap's field picture much later | cause read in the game scripts; mitigation here; **confirmed in game** (a generation takes about 210 ms: the wait was the 5 s timer) |
| [docs/OUTLINE_FIELDS.md](docs/OUTLINE_FIELDS.md) | AI worker only plows the ring of a field outline, not the meadow inside | cause read in the game scripts; fix here; **course confirmed in game** (lanes over the inside), the helper working it not yet |
| [docs/CARGO_COLLISION.md](docs/CARGO_COLLISION.md) | a vehicle's own cargo counts as an obstacle for the AI collision handler | diagnosed; fix lives in RoadFollow; unconfirmed |
| [docs/TRAFFIC_SPLINE_HEIGHT.md](docs/TRAFFIC_SPLINE_HEIGHT.md) | traffic cars keep the old height after terraforming | hypothesis; to be tested with FS25_TrafficLab |

Game version these were read from: FS25 as installed on 2026-10-29.
