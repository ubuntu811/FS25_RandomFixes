# A vehicle carrying another vehicle sees the cargo as an obstacle (AICollisionTriggerHandler)

**Status:** diagnosed from the game scripts and a log; a fix exists in the **RoadFollow** mod only (`RoadLead.ignoreCarried`), **not confirmed in the running game**, and not
yet part of this mod. Whether the vanilla AI helper is affected is **not verified**.
**Game version:** FS25 as installed 2026-10-29.

## Symptom (as seen with a driver-assist mod that uses the game's collision handler)

A truck carrying a loaded vehicle (a damaged contract vehicle on a transporter) was asked for **0 km/h on a clear road**; with cruise control on, it crawled at 2-7 km/h and
the assist switched on and off ("too slow") once a second. The log lines read `asked 0.0 (cruise 80, bend 80.0, ground x1.00, limit inf)`.

## Root cause

`AICollisionTriggerHandler:onVehicleCollisionDistanceCallback` decides whether a hit is the vehicle's own with
`vehicle:getRootVehicle() ~= self.rootVehicle` (and `self.collisionTriggerByVehicle[vehicle] == nil`). A vehicle that is **dynamically mounted** on another one
(`Mountable`; the carrier keeps it in `spec_dynamicMountAttacher.dynamicMountedObjects`, the cargo answers `getDynamicMountObject()`) is a vehicle of its own, so its root vehicle is
itself. A hit on it counts: `hitCounter` is raised for dynamic bodies in the `VEHICLE` collision group, `isBlocked` becomes true, and a strategy built on the handler (the one in RoadFollow does; the game's own strategies were not read for this note) sets `maxSpeed = 0` while `isBlocked`, which stops the vehicle.

## Suggested change for the game

In the callback, also treat as own anything whose `getDynamicMountObject()` chain leads to one of `self.rootVehicle.childVehicles`:

```lua
local function isCarriedBy(object, rootVehicle)
    for _ = 1, 6 do
        if object == nil or object.getDynamicMountObject == nil then return false end
        local mount = object:getDynamicMountObject()
        if mount == nil then
            local root = object:getRootVehicle()
            if root == nil or root == object then return false end
            object = root                                  -- an implement of a mounted vehicle
        elseif mount:getRootVehicle() == rootVehicle then
            return true
        else
            object = mount                                 -- mounted on something that is mounted
        end
    end
    return false
end
```

## What RoadFollow does

`RoadLead.ignoreCarried(handler)` installs a filter in front of the handler's callback: hits on carried objects are skipped (the end of the hit list is still passed on so
the handler finishes its count); `RoadLead.isCarriedBy` is the walk above. The same check keeps the assist's own rays from hitting the cargo.
Tests: `tests/road_lead_test.lua` ("cargo is not an obstacle").

## To do

Move the filter into this mod so that the AI helper benefits too (if it is affected), and confirm with a loaded transporter in the game.
