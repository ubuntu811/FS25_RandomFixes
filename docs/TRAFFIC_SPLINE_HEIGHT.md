# Traffic cars keep the old height after the road is terraformed (investigation)

**Status:** **hypothesis, not confirmed.** Nothing is fixed yet. The tool to find out is the **FS25_TrafficLab** mod (console commands, changes only in memory).
**Game version:** FS25 as installed 2026-10-29.

## Symptom

After terraforming a road, ambient traffic cars keep driving at the old height: floating above the new surface, or sunk into it.

## What the game scripts show

* The traffic system is engine-native (`createTrafficSystem`). Its cars follow **splines** that are children of `trafficSystem.rootNodeId`.
* `TrafficSystem:validateSplines` (console `gsTrafficSystemValidate`) raycasts from 5 m above each spline point onto `TERRAIN + ROAD` collision and warns when the
  spline is more than 0.45 m off. It is a **development-time check**; nothing at run time keeps the splines on the ground.
* `gsTrafficSystemReload` (single player only) deletes the traffic system and creates it again from the same root node.
* The AI helper's navigation has its **own** road splines (`aiSystem:getRoadSplines()`), a separate list.
* Engine functions: `getSplineCV` / `getSplineEP` return **world** coordinates, `setSplineCV` / `setSplineEP` take the spline's **local** space (an easy trap),
  `getTimeAtSplineCV`, `getSplinePosition(spline, t)`, `createSplineFromEditPoints(parent, coords, linear, closed)`.

## Hypothesis

The cars read their height from the spline's control vertices, baked when the traffic system is created; terraforming never touches them.

## What is not known (what TrafficLab is for)

1. Is a changed control vertex (`setSplineCV`) seen by the cars straight away, only after a reload, or not at all?
2. Do control vertices or edit points have to be edited (a cubic spline has fewer edit points than control vertices)?
3. Does `getSplinePosition` (the evaluated spline) change with them?

## Suggested change for the game (if the hypothesis holds)

Either re-snap the affected spline points to the ground when terrain is modified near them (the terrain deformation event knows the area), or let traffic vehicles
use the same downward raycast `validateSplines` already uses, or expose an API to refresh the spline heights.

## How to test

See `FS25_TrafficLab/README` / the header of `FS25_TrafficLab/scripts/TrafficLab.lua`: `tlInfo`, `tlSnap <radius> apply`, `tlProbe`, `tlSnapEP`, `tlReload`, `tlRestore`.
