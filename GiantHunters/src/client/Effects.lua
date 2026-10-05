--!strict
-- Client-side effects: camera shake, sounds, bursts of steam and sparks
-- where a cut lands, dust and a felt thud under giants' footsteps, and
-- spinning things (windmill sails), stomp rings and crumbling walls under
-- climbing giants. Nothing here replicates, so it costs the
-- network nothing. Shake follows the "Screen shake" setting.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Settings = require(script.Parent.Settings)

local Effects = {}

local shake = 0

function Effects.Shake(strength: number)
	shake = math.max(shake, strength * ((Settings.Get("Shake") :: number?) or 1))
end

local stepFx: ((BasePart, number) -> ())? = nil

-- Plays one of Config.Sounds: flat (no `at`), or out in the world at a part
-- or a position.
function Effects.Play(name: string, at: (BasePart | Vector3)?, volume: number?, pitch: number?)
	local def = (Config.Sounds :: any)[name]
	if not def or def.Id == "" then
		return
	end
	-- A little variety every time: nothing sounds like a loop.
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume * (volume or 1) * (0.9 + math.random() * 0.2)
	sound.PlaybackSpeed = def.Pitch * (pitch or 1) * (0.94 + math.random() * 0.12)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 20
	sound.RollOffMaxDistance = 600
	if name == "Step" and stepFx and typeof(at) == "Instance" and at:IsA("BasePart") then
		-- A giant's footstep (GiantAnimator): bigger giants carry further.
		local height = (at.Parent and (at.Parent:GetAttribute("Height") :: number?)) or 20
		sound.RollOffMinDistance = height
		sound.RollOffMaxDistance = height * 18
		stepFx(at, height)
	end
	if typeof(at) == "Vector3" then
		local spot = Instance.new("Attachment")
		spot.WorldPosition = at
		spot.Parent = Workspace.Terrain
		sound.Parent = spot
		Debris:AddItem(spot, 5)
	elseif typeof(at) == "Instance" then
		sound.Parent = at
		Debris:AddItem(sound, 5)
	else
		sound.Parent = SoundService
		Debris:AddItem(sound, 5)
	end
	sound:Play()
end

-- A puff of particles at a point (steam on a nape, sparks on armour...).
function Effects.Burst(position: Vector3, color: Color3, size: number, amount: number)
	local spot = Instance.new("Attachment")
	spot.WorldPosition = position
	spot.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Speed = NumberRange.new(size * 2, size * 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.4
	emitter.Rate = 0
	emitter.Parent = spot
	emitter:Emit(amount)
	Debris:AddItem(spot, 2)
end

-- Pooled steam-and-spark rigs for the nape: a big puff of steam, a ring of
-- sparks flung out flat, a flash of light, and a bright ring that widens.
type BurstRig = { Spot: Attachment, Steam: ParticleEmitter, Sparks: ParticleEmitter, Light: PointLight, Ring: Part }
local rigs: { BurstRig } = {}
local nextRig = 1

local function makeRig(): BurstRig
	local spot = Instance.new("Attachment")
	spot.Name = "NapeBurst"
	spot.Parent = Workspace.Terrain
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Color3.fromRGB(246, 246, 250))
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(0.8, 1.6)
	steam.Drag = 3
	steam.Acceleration = Vector3.new(0, 6, 0)
	steam.SpreadAngle = Vector2.new(180, 180)
	steam.RotSpeed = NumberRange.new(-60, 60)
	steam.Rotation = NumberRange.new(0, 360)
	steam.LightEmission = 0.3
	steam.Rate = 0
	steam.Parent = spot
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 190, 90))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.2, 0.45)
	sparks.Drag = 4
	sparks.Acceleration = Vector3.new(0, -30, 0)
	-- Flung out round the attachment's up axis: a flat ring of sparks.
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.SpreadAngle = Vector2.new(90, 90)
	sparks.Squash = NumberSequence.new(-1.5)
	sparks.Rate = 0
	sparks.Parent = spot
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 235, 255)
	light.Brightness = 0
	light.Range = 16
	light.Parent = spot
	local ring = Instance.new("Part")
	ring.Name = "SparkRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(220, 245, 255)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 1
	ring.Size = Vector3.new(0.05, 1, 1)
	ring.Parent = Workspace.Terrain
	return { Spot = spot, Steam = steam, Sparks = sparks, Light = light, Ring = ring }
end

-- The big burst where a cut lands. `power` ~1 for a hit, ~2 for a clean
-- takedown.
function Effects.NapeBurst(position: Vector3, power: number, color: Color3?)
	local rig = rigs[nextRig]
	if not rig then
		rig = makeRig()
		rigs[nextRig] = rig
	end
	nextRig = nextRig % Config.Feel.MaxBursts + 1
	local camera = Workspace.CurrentCamera
	-- Face the camera, so the ring and the spark spray read as a ring.
	local facing = CFrame.lookAt(position, camera.CFrame.Position)
	rig.Spot.WorldCFrame = facing * CFrame.Angles(-math.pi / 2, 0, 0)
	local size = 2 + power * 1.5
	rig.Steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 1.6) })
	rig.Steam.Speed = NumberRange.new(size * 2, size * 5)
	rig.Steam.Color = ColorSequence.new(color or Color3.fromRGB(246, 246, 250))
	rig.Steam:Emit(math.floor(10 + power * 10))
	rig.Sparks.Speed = NumberRange.new(30 + power * 15, 50 + power * 25)
	rig.Sparks:Emit(math.floor(12 + power * 10))
	rig.Light.Brightness = 3 * power
	TweenService:Create(rig.Light, TweenInfo.new(0.25), { Brightness = 0 }):Play()
	local ring = rig.Ring
	ring.CFrame = facing * CFrame.Angles(0, math.pi / 2, 0)
	ring.Size = Vector3.new(0.05, 1, 1)
	ring.Transparency = 0.05
	local wide = 6 + power * 5
	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, wide, wide), Transparency = 1 }):Play()
end

-- Dust thrown up where a giant's foot comes down, and the ground shaking
-- under you by its size and how close you are.
local dust: { Attachment } = {}
local nextDust = 1
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function footstep(root: BasePart, height: number)
	local camera = Workspace.CurrentCamera
	local distance = (camera.CFrame.Position - root.Position).Magnitude
	local reach = height * Config.Feel.StepReach
	if distance < reach then
		local falloff = 1 - distance / reach
		Effects.Shake(Config.Feel.StepShake * (height / 46) * falloff * falloff)
	end
	if distance > Config.Feel.StepDustRange then
		return
	end
	local model = root.Parent
	groundParams.FilterDescendantsInstances = if model then { model } else {}
	local ground = Workspace:Raycast(root.Position, Vector3.new(0, -height, 0), groundParams)
	if not ground then
		return
	end
	local spot: Attachment = dust[nextDust]
	if not spot then
		local created = Instance.new("Attachment")
		created.Name = "StepDust"
		created.Parent = Workspace.Terrain
		local puff = Instance.new("ParticleEmitter")
		puff.Name = "Puff"
		puff.Color = ColorSequence.new(Color3.fromRGB(196, 182, 160))
		puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		puff.Lifetime = NumberRange.new(0.7, 1.3)
		puff.Drag = 2.5
		puff.EmissionDirection = Enum.NormalId.Top
		puff.SpreadAngle = Vector2.new(80, 80)
		puff.Rotation = NumberRange.new(0, 360)
		puff.Rate = 0
		puff.Parent = created
		dust[nextDust] = created
		spot = created
	end
	nextDust = nextDust % 8 + 1
	local puff = spot:FindFirstChild("Puff") :: ParticleEmitter
	-- Stone and grass throw up different dust.
	puff.Color = ColorSequence.new(if ground.Material == Enum.Material.Grass or ground.Material == Enum.Material.LeafyGrass then Color3.fromRGB(170, 160, 120) else Color3.fromRGB(196, 182, 160))
	local size = math.clamp(height / 10, 1.2, 6)
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 1.8) })
	puff.Speed = NumberRange.new(size * 1.5, size * 3)
	spot.WorldPosition = ground.Position
	puff:Emit(math.floor(math.clamp(height / 6, 3, 10)))
end

-- A giant's stomp (or the Wallbreaker's kick landing): a flat ring of dust
-- thrown out along the ground round the foot, a widening ring, a boom, and
-- a hard shake by size and distance.
function Effects.Stomp(foot: BasePart, height: number)
	local camera = Workspace.CurrentCamera
	local model = foot.Parent
	groundParams.FilterDescendantsInstances = if model then { model } else {}
	local ground = Workspace:Raycast(foot.Position, Vector3.new(0, -height * 0.4, 0), groundParams)
	local at = if ground then ground.Position else foot.Position
	local distance = (camera.CFrame.Position - at).Magnitude
	local reach = height * Config.Feel.StepReach
	if distance < reach then
		local falloff = 1 - distance / reach
		Effects.Shake(Config.Feel.StepShake * 3 * (height / 46) * falloff)
	end
	Effects.Play("Boom", at, math.clamp(height / 46, 0.4, 1.2), 0.9)
	if distance > Config.Feel.StepDustRange * 1.5 then
		return
	end
	local size = math.clamp(height / 8, 1.5, 8)
	local spot = Instance.new("Attachment")
	spot.WorldPosition = at
	spot.Parent = Workspace.Terrain
	local puff = Instance.new("ParticleEmitter")
	puff.Color = ColorSequence.new(if ground and (ground.Material == Enum.Material.Grass or ground.Material == Enum.Material.LeafyGrass) then Color3.fromRGB(170, 160, 120) else Color3.fromRGB(196, 182, 160))
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, size * 2.2) })
	puff.Lifetime = NumberRange.new(0.8, 1.5)
	puff.Speed = NumberRange.new(size * 5, size * 9)
	puff.Drag = 3
	puff.Rotation = NumberRange.new(0, 360)
	-- Flung out round the up axis, close to the ground: a ring.
	puff.EmissionDirection = Enum.NormalId.Top
	puff.SpreadAngle = Vector2.new(85, 85)
	puff.Acceleration = Vector3.new(0, size * 0.6, 0)
	puff.Rate = 0
	puff.Parent = spot
	puff:Emit(math.floor(math.clamp(height / 2, 12, 36)))
	Debris:AddItem(spot, 2)
	local ring = Instance.new("Part")
	ring.Name = "StompRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Color3.fromRGB(210, 196, 170)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.3, size, size)
	ring.CFrame = CFrame.new(at + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = Workspace.Terrain
	local wide = height * 0.9
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, wide, wide), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.7)
end

-- Bits of wall crumbling where a climbing giant grabs on.
function Effects.Crumble(position: Vector3, size: number)
	local camera = Workspace.CurrentCamera
	if (camera.CFrame.Position - position).Magnitude > Config.Feel.StepDustRange then
		return
	end
	local spot = Instance.new("Attachment")
	spot.WorldPosition = position
	spot.Parent = Workspace.Terrain
	local bits = Instance.new("ParticleEmitter")
	bits.Color = ColorSequence.new(Color3.fromRGB(150, 140, 128))
	bits.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.35), NumberSequenceKeypoint.new(1, size * 0.15) })
	bits.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) })
	bits.Lifetime = NumberRange.new(0.8, 1.4)
	bits.Speed = NumberRange.new(size * 2, size * 5)
	bits.SpreadAngle = Vector2.new(70, 70)
	bits.Acceleration = Vector3.new(0, -60, 0)
	bits.Rotation = NumberRange.new(0, 360)
	bits.RotSpeed = NumberRange.new(-180, 180)
	bits.Rate = 0
	bits.Parent = spot
	bits:Emit(8)
	Effects.Burst(position, Color3.fromRGB(196, 186, 170), size, 6)
	Debris:AddItem(spot, 2)
end

function Effects.Init()
	stepFx = footstep
	local camera = Workspace.CurrentCamera
	-- Shake: small random turns after the camera has moved, decaying fast.
	RunService:BindToRenderStep("GiantHuntersShake", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		if shake > 0.01 then
			local amount = shake * 0.025
			camera.CFrame *= CFrame.Angles((math.random() * 2 - 1) * amount, (math.random() * 2 - 1) * amount, 0)
			shake *= math.exp(-dt * 5)
		end
	end)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local shakeRemote = remotes:WaitForChild(Config.Remotes.Shake) :: RemoteEvent
	shakeRemote.OnClientEvent:Connect(function(origin: Vector3, strength: number)
		local distance = (camera.CFrame.Position - origin).Magnitude
		Effects.Shake(strength * math.clamp(1 - distance / 700, 0, 1))
	end)

	-- Spinning models (windmill sails) turn round their pivot's X axis.
	local spinning: { [Model]: { Base: CFrame, Speed: number } } = {}
	local function add(instance: Instance)
		if instance:IsA("Model") and not spinning[instance] then
			spinning[instance] = { Base = instance:GetPivot(), Speed = (instance:GetAttribute("Speed") :: number?) or 0.5 }
		end
	end
	for _, model in CollectionService:GetTagged(Config.Tags.Spin) do
		add(model)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Spin):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.Spin):Connect(function(model)
		spinning[model :: Model] = nil
	end)
	local clock = 0
	RunService.RenderStepped:Connect(function(dt: number)
		clock += dt
		for model, spin in spinning do
			if model.Parent then
				model:PivotTo(spin.Base * CFrame.Angles(clock * spin.Speed, 0, 0))
			end
		end
	end)
end

return Effects
