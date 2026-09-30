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
	-- South of the Hall of Fame, west of the Hatchery: the red carpet where
	-- Brainrots parade past and can be bought before they reach the end.
	Parade = {
		Id = "Parade",
		Center = Vector3.new(-210, WorldLayout.GroundY, -200),
		Size = Vector3.new(140, 60, 130),
		Label = "BRAINROT PARADE",
	},
	-- North of the Market District, beside (not inside) the arena: jump pads,
	-- trampolines, an obby tower with a reward chest, and a slide.
	FunPark = {
		Id = "FunPark",
		Center = Vector3.new(210, WorldLayout.GroundY, 300),
		Size = Vector3.new(130, 90, 140),
		Label = "FUN PARK",
	},
}

-- Doorways where a MapBuilder path enters a zone through a wall that the zone
-- itself builds. Both sides read these, so the path and the gap in the wall
-- can never drift apart.
WorldLayout.Doors = {
	-- Parade -> Hatchery path enters the Hatchery hall's west wall. Centred
	-- between the hall's side pillars at Z = -215 and -195.
	HatcheryWest = { Z = -205, Width = 14 },
}

-- Points of interest out in the open ground (not zones: they own no rect).
-- Shared so the thing and the trail/sign leading to it can't drift apart.
WorldLayout.Landmarks = {
	LilyPond = Vector3.new(-220, WorldLayout.GroundY, 330),
	-- Giant golden Brainrot statues: skyline landmarks you can steer by.
	StatueWest = Vector3.new(-250, WorldLayout.GroundY, 175),
	StatueEast = Vector3.new(255, WorldLayout.GroundY, 150),
}

-- Themed wild areas in the open ground between zones (WildsZone builds
-- them). Rects, like zones, but they aren't WorldLayout.Zones: no floor, no
-- gameplay - scenery you can walk through.
WorldLayout.Wilds = {
	-- Between the Market and the Fun Park, around the Fun Park path.
	CandyLand = { Center = Vector3.new(210, WorldLayout.GroundY, 152), Size = Vector3.new(128, 1, 136) },
	-- North of the Lily Pond.
	CrystalGrove = { Center = Vector3.new(-185, WorldLayout.GroundY, 399), Size = Vector3.new(88, 1, 50) },
	-- The southern strip below the Parade, Hatchery and Lounge.
	TulipFields = { Center = Vector3.new(-15, WorldLayout.GroundY, -290), Size = Vector3.new(500, 1, 30) },
}

-- Scenery beyond the boundary: seen, never reached.
WorldLayout.Backdrops = {
	Volcano = Vector3.new(140, WorldLayout.GroundY, -480),
	Mountains = {
		{ Center = Vector3.new(-170, WorldLayout.GroundY, 600), Radius = 130, Height = 120 },
		{ Center = Vector3.new(40, WorldLayout.GroundY, 650), Radius = 150, Height = 150 },
		{ Center = Vector3.new(230, WorldLayout.GroundY, 595), Radius = 120, Height = 110 },
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

-- Which zone (if any) a world position is standing in, ignoring height.
-- Used by the client lighting controller to pick a zone "mood"; zones never
-- overlap, so the first match is the only match.
function WorldLayout.ZoneAt(position: Vector3): string?
	for zoneId, zone in WorldLayout.Zones :: { [string]: ZoneRect } do
		local halfX = zone.Size.X / 2
		local halfZ = zone.Size.Z / 2
		if math.abs(position.X - zone.Center.X) <= halfX and math.abs(position.Z - zone.Center.Z) <= halfZ then
			return zoneId
		end
	end
	return nil
end

return WorldLayout
