--!strict
-- The footprint of every connector path MapBuilder lays down, so later
-- builders (LandscapeZone) can keep props off the walkways. MapBuilder owns
-- the paths and fills this in before any zone builds; zones only read it.
-- BiomeZone also registers its keep-out areas here (the pond, the band of
-- edge hills), so "near a path" really means "not free for a prop".
-- Deliberately a separate module: a zone requiring MapBuilder itself would
-- be a circular require, since MapBuilder is what requires the zones.

local PathRegistry = {}

export type Rect = {
	Center: Vector3,
	Size: Vector3,
}

local rects: { Rect } = {}

function PathRegistry.Clear()
	table.clear(rects)
end

function PathRegistry.Add(center: Vector3, size: Vector3)
	table.insert(rects, { Center = center, Size = size })
end

-- True when `position` (ignoring height) is within `margin` studs of any
-- registered path.
function PathRegistry.IsNearPath(position: Vector3, margin: number): boolean
	for _, rect in rects do
		if
			math.abs(position.X - rect.Center.X) <= rect.Size.X / 2 + margin
			and math.abs(position.Z - rect.Center.Z) <= rect.Size.Z / 2 + margin
		then
			return true
		end
	end
	return false
end

return PathRegistry
