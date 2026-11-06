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

## Shop search: it also knows what a machine is

Typing "cotton" into the shop's search found three things with cotton in their name and none of the cotton harvesters, though the shop files them under **Cotton Harvesters** (the
game's search index holds only title, brand, author and DLC title, not the category). The search still runs as before; the items whose **category titles, brand and name together contain every
word typed** (any order, any case: "case cotton", "forage", "tractors") are added after the game's own results, nobody twice, and only items the shop shows (vehicles and hand tools, in the
store, unlocked: the game's own index conditions).

Put on the store manager the first time the shop's search is used (`StoreManager:search` is one line that hands over to the engine's index). If anything does not fit the game's search runs
alone and the log says why.

Test: `lua5.1 tests/smart_shop_search_test.lua` (a fake store, 16 checks).

## Construction screen: the Painting menu without the damage variants

The mod "All The Ground Textures" puts every ALL-CAPS terrain layer into the Painting menu of the construction screen. The damage variants made for Immersive Weathering
(COBBLESTONE03_CRACKED1, _MISSING2, _WORN ...) are ALL-CAPS layers too, five to seven more tiles per texture, which would bury the real ones. They are not meant to be painted by hand (a
set's "matching details" lays them), so just before the screen builds its paint brushes they are taken out of the ground type list: any layer named <another layer of the map>_<something with a
damage word> (crack, missing, worn, damage, broken, chip, pothole, hole). DIRT_ROAD or STONY_DIRT stay. It does not matter which mod added them or which loaded first; the filter runs at
the last moment, and the log says how many it left out.

One entry per texture stays: **`NAME_DAMAGED`** ("Cobblestone03 Damaged"), the mix of the intact layer and all its variants. Paint a surface with the texture, then brush the damaged one in places: some
cracks and missing stones, without choosing a variant. (The mix is made by `add_layers.py` in Immersive Weathering's tools; how the engine blends its parts, patchy by noise or not, I have not seen in the game.)

Test: `lua5.1 tests/hide_layer_variants_test.lua` (a fake ground type manager, 9 checks).

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

## Puddles stay on the ground (ReseatDecals)

The map's puddles are plain meshes at a fixed height (CreativeHorizon: ~2,330 `roadPuddlePiece` + `intersectionPuddles`); the road under them is baked into the terrain surface. Lower or raise a road and the puddles float or sink. (The map's other decals, road pieces, centre lines, parking lines, manholes, tyre tracks, are baked into the terrain too and need nothing; sign decals sit on posts and are left alone.)

On demand, nothing in the background (nobody deforms the terrain every day): a WAILA layer scan does it. WAILA calls its scan hooks when a scan starts (`Waila.registerScanHook`), with the rectangle the scan covers: the whole map for "Scan the whole map" (Shift+G), the 3 x 3 chunks around you for "Rescan around me". RandomFixes then reseats the puddles inside that rectangle. The puddles have no collision (a raycast cannot hit them), so where they are comes from one walk over the map file's own nodes (the terrain's parent, not the whole mission scene; each puddle's world bounding sphere is its position), in 8 ms slices the first time (about half a second), after that the list is kept; then every puddle's new height is worked out and set in one go (tens of milliseconds). The row "Reseat the map's puddles and guide posts on the ground" of the Terrain tab does the whole map on its own, without the layer scan (so does the console command `reseatDecals`); a WAILA with neither the scan hook nor `Waila.addDebugAction` gets a tab of its own. The row/log says what it found and moved (`[RandomFixes] puddles: ...`). The normal height of a puddle over its level is the median of all of them, so it assumes most puddles are untouched (a whole road lowered at once would be taken for normal). The water level of a puddle is the lowest ground height on its BORDER (eight samples in a ring, the ground's slope taken out; a dip or a mound at the border does not tilt the slope): a lowered or raised stretch moves the puddles with it; a pothole INSIDE the border leaves the puddle at the rim (the water fills the hole, nothing sinks underground); a dip that crosses the border lets the water down to the lowest point there, the terrain covers the part of the mesh over higher ground; fill the dip and press the button again, the level comes back up. Names matched: `ReseatDecals.PATTERNS`.

The moves are saved like MovePlaceablesAdvanced saves its moved map buildings: an own file in the savegame folder, `reseatDecals.xml`, written when the game saves. A puddle has no id (the map file's nodes sit at the origin, the vertices carry the world position), so its key is its name plus the x / z of its bounding sphere's centre; the file holds the moved ones with how far (metres, + up). At the next load they are put back a few seconds after the mission starts, only when the file has any (a savegame without edits never indexes the scene), so the button is pressed once per edit, not once per session.

### Guide posts

The roadside guide posts follow an edited road too, each at its own spot. CreativeHorizon builds them as a container group `Leitpfosten` at the world origin holding hundreds of inner `Leitpfosten` pair groups, each with a `leitpfosten_r` and a `leitpfosten_l` 4 m to its sides; the nodes that are moved are those single posts (`ReseatDecals.POST_NAMES`), and only when they have a `joint` child. The first version matched the container group instead, measured it as 100 m under the ground and moved it: every guide post on the map vanished. Hence the safeguards: never a container,  only the single posts with a `joint` child are taken, anything over 6 m off is skipped, and a post with a structure under it is left alone or follows it, like a puddle. The posts are dynamic bodies on breakable joints; `reseatPostTest [dy]` measured that moving the node moves its collision body (`coli`) with it, by the same amount, and that it stays there. Posts get no lift, their own normal offset over the ground (the median of all posts). The moves are saved and put back at load like the puddles'. Poles (`pole01/02`) and traffic signs are not in.

What is left alone, and what follows a structure:

Pieces that **rest on a structure** take the structure's surface as their level: before a piece is moved, or when it is too far off the terrain to be moved (only the few dozen that qualify, not thousands), a ray goes straight down from 30 cm above it, 70 cm long, against static objects, buildings and road colliders (`CollisionFlag` STATIC_OBJECT, BUILDING, ROAD; not the terrain). The height where it hits is the true surface height there, and the piece is set to that plus its class's normal offset (and the puddle lift): a bridge deck that did not move leaves it where it is (the difference is below the tolerance), a deck or slab that was moved (MovePlaceablesAdvanced) takes it along. A puddle has no collision of its own, so its own spot is cast; a post has (its parts are ignored), so four spots 30 cm to its sides are (the highest hit counts). A piece with nothing under it that is far off is a cut road, and moves. As a safety net anything more than 6 m off the terrain (`MAX_SHIFT_M`) with no structure under it is left alone, and moves of that size in an old `reseatDecals.xml` are ignored at load (the first real pass found puddles 8.6 m off: bridges). The log counts both kinds. A puddle that is moved gets 1.5 cm on top (`LIFT_M`) so the ground's 1 m triangles do not poke through it.

An optional extra: `ReseatDecals.POST_MAX_SHARE = 0.10` makes a pass refuse to move more than that share of all the posts (at least `POST_MAX_MIN`, 8) at once; it is off by default (once the algorithm is trusted it is not needed). If a bad pass was ever saved, delete `reseatDecals.xml` in the savegame folder: the next load starts from the map's own heights.
