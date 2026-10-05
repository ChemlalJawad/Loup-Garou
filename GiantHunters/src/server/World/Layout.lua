--!strict
-- Where the big pieces of the district go, shared by the builders so the
-- ground, the town and the wilds agree. Angles are radians from +Z (south)
-- toward +X (east), like Geo.Polar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

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

-- Height of the ground at (x, z): the hills and the castle hill (the
-- small rolling bumps are ignored).
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

return Layout
