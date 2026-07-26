--!strict
-- Tiny Workspace-instance builder for the procedural map. Same spirit as
-- ReplicatedStorage.Shared.UIKit.Util.Create: a plain imperative
-- `Instance.new` + property-assignment helper, no scene-graph framework,
-- because this project has no build step and needs to stay readable by
-- anyone opening MapBuilder.lua (or its zone modules) cold.

local WorldKit = {}

export type PartProps = { [string]: any }

-- A plain anchored Part with sensible smooth-surface defaults. Pass any
-- BasePart property (Size, Position/CFrame, Color, Material, Transparency,
-- CanCollide, ...); anything omitted falls back to a safe default.
function WorldKit.Part(props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.Name or "Part"
	part.Anchored = if props.Anchored == nil then true else props.Anchored
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = props.Size or Vector3.new(4, 1, 4)
	part.Color = props.Color or Color3.fromRGB(255, 255, 255)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0

	if props.CFrame then
		part.CFrame = props.CFrame
	elseif props.Position then
		part.CFrame = CFrame.new(props.Position)
	end

	-- Pass through anything else (e.g. Shape = Enum.PartType.Ball for the
	-- egg/beacon shapes) so callers aren't limited to the defaults above.
	local HANDLED_KEYS = {
		Name = true,
		Anchored = true,
		CanCollide = true,
		CastShadow = true,
		Size = true,
		Color = true,
		Material = true,
		Transparency = true,
		CFrame = true,
		Position = true,
		Parent = true,
	}
	for key, value in props do
		if not HANDLED_KEYS[key] then
			(part :: any)[key] = value
		end
	end

	part.Parent = props.Parent
	return part
end

-- An upright cylinder (round faces up/down, like a drum or pillar) centered
-- at `Position`. Plain Roblox cylinder Parts lie on their side by default
-- (round faces point along local X); this bakes in the 90-degree fix so
-- every caller doesn't have to re-derive the rotation.
function WorldKit.UprightCylinder(props: PartProps): Part
	local diameter = props.Diameter or 4
	local height = props.Height or 2

	local part = Instance.new("Part")
	part.Name = props.Name or "Cylinder"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = if props.Anchored == nil then true else props.Anchored
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(height, diameter, diameter)
	part.Color = props.Color or Color3.fromRGB(255, 255, 255)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0

	local position: Vector3 = props.Position or Vector3.new(0, 0, 0)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

	part.Parent = props.Parent
	return part
end

-- Four thin Neon strips forming a rectangular outline of `Width` x `Depth`
-- centered on `Center`, e.g. to trim a plaza band or platform edge. Returns
-- the four Parts in case a caller wants to attach a PointLight to one.
function WorldKit.NeonBorder(props: PartProps): { Part }
	local width: number = props.Width
	local depth: number = props.Depth
	local center: Vector3 = props.Center
	local thickness = props.Thickness or 0.6
	local height = props.Height or 0.4
	local color = props.Color or Color3.fromRGB(57, 255, 136)
	local baseName = props.Name or "NeonBorder"
	local parent = props.Parent

	local specs = {
		{ Size = Vector3.new(width, height, thickness), Offset = Vector3.new(0, 0, depth / 2 - thickness / 2) },
		{ Size = Vector3.new(width, height, thickness), Offset = Vector3.new(0, 0, -(depth / 2 - thickness / 2)) },
		{ Size = Vector3.new(thickness, height, depth), Offset = Vector3.new(width / 2 - thickness / 2, 0, 0) },
		{ Size = Vector3.new(thickness, height, depth), Offset = Vector3.new(-(width / 2 - thickness / 2), 0, 0) },
	}

	local strips = {}
	for i, spec in specs do
		local strip = WorldKit.Part({
			Name = `{baseName}_{i}`,
			Size = spec.Size,
			Position = center + spec.Offset,
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		table.insert(strips, strip)
	end

	return strips
end

-- A floating text sign (BillboardGui) adorned to `props.Adornee`, used for
-- lightweight wayfinding (HATCHERY / SHOP / CTF ARENA) without a mesh/import
-- pipeline.
function WorldKit.Sign(props: PartProps): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = props.Name or "Sign"
	billboard.Adornee = props.Adornee
	billboard.Size = props.Size or UDim2.new(0, 240, 0, 64)
	billboard.StudsOffset = props.StudsOffset or Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = props.Adornee

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or Color3.fromRGB(245, 245, 250)
	label.Font = props.Font or Enum.Font.GothamBlack
	label.TextSize = props.TextSize or 30
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = Color3.fromRGB(10, 10, 16)
	label.Parent = billboard

	return billboard
end

-- A SpawnLocation part. `Neutral` defaults to false (Roblox's own default is
-- true) because most callers here are team-specific bases meant to be
-- reserved for CTFService's own teleporting, not Roblox's automatic respawn
-- picker - only the hub's spawn should opt back into Neutral = true.
function WorldKit.Spawn(props: PartProps): SpawnLocation
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = props.Name or "Spawn"
	spawn.Anchored = true
	spawn.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Size = props.Size or Vector3.new(12, 1, 12)
	spawn.Color = props.Color or Color3.fromRGB(255, 255, 255)
	spawn.Material = props.Material or Enum.Material.SmoothPlastic
	spawn.Neutral = if props.Neutral == nil then false else props.Neutral
	spawn.Enabled = if props.Enabled == nil then true else props.Enabled
	spawn.Duration = 0 -- no forced spawn-immunity lock

	if props.TeamColor then
		spawn.TeamColor = props.TeamColor
	end

	if props.CFrame then
		spawn.CFrame = props.CFrame
	elseif props.Position then
		spawn.CFrame = CFrame.new(props.Position)
	end

	spawn.Parent = props.Parent
	return spawn
end

return WorldKit
