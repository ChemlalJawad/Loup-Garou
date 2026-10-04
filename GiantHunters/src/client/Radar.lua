--!strict
-- The radar, bottom right (top right on touch screens, clear of the
-- buttons): turns with the camera (up = where you're looking). Giants are
-- red dots sized by height (runners orange, armoured grey), other hunters
-- blue, supply crates cyan, the gate a yellow mark, the Great Wall a ring.
-- Giants beyond its range show as arrows round the edge, pointing at them.
-- Shapes say it too, for every kind of colour vision: hunters and crates
-- are round, giants square, abnormals (runners, sprinters) diamonds, and a
-- giant reaching to grab flashes white.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)

local Radar = {}

local SIZE = 176
local RANGE = 280 -- studs from the centre to the edge
local SCALE = (SIZE / 2) / RANGE

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	for key, value in props do
		if key ~= "Parent" then
			(f :: any)[key] = value
		end
	end
	f.Parent = props.Parent
	return f
end

local function round(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = parent
end

-- Builds the radar in `gui`; returns its panel (the HUD scales it).
function Radar.Init(gui: ScreenGui): Frame
	local touch = UserInputService.TouchEnabled
	local panel = frame({
		Name = "Radar",
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 1),
		Position = if touch then UDim2.new(1, -12, 0, 52) else UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.fromRGB(20, 26, 22),
		BackgroundTransparency = 0.25,
		ClipsDescendants = true,
		Parent = gui,
	})
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(190, 170, 120)
	stroke.Thickness = 2
	stroke.Parent = panel

	-- The wall: a ring, re-centred every update.
	local wall = frame({ Name = "Wall", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Size = UDim2.fromOffset(Config.World.WallRadius * 2 * SCALE, Config.World.WallRadius * 2 * SCALE), Parent = panel })
	round(wall)
	local wallStroke = Instance.new("UIStroke")
	wallStroke.Color = Color3.fromRGB(200, 190, 170)
	wallStroke.Thickness = 3
	wallStroke.Parent = wall
	local gate = frame({ Name = "Gate", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.fromRGB(255, 210, 80), Rotation = 45, Parent = panel })

	-- You: an arrow in the middle, always pointing up.
	local you = Instance.new("TextLabel")
	you.AnchorPoint = Vector2.new(0.5, 0.5)
	you.Position = UDim2.fromScale(0.5, 0.5)
	you.Size = UDim2.fromOffset(16, 16)
	you.BackgroundTransparency = 1
	you.Text = "▲"
	you.TextColor3 = Color3.fromRGB(255, 255, 255)
	you.TextScaled = true
	you.ZIndex = 5
	you.Parent = panel

	local dots: { Frame } = {}
	local function dot(i: number): Frame
		local d = dots[i]
		if not d then
			local created = frame({ AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 3, Parent = panel })
			round(created)
			dots[i] = created
			d = created
		end
		local shown = d :: Frame
		shown.Visible = true
		return shown
	end

	-- Edge arrows for giants out of range.
	local arrows: { TextLabel } = {}
	local function arrow(i: number): TextLabel
		local a = arrows[i]
		if not a then
			local created = Instance.new("TextLabel")
			created.AnchorPoint = Vector2.new(0.5, 0.5)
			created.Size = UDim2.fromOffset(14, 14)
			created.BackgroundTransparency = 1
			created.Text = "▲"
			created.TextScaled = true
			created.TextStrokeTransparency = 0.4
			created.ZIndex = 4
			created.Parent = panel
			arrows[i] = created
			a = created
		end
		local shown = a :: TextLabel
		shown.Visible = true
		return shown
	end

	local player = Players.LocalPlayer
	local camera = Workspace.CurrentCamera
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 1 / 15 then
			return
		end
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		local here = root.Position
		-- Camera heading: radar "up" is the flat look direction.
		local look = Geo.Flat(camera.CFrame.LookVector)
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		end
		look = look.Unit
		local right = Vector3.new(-look.Z, 0, look.X)
		local function toRadar(p: Vector3): (number, number, boolean)
			local d = Geo.Flat(p - here)
			local x, y = d:Dot(right) * SCALE, -d:Dot(look) * SCALE
			return SIZE / 2 + x, SIZE / 2 + y, math.abs(x) < SIZE / 2 + 8 and math.abs(y) < SIZE / 2 + 8
		end
		local cx, cy = toRadar(Vector3.zero)
		wall.Position = UDim2.fromOffset(cx, cy)
		local gx, gy, gateVisible = toRadar(Geo.Polar(Config.World.GateAngle, Config.World.WallRadius + Config.World.WallThickness / 2))
		gate.Position = UDim2.fromOffset(gx, gy)
		gate.Visible = gateVisible

		local count = 0
		local arrowCount = 0
		local function place(p: Vector3, size: number, color: Color3, edge: boolean?, shape: string?)
			local x, y, visible = toRadar(p)
			if visible then
				count += 1
				local d = dot(count)
				d.Position = UDim2.fromOffset(x, y)
				d.Size = UDim2.fromOffset(size, size)
				d.BackgroundColor3 = color
				local corner = d:FindFirstChildOfClass("UICorner")
				if corner then
					corner.CornerRadius = if shape then UDim.new(0, 2) else UDim.new(1, 0)
				end
				d.Rotation = if shape == "Diamond" then 45 else 0
			elseif edge then
				-- Off the radar: an arrow on the rim, pointing its way.
				local dx, dy = x - SIZE / 2, y - SIZE / 2
				local rim = SIZE / 2 - 9
				local stretch = rim / math.max(math.abs(dx), math.abs(dy))
				arrowCount += 1
				local a = arrow(arrowCount)
				a.Position = UDim2.fromOffset(SIZE / 2 + dx * stretch, SIZE / 2 + dy * stretch)
				a.Rotation = math.deg(math.atan2(dx, -dy))
				a.TextColor3 = color
			end
		end
		for _, crate in CollectionService:GetTagged(Config.Tags.Supply) do
			if crate:IsA("BasePart") then
				place(crate.Position, 6, Color3.fromRGB(110, 225, 255))
			end
		end
		for _, other in Players:GetPlayers() do
			local otherRoot = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				place(otherRoot.Position, 7, Color3.fromRGB(90, 150, 255))
			end
		end
		for _, giant in CollectionService:GetTagged(Config.Tags.Giant) do
			if giant:IsA("Model") and not giant:GetAttribute("Defeated") then
				local giantRoot = giant:FindFirstChild("Root")
				if giantRoot and giantRoot:IsA("BasePart") then
					local height = (giant:GetAttribute("Height") :: number?) or 20
					local kind = giant:GetAttribute("Kind")
					local side = giant:GetAttribute("Side")
					local color = if giant:GetAttribute("Grabbing") and os.clock() % 0.3 < 0.15 then Color3.new(1, 1, 1)
						elseif side == "Humans" then Color3.fromRGB(90, 160, 255)
						elseif side == "Giants" then Color3.fromRGB(255, 60, 140)
						elseif kind == "Runner" then Color3.fromRGB(255, 160, 40)
						elseif kind == "Beast" then Color3.fromRGB(150, 90, 60)
						elseif kind == "Armored" then Color3.fromRGB(190, 185, 170)
						elseif kind == "Sprinter" then Color3.fromRGB(200, 120, 255)
						elseif kind == "Crawler" then Color3.fromRGB(150, 170, 70)
						else Color3.fromRGB(240, 70, 60)
					place(giantRoot.Position, math.clamp(height / 4, 6, 14), color, true, if giant:GetAttribute("Abnormal") then "Diamond" else "Square")
				end
			end
		end
		for i = count + 1, #dots do
			dots[i].Visible = false
		end
		for i = arrowCount + 1, #arrows do
			arrows[i].Visible = false
		end
	end)
	return panel
end

return Radar
