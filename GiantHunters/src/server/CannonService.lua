--!strict
-- Wall cannons, on the wall either side of the south gate. Walk up to one
-- and fire: it swings round to the nearest giant in range and lobs a ball
-- at its head. No harm done, but the giant is dazed for a few seconds and
-- drops anyone it was holding.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GiantService = require(script.Parent.GiantService)
local Broadcast = require(script.Parent.Broadcast)

local CannonService = {}

local RANGE = 420
local COOLDOWN = 8
local FLIGHT = 0.9

local function smoke(at: CFrame)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = at
	holder.Parent = Workspace
	local puff = Instance.new("ParticleEmitter")
	puff.Color = ColorSequence.new(Color3.fromRGB(220, 215, 205))
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	puff.Lifetime = NumberRange.new(1, 1.8)
	puff.Speed = NumberRange.new(6, 14)
	puff.SpreadAngle = Vector2.new(25, 25)
	puff.Rate = 0
	puff.Parent = holder
	puff:Emit(30)
	local sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.Boom.Id
	sound.Volume = Config.Sounds.Boom.Volume
	sound.PlaybackSpeed = Config.Sounds.Boom.Pitch
	sound.RollOffMaxDistance = 600
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 3)
end

local function fire(cannon: Model, prompt: ProximityPrompt, player: Player)
	local barrel = cannon:FindFirstChild("Barrel")
	if not barrel or not barrel:IsA("BasePart") then
		return
	end
	local target, head = GiantService.CannonTarget(barrel.Position, RANGE)
	if not target or not head then
		Broadcast.Feed("No giant in range of this cannon", "Info", player)
		return
	end
	prompt.Enabled = false
	task.delay(COOLDOWN, function()
		prompt.Enabled = true
	end)
	-- Swing round to face it: the barrel points along the cannon's local +Z.
	local pivot = cannon:GetPivot()
	local flat = Vector3.new(head.Position.X - pivot.Position.X, 0, head.Position.Z - pivot.Position.Z)
	if flat.Magnitude > 1 then
		cannon:PivotTo(CFrame.lookAt(pivot.Position, pivot.Position - flat.Unit))
	end
	local muzzle = barrel.CFrame * CFrame.new(4.4, 0, 0) -- along the barrel's axis
	smoke(muzzle)

	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 2.4
	ball.Color = Color3.fromRGB(40, 40, 46)
	ball.Material = Enum.Material.Metal
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CFrame = muzzle
	ball.Parent = Workspace
	local from = muzzle.Position
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.min((os.clock() - start) / FLIGHT, 1)
		local to = head.Position
		local apex = (from + to) / 2 + Vector3.new(0, 30, 0)
		ball.Position = from:Lerp(apex, t):Lerp(apex:Lerp(to, t), t)
		if t >= 1 then
			connection:Disconnect()
			ball:Destroy()
			GiantService.CannonHit(target, player)
			Broadcast.Shake(to, 0.8)
		end
	end)
end

local function wire(cannon: Instance)
	if not cannon:IsA("Model") then
		return
	end
	local barrel = cannon:FindFirstChild("Barrel")
	if not barrel or not barrel:IsA("BasePart") or barrel:FindFirstChildOfClass("ProximityPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Fire!"
	prompt.ObjectText = "Wall cannon"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = barrel
	prompt.Triggered:Connect(function(player)
		fire(cannon, prompt, player)
	end)
end

function CannonService.Init()
	for _, cannon in CollectionService:GetTagged(Config.Tags.Cannon) do
		wire(cannon)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Cannon):Connect(wire)
end

return CannonService
