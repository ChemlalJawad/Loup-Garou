--!strict
-- Where the big pieces of the district go, shared by the builders so the
-- ground, the town and the wilds agree. Angles are radians from +Z (south)
-- toward +X (east), like Geo.Polar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)

local Layout = {}

local W = Config.World

-- Outside the wall.
Layout.Forest = { Angle = math.rad(50), Spread = math.rad(28), Inner = 370, Outer = 650 } -- south-east
Layout.Farms = { Angle = math.rad(-52), Spread = math.rad(24), Inner = 370, Outer = 610 } -- south-west
Layout.RoadHalfWidth = 9

-- Further out, places built for the grapple:
--   * the Great Forest (east): trees taller than the wall, nothing else -
--     swing from trunk to trunk for a kilometre;
--   * the Training Grounds (north, behind the hunters' post): practice
--     trees and wooden giant dummies to slash;
--   * the old castle (west), on its hill (Config.World.Castle);
--   * signal towers along the roads between them, so you can hook your way
--     across the open plains.
Layout.GreatForest = { Angle = math.rad(95), Spread = math.rad(32), Inner = 720, Outer = 1240 }
Layout.Training = { Angle = math.rad(180), Spread = math.rad(26), Inner = 340, Outer = 580 }
Layout.Castle = W.Castle

-- Roads out on the plains, as polylines (flat points; y ignored).
local function polar(degrees: number, radius: number): Vector3
	local a = math.rad(degrees)
	return Vector3.new(math.sin(a) * radius, 0, math.cos(a) * radius)
end
local castleDegrees = math.deg(W.Castle.Angle)
-- The castle's gate faces the town: a ramp climbs the hill to it, from here.
Layout.CastleRampFoot = polar(castleDegrees, W.Castle.Radius - 150)
Layout.CastleRampTop = polar(castleDegrees, W.Castle.Radius - 42)
Layout.Roads = {
	-- From the gate road west to the foot of the castle ramp.
	{ polar(0, 420), polar(-30, 560), polar(-60, 700), Layout.CastleRampFoot },
	-- From the gate road east into the Great Forest.
	{ polar(0, 470), polar(35, 560), polar(70, 680), polar(92, 800) },
	-- Round the north, behind the wall, to the Training Grounds: it skirts
	-- the outer edge of the grounds rather than cutting through them.
	{ Layout.CastleRampFoot, polar(-120, 645), polar(-152, 650), polar(180, 650), polar(152, 650), polar(128, 690), polar(105, 740) },
}

-- Landmark set pieces out on the plains (World/Landmarks), placed to help
-- find your way and to swing along:
--   * the old mill tower, a broken ruin in the far north-west;
--   * the aqueduct, a long line of tall arches striding north-east across
--     the plains (and over the north road): a swinging line;
--   * the watch-fort on the east road where it enters the Great Forest.
Layout.MillRuin = polar(228, 1060)
Layout.Aqueduct = { From = polar(134, 430), To = polar(158, 930), Height = 64 }
Layout.WatchFortRoad = 0.3 -- how far along the east road's last leg (into the Great Forest)

-- The road out of the south gate wobbles a little as it heads south.
function Layout.RoadX(z: number): number
	return 14 * math.sin(z / 90)
end

local function segmentDistance(p: Vector3, a: Vector3, b: Vector3): number
	local abX, abZ = b.X - a.X, b.Z - a.Z
	local lengthSq = abX * abX + abZ * abZ
	local t = if lengthSq > 1e-6 then math.clamp(((p.X - a.X) * abX + (p.Z - a.Z) * abZ) / lengthSq, 0, 1) else 0
	local dx, dz = p.X - (a.X + abX * t), p.Z - (a.Z + abZ * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- Flat distance from `p` to the nearest plains road (Layout.Roads).
function Layout.DistanceToPlainRoads(p: Vector3): number
	local best = math.huge
	for _, road in Layout.Roads do
		for i = 1, #road - 1 do
			best = math.min(best, segmentDistance(p, road[i], road[i + 1]))
		end
	end
	return best
end

-- Is `p` within `reach` of a plains road? Cheap enough for every voxel
-- column of the ground pass (each road leg's bounding box is checked
-- first).
type Leg = { A: Vector3, B: Vector3, MinX: number, MaxX: number, MinZ: number, MaxZ: number }
local legs: { Leg } = {}
for _, road in Layout.Roads do
	for i = 1, #road - 1 do
		local a, b = road[i], road[i + 1]
		table.insert(legs, { A = a, B = b, MinX = math.min(a.X, b.X), MaxX = math.max(a.X, b.X), MinZ = math.min(a.Z, b.Z), MaxZ = math.max(a.Z, b.Z) })
	end
end
function Layout.NearPlainRoad(p: Vector3, reach: number): boolean
	for _, leg in legs do
		if p.X > leg.MinX - reach and p.X < leg.MaxX + reach and p.Z > leg.MinZ - reach and p.Z < leg.MaxZ + reach then
			if segmentDistance(p, leg.A, leg.B) < reach then
				return true
			end
		end
	end
	return false
end

-- Flat distance from `p` to the nearest road outside the wall: the plains
-- roads and the road south from the gate (measured across it).
function Layout.DistanceToRoads(p: Vector3): number
	local best = Layout.DistanceToPlainRoads(p)
	if p.Z > W.WallRadius + W.WallThickness - 4 then
		best = math.min(best, math.abs(p.X - Layout.RoadX(p.Z)))
	end
	return best
end

-- The ring of hills round the edge of the land, as terrain balls. Built
-- from its own seed so the ground and the wilds (firs on the slopes) agree.
-- Each ball stays inside World.EdgeRadius, and neighbours sit 0.75 of a
-- radius apart so the ring has no gaps.
export type Ball = { Centre: Vector3, Radius: number, Rocky: boolean }
local function makeHills(): { Ball }
	local rng = Random.new(5150)
	local hills: { Ball } = {}
	local angle = rng:NextNumber(0, 0.1)
	local stop = angle + math.pi * 2
	while angle < stop do
		local radius = rng:NextNumber(60, 120)
		local room = math.max(15, W.EdgeRadius - W.LandRadius - radius)
		local distance = W.LandRadius + rng:NextNumber(15, room)
		local centre = Vector3.new(math.sin(angle) * distance, -radius * rng:NextNumber(0.3, 0.5), math.cos(angle) * distance)
		table.insert(hills, { Centre = centre, Radius = radius, Rocky = rng:NextNumber() < 0.2 })
		angle += radius * 0.75 / distance
	end
	return hills
end
Layout.Hills = makeHills()

-- The castle's hill, as a terrain ball (its top is flat at Castle.Top).
function Layout.CastleHill(): Ball
	local castle = W.Castle
	local centre = polar(castleDegrees, castle.Radius)
	return { Centre = Vector3.new(centre.X, castle.Top - castle.HillRadius, centre.Z), Radius = castle.HillRadius, Rocky = false }
end

-- Terrain mounds and rocks of the far wilds (the gorge, the outcrops, the
-- lake's island, the Elder Tree's mound): filled in at the end of this file.
Layout.FeatureBalls = {} :: { Ball }

-- Height of the ground at (x, z): the hills, the castle hill and the far
-- wilds' rocks (the small rolling bumps are ignored).
function Layout.GroundHeight(x: number, z: number): number
	local height = 0
	local function ball(b: Ball)
		local dx, dz = x - b.Centre.X, z - b.Centre.Z
		local d2 = dx * dx + dz * dz
		if d2 < b.Radius * b.Radius then
			height = math.max(height, b.Centre.Y + math.sqrt(b.Radius * b.Radius - d2))
		end
	end
	for _, hill in Layout.Hills do
		ball(hill)
	end
	ball(Layout.CastleHill())
	for _, feature in Layout.FeatureBalls do
		ball(feature)
	end
	return height
end

-- Inside the wall: reserved sites (in polar terms) that the row houses
-- leave free. The town's tall landmarks are spread round the compass so
-- there is always a perch in reach: the church (north), the clock tower
-- (west, before the market), the granary (east, behind the headquarters)
-- and the river light and the water mill on the river's banks.
export type Site = { Angle: number, Spread: number, Inner: number, Outer: number }
Layout.Sites = {
	Church = { Angle = math.rad(180), Spread = math.rad(17), Inner = 64, Outer = 113 },
	Depot = { Angle = math.rad(90), Spread = math.rad(19), Inner = 64, Outer = 113 },
	Market = { Angle = math.rad(270), Spread = math.rad(14), Inner = 127, Outer = 193 },
	GateSquare = { Angle = 0, Spread = math.rad(24), Inner = 206, Outer = 300 },
	Garden = { Angle = math.rad(135), Spread = math.rad(9), Inner = 127, Outer = 193 },
	ClockTower = { Angle = math.rad(270), Spread = math.rad(9), Inner = 64, Outer = 113 },
	RiverLight = { Angle = math.rad(207), Spread = math.rad(10), Inner = 140, Outer = 193 },
	WaterMill = { Angle = math.rad(152), Spread = math.rad(8), Inner = 140, Outer = 193 },
	Granary = { Angle = math.rad(90), Spread = math.rad(6), Inner = 206, Outer = 271 },
} :: { [string]: Site }

local function inSector(angle: number, radius: number, sector: Site): boolean
	local delta = (angle - sector.Angle + math.pi) % (2 * math.pi) - math.pi
	return math.abs(delta) <= sector.Spread and radius >= sector.Inner and radius <= sector.Outer
end
Layout.InSector = inSector

-- A polar sector test for points (used for the forest and farm regions).
function Layout.InRegion(p: Vector3, region: { Angle: number, Spread: number, Inner: number, Outer: number }): boolean
	return inSector(math.atan2(p.X, p.Z), math.sqrt(p.X * p.X + p.Z * p.Z), region :: Site)
end

function Layout.InAnySite(angle: number, radius: number): boolean
	for _, site in Layout.Sites do
		if inSector(angle, radius, site) then
			return true
		end
	end
	return false
end

-- === The far wilds: the old frontier ========================================
-- Beyond the roads, the land the first settlers held before the Great Wall
-- went up (World/Frontier builds it; World/Ground digs and raises its
-- terrain):
--   * the old outer wall, a broken ring at the foot of the hills, past where
--     giants walk (Geo.LAND_LIMIT), with a ruined gatehouse on the south road;
--   * Needle Rock Gorge (south-south-west, beyond the farms): two rock
--     ridges round a ravine with rope bridges, and tall stone spires;
--   * Misty Lake (south-south-east, beyond the forest), with an island
--     tower, a pier, reeds and drifting mist;
--   * the Elder Tree (north, beyond the north road), the tallest thing in
--     the land;
--   * a few ponds, rocky outcrops and flower meadows on the open plains.
-- Giants never roam here (their roam zones and spawns are elsewhere) and
-- walk through terrain anyway, so none of it can trap one.

export type Circle = { Centre: Vector3, Radius: number }
export type Spire = { At: Vector3, Height: number, Width: number }

Layout.OuterWall = { Radius = 1196, Thickness = 12, Height = 64 }
Layout.Gorge = { Angle = math.rad(-38), Spread = math.rad(12), Inner = 790, Outer = 1100 }
Layout.ElderTree = polar(195, 830)

local lakeCentre = polar(30, 905)
Layout.Lake = {
	Centre = lakeCentre,
	-- The water: a big round basin and three bays.
	Circles = {
		{ Centre = lakeCentre, Radius = 96 },
		{ Centre = lakeCentre + polar(80, 80), Radius = 52 },
		{ Centre = lakeCentre + polar(-40, 70), Radius = 46 },
		{ Centre = lakeCentre + polar(140, 70), Radius = 44 },
	} :: { Circle },
	Island = lakeCentre + polar(20, 18),
}
Layout.Ponds = {
	{ Centre = polar(-118, 870), Radius = 22 },
	{ Centre = polar(-150, 940), Radius = 18 },
	{ Centre = polar(12, 1010), Radius = 20 },
	{ Centre = polar(140, 1070), Radius = 18 },
} :: { Circle }

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- In the lake or a pond (or within `margin` of the water).
function Layout.InWater(p: Vector3, margin: number): boolean
	for _, circle in Layout.Lake.Circles do
		if flatDistance(p, circle.Centre) < circle.Radius + margin then
			return true
		end
	end
	for _, pond in Layout.Ponds do
		if flatDistance(p, pond.Centre) < pond.Radius + margin then
			return true
		end
	end
	return false
end

-- The gorge's axis runs straight out from the town; `lateral` is across it.
local gorgeAlong = polar(math.deg(Layout.Gorge.Angle), 1)
local gorgeAcross = Vector3.new(gorgeAlong.Z, 0, -gorgeAlong.X)
Layout.GorgeAlong, Layout.GorgeAcross = gorgeAlong, gorgeAcross
Layout.GorgeRun = { From = Layout.Gorge.Inner + 40, To = Layout.Gorge.Outer - 40 } -- where the ridges stand

-- The ridges: on each side a big low rock with a craggy top on its outer
-- shoulder, tallest halfway along, the inner faces 10-ish studs off the axis.
local function makeGorge(): ({ Ball }, { Spire })
	local rng = Random.new(6020)
	local run = Layout.GorgeRun
	local ridges: { Ball } = {}
	local d = run.From
	while d <= run.To do
		local rise = math.sin((d - run.From) / (run.To - run.From) * math.pi)
		for _, side in { -1, 1 } do
			local low = rng:NextNumber(46, 54)
			local lowTop = rng:NextNumber(30, 44)
			local at = gorgeAlong * (d + rng:NextNumber(-4, 4)) + gorgeAcross * side * (low + rng:NextNumber(7, 11))
			table.insert(ridges, { Centre = Vector3.new(at.X, lowTop - low, at.Z), Radius = low, Rocky = true })
			-- (some steps have no crag: a notch in the skyline)
			if rng:NextNumber() < 0.8 then
				local crag = rng:NextNumber(18, 30)
				local cragTop = 52 + rise * 36 + rng:NextNumber(-8, 8)
				local top = gorgeAlong * (d + rng:NextNumber(-8, 8)) + gorgeAcross * side * (low + rng:NextNumber(12, 22))
				table.insert(ridges, { Centre = Vector3.new(top.X, cragTop - crag, top.Z), Radius = crag, Rocky = true })
			end
		end
		d += rng:NextNumber(26, 36)
	end
	-- Spires stand round the ridges, clear of them and of each other.
	local spires: { Spire } = {}
	local g = Layout.Gorge
	for _ = 1, 600 do
		if #spires >= 13 then
			break
		end
		local p = polar(math.deg(g.Angle + rng:NextNumber(-g.Spread, g.Spread) * 0.92), rng:NextNumber(g.Inner + 10, g.Outer - 10))
		local width = rng:NextNumber(18, 28)
		local ok = Layout.DistanceToRoads(p) > 40 and not Geo.InRiver(p.X, p.Z, 30)
		for _, ridge in ridges do
			ok = ok and flatDistance(p, ridge.Centre) > ridge.Radius + width
		end
		for _, other in spires do
			ok = ok and flatDistance(p, other.At) > 52
		end
		if ok then
			table.insert(spires, { At = p, Height = rng:NextNumber(76, 150), Width = width })
		end
	end
	return ridges, spires
end
Layout.GorgeRidges, Layout.GorgeSpires = makeGorge()

-- On the stony floor between the ridges (`margin` widens it).
function Layout.InRavine(p: Vector3, margin: number): boolean
	local along = p.X * gorgeAlong.X + p.Z * gorgeAlong.Z
	local across = math.abs(p.X * gorgeAcross.X + p.Z * gorgeAcross.Z)
	return along > Layout.GorgeRun.From - 30 - margin and along < Layout.GorgeRun.To + 30 + margin and across < 22 + margin
end

-- Low rocky outcrops dotted over the open plains: humps of rock to land on
-- (they keep off the roads, the river, the named places and the ring where
-- giants appear).
local function openPlain(p: Vector3, margin: number): boolean
	for _, region in { Layout.Forest, Layout.Farms, Layout.GreatForest, Layout.Training, Layout.Gorge } do
		local r = math.sqrt(p.X * p.X + p.Z * p.Z)
		local off = math.abs((math.atan2(p.X, p.Z) - region.Angle + math.pi) % (2 * math.pi) - math.pi) - region.Spread
		if r > region.Inner - margin and r < region.Outer + margin and (off <= 0 or off * r < margin) then
			return false
		end
	end
	local aqueduct = Layout.Aqueduct
	return not Geo.InCastleHill(p, margin)
		and not Geo.InRiver(p.X, p.Z, margin)
		and not Layout.InWater(p, margin)
		and Layout.DistanceToRoads(p) > 30 + margin
		and segmentDistance(p, aqueduct.From, aqueduct.To) > margin
		and flatDistance(p, Layout.MillRuin) > 40 + margin
		and flatDistance(p, Layout.ElderTree) > 120 + margin
end
Layout.OpenPlain = openPlain

local function makeOutcrops(): { Ball }
	local rng = Random.new(3131)
	local rocks: { Ball } = {}
	local spots: { Vector3 } = {}
	for _ = 1, 400 do
		if #spots >= 15 then
			break
		end
		local p = polar(rng:NextNumber(0, 360), rng:NextNumber(470, Layout.OuterWall.Radius - 80))
		local r = math.sqrt(p.X * p.X + p.Z * p.Z)
		local ok = openPlain(p, 40) and math.abs(r - W.GiantSpawnRadius) > 50
		for _, other in spots do
			ok = ok and flatDistance(p, other) > 140
		end
		if ok then
			table.insert(spots, p)
			local big = rng:NextNumber(16, 26)
			table.insert(rocks, { Centre = p - Vector3.new(0, big * rng:NextNumber(0.35, 0.55), 0), Radius = big, Rocky = true })
			local turn = rng:NextNumber(0, 360)
			local small = big * rng:NextNumber(0.45, 0.7)
			local beside = p + polar(turn, big * 0.8)
			table.insert(rocks, { Centre = beside - Vector3.new(0, small * 0.45, 0), Radius = small, Rocky = true })
		end
	end
	return rocks
end
Layout.Outcrops = makeOutcrops()

-- The feet of the spires, the island and the Elder Tree's mound.
Layout.SpireFeet = {} :: { Ball }
for _, spire in Layout.GorgeSpires do
	table.insert(Layout.SpireFeet, { Centre = spire.At - Vector3.new(0, spire.Width * 0.5, 0), Radius = spire.Width * 0.9, Rocky = true })
end
Layout.IslandBall = { Centre = Layout.Lake.Island - Vector3.new(0, 16, 0), Radius = 30, Rocky = false } :: Ball
Layout.ElderMound = { Centre = Layout.ElderTree - Vector3.new(0, 46, 0), Radius = 56, Rocky = false } :: Ball
for _, list in { Layout.GorgeRidges, Layout.Outcrops, Layout.SpireFeet, { Layout.IslandBall, Layout.ElderMound } } do
	for _, b in list do
		table.insert(Layout.FeatureBalls, b)
	end
end

-- (Everything of the gorge's lies within this of its middle.)
local gorgeMiddle = gorgeAlong * ((Layout.Gorge.Inner + Layout.Gorge.Outer) / 2)
local gorgeReach = (Layout.Gorge.Outer - Layout.Gorge.Inner) / 2 + Layout.Gorge.Outer * math.sin(Layout.Gorge.Spread) + 40

-- Taken by the far wilds' set pieces (with `margin`): the outer wall's
-- ring (and the blocks fallen from it), the water, the gorge's rocks and
-- ravine, the outcrops and the foot of the Elder Tree. Nothing else is
-- built here.
function Layout.Reserved(p: Vector3, margin: number): boolean
	local r = math.sqrt(p.X * p.X + p.Z * p.Z)
	local wall = Layout.OuterWall
	if math.abs(r - wall.Radius) < wall.Thickness / 2 + 28 + margin then
		return true
	end
	if Layout.InWater(p, margin) or Layout.InRavine(p, margin) or flatDistance(p, Layout.ElderTree) < 44 + margin then
		return true
	end
	local function inRocks(rocks: { Ball }): boolean
		for _, rock in rocks do
			if flatDistance(p, rock.Centre) < rock.Radius + margin then
				return true
			end
		end
		return false
	end
	if flatDistance(p, gorgeMiddle) < gorgeReach + margin and (inRocks(Layout.GorgeRidges) or inRocks(Layout.SpireFeet)) then
		return true
	end
	return inRocks(Layout.Outcrops)
end

-- Flower meadows: where this is high the plains grow leafy grass (World/
-- Ground) and wildflowers (World/Frontier).
function Layout.Meadow(x: number, z: number): number
	return math.noise(x / 70, z / 70, 3.7)
end

return Layout
