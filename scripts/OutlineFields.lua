--[[
    OutlineFields.lua -- plow the OUTLINE of a new field (a closed ring) on a meadow and the AI worker (and the steering assist's lanes) only work that ring: the untouched meadow
    inside is an "island" of the field, a hole, and the field course leaves islands out. Details and the suggested game fix: docs/OUTLINE_FIELDS.md.

    The game: FieldCourseField detects the field from the ground type map and then its islands (ground type 0 inside the boundary: ponds, tree groups ... and the meadow inside a plowed
    outline); finishTask turns the island list into field.islands, which the course generator keeps its lanes out of. And the plow's AI only counts ground types it can work as workable
    (setPlowAIRequirements: stubble, cultivated, grass ... not "no field"), so even a course over the inside would be thrown away as "nothing to work here".

    Here, when the player may create fields ("createFields" permission, the game's own switch for it):
      1. an island that is the hole of a plowed outline is dropped before the course is made: it is big (a quarter of the field or more), SOLID (it fills most of its convex hull: a
         notch such as a spur plowed into it does not matter, a C-shaped lake is not a hole) and its hull lies within OUTLINE_WIDTH of the field's boundary all the way round (a ring of a
         pass or two); a pond or a tree group in the middle of a field, or at one edge, is not such an island and stays;
         That is for a fresh outline. A field that is already part plowed (the hole left is not a ring any more: one side borders plowed ground) is judged by what is IN the hole instead:
         judged by what a top-down ray finds on a grid inside it (as WAILA's layer scan does it): water, buildings, trees. A small hole (below SMALL_HOLE_AREA: what is left of plowing round
         something) is filled when nothing at all is on it (a fine grid); a bigger one must also be solid. Bare meadow is filled; the
         water, forest and buildings INSIDE a hole become islands of their own (carved out, with a margin), so the lanes go round them and the rest is plowed; a hole that is mostly
         such things (a lake, a farmyard) stays one island. (If the ray cannot be cast, only the outline signature counts.)
         and a helper (or the assist's preview) started ON THE GRASS INSIDE the outline, where the game finds no field at all, detects from the nearest field ground instead and is
         accepted only when the vehicle really is inside a hole that was dropped;
      2. the plow, cultivator and disc harrow count ground type 0 (not a field yet) as workable for the AI as well, because the plow creates the field as it works (createField),
         again only with the permission, and kept when the game rebuilds its requirements;
      3. and for the helper's job on such a course those tools are set to CREATE fields: every plow and cultivator has a "limit to field" setting (on by default; the player toggles it with
         a key) and with it on they work existing field ground only, so the helper would drive over the meadow and leave it alone. It is switched off for that job only: the tool goes back to
         the player's own setting when the helper has stopped.
]]
OutlineFields = {}
OutlineFields.ENABLED = true
OutlineFields.OUTLINE_WIDTH = 25.0          -- metres: the hole lies this close to the field's boundary (the plowed ring is at most this wide)
OutlineFields.MIN_SHARE = 0.25              -- ... and is at least this share of the field's area
OutlineFields.RING_SHARE = 0.9              -- ... and this share of its convex hull's boundary is within OUTLINE_WIDTH of the field's boundary
OutlineFields.MIN_SOLIDITY = 0.7            -- ... and it fills at least this share of its convex hull (a spur plowed into it, or several, are notches; a C-shaped lake is not a hole)
OutlineFields.SMALL_STEP = 2.0              -- metres: the grid for a small hole (below SMALL_HOLE_AREA): fine enough to find a post or a trunk
OutlineFields.SMALL_HOLE_AREA = 2500.0      -- square metres (a quarter of a hectare): a hole below this is judged on the fine grid (SMALL_STEP) and filled only when nothing at all stands on it
OutlineFields.OBSTACLE_STEP = 8.0           -- metres between the points inside a hole that are checked for water, buildings and trees ...
OutlineFields.OBSTACLE_MAX_SAMPLES = 400    -- ... (the step grows for a big hole so that there are at most this many)
OutlineFields.OBSTACLE_SHARE = 0.05         -- a hole with at most this share of such points is plain meadow: filled as it is (a stray tree is the helper's own business)
OutlineFields.KEEP_SHARE = 0.6              -- a hole with more than this share is mostly water, forest or buildings: it stays an island as the game made it
OutlineFields.LINK_STEPS = 2.2              -- points with something on them that are this many grid steps apart or less are one lake / forest / yard
OutlineFields.OBSTACLE_MARGIN = 4.0         -- metres: the carved island is the cluster plus this much all round (the vehicle has to turn beside it)
OutlineFields.MAX_OBSTACLE_ISLANDS = 20     -- at most this many carved islands (the game syncs 31 in all), the biggest first
OutlineFields.RAY_ABOVE = 60                -- the ray starts this far above the terrain (as WAILA's layer scan)
OutlineFields.WATER_DEPTH = 0.15            -- a water plane this far above the terrain is water
OutlineFields.BUILDING_HEIGHT = 1.5
OutlineFields.STATIC_HEIGHT = 2.5
OutlineFields.SEARCH_STEP = 2.0             -- metres: a start point that is not a field looks for field ground round it in rings this far apart ...
OutlineFields.SEARCH_MAX = 150.0            -- ... up to this far
OutlineFields.SEARCH_RAYS = 24
OutlineFields.SAMPLE_STEP = 5.0             -- metres between the points of the island's boundary that are checked

local function say(format, ...)
    print(string.format("[RandomFixes] " .. format, ...))
end

-- area of a polygon given as { {x, z} ... } (open or closed)
function OutlineFields.polygonArea(line)
    local sum, n = 0, #line
    for i = 1, n do
        local a, b = line[i], line[i % n + 1]
        sum = sum + (a[1] * b[2] - b[1] * a[2])
    end
    return math.abs(sum) / 2
end

local function distanceToSegment(px, pz, a, b)
    local sx, sz = b[1] - a[1], b[2] - a[2]
    local lengthSq = sx * sx + sz * sz
    local t = 0
    if lengthSq > 1e-9 then
        t = math.max(0, math.min(1, ((px - a[1]) * sx + (pz - a[2]) * sz) / lengthSq))
    end
    local dx, dz = px - (a[1] + sx * t), pz - (a[2] + sz * t)
    return math.sqrt(dx * dx + dz * dz)
end

function OutlineFields.distanceToLine(px, pz, line)
    local best, n = math.huge, #line
    for i = 1, n do
        best = math.min(best, distanceToSegment(px, pz, line[i], line[i % n + 1]))
    end
    return best
end

-- the convex hull of a polygon's points (Andrew's monotone chain), as a closed-less list
function OutlineFields.convexHull(points)
    local sorted = {}
    for _, p in ipairs(points) do
        sorted[#sorted + 1] = { p[1], p[2] }
    end
    table.sort(sorted, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    if #sorted < 3 then
        return sorted
    end
    local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
    local lower = {}
    for _, p in ipairs(sorted) do
        while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do table.remove(lower) end
        lower[#lower + 1] = p
    end
    local upper = {}
    for i = #sorted, 1, -1 do
        local p = sorted[i]
        while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do table.remove(upper) end
        upper[#upper + 1] = p
    end
    table.remove(lower)
    table.remove(upper)
    for _, p in ipairs(upper) do lower[#lower + 1] = p end
    return lower
end

function OutlineFields.pointInPolygon(px, pz, line)
    local inside, n = false, #line
    local j = n
    for i = 1, n do
        local a, b = line[i], line[j]
        if (a[2] > pz) ~= (b[2] > pz) and px < (b[1] - a[1]) * (pz - a[2]) / (b[2] - a[2]) + a[1] then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- Is `island` (a boundary line) the hole of a plowed outline of the field with boundary `outer`? Big, solid (a spur plowed into it is only a notch), and its hull close to the outer
-- boundary all the way round.
function OutlineFields.isOutlineHole(outer, island)
    if outer == nil or island == nil or #outer < 3 or #island < 3 then
        return false
    end
    local outerArea = OutlineFields.polygonArea(outer)
    local islandArea = OutlineFields.polygonArea(island)
    if outerArea <= 0 or islandArea < OutlineFields.MIN_SHARE * outerArea then
        return false
    end
    local hull = OutlineFields.convexHull(island)
    local hullArea = OutlineFields.polygonArea(hull)
    if #hull < 3 or hullArea <= 0 or islandArea / hullArea < OutlineFields.MIN_SOLIDITY then
        return false
    end
    local near, total, n = 0, 0, #hull
    for i = 1, n do
        local a, b = hull[i], hull[i % n + 1]
        local length = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        local steps = math.max(1, math.ceil(length / OutlineFields.SAMPLE_STEP))
        for k = 0, steps - 1 do
            local f = k / steps
            total = total + 1
            if OutlineFields.distanceToLine(a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, outer) <= OutlineFields.OUTLINE_WIDTH then
                near = near + 1
            end
        end
    end
    return total > 0 and near / total >= OutlineFields.RING_SHARE
end

-- ===== what is in a hole =====
-- Is there water, a building or another tall static thing (a tree, a rock) at (x, z)? A ray from above, as WAILA's layer scan does it. nil when the ray cannot be cast here.
local rayTarget = {}
function rayTarget:onRay(hitObjectId, x, y)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.node, self.y = hitObjectId, y
    end
    return false
end

function OutlineFields.obstacleAt(x, z)
    if raycastClosest == nil or CollisionFlag == nil or getTerrainHeightAtWorldPos == nil or bit32 == nil or CollisionFlag.getHasGroupFlagSet == nil then
        return nil
    end
    local ok, result = pcall(function()
        local terrainY = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
        rayTarget.node, rayTarget.y = nil, nil
        local mask = bit32.bor(bit32.bor(CollisionFlag.BUILDING, CollisionFlag.STATIC_OBJECT), CollisionFlag.WATER)
        raycastClosest(x, terrainY + OutlineFields.RAY_ABOVE, z, 0, -1, 0, OutlineFields.RAY_ABOVE + 5, "onRay", rayTarget, mask)
        if rayTarget.node == nil then
            return false
        end
        local height = rayTarget.y - terrainY
        if CollisionFlag.getHasGroupFlagSet(rayTarget.node, CollisionFlag.WATER) then
            return height > OutlineFields.WATER_DEPTH
        elseif CollisionFlag.getHasGroupFlagSet(rayTarget.node, CollisionFlag.BUILDING) then
            return height > OutlineFields.BUILDING_HEIGHT
        end
        return height > OutlineFields.STATIC_HEIGHT
    end)
    if not ok then
        return nil
    end
    return result
end

-- Points on a grid inside a polygon (at most `maxSamples`, the step grows for a big polygon)
function OutlineFields.samplesInside(line, step, maxSamples, exclude)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(line) do
        minX, minZ, maxX, maxZ = math.min(minX, p[1]), math.min(minZ, p[2]), math.max(maxX, p[1]), math.max(maxZ, p[2])
    end
    local area = OutlineFields.polygonArea(line)
    step = math.max(step, math.sqrt(math.max(area, 1) / maxSamples))
    local points = {}
    local z = minZ + step / 2
    while z < maxZ do
        local x = minX + step / 2
        while x < maxX do
            if OutlineFields.pointInPolygon(x, z, line) then
                local excluded = false
                for _, other in ipairs(exclude or {}) do
                    if OutlineFields.pointInPolygon(x, z, other) then
                        excluded = true
                        break
                    end
                end
                if not excluded then
                    points[#points + 1] = { x, z }
                end
            end
            x = x + step
        end
        z = z + step
    end
    return points, step
end

-- The share of points inside the island that have water, a building or something tall on them, and those points; nil when that cannot be told.
function OutlineFields.scanObstacles(island, obstacleFn, gridStep)
    obstacleFn = obstacleFn or OutlineFields.obstacleAt
    local points, step = OutlineFields.samplesInside(island, gridStep or OutlineFields.OBSTACLE_STEP, OutlineFields.OBSTACLE_MAX_SAMPLES)
    if #points == 0 then
        return nil
    end
    local flagged = {}
    for _, p in ipairs(points) do
        local obstacle = obstacleFn(p[1], p[2])
        if obstacle == nil then
            return nil
        end
        if obstacle then
            flagged[#flagged + 1] = p
        end
    end
    return #flagged / #points, flagged, step
end

function OutlineFields.obstacleShare(island)
    local share = OutlineFields.scanObstacles(island)
    return share
end

-- Points that lie close together (within LINK_STEPS grid steps) are one cluster: a lake, a stand of trees, a yard. Returns the clusters, the biggest first.
function OutlineFields.clusterPoints(points, step)
    local link2 = (OutlineFields.LINK_STEPS * step) ^ 2
    local seen, clusters = {}, {}
    for i = 1, #points do
        if not seen[i] then
            local cluster, queue = {}, { i }
            seen[i] = true
            while #queue > 0 do
                local index = table.remove(queue)
                cluster[#cluster + 1] = points[index]
                for j = 1, #points do
                    if not seen[j] and (points[j][1] - points[index][1]) ^ 2 + (points[j][2] - points[index][2]) ^ 2 <= link2 then
                        seen[j] = true
                        queue[#queue + 1] = j
                    end
                end
            end
            clusters[#clusters + 1] = cluster
        end
    end
    table.sort(clusters, function(a, b) return #a > #b end)
    return clusters
end

function OutlineFields.signedArea(line)
    local sum, n = 0, #line
    for i = 1, n do
        local a, b = line[i], line[i % n + 1]
        sum = sum + (a[1] * b[2] - b[1] * a[2])
    end
    return sum / 2
end

-- The polygon of a cluster: its points plus a margin all round (the hull of squares round them), kept inside `island` (a vertex that falls outside is pulled towards the cluster's
-- middle), wound the way `sign` says (the sign of the signed area of the hole it is carved out of).
function OutlineFields.clusterPolygon(cluster, step, island, sign)
    local half = step / 2 + OutlineFields.OBSTACLE_MARGIN
    local corners, cx, cz = {}, 0, 0
    for _, p in ipairs(cluster) do
        cx, cz = cx + p[1], cz + p[2]
        corners[#corners + 1] = { p[1] - half, p[2] - half }
        corners[#corners + 1] = { p[1] + half, p[2] - half }
        corners[#corners + 1] = { p[1] + half, p[2] + half }
        corners[#corners + 1] = { p[1] - half, p[2] + half }
    end
    cx, cz = cx / #cluster, cz / #cluster
    local hull = OutlineFields.convexHull(corners)
    for _, v in ipairs(hull) do
        local tries = 0
        while not OutlineFields.pointInPolygon(v[1], v[2], island) and tries < 40 do
            local dx, dz = cx - v[1], cz - v[2]
            local length = math.sqrt(dx * dx + dz * dz)
            if length < 1 then
                break
            end
            v[1], v[2] = v[1] + dx / length, v[2] + dz / length
            tries = tries + 1
        end
    end
    if #hull < 3 then
        return nil
    end
    local line = {}
    for _, v in ipairs(hull) do
        line[#line + 1] = { v[1], v[2] }
    end
    if (OutlineFields.signedArea(line) >= 0) ~= (sign >= 0) then
        local reversed = {}
        for i = #line, 1, -1 do
            reversed[#reversed + 1] = line[i]
        end
        line = reversed
    end
    return line
end

-- What to do with a hole: nil = leave it as the game made it; { obstacles = { polygon ... }, share } = fill it, and keep these islands inside it.
function OutlineFields.fillPlan(outer, island)
    if island == nil or #island < 3 then
        return nil
    end
    local area = OutlineFields.polygonArea(island)
    if area < OutlineFields.SMALL_HOLE_AREA then
        -- small: what is left of plowing round something (a corrected line's wedge, a skipped patch) is far more likely than a feature of the map, so it is filled; a post, a trunk,
        -- a rock or water anywhere on it (found on the fine grid) keeps it an island as the game made it. A hole too small for a single grid point cannot be judged: kept.
        local smallShare = OutlineFields.scanObstacles(island, nil, OutlineFields.SMALL_STEP)
        if smallShare == nil or smallShare > 0 then
            return nil
        end
        return { obstacles = {}, share = 0, small = true }
    end
    local hullArea = OutlineFields.polygonArea(OutlineFields.convexHull(island))
    if hullArea <= 0 or area / hullArea < OutlineFields.MIN_SOLIDITY then
        return nil
    end
    local share, flagged, step = OutlineFields.scanObstacles(island)
    if share == nil then
        -- the ray cannot be cast: only the signature of a plowed outline counts, and nothing is carved out
        if OutlineFields.isOutlineHole(outer, island) then
            return { obstacles = {}, share = 0 }
        end
        return nil
    end
    if share > OutlineFields.KEEP_SHARE then
        return nil
    end
    local polygons = {}
    if share > OutlineFields.OBSTACLE_SHARE then
        local sign = OutlineFields.signedArea(island)
        for _, cluster in ipairs(OutlineFields.clusterPoints(flagged, step)) do
            if #polygons >= OutlineFields.MAX_OBSTACLE_ISLANDS then
                break
            end
            local polygon = OutlineFields.clusterPolygon(cluster, step, island, sign)
            if polygon ~= nil then
                polygons[#polygons + 1] = polygon
            end
        end
    end
    return { obstacles = polygons, share = share }
end

function OutlineFields.shouldFill(outer, island)
    return OutlineFields.fillPlan(outer, island) ~= nil
end

-- An island boundary object of the game's own kind (FieldCourseBoundary) from a polygon, made the way FieldCourseField makes the islands it detects. nil when that fails.
function OutlineFields.makeIslandBoundary(field, line)
    if FieldCourseBoundary == nil or FieldCourseBoundary.createByBoundaryLine == nil then
        return nil
    end
    local ok, boundary = pcall(function()
        local made = FieldCourseBoundary.createByBoundaryLine(line, field.segmentSplitAngle)
        if made == nil then
            return nil
        end
        if made.extend ~= nil then
            made = made:extend(-0.25) or made
        end
        local boundaryLine = made.boundaryLine
        if g_fieldCourseManager ~= nil and g_fieldCourseManager.roundToTerrainDetailPixel ~= nil then
            for i = 1, #boundaryLine do
                boundaryLine[i][1], boundaryLine[i][2] = g_fieldCourseManager:roundToTerrainDetailPixel(boundaryLine[i][1], boundaryLine[i][2])
            end
        end
        made:regenerateSegments()
        return made
    end)
    if ok then
        return boundary
    end
    return nil
end

-- May fields be created: the game's own permission (a player's, or a vehicle owner's connection)
function OutlineFields.allowed(connection)
    if not OutlineFields.ENABLED or g_currentMission == nil then
        return false
    end
    if g_currentMission.getHasPlayerPermission == nil then
        return false
    end
    local ok, allowed = pcall(g_currentMission.getHasPlayerPermission, g_currentMission, "createFields", connection)
    return ok and allowed == true
end

-- Is there field ground at (x, z)? (the game's ground type map; unknown: treated as a field, so nothing is interfered with)
function OutlineFields.isFieldAt(x, z)
    local system = g_currentMission ~= nil and g_currentMission.fieldGroundSystem or nil
    if system == nil or system.getValueAtWorldPos == nil or FieldDensityMap == nil or FieldDensityMap.GROUND_TYPE == nil then
        return true
    end
    local ok, value = pcall(system.getValueAtWorldPos, system, FieldDensityMap.GROUND_TYPE, x, 0, z)
    return not ok or (value or 0) > 0
end

-- The nearest field ground round (x, z): rings outward, SEARCH_RAYS directions each. nil when there is none within SEARCH_MAX.
function OutlineFields.nearestField(x, z)
    local rays = OutlineFields.SEARCH_RAYS
    for distance = OutlineFields.SEARCH_STEP, OutlineFields.SEARCH_MAX, OutlineFields.SEARCH_STEP do
        for k = 0, rays - 1 do
            local angle = 2 * math.pi * k / rays
            local px, pz = x + distance * math.cos(angle), z + distance * math.sin(angle)
            if OutlineFields.isFieldAt(px, pz) then
                return px, pz
            end
        end
    end
    return nil
end

-- before the game turns the island list into field.islands: the bare holes go (the lakes, forest and yards inside them stay islands of their own). Returns the boundary lines of the
-- islands that were dropped.
function OutlineFields.dropOutlineHoles(field, success)
    local dropped = {}
    if success ~= true or field == nil or field.islandBoundaries == nil or field.fieldRootBoundary == nil or not OutlineFields.allowed() then
        return dropped
    end
    local outer = field.fieldRootBoundary.boundaryLine
    local kept, carvedIslands = {}, {}
    for _, boundary in ipairs(field.islandBoundaries) do
        local plan = OutlineFields.fillPlan(outer, boundary.boundaryLine)
        local carved, failed = {}, false
        if plan ~= nil then
            for _, polygon in ipairs(plan.obstacles) do
                local made = OutlineFields.makeIslandBoundary(field, polygon)
                if made ~= nil then
                    carved[#carved + 1] = made
                else
                    failed = true
                end
            end
        end
        if plan == nil or (failed and plan.share > OutlineFields.OBSTACLE_SHARE) then
            kept[#kept + 1] = boundary             -- (a hole whose lakes could not be carved out is left alone: better no lanes than lanes through a lake)
        else
            dropped[#dropped + 1] = boundary.boundaryLine
            for _, made in ipairs(carved) do
                carvedIslands[#carvedIslands + 1] = made
            end
            say("outline field: an island of %.2f ha (%.0f%% of the field) is bare meadow inside the field (the inside of an outline, or what is left of it): the course covers it%s",
                OutlineFields.polygonArea(boundary.boundaryLine) / 10000, 100 * OutlineFields.polygonArea(boundary.boundaryLine) / math.max(1, OutlineFields.polygonArea(outer)),
                #carved > 0 and string.format("; %d lake / forest / building area(s) in it (%.0f%% of the hole) stay islands", #carved, 100 * plan.share) or "")
        end
    end
    if #dropped > 0 then
        for _, made in ipairs(carvedIslands) do
            kept[#kept + 1] = made
        end
        field.islandBoundaries = kept
        field.rfFilledOutline = true               -- the course made from this field covers ground that is not a field yet: the helper has to create it
    end
    return dropped
end

-- finishTask: drops the holes, and decides whether a detection that was started from INSIDE an outline stands: only when the start point really is inside a dropped hole
function OutlineFields.finish(field, success)
    local dropped = OutlineFields.dropOutlineHoles(field, success)
    if success == true and field ~= nil and field.rfInsideStart ~= nil then
        local start = field.rfInsideStart
        for _, line in ipairs(dropped) do
            if OutlineFields.pointInPolygon(start[1], start[2], line) then
                say("outline field: started from inside the outline (%.0f %.0f): the field is the plowed ring and its inside", start[1], start[2])
                return success
            end
        end
        return false                                 -- (found some other field's ground near the start point: that is not the field the vehicle is in)
    end
    return success
end

-- detectAtPosition: a start point that is not a field (the grass inside an outline) looks for the nearest field ground and detects from there
function OutlineFields.start(field, x, z)
    if not OutlineFields.allowed() or x == nil or z == nil or OutlineFields.isFieldAt(x, z) then
        return x, z
    end
    local fx, fz = OutlineFields.nearestField(x, z)
    if fx == nil then
        return x, z
    end
    if g_fieldCourseManager ~= nil and g_fieldCourseManager.roundToTerrainDetailPixel ~= nil then
        fx, fz = g_fieldCourseManager:roundToTerrainDetailPixel(fx, fz)
    end
    field.rfInsideStart = { x, z }
    return fx, fz
end

-- The tools that create fields count "no field" ground (type 0) as workable for the AI, with the permission, and whenever the game rebuilds its requirements.
function OutlineFields.addNoFieldGround(vehicle)
    local spec = vehicle.spec_aiImplement
    if spec == nil or spec.terrainDetailRequiredValueRanges == nil or spec.groundTypeFirstChannel == nil or not OutlineFields.allowed(vehicle.getOwnerConnection ~= nil and vehicle:getOwnerConnection() or nil) then
        return false
    end
    for _, range in ipairs(spec.terrainDetailRequiredValueRanges) do
        if range[1] == 0 and range[2] == 0 then
            return false
        end
    end
    -- only when the tool has ground types to work at all (a requirement list of its own that the game fills): 0 is added to it, never alone
    if #spec.terrainDetailRequiredValueRanges == 0 then
        return false
    end
    table.insert(spec.terrainDetailRequiredValueRanges, { 0, 0, spec.groundTypeFirstChannel, spec.groundTypeNumChannels })
    if vehicle.updateFieldCropsQuery ~= nil then
        vehicle:updateFieldCropsQuery()
    end
    return true
end

function OutlineFields.hookVehicle(vehicle)
    if vehicle == nil or (vehicle.spec_plow == nil and vehicle.spec_cultivator == nil) or vehicle.rfOutlineHooked then
        return
    end
    vehicle.rfOutlineHooked = true
    if vehicle.addAIGroundTypeRequirements ~= nil then
        local original = vehicle.addAIGroundTypeRequirements
        -- (the game clears the requirements and adds them again whenever the tool's state changes: 0 is added each time)
        vehicle.addAIGroundTypeRequirements = function(self, ...)
            original(self, ...)
            OutlineFields.addNoFieldGround(self)
        end
        OutlineFields.addNoFieldGround(vehicle)
    end
    -- the "limit to field" setting of the tool (on by default: it only works ground that is a field already): while the helper is on a course that fills an outline, and only then,
    -- it says "not limited". Once the helper has stopped the flag is dropped and the player's own setting counts again.
    for _, name in ipairs({ "getCultivatorLimitToField", "getPlowLimitToField" }) do
        local getter = vehicle[name]
        if getter ~= nil then
            vehicle[name] = function(self, ...)
                if self.rfCreateFields then
                    if self.getIsAIActive ~= nil and self:getIsAIActive() then
                        return false
                    end
                    self.rfCreateFields = nil
                end
                return getter(self, ...)
            end
        end
    end
end

-- Does the course of this field cover ground that is not a field yet? (the field's boundary minus its islands, checked on a grid; works for a course made now and for one restored
-- from a savegame, which never went through the island filter and carries no mark)
OutlineFields.COVER_STEP = 10.0
OutlineFields.COVER_MAX_SAMPLES = 600
OutlineFields.COVER_MIN_POINTS = 3
function OutlineFields.coversNonField(courseField)
    if courseField == nil then
        return false
    end
    local outer = courseField.fieldRootBoundary ~= nil and courseField.fieldRootBoundary.boundaryLine or courseField.boundaryPositions
    if outer == nil or #outer < 3 then
        return false
    end
    local islands = {}
    for _, island in ipairs(courseField.islands or {}) do
        if island.rootBoundary ~= nil and island.rootBoundary.boundaryLine ~= nil then
            islands[#islands + 1] = island.rootBoundary.boundaryLine
        end
    end
    local points = OutlineFields.samplesInside(outer, OutlineFields.COVER_STEP, OutlineFields.COVER_MAX_SAMPLES, islands)
    local bare = 0
    for _, p in ipairs(points) do
        if not OutlineFields.isFieldAt(p[1], p[2]) then
            bare = bare + 1
        end
    end
    return bare >= OutlineFields.COVER_MIN_POINTS and bare >= 0.02 * #points
end

-- The helper's course has arrived (AIDriveStrategyFieldCourse:onFieldCourseLoadedCallback): when it comes from a field whose outline was filled, the plows and cultivators of the helper's
-- rig create fields for this job.
function OutlineFields.onCourseLoaded(strategy, fieldCourse)
    if fieldCourse == nil or strategy == nil or strategy.vehicle == nil or not OutlineFields.ENABLED then
        return 0
    end
    local course = fieldCourse.fieldCourse or fieldCourse             -- (an AIFieldCourse wraps the FieldCourse)
    local field = course.courseField
    if field == nil or strategy.vehicle.getAttachedAIImplements == nil then
        return 0
    end
    if field.rfFilledOutline ~= true and not OutlineFields.coversNonField(field) then
        return 0
    end
    local count = 0
    for _, implement in ipairs(strategy.vehicle:getAttachedAIImplements() or {}) do
        local tool = implement.object
        if tool ~= nil and tool.rfOutlineHooked and OutlineFields.allowed(tool.getOwnerConnection ~= nil and tool:getOwnerConnection() or nil) then
            tool.rfCreateFields = true
            count = count + 1
        end
    end
    if count > 0 then
        say("outline field: the helper's course covers ground that is not a field yet: %d tool(s) create the field as they work", count)
    end
    return count
end

-- Console: rfOutlineFields [on|off]: whether the inside of a plowed outline is part of the field for the AI. (A frame of plowed ground with a meadow deliberately left in the middle
-- looks exactly like an outline; with the switch off the game's own islands are used and that inside is driven by hand.)
function OutlineFields.consoleToggle(_, argument)
    if argument == "on" then
        OutlineFields.ENABLED = true
    elseif argument == "off" then
        OutlineFields.ENABLED = false
    else
        OutlineFields.ENABLED = not OutlineFields.ENABLED
    end
    return "RandomFixes outline fields (the inside of a plowed outline is part of the field for the AI worker): " .. (OutlineFields.ENABLED and "ON" or "OFF (the game's own islands; applies from the next course made)")
end
if addConsoleCommand ~= nil then
    addConsoleCommand("rfOutlineFields", "Switch the AI worker filling the inside of a plowed outline on / off (on | off, or no argument to toggle)", "consoleToggle", OutlineFields)
end

-- ===== hooks (the game's classes, patched once when this file loads) =====
if FieldCourseField ~= nil and FieldCourseField.finishTask ~= nil and Utils ~= nil and not OutlineFields.hooked then
    OutlineFields.hooked = true
    FieldCourseField.finishTask = Utils.overwrittenFunction(FieldCourseField.finishTask, function(self, superFunc, success)
        local ok, result = pcall(OutlineFields.finish, self, success)
        if not ok then
            say("outline field: skipped (%s)", tostring(result))
            result = success
        end
        return superFunc(self, result)
    end)
    if FieldCourseField.detectAtPosition ~= nil then
        FieldCourseField.detectAtPosition = Utils.overwrittenFunction(FieldCourseField.detectAtPosition, function(self, superFunc, x, z, ...)
            local ok, sx, sz = pcall(OutlineFields.start, self, x, z)
            if not ok then
                sx, sz = x, z
            end
            return superFunc(self, sx, sz, ...)
        end)
    end
    if AIDriveStrategyFieldCourse ~= nil and AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback ~= nil then
        AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback = Utils.prependedFunction(AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback, function(self, fieldCourse)
            local ok, err = pcall(OutlineFields.onCourseLoaded, self, fieldCourse)
            if not ok then
                say("outline field: the helper's tools were not set to create the field (%s)", tostring(err))
            end
        end)
    end
    if AIImplement ~= nil and AIImplement.onPostLoad ~= nil then
        AIImplement.onPostLoad = Utils.appendedFunction(AIImplement.onPostLoad, function(self)
            local ok, err = pcall(OutlineFields.hookVehicle, self)
            if not ok then
                say("outline field: a vehicle was skipped (%s)", tostring(err))
            end
        end)
    end
    say("outline field: the inside of a plowed outline is part of the field for the AI worker (with the createFields permission)")
end
