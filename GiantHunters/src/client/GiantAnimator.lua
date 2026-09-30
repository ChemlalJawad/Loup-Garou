--!strict
-- Animates every giant on this client only:
--   * a heavy, lumbering walk: hips and shoulders swing, knees and elbows
--     bend on the right part of the stride, the trunk sways and bobs with
--     each step, speed from the real velocity; slow breathing when idle;
--   * the grab: the trunk lunges and both arms swing up and forward (the
--     warning);
--   * the stare: the head turns to follow the nearest hunter. Unnerving,
--     in a cartoon way.
-- Motor6D.Transform isn't replicated, so this costs the network nothing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local GiantAnimator = {}

type Animated = {
	Model: Model,
	Root: BasePart,
	Motors: { [string]: Motor6D },
	Phase: number,
	Breath: number,
	Reach: number, -- 0..1, eased toward the grab pose
	Look: CFrame, -- current head turn, eased
}

local animated: { [Model]: Animated } = {}
local VISIBLE_DISTANCE = 700
local STARE_DISTANCE = 120

local function add(instance: Instance)
	if not instance:IsA("Model") or animated[instance] then
		return
	end
	local root = instance:WaitForChild("Root", 5)
	if not root or not root:IsA("BasePart") then
		return
	end
	local motors: { [string]: Motor6D } = {}
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Motor6D") then
			motors[descendant.Name] = descendant
		end
	end
	animated[instance] = { Model = instance, Root = root, Motors = motors, Phase = math.random() * 6, Breath = math.random() * 6, Reach = 0, Look = CFrame.new() }
end

local function set(motors: { [string]: Motor6D }, name: string, transform: CFrame)
	local m = motors[name]
	if m then
		m.Transform = transform
	end
end

function GiantAnimator.Init()
	local tag = Config.Tags.Giant
	for _, giant in CollectionService:GetTagged(tag) do
		task.spawn(add, giant)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(giant)
		task.spawn(add, giant)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(giant)
		animated[giant :: Model] = nil
	end)

	local player = Players.LocalPlayer
	RunService.RenderStepped:Connect(function(dt: number)
		local character = player.Character
		local here = character and character:FindFirstChild("HumanoidRootPart")
		local herePosition = if here and here:IsA("BasePart") then here.Position else nil
		for model, giant in animated do
			if not model.Parent then
				animated[model] = nil
				continue
			end
			if model:GetAttribute("Defeated") then
				continue
			end
			if herePosition and (giant.Root.Position - herePosition).Magnitude > VISIBLE_DISTANCE then
				continue
			end
			local height = (model:GetAttribute("Height") :: number?) or 20
			local velocity = giant.Root.AssemblyLinearVelocity
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			giant.Phase += dt * speed / (height * 0.11) -- longer legs, slower steps
			local stride = math.clamp(speed / 6, 0, 1)
			local s = math.sin(giant.Phase)
			local swing = s * 0.5 * stride

			local wantReach = if model:GetAttribute("Grabbing") then 1 else 0
			giant.Reach += (wantReach - giant.Reach) * math.min(dt * 6, 1)
			local reach = giant.Reach

			local motors = giant.Motors
			-- Trunk (on top of the slouch baked into the rig): sways and
			-- rises over each step, breathes, lunges into a grab.
			giant.Breath += dt * 1.4
			local bob = math.abs(math.cos(giant.Phase)) * height * 0.012 * stride
			local lean = math.sin(giant.Breath) * 0.02 - reach * 0.22
			set(motors, "Waist", CFrame.new(0, bob, 0) * CFrame.Angles(lean, s * 0.06 * stride, s * 0.05 * stride))
			-- Legs: the knee bends while that leg swings forward.
			set(motors, "LeftHip", CFrame.Angles(swing, 0, 0))
			set(motors, "RightHip", CFrame.Angles(-swing, 0, 0))
			set(motors, "LeftKnee", CFrame.Angles(-math.max(s, 0) * 0.7 * stride, 0, 0))
			set(motors, "RightKnee", CFrame.Angles(-math.max(-s, 0) * 0.7 * stride, 0, 0))
			-- Arms: swing opposite the legs, elbows loosely bent; the grab
			-- lifts both straight out in front.
			local lift = reach * 1.45
			set(motors, "LeftShoulder", CFrame.Angles(-swing * 0.8 * (1 - reach) + lift, 0, -0.08 - reach * 0.25))
			set(motors, "RightShoulder", CFrame.Angles(swing * 0.8 * (1 - reach) + lift, 0, 0.08 + reach * 0.25))
			local elbowBend = (0.25 + math.abs(s) * 0.2 * stride) * (1 - reach)
			set(motors, "LeftElbow", CFrame.Angles(elbowBend, 0, 0))
			set(motors, "RightElbow", CFrame.Angles(elbowBend, 0, 0))

			-- Head: stare at you if you're close, otherwise look ahead.
			local want = CFrame.new()
			if herePosition and (herePosition - giant.Root.Position).Magnitude < STARE_DISTANCE then
				local headWorld = giant.Root.CFrame * CFrame.new(0, height * 0.5, 0)
				local localDir = headWorld:VectorToObjectSpace((herePosition - headWorld.Position).Unit)
				local yaw = math.clamp(math.atan2(-localDir.X, -localDir.Z), -1.1, 1.1)
				local pitch = math.clamp(math.asin(math.clamp(localDir.Y, -1, 1)), -0.6, 0.5)
				want = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
			end
			giant.Look = giant.Look:Lerp(want, math.min(dt * 3, 1))
			set(motors, "Neck", giant.Look)
		end
	end)
end

return GiantAnimator
