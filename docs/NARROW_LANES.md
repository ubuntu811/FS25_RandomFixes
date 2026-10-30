# Steering assist plans its lanes for the widest implement (fixed by NarrowLanes.lua)

**Status:** fixed in this mod. **Confirmed in the running game** (2026-10-29, a tractor with a front mower and a rear windrower: the steering assist lanes follow
the narrower tool) with the first version of the patch, which lived in the TaskMap mod and applied to every caller of the lane planner. The version in this mod keeps that
scope (steering assist **and** AI helper) and adds the `implementData` alignment that prevents the crash below; it has offline tests only (20 checks, a fake engine);
**the AI helper with the aligned table is not yet confirmed in the game.**
**Game version:** FS25 as installed 2026-10-29, scripts as read from the game archive.

## Symptom

A tractor with two separate implements attached (for example a mower and a windrower, or any two tools that are not one coupled combination) gets
steering assist lanes that are as wide as the **widest** tool. The narrower tool leaves gaps or has to be driven by hand; the alternative is to
drive the field twice, once per tool.

Reproduce: attach two implements of different working widths, select the steering assist (the lane key), drive onto a field. The lane spacing
shown is the wider tool's.

## Root cause

* `FieldCourseSettings.generate(rootVehicle)` loops over `rootVehicle:getAttachedAIImplements()`. For each implement it reads
  `aiMarkerWidth` (`implement.object:getAIMarkers()`, after `updateAIMarkerWidth()`), stores `data.width`, and widens an envelope:
  `implementMinX = math.min(-data.width * 0.5 + implementSideOffset, implementMinX)` and
  `implementMaxX = math.max( data.width * 0.5 + implementSideOffset, implementMaxX)`.
  After the loop `implementWidth = implementMaxX - implementMinX` and `sideOffset = implementMinX + implementWidth * 0.5`.
  The lane width is the **union envelope** of all implements.
* `AIAutomaticSteering:getAttacherToolWorkingWidth()` takes the **maximum** of `aiMarkerWidth` / `getAIWorkAreaWidth()` over
  `self.rootVehicle.childVehicles`. `AIAutomaticSteering:onUpdateTick` compares it with
  `steeringFieldCourse.fieldCourseSettings.implementWidth` (tolerance 0.05 m) to decide whether to regenerate the course.
* Callers of `FieldCourseSettings.generate`: `AIAutomaticSteering` (steering assist), `AIModeSelection` (default settings, five places) and
  `AIDriveStrategyFieldCourse` (the AI helper).

The union is the right answer for **one coupled combination** (a cultivator carrying a seeder: one pass, one width). It is the wrong answer for
independent tools that are worked separately.

## Suggested change for the game

Either of these, small:

1. **A setting** in the AI mode panel for combinations: lane width follows "widest" (today) or "narrowest".
2. **A better default:** when the implements are not coupled (no `parentAIImplement` relation between them), size the lanes by the narrowest.

Sketch (in `FieldCourseSettings.generate`, before the loop that fills `implementData`):

```lua
local widths = {}
for i, implement in ipairs(attachedAIImplements) do
    implement.object:updateAIMarkerWidth()
    local _, _, _, _, width = implement.object:getAIMarkers()
    widths[i] = width
end
-- only the implements within a few centimetres of the narrowest decide the lane width
local widthSource = narrowestOf(attachedAIImplements, widths, 0.05)
-- ... use widthSource for implementMinX / implementMaxX / implementWidth / sideOffset,
--     but keep ALL implements for toolFrontOffset / toolBackOffset / turning radius / headlands
```

and in `AIAutomaticSteering:getAttacherToolWorkingWidth` return the **minimum** (not the maximum) over the implements that have a width, so the
regeneration check compares like with like.

Note for an upstream implementation: the length / offset / turning-radius / headland computations in `generate` should keep using **all**
implements; only the width should come from the narrowest. The mod's version cannot do that cleanly (see below).

## What this mod does

`scripts/NarrowLanes.lua` wraps `FieldCourseSettings.generate`. For that one synchronous call, for every caller (the steering assist and the AI helper),
`rootVehicle.getAttachedAIImplements` returns the narrowest
implements (within 5 cm of the smallest width; implements without any width are kept as the game would treat them) and is restored afterwards, also
when the planner raises an error. `AIAutomaticSteering.getAttacherToolWorkingWidth` is replaced by the minimum.

* The **AI helper gets the narrow lanes too**; that is where it matters most: a mower with a windrower behind it would otherwise be worked in windrower-wide rows
  with one narrow strip mowed. The helper decides per implement whether to lower it from the implement's own work area, so the wide tool still works where there is
  something for it to do.
* Lowered or raised does not matter; the course is made before anything is lowered.
* Limitation of the wrapper approach: turning geometry, headland offsets and tool lengths are computed from the kept implements only.

## A crash found on the way (read this before touching `generate`)

The first version of the patch (in the TaskMap mod) applied to **every** caller of the planner. When an AI helper started on a vehicle with two implements,
`AIDriveStrategyFieldCourse:update` failed on every frame with `attempt to index nil with 'isLowered'` (7,000+ errors in a few seconds) and the game died:
the strategy indexes the planner's **second result**, `implementData`, by the vehicle's own implement list (`for i, implement in ipairs(aiImplements) do local data =
self.implementData[i]`), and a table built from a shortened list has no entry for a dropped implement.

Two lessons for anyone changing the planner, in the game or in a mod:

* `implementData[i]` is **positional**: it must have one entry for every implement the caller will iterate. The steering assist and `AIModeSelection` ignore this
  second result; the AI helper does not.
* The mod therefore puts the returned `implementData` back in the order of the full implement list (a dropped implement gets a copy of a kept entry, not lowered
  and without its `parentAIImplement` link, which the strategy walks to raise parents), so that a caller that does index it cannot fail. An earlier version of this
  mod avoided the crash by not narrowing for the AI helper at all; with the table aligned that is not needed.

## Multiplayer

The client generates the course settings and sends them to the server (`AIAutomaticSteeringRequestEvent`), so **every client needs the fix**.
`multiplayer supported="true"` in `modDesc.xml`.

## Tests

`lua5.1 tests/narrow_lanes_test.lua` (20 checks): the filter (narrowest, ties, no width, single implement), the wrapper (results passed back, restored after an error,
switched off, worker mode narrowed too), `implementData` aligned with the full list (also with an AI helper active, copies without a parent link), the minimum working width.
