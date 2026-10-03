--!strict
-- Where the big pieces of the district go, shared by the builders so the
-- ground, the town and the wilds agree. Angles are radians from +Z (south)
-- toward +X (east), like Geo.Polar.

local Layout = {}

-- Outside the wall.
Layout.Forest = { Angle = math.rad(50), Spread = math.rad(28), Inner = 370, Outer = 650 } -- south-east
Layout.Farms = { Angle = math.rad(-52), Spread = math.rad(24), Inner = 370, Outer = 610 } -- south-west
Layout.RoadHalfWidth = 9

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
