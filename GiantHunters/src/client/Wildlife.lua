--!strict
-- Wild creatures, on this client only and only near the camera:
--
--   * by day, a few deer and rabbits graze in the grassy meadows outside the
--     wall: they nibble, wander a few steps, and run (rabbits hop) from a
--     giant or a hunter coming close, then are tidied away out of sight and
--     turn up somewhere else;
--   * at night, swarms of fireflies drift and blink low over the ground
--     under the trees and along the river.
--
-- Few parts (eight a deer, five a rabbit, one a firefly), moved together
-- with BulkMoveTo; half as many on phones and low graphics
-- (SkyController.LowEnd). Numbers: Config.Wildlife.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local SkyController = require(script.Parent.SkyController)

local Wildlife = {}

local C = Config.Wildlife
local W = Config.World

type Piece = { Part: BasePart, Offset: CFrame, Head: boolean? }
type Animal = {
	Kind: string, -- "Deer" | "Rabbit"
	Pieces: { Piece },
	Position: Vector3, -- on the ground
	Heading: number, -- radians round Y
	State: string, -- "Away" | "Graze" | "Walk" | "Flee"
	Timer: number,
	Speed: number,
	Hop: number,
	Graze: number, -- 0 head up .. 1 head down
	NextGround: number,
}
type Firefly = { Part: BasePart, Base: Vector3, Phase: number, Rates: Vector3 }
type Swarm = { Flies: { Firefly }, Centre: Vector3?, Light: PointLight?, Timer: number }

local folder: Folder
local animals: { Animal } = {}
local swarms: { Swarm } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = false

local function piece(size: Vector3, color: Color3, shape: Enum.PartType?, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = folder
	return p
end

local function makeDeer(): Animal
	local coat, light, dark = Color3.fromRGB(150, 100, 62), Color3.fromRGB(236, 226, 206), Color3.fromRGB(70, 52, 40)
	local pieces: { Piece } = {
		{ Part = piece(Vector3.new(2, 2, 4.4), coat), Offset = CFrame.new(0, 3.4, 0) },
		{ Part = piece(Vector3.new(0.8, 2.4, 0.8), coat), Offset = CFrame.new(0, 4.6, 2) * CFrame.Angles(math.rad(-30), 0, 0), Head = true },
		{ Part = piece(Vector3.new(1, 1, 1.8), coat), Offset = CFrame.new(0, 5.6, 2.7), Head = true },
		{ Part = piece(Vector3.new(0.6, 0.5, 0.3), light), Offset = CFrame.new(0, 3.9, -2.3) },
	}
	for _, x in { -0.65, 0.65 } do
		for _, z in { -1.6, 1.6 } do
			table.insert(pieces, { Part = piece(Vector3.new(0.4, 2.6, 0.4), dark), Offset = CFrame.new(x, 1.3, z) })
		end
	end
	return { Kind = "Deer", Pieces = pieces, Position = Vector3.zero, Heading = 0, State = "Away", Timer = math.random() * 5, Speed = 0, Hop = 0, Graze = 0, NextGround = 0 }
end

local function makeRabbit(): Animal
	local fur = if math.random() < 0.5 then Color3.fromRGB(150, 130, 110) else Color3.fromRGB(200, 196, 188)
	local pieces: { Piece } = {
		{ Part = piece(Vector3.new(1, 1, 1.4), fur), Offset = CFrame.new(0, 0.6, 0) },
		{ Part = piece(Vector3.new(0.8, 0.8, 0.8), fur), Offset = CFrame.new(0, 1.1, 0.75), Head = true },
		{ Part = piece(Vector3.new(0.2, 0.9, 0.15), fur), Offset = CFrame.new(-0.2, 1.85, 0.65), Head = true },
		{ Part = piece(Vector3.new(0.2, 0.9, 0.15), fur), Offset = CFrame.new(0.2, 1.85, 0.65), Head = true },
		{ Part = piece(Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(245, 245, 240), Enum.PartType.Ball), Offset = CFrame.new(0, 0.75, -0.75) },
	}
	return { Kind = "Rabbit", Pieces = pieces, Position = Vector3.zero, Heading = 0, State = "Away", Timer = math.random() * 5, Speed = 0, Hop = 0, Graze = 0, NextGround = 0 }
end

local function setVisible(animal: Animal, on: boolean)
	local t = if on then 0 else 1
	for _, p in animal.Pieces do
		p.Part.Transparency = t
	end
end

local function night(): boolean
	local hour = Lighting.ClockTime
	return hour >= Config.DayNight.NightStart - 0.5 or hour < Config.DayNight.NightEnd + 0.5
end

-- Grass outside the wall, dry, not on the castle hill.
local function meadowAt(x: number, z: number): Vector3?
	local p = Vector3.new(x, 0, z)
	if Geo.RadiusOf(p) < W.WallRadius + W.WallThickness + 20 or Geo.RadiusOf(p) > W.LandRadius - 80 or Geo.InRiver(x, z, 12) or Geo.InCastleHill(p, 10) then
		return nil
	end
	local hit = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -520, 0), rayParams)
	if hit and hit.Instance:IsA("Terrain") and hit.Normal.Y > 0.85 and (hit.Material == Enum.Material.Grass or hit.Material == Enum.Material.LeafyGrass) then
		return hit.Position
	end
	return nil
end

local function farFrom(p: Vector3, points: { Vector3 }, distance: number): boolean
	for _, q in points do
		if Geo.Flat(q - p).Magnitude < distance then
			return false
		end
	end
	return true
end

local function spawnAnimal(animal: Animal, camera: Vector3, giants: { Vector3 }, hunters: { Vector3 })
	for _ = 1, 6 do
		local angle = math.random() * math.pi * 2
		local distance = C.Range[1] + math.random() * (C.Range[2] - C.Range[1])
		local spot = meadowAt(camera.X + math.sin(angle) * distance, camera.Z + math.cos(angle) * distance)
		if spot and farFrom(spot, giants, C.FleeGiant * 1.5) and farFrom(spot, hunters, C.FleeHunter * 2) then
			animal.Position = spot
			animal.Heading = math.random() * math.pi * 2
			animal.State = "Graze"
			animal.Timer = 2 + math.random() * 5
			setVisible(animal, true)
			return
		end
	end
	animal.Timer = 2 + math.random() * 3 -- try again soon
end

-- The nearest threat (a giant or a hunter close enough), if any.
local function threat(animal: Animal, giants: { Vector3 }, hunters: { Vector3 }): Vector3?
	for _, g in giants do
		if Geo.Flat(g - animal.Position).Magnitude < C.FleeGiant then
			return g
		end
	end
	for _, h in hunters do
		if Geo.Flat(h - animal.Position).Magnitude < C.FleeHunter then
			return h
		end
	end
	return nil
end

local function stepAnimal(animal: Animal, dt: number, camera: Vector3, giants: { Vector3 }, hunters: { Vector3 }, parts: { BasePart }, frames: { CFrame })
	animal.Timer -= dt
	if animal.State == "Away" then
		if animal.Timer <= 0 and not night() then
			spawnAnimal(animal, camera, giants, hunters)
		end
		return
	end
	if night() or Geo.Flat(animal.Position - camera).Magnitude > C.Despawn then
		animal.State, animal.Timer = "Away", 3 + math.random() * 6
		setVisible(animal, false)
		return
	end
	local scary = threat(animal, giants, hunters)
	if scary and animal.State ~= "Flee" then
		local away = Geo.Flat(animal.Position - scary)
		animal.Heading = math.atan2(away.X, away.Z) + (math.random() - 0.5) * 0.6
		animal.State, animal.Timer = "Flee", 3 + math.random() * 2
	end
	if animal.Timer <= 0 then
		if animal.State == "Flee" then
			-- Out of sight now: gone, to turn up somewhere else.
			animal.State, animal.Timer = "Away", 4 + math.random() * 6
			setVisible(animal, false)
			return
		elseif animal.State == "Graze" then
			animal.State, animal.Timer = "Walk", 1.5 + math.random() * 2.5
			animal.Heading += (math.random() - 0.5) * 2
		else
			animal.State, animal.Timer = "Graze", 3 + math.random() * 6
		end
	end
	local fast = if animal.Kind == "Deer" then C.DeerSpeed else C.RabbitSpeed
	local target = if animal.State == "Flee" then fast elseif animal.State == "Walk" then fast * 0.12 else 0
	animal.Speed += (target - animal.Speed) * math.min(dt * 4, 1)
	animal.Graze += ((if animal.State == "Graze" then 1 else 0) - animal.Graze) * math.min(dt * 3, 1)
	if animal.Speed > 0.05 then
		local forward = Vector3.new(math.sin(animal.Heading), 0, math.cos(animal.Heading))
		local nextPos = animal.Position + forward * animal.Speed * dt
		local now = os.clock()
		if now >= animal.NextGround then
			animal.NextGround = now + 0.25
			local ground = meadowAt(nextPos.X + forward.X * 4, nextPos.Z + forward.Z * 4)
			if ground then
				nextPos = Vector3.new(nextPos.X, ground.Y, nextPos.Z)
			elseif animal.State ~= "Flee" then
				animal.Heading += math.pi -- no grass ahead: turn round
				nextPos = animal.Position
			end
		end
		animal.Position = nextPos
		animal.Hop += dt * (if animal.Kind == "Rabbit" then 9 else 7) * math.clamp(animal.Speed / 6, 0.5, 2)
	end
	local lift = 0
	if animal.Speed > 1 then
		lift = math.abs(math.sin(animal.Hop)) * (if animal.Kind == "Rabbit" then 0.9 else 0.5)
	end
	local body = CFrame.new(animal.Position + Vector3.new(0, lift, 0)) * CFrame.Angles(0, animal.Heading, 0)
	for _, p in animal.Pieces do
		local offset = p.Offset
		if p.Head and animal.Graze > 0.01 then
			-- Nibbling: the head goes down (and bobs a little).
			local drop = animal.Graze * (if animal.Kind == "Deer" then 2.6 else 0.45)
			offset = CFrame.new(0, -drop + math.sin(os.clock() * 5 + animal.Hop) * 0.08 * animal.Graze, 0.3 * animal.Graze) * offset
		end
		table.insert(parts, p.Part)
		table.insert(frames, body * offset)
	end
end

-- === Fireflies ===============================================================

-- Under the trees (something solid overhead) or by the river.
local function fireflySpot(camera: Vector3): Vector3?
	for _ = 1, 8 do
		local angle = math.random() * math.pi * 2
		local distance = 30 + math.random() * 120
		local x, z = camera.X + math.sin(angle) * distance, camera.Z + math.cos(angle) * distance
		local riverside = Geo.InRiver(x, z, 40) and not Geo.InRiver(x, z, 2)
		local down = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -520, 0), rayParams)
		if down and down.Material ~= Enum.Material.Water then
			local ground = down.Position
			if not down.Instance:IsA("Terrain") then
				-- A canopy (or a roof): find the ground below it.
				local below = Workspace:Raycast(ground - Vector3.new(0, 1, 0), Vector3.new(0, -260, 0), rayParams)
				if below and below.Instance:IsA("Terrain") and below.Material ~= Enum.Material.Water and ground.Y - below.Position.Y > 12 and Geo.RadiusOf(ground) > W.WallRadius + W.WallThickness then
					return below.Position
				end
			elseif riverside then
				return ground
			end
		end
	end
	return nil
end

local function stepSwarm(swarm: Swarm, dt: number, clock: number, camera: Vector3, dark: boolean, parts: { BasePart }, frames: { CFrame }, blink: boolean)
	local centre = swarm.Centre
	if not centre then
		swarm.Timer -= dt
		if dark and swarm.Timer <= 0 then
			swarm.Centre = fireflySpot(camera)
			swarm.Timer = 5
			if swarm.Centre then
				for _, fly in swarm.Flies do
					fly.Base = Vector3.new((math.random() - 0.5) * 18, 1 + math.random() * 4, (math.random() - 0.5) * 18)
					fly.Part.Transparency = 0.2
				end
				if swarm.Light then
					swarm.Light.Enabled = true
				end
			end
		end
		return
	end
	if not dark or Geo.Flat(centre - camera).Magnitude > 220 then
		swarm.Centre = nil
		swarm.Timer = 3 + math.random() * 4
		for _, fly in swarm.Flies do
			fly.Part.Transparency = 1
		end
		if swarm.Light then
			swarm.Light.Enabled = false
		end
		return
	end
	for _, fly in swarm.Flies do
		local r = fly.Rates
		local p = centre + fly.Base + Vector3.new(math.sin(clock * r.X + fly.Phase) * 2.5, math.sin(clock * r.Y + fly.Phase * 2) * 1.2, math.cos(clock * r.Z + fly.Phase) * 2.5)
		table.insert(parts, fly.Part)
		table.insert(frames, CFrame.new(p))
		if blink then
			fly.Part.Transparency = if math.sin(clock * (r.X + 1.3) + fly.Phase * 3) > 0.2 then 0.1 else 0.9
		end
	end
	if swarm.Light then
		local lightPart = swarm.Light.Parent :: BasePart
		table.insert(parts, lightPart)
		table.insert(frames, CFrame.new(centre + Vector3.new(0, 3, 0)))
	end
end

function Wildlife.Init()
	folder = Instance.new("Folder")
	folder.Name = "Wildlife"
	folder.Parent = Workspace
	rayParams.FilterDescendantsInstances = { folder }
	local low = SkyController.LowEnd()
	local scale = if low then C.LowEndScale else 1

	for _ = 1, math.max(math.floor(C.Deer * scale), 1) do
		table.insert(animals, makeDeer())
	end
	for _ = 1, math.max(math.floor(C.Rabbits * scale), 1) do
		table.insert(animals, makeRabbit())
	end
	local perSwarm = math.max(math.floor(C.Fireflies * scale / C.FireflySwarms), 3)
	for _ = 1, C.FireflySwarms do
		local swarm: Swarm = { Flies = {}, Centre = nil, Light = nil, Timer = math.random() * 3 }
		for _ = 1, perSwarm do
			local p = piece(Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(220, 255, 120), Enum.PartType.Ball, Enum.Material.Neon)
			table.insert(swarm.Flies, { Part = p, Base = Vector3.zero, Phase = math.random() * 6, Rates = Vector3.new(0.4 + math.random() * 0.6, 0.6 + math.random() * 0.8, 0.4 + math.random() * 0.6) })
		end
		if not low then
			local holder = piece(Vector3.new(0.2, 0.2, 0.2), Color3.new(0, 0, 0))
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(200, 255, 120)
			glow.Range = 10
			glow.Brightness = 0.6
			glow.Enabled = false
			glow.Parent = holder
			swarm.Light = glow
		end
		table.insert(swarms, swarm)
	end

	local clock = 0
	local nextScan = 0
	local nextBlink = 0
	local giants: { Vector3 } = {}
	local hunters: { Vector3 } = {}
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local here = camera.CFrame.Position
		if clock >= nextScan then
			nextScan = clock + 0.25
			giants, hunters = {}, {}
			for _, giant in CollectionService:GetTagged(Config.Tags.Giant) do
				local root = giant:FindFirstChild("Root")
				if root and root:IsA("BasePart") then
					table.insert(giants, root.Position)
				end
			end
			for _, other in Players:GetPlayers() do
				local character = other.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					table.insert(hunters, root.Position)
				end
			end
		end
		local parts: { BasePart } = {}
		local frames: { CFrame } = {}
		for _, animal in animals do
			stepAnimal(animal, dt, here, giants, hunters, parts, frames)
		end
		local dark = night()
		local blink = clock >= nextBlink
		if blink then
			nextBlink = clock + 0.1
		end
		for _, swarm in swarms do
			stepSwarm(swarm, dt, clock, here, dark, parts, frames, blink)
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return Wildlife
