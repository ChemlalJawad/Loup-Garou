--!strict
-- Spatial allocation contract for the world.
--
-- Multiple zone modules are built independently, so each one gets an exclusive
-- rectangle of the map and must keep all of its geometry inside it. Zones read
-- their own bounds from here instead of hardcoding coordinates, which is what
-- keeps two separately-authored zones from occupying the same studs.
--
-- Rules:
--  * Build only within your zone's rect (Center +/- Size/2). Decorative
--    overhangs of a stud or two are fine; a building that crosses into a
--    neighbour is not.
--  * `GroundY` is the shared walkable ground level. Your zone's floor top
--    surface should sit at GroundY so players walk between zones seamlessly.
--  * Paths between zones are owned by MapBuilder, not by any single zone.

local WorldLayout = {}

export type ZoneRect = {
	Id: string,
	Center: Vector3,
	Size: Vector3, -- X = width, Y = nominal height headroom, Z = depth
	Label: string,
}

WorldLayout.GroundY = 0

-- The full ground plate spans every zone plus path margins.
WorldLayout.GroundPlate = {
	Center = Vector3.new(0, WorldLayout.GroundY - 2, 60),
	Size = Vector3.new(620, 4, 800),
}

WorldLayout.Zones = {
	Hub = {
		Id = "Hub",
		Center = Vector3.new(0, WorldLayout.GroundY, 0),
		Size = Vector3.new(150, 80, 150),
		Label = "CENTRAL PLAZA",
	},
	Hatchery = {
		Id = "Hatchery",
		Center = Vector3.new(0, WorldLayout.GroundY, -200),
		Size = Vector3.new(150, 70, 130),
		Label = "HATCHERY",
	},
	Commercial = {
		Id = "Commercial",
		Center = Vector3.new(210, WorldLayout.GroundY, 0),
		Size = Vector3.new(140, 70, 150),
		Label = "MARKET DISTRICT",
	},
	Arena = {
		Id = "Arena",
		Center = Vector3.new(0, WorldLayout.GroundY, 300),
		Size = Vector3.new(260, 90, 320),
		Label = "CTF ARENA",
	},
	Plaza = {
		Id = "Plaza",
		Center = Vector3.new(-210, WorldLayout.GroundY, 0),
		Size = Vector3.new(140, 70, 150),
		Label = "HALL OF FAME",
	},
	Lounge = {
		Id = "Lounge",
		Center = Vector3.new(210, WorldLayout.GroundY, -200),
		Size = Vector3.new(120, 60, 120),
		Label = "VIP LOUNGE",
	},
}

function WorldLayout.Get(zoneId: string): ZoneRect
	local zone = (WorldLayout.Zones :: any)[zoneId]
	assert(zone, `WorldLayout: unknown zone "{zoneId}"`)
	return zone
end

-- Convenience: a corner-relative point inside a zone, where (0,0) is the
-- zone's min-X/min-Z corner and (1,1) is max-X/max-Z. Lets a zone module lay
-- things out proportionally without re-deriving its own edges.
function WorldLayout.PointIn(zoneId: string, fractionX: number, fractionZ: number, y: number?): Vector3
	local zone = WorldLayout.Get(zoneId)
	local minX = zone.Center.X - zone.Size.X / 2
	local minZ = zone.Center.Z - zone.Size.Z / 2
	return Vector3.new(
		minX + zone.Size.X * fractionX,
		y or zone.Center.Y,
		minZ + zone.Size.Z * fractionZ
	)
end

return WorldLayout
