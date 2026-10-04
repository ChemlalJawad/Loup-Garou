--!strict
-- Small flocks of birds circling over the roofs and treetops near the
-- camera, on this client only (three parts a bird: a body and two
-- flapping wings). A giant coming close sends a flock flying off; it
-- settles over somewhere else a little later. They roost at night and
-- shelter from the rain.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local SkyController = require(script.Parent.SkyController)
local Weather = require(script.Parent.Weather)

local Birds = {}

local A = Config.Ambient

type Bird = { Body: BasePart, Wings: { BasePart }, Radius: number, Offset: number, Height: number, Flap: number, Out: Vector3 }
type Flock = {
	Birds: { Bird },
	Centre: Vector3?,
	Speed: number, -- radians a second round the centre
	State: string, -- "Circle", "Scatter", "Away"
	Timer: number,
	Arrive: number, -- 1 just arriving (spiralling in from far) .. 0 settled
}

local flocks: { Flock } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = false

local function birdPart(parent: Instance, size: Vector3, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function setVisible(flock: Flock, on: boolean)
	for _, bird in flock.Birds do
		local t = if on then 0 else 1
		if bird.Body.Transparency ~= t then
			bird.Body.Transparency = t
			for _, wing in bird.Wings do
				wing.Transparency = t
			end
		end
	end
end

-- A new place to circle: over whatever is tall (a roof, a tree) somewhere
-- round the camera, away from giants.
local function settle(flock: Flock, camera: Vector3, giants: { Vector3 })
	for _ = 1, 8 do
		local angle = math.random() * math.pi * 2
		local distance = 40 + math.random() * 140
		local x, z = camera.X + math.sin(angle) * distance, camera.Z + math.cos(angle) * distance
		local result = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -500, 0), rayParams)
		local top = if result then result.Position.Y else 0
		local centre = Vector3.new(x, top + 22 + math.random() * 14, z)
		local clear = true
		for _, g in giants do
			if (Vector3.new(g.X, 0, g.Z) - Vector3.new(x, 0, z)).Magnitude < A.BirdScatter * 1.5 then
				clear = false
				break
			end
		end
		if clear then
			flock.Centre = centre
			flock.State = "Circle"
			flock.Arrive = 1
			return
		end
	end
	flock.Centre = nil
end

function Birds.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Birds"
	folder.Parent = Workspace
	rayParams.FilterDescendantsInstances = { folder }
	local count = if SkyController.LowEnd() then A.FlocksLowEnd else A.Flocks
	for _ = 1, count do
		local flock: Flock = { Birds = {}, Centre = nil, Speed = (0.35 + math.random() * 0.25) * (if math.random() < 0.5 then -1 else 1), State = "Away", Timer = math.random() * 4, Arrive = 1 }
		local white = math.random() < 0.4 -- gulls or crows
		local color = if white then Color3.fromRGB(236, 236, 230) else Color3.fromRGB(50, 50, 56)
		for _ = 1, A.BirdsPerFlock do
			local body = birdPart(folder, Vector3.new(0.5, 0.4, 1.2), color)
			local wings = { birdPart(folder, Vector3.new(1.3, 0.08, 0.6), color), birdPart(folder, Vector3.new(1.3, 0.08, 0.6), color) }
			table.insert(flock.Birds, {
				Body = body,
				Wings = wings,
				Radius = 10 + math.random() * 14,
				Offset = math.random() * math.pi * 2,
				Height = (math.random() - 0.5) * 8,
				Flap = math.random() * 6,
				Out = Vector3.new(math.random() - 0.5, 0.4 + math.random() * 0.4, math.random() - 0.5).Unit,
			})
		end
		setVisible(flock, false)
		table.insert(flocks, flock)
	end

	local clock = 0
	local nextGiants = 0
	local giants: { Vector3 } = {}
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local here = camera.CFrame.Position
		if clock >= nextGiants then
			nextGiants = clock + 0.5
			giants = {}
			for _, giant in CollectionService:GetTagged(Config.Tags.Giant) do
				local root = giant:FindFirstChild("Root")
				if root and root:IsA("BasePart") then
					table.insert(giants, root.Position)
				end
			end
		end
		local hour = Lighting.ClockTime
		local resting = hour >= Config.DayNight.NightStart - 0.5 or hour < Config.DayNight.NightEnd + 0.5 or Weather.Raining()

		local parts: { BasePart } = {}
		local frames: { CFrame } = {}
		for _, flock in flocks do
			local centre = flock.Centre
			if flock.State == "Away" then
				flock.Timer -= dt
				if flock.Timer <= 0 and not resting then
					settle(flock, here, giants)
				end
				setVisible(flock, flock.State ~= "Away")
				continue
			end
			if not centre then
				flock.State = "Away"
				continue
			end
			-- Gone too far from the camera, or bedtime: go somewhere else.
			if resting or (Vector3.new(centre.X - here.X, 0, centre.Z - here.Z)).Magnitude > 320 then
				flock.State, flock.Timer = "Away", 3 + math.random() * 4
				setVisible(flock, false)
				continue
			end
			if flock.State == "Circle" then
				for _, g in giants do
					if (Vector3.new(g.X - centre.X, 0, g.Z - centre.Z)).Magnitude < A.BirdScatter then
						flock.State, flock.Timer = "Scatter", 0
						break
					end
				end
			end
			flock.Arrive = math.max(flock.Arrive - dt * 0.25, 0)
			if flock.State == "Scatter" then
				flock.Timer += dt
				if flock.Timer > 4 then
					flock.State, flock.Timer = "Away", 6 + math.random() * 6
					setVisible(flock, false)
					continue
				end
			end
			for _, bird in flock.Birds do
				local angle = bird.Offset + clock * flock.Speed * (1 + bird.Radius / 60)
				local radius = bird.Radius * (1 + flock.Arrive * 4)
				local p = centre + Vector3.new(math.cos(angle) * radius, bird.Height + math.sin(clock * 0.7 + bird.Offset) * 2 + flock.Arrive * 20, math.sin(angle) * radius)
				local heading = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * math.sign(flock.Speed)
				local flapRate = 9
				if flock.State == "Scatter" then
					-- Off they go: out and up, fast.
					p += bird.Out * flock.Timer * 45
					heading = (bird.Out + heading * 0.3).Unit
					flapRate = 18
				end
				bird.Flap += dt * flapRate
				-- Flap in bursts, then glide.
				local flapping = flock.State == "Scatter" or math.sin(bird.Flap * 0.15) > -0.2
				local wingAngle = if flapping then math.sin(bird.Flap) * 0.7 else 0.08
				local body = CFrame.lookAt(p, p + heading) * CFrame.Angles(0, 0, -math.sign(flock.Speed) * 0.25)
				table.insert(parts, bird.Body)
				table.insert(frames, body)
				for i, side in { -1, 1 } do
					table.insert(parts, bird.Wings[i])
					table.insert(frames, body * CFrame.new(side * 0.25, 0.1, 0) * CFrame.Angles(0, 0, side * wingAngle) * CFrame.new(side * 0.65, 0, 0))
				end
			end
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return Birds
