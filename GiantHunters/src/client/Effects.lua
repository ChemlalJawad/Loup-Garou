--!strict
-- Client-side effects: camera shake, sounds, bursts of steam and sparks
-- where a cut lands, and spinning things (windmill sails). Nothing here
-- replicates, so it costs the network nothing.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Effects = {}

local shake = 0

function Effects.Shake(strength: number)
	shake = math.max(shake, strength)
end

-- Plays one of Config.Sounds: flat (no `at`), or out in the world at a part
-- or a position.
function Effects.Play(name: string, at: (BasePart | Vector3)?, volume: number?, pitch: number?)
	local def = (Config.Sounds :: any)[name]
	if not def or def.Id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume * (volume or 1)
	sound.PlaybackSpeed = def.Pitch * (pitch or 1)
	sound.RollOffMaxDistance = 600
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

function Effects.Init()
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
