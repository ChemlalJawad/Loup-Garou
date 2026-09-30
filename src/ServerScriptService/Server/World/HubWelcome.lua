--!strict
-- The welcome corner around the Hub spawn pad: what every player sees in
-- their first seconds, so it should feel like arriving at a party, not at a
-- bus stop. Built by HubZone right after the spawn pad (this module isn't a
-- "...Zone", so MapBuilder doesn't auto-run it).
--
--   * A pastel rainbow arch behind the pad - the default camera sits behind
--     the character, so the arch frames the very first view.
--   * Bunting (little triangle flags) strung from the arch to the colonnade.
--   * A "YOU ARE HERE" map board beside the pad, drawn from WorldLayout so it
--     can never disagree with the real map.
--   * Flower beds either side of the arch.
-- The waving Brainrot greeters are client-side (GreeterController).
--
-- ~100 parts, all non-colliding decor except the board.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)

local HubWelcome = {}

local PASTELS = {
	Color3.fromRGB(255, 150, 160),
	Color3.fromRGB(255, 200, 130),
	Color3.fromRGB(255, 240, 140),
	Color3.fromRGB(160, 230, 160),
	Color3.fromRGB(150, 200, 255),
	Color3.fromRGB(200, 170, 255),
}

local function decor(props: WorldKit.PartProps): Part
	props.CanCollide = false
	props.CanTouch = false
	props.CastShadow = false
	return WorldKit.Part(props)
end

local function rainbowArch(parent: Instance, base: Vector3, radius: number)
	local band = 0.75
	local segments = 12
	for b, color in PASTELS do
		local r = radius - (b - 1) * band
		local length = (math.pi * r / segments) * 1.12 -- overlap hides seams
		for s = 0, segments - 1 do
			local angle = math.pi * (s + 0.5) / segments
			decor({
				Name = `Arch{b}_{s}`,
				Size = Vector3.new(length, band, 1.2),
				CFrame = CFrame.new(base + Vector3.new(math.cos(angle) * r, math.sin(angle) * r, 0))
					* CFrame.Angles(0, 0, angle + math.pi / 2),
				Color = color,
				Material = Enum.Material.SmoothPlastic,
				Parent = parent,
			})
		end
	end
	-- Fluffy cloud feet where the arch meets the ground.
	for _, side in { -1, 1 } do
		for i, offset in { Vector3.new(0, 0.8, 0), Vector3.new(1.1, 0.4, 0.6), Vector3.new(-1, 0.5, -0.5) } do
			decor({
				Name = `ArchCloud{i}`,
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * (2.6 - i * 0.3),
				Position = base + Vector3.new(side * (radius - band * 2.5), 0, 0) + offset,
				Color = Color3.fromRGB(255, 255, 255),
				Parent = parent,
			})
		end
	end
end

local function bunting(parent: Instance, from: Vector3, to: Vector3, flags: number)
	local span = to - from
	local sag = Vector3.new(0, -1.2, 0)
	local function pointAt(t: number): Vector3
		return from + span * t + sag * (4 * t * (1 - t)) -- gentle parabola
	end
	for i = 0, flags - 1 do
		local a, b = pointAt(i / flags), pointAt((i + 1) / flags)
		decor({
			Name = "String",
			Size = Vector3.new(0.08, 0.08, (b - a).Magnitude),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = Color3.fromRGB(250, 250, 250),
			Parent = parent,
		})
		-- A triangle flag hanging from the middle of each string segment.
		local mid = pointAt((i + 0.5) / flags)
		local flag = WorldKit.Wedge({
			Name = "Flag",
			Size = Vector3.new(0.1, 1.2, 1),
			Position = mid - Vector3.new(0, 0.6, 0),
			Rotation = CFrame.lookAt(Vector3.zero, span.Unit) * CFrame.Angles(math.pi, 0, 0),
			Color = PASTELS[i % #PASTELS + 1],
			CanCollide = false,
			Parent = parent,
		})
		flag.CanQuery = false
		flag.CanTouch = false
		flag.CastShadow = false
	end
end

local ZONE_COLORS: { [string]: Color3 } = {
	Hub = Color3.fromRGB(255, 225, 120),
	Hatchery = Color3.fromRGB(255, 170, 120),
	Commercial = Color3.fromRGB(120, 210, 150),
	Arena = Color3.fromRGB(140, 170, 255),
	Plaza = Color3.fromRGB(230, 190, 110),
	Lounge = Color3.fromRGB(200, 150, 255),
	Parade = Color3.fromRGB(255, 120, 140),
	FunPark = Color3.fromRGB(120, 220, 240),
}

local function mapBoard(parent: Instance, position: Vector3, facing: Vector3, spawnAt: Vector3, floorY: number)
	local board = WorldKit.Part({
		Name = "MapBoard",
		Size = Vector3.new(9, 6.5, 0.4),
		CFrame = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z)),
		Color = WorldKit.Palette.Wood,
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	-- Two legs from the board's bottom edge down to the floor.
	local legHeight = (position.Y - 3.25) - floorY + 0.3
	for _, x in { -3.8, 3.8 } do
		decor({
			Name = "BoardLeg",
			Size = Vector3.new(0.5, legHeight, 0.5),
			CFrame = board.CFrame * CFrame.new(x, -3.25 - legHeight / 2 + 0.3, 0.3),
			Color = WorldKit.Palette.Wood,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Map"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(600, 440)
	gui.LightInfluence = 0.2
	gui.MaxDistance = 120
	gui.Adornee = board
	gui.Parent = board

	local paper = Instance.new("Frame")
	paper.Size = UDim2.new(1, -24, 1, -24)
	paper.Position = UDim2.new(0, 12, 0, 12)
	paper.BackgroundColor3 = Color3.fromRGB(250, 244, 225)
	paper.Parent = gui
	Instance.new("UICorner").Parent = paper

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Text = "WHERE TO GO"
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 30
	title.TextColor3 = Color3.fromRGB(70, 50, 40)
	title.Parent = paper

	-- The map area: the ground plate mapped into the paper, north up. The
	-- board faces the player, so world +X (east) is drawn on the right.
	local plate = WorldLayout.GroundPlate
	local area = Instance.new("Frame")
	area.BackgroundColor3 = Color3.fromRGB(150, 205, 130)
	area.Position = UDim2.new(0, 16, 0, 46)
	area.Size = UDim2.new(1, -32, 1, -62)
	area.Parent = paper
	Instance.new("UICorner").Parent = area

	local function toMap(worldPos: Vector3): UDim2
		local u = (worldPos.X - (plate.Center.X - plate.Size.X / 2)) / plate.Size.X
		local v = 1 - (worldPos.Z - (plate.Center.Z - plate.Size.Z / 2)) / plate.Size.Z
		return UDim2.new(u, 0, v, 0)
	end

	for zoneId, zone in WorldLayout.Zones :: { [string]: WorldLayout.ZoneRect } do
		local box = Instance.new("TextLabel")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = toMap(zone.Center)
		box.Size = UDim2.new(zone.Size.X / plate.Size.X, -4, zone.Size.Z / plate.Size.Z, -4)
		box.BackgroundColor3 = ZONE_COLORS[zoneId] or Color3.fromRGB(230, 230, 230)
		box.Text = zone.Label
		box.TextWrapped = true
		box.TextScaled = true
		box.Font = Enum.Font.GothamBold
		box.TextColor3 = Color3.fromRGB(50, 40, 40)
		box.Parent = area
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = box
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 3)
		pad.PaddingRight = UDim.new(0, 3)
		pad.Parent = box
	end

	local here = Instance.new("TextLabel")
	here.AnchorPoint = Vector2.new(0.5, 1)
	here.Position = toMap(spawnAt)
	here.Size = UDim2.new(0, 110, 0, 30)
	here.BackgroundColor3 = Color3.fromRGB(230, 60, 80)
	here.Text = "YOU ARE HERE"
	here.Font = Enum.Font.GothamBlack
	here.TextSize = 14
	here.TextColor3 = Color3.fromRGB(255, 255, 255)
	here.ZIndex = 5
	here.Parent = area
	Instance.new("UICorner").Parent = here
end

-- `padCentre` is the centre of the spawn pad at floor level (the dais top);
-- the player faces -Z.
function HubWelcome.Build(parent: Instance, padCentre: Vector3)
	local folder = WorldKit.Group("Welcome", parent)
	local floorY = padCentre.Y
	-- Just behind the pad, still on the dais: the default camera sits behind
	-- the character, so this frames the very first view.
	local archZ = padCentre.Z + 5

	rainbowArch(folder, Vector3.new(padCentre.X, floorY, archZ), 8.5)

	-- Bunting from the arch top out to the two nearest colonnade pillars
	-- (radius 30, at 60 and 120 degrees), then on to the next pair.
	local archTop = Vector3.new(padCentre.X, floorY + 8.2, archZ)
	local hub = WorldLayout.Get("Hub").Center
	local function pillarTop(degrees: number): Vector3
		local a = math.rad(degrees)
		return hub + Vector3.new(math.cos(a) * 30, WorldLayout.GroundY + 10.5, math.sin(a) * 30)
	end
	bunting(folder, archTop, pillarTop(60), 7)
	bunting(folder, archTop, pillarTop(120), 7)
	bunting(folder, pillarTop(60), pillarTop(30), 6)
	bunting(folder, pillarTop(120), pillarTop(150), 6)

	-- Map board on the pad's east side, turned toward the pad.
	mapBoard(folder, Vector3.new(padCentre.X + 13, floorY + 3.9, padCentre.Z - 2), padCentre, padCentre, floorY)

	-- Flower beds outside the arch's feet, on the mid ring one step down.
	for _, x in { -8, 8 } do
		WorldKit.FlowerBed({ Position = Vector3.new(padCentre.X + x, floorY - 1, padCentre.Z + 10), Parent = folder })
	end
end

return HubWelcome
