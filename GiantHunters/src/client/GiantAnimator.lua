--!strict
-- Animates every giant on this client only: a lumbering walk cycle driven
-- by how fast it's actually moving, and arms raised forward while it winds
-- up a grab (the "get out of there!" warning). Motor6D.Transform isn't
-- replicated, so this costs the network nothing.

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
	Reach: number, -- 0..1, eased toward the grab pose
}

local animated: { [Model]: Animated } = {}
local VISIBLE_DISTANCE = 700

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
	animated[instance] = { Model = instance, Root = root, Motors = motors, Phase = math.random() * 6, Reach = 0 }
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
			-- Longer legs take slower steps.
			giant.Phase += dt * speed / (height * 0.12)
			local stride = math.clamp(speed / 6, 0, 1) * 0.55
			local swing = math.sin(giant.Phase) * stride

			local wantReach = if model:GetAttribute("Grabbing") then 1 else 0
			giant.Reach += (wantReach - giant.Reach) * math.min(dt * 6, 1)

			local motors = giant.Motors
			if motors.LeftHip then
				motors.LeftHip.Transform = CFrame.Angles(swing, 0, 0)
			end
			if motors.RightHip then
				motors.RightHip.Transform = CFrame.Angles(-swing, 0, 0)
			end
			-- Arms swing opposite to the legs, and lift forward to grab.
			local lift = giant.Reach * 1.5
			if motors.LeftShoulder then
				motors.LeftShoulder.Transform = CFrame.Angles(-swing * (1 - giant.Reach) + lift, 0, -0.1 - giant.Reach * 0.2)
			end
			if motors.RightShoulder then
				motors.RightShoulder.Transform = CFrame.Angles(swing * (1 - giant.Reach) + lift, 0, 0.1 + giant.Reach * 0.2)
			end
		end
	end)
end

return GiantAnimator
