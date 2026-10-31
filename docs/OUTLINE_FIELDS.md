# AI worker only works the ring of a plowed outline, not the meadow inside (FieldCourseField islands)

**Status:** cause read in the game scripts; fix in this mod (`scripts/OutlineFields.lua`), 79 offline checks (fake boundaries, a fake `FieldCourseField` and fake tools); **the course part is
confirmed in the running game (2026-10-30): after plowing the outline of a field on a meadow, the AI settings preview shows up/down lanes over the whole inside, with the plowed ring as the
headland.** In the first try the helper drove over the meadow without working it: the tools' "limit to field" setting (see 3 below). Fixed in this version, **not yet confirmed**: the helper
really working the inside (the tool creating the field as it goes). Open points are listed at the end.
**Game version:** FS25 as installed 2026-10-30, scripts as read from the game archive and the decompiled `FieldCourseField`, `FieldCourseManager`, `AIDriveStrategyFieldCourse`, `AIImplement`, `Plow`, `Cultivator`.

## Symptom

Plow the outline of a new field on a meadow (a closed ring, one or two passes wide). The AI settings dialog draws the field course along the ring only, and a helper started on it
works the ring and nothing else; the meadow inside is left alone. (The steering assist's lanes are made by the same code and have the same hole.)

## Cause

* `FieldCourseField` finds the field's boundary from the ground type map, then its **islands**: ground type 0 inside the boundary (`islandDetection`, a filter "ground type > 0"). Ponds, tree groups
  and a meadow enclosed by a plowed outline all come out as islands. `finishTask` turns the island list into `field.islands`, and the course generator keeps its lanes out of them.
* Nothing in the game ever sets `FieldCourseField.ignoreIslands` (the switch that skips island detection).
* Plows and cultivators have a **"limit to field"** setting (`spec.limitToField`, **on by default**; the player toggles it with a key, `IMPLEMENT_EXTRA3`): with it on, `updatePlowArea` /
  `updateCultivatorArea` get `createField = false` and only work ground that is a field already. The helper never changes it, so on a course over a meadow it drives over the grass and leaves it.
* Even with lanes over the inside, the AI would throw them away: `AIDriveStrategyFieldCourse` keeps a segment only when some implement finds workable ground under it
  (`AIVehicleUtil.getAIAreaOfVehicle`, a `FieldCropsQuery` built from the tool's required ground types), and the plow's list (`Plow.AI_REQUIRED_GROUND_TYPES`: stubble, cultivated, grass, sown ...)
  has no "not a field yet" (ground type 0), which is what the meadow inside is. `Plow:setPlowAIRequirements` clears and rebuilds that list whenever the tool's state changes.

## Suggested change for the game

Treat the hole of a closed plowed outline as part of the field when the player may create fields: drop islands that are the inside of a ring (see the rule below), and let the field-creating
tools (plow, cultivator, disc harrow, which call their `update...Area` with `createField`) count ground type 0 as workable. A `FieldCourseSettings` option ("work the inside of an outline")
would be the clean form.

## What this mod does (only with the `createFields` permission; `OutlineFields.ENABLED = false` switches it off)

1. **Islands.** `FieldCourseField.finishTask` is wrapped (before the original): an island is dropped when it is at least `MIN_SHARE` (25%) of the field's area, **solid** (it fills at least
   `MIN_SOLIDITY` = 70% of its convex hull) **and** at least `RING_SHARE` (90%) of its **convex hull's** boundary (sampled every 5 m) lies within `OUTLINE_WIDTH` (25 m) of the field's boundary:
   the signature of the hole of a plowed outline, a ring of a pass or two. The hull is what makes a spur plowed into the hole (the helper's first try left one 38 m long) only a notch: measured on a
   220 x 100 m field, the rule on the island's own edge flipped for a spur longer than about 50 m; on the hull it does not matter how long the spur is. A pond or tree group in the middle of a
   field, a lake at an edge, a big island far from the boundary, or a C-shaped lake (a ring-like hull, half empty: solidity about 48%) is not that and stays.
   **Starting inside.** The game finds a field from the vehicle's position, and the grass inside an outline is not a field ("No field detected for preview"). `FieldCourseField:detectAtPosition` is
   wrapped: a start point that is not field ground (`FieldGroundSystem:getValueAtWorldPos`, ground type 0) looks for the nearest field ground (rings of 24 rays every 2 m up to 150 m) and the detection
   is made from there; it stands only when the original start point lies inside a hole that was dropped (otherwise it fails as before: that was some other field's ground). The course is made after detection has finished, so nothing has to be recalculated. The log
   says what was dropped (`[RandomFixes] outline field: an island of ... ha ...`).
2. **Workable ground.** Plows and cultivators get ground type 0 added to their AI requirements (in the ground type map's channels), after loading (`AIImplement:onPostLoad`) and every time the game
   adds its requirements again (the instance's `addAIGroundTypeRequirements` is wrapped), never twice, never when the tool has no requirements of its own (that would make everything workable),
   not for other implements (a sprayer is left alone), and not without the permission. The plow then creates the field as it works the inside.
3. **Field creation for the helper's job.** `FieldCourseField` is marked (`rfFilledOutline`) when an island was dropped. When the helper's course arrives
   (`AIDriveStrategyFieldCourse:onFieldCourseLoadedCallback`, `fieldCourse.courseField`) and comes from a marked field, the plows and cultivators of the helper's rig are flagged, and their
   `getPlowLimitToField` / `getCultivatorLimitToField` answer "not limited" while the helper is active. When the helper has stopped the flag is dropped and the player's own setting counts again;
   an ordinary course never switches anything. The game's own permission check (`createFields` for the tool's owner) still comes after that, so without the permission nothing is created.

## What went wrong with a part plowed field (2026-10-30), and the change

After the helper had plowed half of an outlined field, a new course (preview or a restarted job) showed lanes over the plowed half only: the rule above looked for the SHAPE of an outline hole (its hull
close to the field's boundary all round), and the hole that is left is no longer a ring: one whole side borders the plowed half. And the helper's job, restored from the savegame after a game restart,
stopped plowing: the course was loaded from XML, never went through the island filter, and so carried no `rfFilledOutline` mark: the tools were back at "limit to field".

* **The hole is judged by what is in it** (`OutlineFields.shouldFill`): at least `SMALL_HOLE_AREA` (0.25 ha; below it the small-hole rule below applies), for a bigger one solid (70% of its hull), and with at most `OBSTACLE_SHARE` (5%) of the points on a grid
  inside it (8 m apart, at most 400) having water (a plane more than 0.15 m above the terrain), a building (more than 1.5 m) or another tall static thing (more than 2.5 m: a tree, a rock), found with a
  ray from 60 m above, the same way WAILA's layer scan finds them. Up to `OBSTACLE_SHARE` it is filled as it is (a single tree is the helper's own collision business).
  Between that and `KEEP_SHARE` (60%) the hole is filled **and the lakes, forest and buildings in it are carved out as islands of their own** (`OutlineFields.fillPlan`): the flagged grid points
  are clustered (points within 2.2 grid steps are one lake / stand / yard, at most 20 clusters, the biggest first), each cluster becomes its hull plus a 4 m margin, kept inside the hole and
  wound like the island it replaces, and is turned into a game boundary (`FieldCourseBoundary.createByBoundaryLine`, as `FieldCourseField` does for its own islands). The lanes go round them and the rest is
  plowed. A hole that is mostly such things (a lake, a farmyard) stays one island as the game made it, and so does a hole whose carved islands could not be made. When the ray cannot be cast the old
  outline signature is the fallback (no carving).
* **The create-fields switch is stateless, and only for plows and cultivators** (`OutlineFields.coversNonField`): when the helper's course arrives, the course's boundary minus its islands is checked on a grid (10 m, at most 600 points) for
  ground that is not a field; if there is some (at least 3 points and 2%), the plows and cultivators create fields for this job, whether the course was made now or restored from a savegame. No flag outlives
  the job and seeders, harvesters and the like are never hooked, so a normal map field with real islands (the course keeps them) is worked exactly as before.

## Small holes (a corrected outline)

Correcting the shape of an outline while plowing it leaves narrow wedges of grass between the first line and the corrected one, and plowing round something leaves small patches: closed islands,
but no work width fits in them and the helper would have to plow round each. A hole below `SMALL_HOLE_AREA` (a quarter of a hectare) is **filled when nothing at all stands on it**, found with the same
top-down ray as for big holes but on a fine grid (`SMALL_STEP`, 2 m: a post or a trunk is found); a post, a trunk, a rock, a building or water anywhere on it keeps it an island as the game made it.
There is no minimum size or shape rule (an earlier version had one, `MIN_HOLE_AREA`, and a width rule for slivers: the contents decide, not the size). A hole too small for a single grid point cannot
be judged and is kept. Not covered: a map feature that has no collision for a ray (a flat concrete pad painted as ground type 0): it counts as bare.

## Keeping an island

Any bare meadow inside a field is filled, whatever its size (a bigger hole must also be solid; a hole of a part plowed field has no ring). `rfOutlineFields off` gives the game's own
behaviour (such an inside is then worked by hand); `SMALL_HOLE_AREA`, `OBSTACLE_SHARE`, `KEEP_SHARE` and `OBSTACLE_MARGIN` can be changed. Holes that are mostly water or buildings and smaller islands are not touched; water, forest and buildings inside a filled hole stay islands.

## Verification status

* Offline (92 checks in all, a fake engine; the carving part: a pond in a hole gives one island inside the hole wound like the original, a pond and two stands of trees give three, a lake that is most of the hole is kept, `finishTask` swaps the hole for the pond island and keeps the hole when it cannot be made). Earlier: 26 checks: area and distance helpers; a ring 8 m and 20 m wide is a hole; a pond, a 120 x 120 m patch in the middle, a lake at one edge and a big island along one side are kept; the
  `finishTask` hook (dropped before the original runs, failed detection, no permission, switched off, odd input); the tools (0 added next to the game's types, in the right channels, again after
  the game clears and re-adds, never twice, query rebuilt, sprayer left alone, cultivator included, no permission, empty list).
* **Seen in the game:** the preview over the whole inside; the helper started on the ring drove across the inside without working it (before step 3).
* **Not seen yet:** the helper working the inside after step 3. To try: plow the outline of a field on a meadow, stand on the plowed ring, open the AI settings (the preview should show lanes over the inside), start the helper
  with a plow or cultivator. Things this cannot tell from the scripts:
  * whether `FieldCropsQuery:addRequiredGroundValue(0, 0, ...)` accepts value 0 as "no field" (the code path is the same as for the other ground types);
  * whether the helper's own `createFields` permission check passes for the AI worker's farm in multiplayer (it is the same check the plow makes: `getHasPlayerPermission("createFields", ownerConnection)`);
  * a helper started on the unplowed inside finds no field at all (detection starts from the vehicle's position): start it on the ring.
