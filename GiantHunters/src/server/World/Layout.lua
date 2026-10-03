--!strict
-- Where the big pieces of the district go, shared by the builders so the
-- ground, the town and the wilds agree. Angles are radians from +Z (south)
-- toward +X (east), like Geo.Polar.

local Layout = {}

-- Outside the wall.
Layout.Forest = { Angle = math.rad(50), Spread = math.rad(28), Inner = 370, Outer = 650 } -- south-east
Layout.Farms = { Angle = math.rad(-52), Spread = math.rad(24), Inner = 370, Outer = 610 } -- south-west
Layout.RoadHalfWidth = 9

-- Further out, places built for the grapple:
--   * the Great Forest (east): trees taller than the wall, nothing else -
--     swing from trunk to trunk for a kilometre;
--   * the Training Grounds (north, behind the hunters' post): practice
--     trees and wooden giant dummies to slash;
--   * the old castle (west), on its hill;
--   * signal towers along the roads between them, so you can hook your way
--     across the open plains.
Layout.GreatForest = { Angle = math.rad(95), Spread = math.rad(32), Inner = 720, Outer = 1240 }
Layout.Training = { Angle = math.rad(180), Spread = math.rad(26), Inner = 340, Outer = 580 }
Layout.Castle = { Angle = math.rad(282), Radius = 900, HillRadius = 120, Top = 50 }

-- Roads out on the plains, as polylines (flat points; y ignored).
local function polar(degrees: number, radius: number): Vector3
	local a = math.rad(degrees)
	return Vector3.new(math.sin(a) * radius, 0, math.cos(a) * radius)
end
Layout.Roads = {
	-- From the gate road west to the castle.
	{ polar(0, 420), polar(-30, 560), polar(-60, 760), polar(-78, 880) },
	-- From the gate road east into the Great Forest.
	{ polar(0, 470), polar(35, 560), polar(70, 680), polar(92, 800) },
	-- Round the north, behind the wall, to the Training Grounds.
	{ polar(-78, 880), polar(-120, 620), polar(-155, 420), polar(180, 380), polar(140, 520), polar(105, 720) },
}

-- The road out of the south gate wobbles a little as it heads south.
function Layout.RoadX(z: number): number
	return 14 * math.sin(z / 90)
end

-- Inside the wall: reserved sites (in polar terms) that the row houses
-- leave free.
export type Site = { Angle: number, Spread: number, Inner: number, Outer: number }
Layout.Sites = {
	Church = { Angle = math.rad(180), Spread = math.rad(17), Inner = 64, Outer = 113 },
	Depot = { Angle = math.rad(90), Spread = math.rad(19), Inner = 64, Outer = 113 },
	Market = { Angle = math.rad(270), Spread = math.rad(14), Inner = 127, Outer = 193 },
	GateSquare = { Angle = 0, Spread = math.rad(24), Inner = 206, Outer = 300 },
	Garden = { Angle = math.rad(135), Spread = math.rad(9), Inner = 127, Outer = 193 },
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
