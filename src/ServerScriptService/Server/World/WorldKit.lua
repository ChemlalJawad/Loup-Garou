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

-- === Structural primitives ==================================================
-- Added for the world-expansion pass: zone modules compose these instead of
-- hand-rolling CFrame math per building. All of them accept the same loose
-- `PartProps` bag as WorldKit.Part.

-- A folder/Model to group a structure under, so the Workspace tree stays
-- navigable instead of being one flat pile of Parts.
function WorldKit.Group(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- A wedge (ramp). `Rotation` is a CFrame the wedge is multiplied by, so a
-- caller can face it any direction without recomputing the base orientation.
function WorldKit.Wedge(props: PartProps): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = props.Name or "Wedge"
	wedge.Anchored = if props.Anchored == nil then true else props.Anchored
	wedge.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	wedge.Size = props.Size or Vector3.new(4, 4, 8)
	wedge.Color = props.Color or Color3.fromRGB(200, 200, 200)
	wedge.Material = props.Material or Enum.Material.SmoothPlastic
	wedge.Transparency = props.Transparency or 0
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth

	local base = if props.Position then CFrame.new(props.Position) else CFrame.new()
	wedge.CFrame = base * (props.Rotation or CFrame.new())
	wedge.Parent = props.Parent
	return wedge
end

function WorldKit.Sphere(props: PartProps): Part
	local diameter = props.Diameter or 4
	return WorldKit.Part({
		Name = props.Name or "Sphere",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		Position = props.Position,
		Color = props.Color,
		Material = props.Material,
		Transparency = props.Transparency,
		CanCollide = props.CanCollide,
		CastShadow = props.CastShadow,
		Parent = props.Parent,
	})
end

-- A vertical pillar with optional glowing cap, the workhorse for colonnades
-- and arena cover.
function WorldKit.Pillar(props: PartProps): Part
	local height = props.Height or 12
	local thickness = props.Thickness or 2
	local basePosition: Vector3 = props.Position or Vector3.new(0, 0, 0)

	local pillar = WorldKit.Part({
		Name = props.Name or "Pillar",
		Size = Vector3.new(thickness, height, thickness),
		Position = basePosition + Vector3.new(0, height / 2, 0),
		Color = props.Color or Color3.fromRGB(40, 40, 56),
		Material = props.Material or Enum.Material.Concrete,
		Parent = props.Parent,
	})

	if props.CapColor then
		WorldKit.Part({
			Name = (props.Name or "Pillar") .. "Cap",
			Size = Vector3.new(thickness + 0.6, 0.5, thickness + 0.6),
			Position = basePosition + Vector3.new(0, height + 0.25, 0),
			Color = props.CapColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = props.Parent,
		})
	end

	return pillar
end

-- A straight run of steps climbing `Height` over `Run` studs along +Z (or +X
-- when `Axis == "X"`). Returns the top-surface Y so callers can land a
-- platform flush on it.
function WorldKit.Stairs(props: PartProps): number
	local steps: number = props.Steps or 8
	local width: number = props.Width or 10
	local height: number = props.Height or 8
	local run: number = props.Run or 12
	local axis: string = props.Axis or "Z"
	local start: Vector3 = props.Position or Vector3.new(0, 0, 0)
	local color = props.Color or Color3.fromRGB(46, 46, 64)

	local stepHeight = height / steps
	local stepRun = run / steps

	for i = 1, steps do
		local riseCenter = start.Y + (stepHeight * i) - stepHeight / 2
		local advance = (stepRun * (i - 1)) + stepRun / 2
		local size = if axis == "Z"
			then Vector3.new(width, stepHeight, stepRun)
			else Vector3.new(stepRun, stepHeight, width)
		local offset = if axis == "Z" then Vector3.new(0, 0, advance) else Vector3.new(advance, 0, 0)

		WorldKit.Part({
			Name = `{props.Name or "Stairs"}_Step{i}`,
			Size = size,
			Position = Vector3.new(start.X, riseCenter, start.Z) + offset,
			Color = color,
			Material = props.Material or Enum.Material.Concrete,
			Parent = props.Parent,
		})
	end

	return start.Y + height
end

-- A wall segment with an optional neon strip along its top edge.
function WorldKit.Wall(props: PartProps): Part
	local wall = WorldKit.Part({
		Name = props.Name or "Wall",
		Size = props.Size or Vector3.new(20, 10, 1),
		Position = props.Position,
		CFrame = props.CFrame,
		Color = props.Color or Color3.fromRGB(32, 32, 46),
		Material = props.Material or Enum.Material.Concrete,
		Transparency = props.Transparency,
		Parent = props.Parent,
	})

	if props.TrimColor then
		local size = wall.Size
		WorldKit.Part({
			Name = wall.Name .. "Trim",
			Size = Vector3.new(size.X, 0.4, size.Z),
			CFrame = wall.CFrame * CFrame.new(0, size.Y / 2 + 0.2, 0),
			Color = props.TrimColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = props.Parent,
		})
	end

	return wall
end

-- A railing: thin posts plus a top rail, for balconies and plaza edges.
function WorldKit.Railing(props: PartProps)
	local length: number = props.Length or 20
	local axis: string = props.Axis or "X"
	local center: Vector3 = props.Position or Vector3.new(0, 0, 0)
	local height = props.Height or 3.5
	local color = props.Color or Color3.fromRGB(52, 52, 74)
	local postSpacing = props.PostSpacing or 4

	local postCount = math.max(2, math.floor(length / postSpacing) + 1)
	for i = 1, postCount do
		local t = (i - 1) / (postCount - 1)
		local along = (t - 0.5) * length
		local offset = if axis == "X" then Vector3.new(along, 0, 0) else Vector3.new(0, 0, along)
		WorldKit.Part({
			Name = `{props.Name or "Railing"}_Post{i}`,
			Size = Vector3.new(0.4, height, 0.4),
			Position = center + offset + Vector3.new(0, height / 2, 0),
			Color = color,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = props.Parent,
		})
	end

	local railSize = if axis == "X" then Vector3.new(length, 0.35, 0.5) else Vector3.new(0.5, 0.35, length)
	WorldKit.Part({
		Name = `{props.Name or "Railing"}_Rail`,
		Size = railSize,
		Position = center + Vector3.new(0, height, 0),
		Color = props.RailColor or color,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = props.Parent,
	})
end

-- A checkerboard/banded floor built from alternating tiles. Reads as
-- "designed" where a single flat slab reads as placeholder. Keeps part count
-- in check by using `TileSize` bands rather than per-stud tiles.
function WorldKit.TiledFloor(props: PartProps)
	local width: number = props.Width or 60
	local depth: number = props.Depth or 60
	local tileSize: number = props.TileSize or 10
	local center: Vector3 = props.Position or Vector3.new(0, 0, 0)
	local colorA = props.ColorA or Color3.fromRGB(27, 27, 40)
	local colorB = props.ColorB or Color3.fromRGB(36, 36, 52)
	local thickness = props.Thickness or 1

	local cols = math.max(1, math.floor(width / tileSize))
	local rows = math.max(1, math.floor(depth / tileSize))

	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			local isEven = (col + row) % 2 == 0
			local x = center.X - width / 2 + tileSize / 2 + col * tileSize
			local z = center.Z - depth / 2 + tileSize / 2 + row * tileSize
			WorldKit.Part({
				Name = `{props.Name or "Tile"}_{col}_{row}`,
				Size = Vector3.new(tileSize, thickness, tileSize),
				Position = Vector3.new(x, center.Y, z),
				Color = if isEven then colorA else colorB,
				Material = props.Material or Enum.Material.SmoothPlastic,
				Parent = props.Parent,
			})
		end
	end
end

-- Flat text painted onto one face of a part (SurfaceGui), for storefront
-- lettering and arena banners. Unlike WorldKit.Sign this doesn't float or
-- always-face-camera - it sits on the surface like real signage.
function WorldKit.SurfaceLabel(props: PartProps): SurfaceGui
	local adornee: BasePart = props.Adornee
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = props.Name or "SurfaceLabel"
	surfaceGui.Adornee = adornee
	surfaceGui.Face = props.Face or Enum.NormalId.Front
	surfaceGui.CanvasSize = props.CanvasSize or Vector2.new(400, 120)
	surfaceGui.LightInfluence = props.LightInfluence or 0
	surfaceGui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or Color3.fromRGB(245, 245, 250)
	label.Font = props.Font or Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = surfaceGui

	return surfaceGui
end

function WorldKit.Light(props: PartProps): PointLight
	local light = Instance.new("PointLight")
	light.Name = props.Name or "Light"
	light.Color = props.Color or Color3.fromRGB(255, 255, 255)
	light.Brightness = props.Brightness or 2
	light.Range = props.Range or 20
	light.Shadows = if props.Shadows == nil then false else props.Shadows
	light.Parent = props.Parent
	return light
end

-- A simple looping particle emitter, for fountain mist, hatchery sparkles and
-- flag-stand glow motes.
function WorldKit.Emitter(props: PartProps): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = props.Name or "Emitter"
	emitter.Color = ColorSequence.new(props.Color or Color3.fromRGB(255, 255, 255))
	emitter.Rate = props.Rate or 8
	emitter.Lifetime = props.Lifetime or NumberRange.new(1, 2)
	emitter.Speed = props.Speed or NumberRange.new(2, 4)
	emitter.SpreadAngle = props.SpreadAngle or Vector2.new(20, 20)
	emitter.Size = props.SizeSequence or NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = props.TransparencySequence or NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = props.LightEmission or 0.6
	emitter.Parent = props.Parent
	return emitter
end

return WorldKit
