--!strict
-- Animates every giant on this client only, from the attributes the
-- server sets:
--   * a heavy, lumbering walk: hips and shoulders swing, knees and elbows
--     bend, the trunk sways and bobs, footsteps thud (and shake the ground
--     under the big ones); slow breathing when idle. Runners flail;
--   * Grabbing: the trunk lunges and both arms swing up and out (the
--     warning); Holding: one hand holds you up in front of its face;
--   * Swat: one arm winds up out to the side, then sweeps across;
--   * Kneeling (ankle cut): down on its knees, hands forward;
--   * Dazed (eyes, cannonball): hands to its face, head wobbling, stars;
--   * Leap (runners): legs tucked; Kick (the Wallbreaker): one big kick;
--   * the stare: the head turns to follow the nearest hunter.
-- Motor6D.Transform isn't replicated, so all of this is free network-wise.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Parent.Effects)

local GiantAnimator = {}

type Animated = {
	Model: Model,
	Root: BasePart,
	Head: BasePart?,
	Motors: { [string]: Motor6D },
	Height: number,
	Abnormal: boolean,
	Phase: number,
	Breath: number,
	Look: CFrame,
	Reach: number,
	Hold: number,
	Kneel: number,
	Daze: number,
	Kick: number,
	Leap: number,
	SwatRaise: number,
	SwatSide: number,
	LastSwat: string,
	SwingTimer: number,
	Swing: number,
	LastStep: number,
	Stars: { BasePart }?,
}

type Arm = { X: number, Z: number, Elbow: number, Side: number }

local animated: { [Model]: Animated } = {}
local VISIBLE_DISTANCE = 800
local STARE_DISTANCE = 140

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
	local head = instance:FindFirstChild("Head")
	animated[instance] = {
		Model = instance,
		Root = root,
		Head = if head and head:IsA("BasePart") then head else nil,
		Motors = motors,
		Height = (instance:GetAttribute("Height") :: number?) or 20,
		Abnormal = instance:GetAttribute("Abnormal") == true,
		Phase = math.random() * 6,
		Breath = math.random() * 6,
		Look = CFrame.new(),
		Reach = 0,
		Hold = 0,
		Kneel = 0,
		Daze = 0,
		Kick = 0,
		Leap = 0,
		SwatRaise = 0,
		SwatSide = 1,
		LastSwat = "",
		SwingTimer = 0,
		Swing = 0,
		LastStep = 0,
		Stars = nil,
	}
end

local function set(motors: { [string]: Motor6D }, name: string, transform: CFrame)
	local m = motors[name]
	if m then
		m.Transform = transform
	end
end

local function ease(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * math.min(dt * rate, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Little gold stars circling a dazed giant's head.
local function updateStars(giant: Animated, on: boolean, t: number)
	local head = giant.Head
	if on and head and not giant.Stars then
		local stars: { BasePart } = {}
		for i = 1, 4 do
			local star = Instance.new("Part")
			star.Name = "DazeStar"
			star.Shape = Enum.PartType.Ball
			star.Size = Vector3.one * math.max(giant.Height * 0.04, 1)
			star.Color = Color3.fromRGB(255, 220, 80)
			star.Material = Enum.Material.Neon
			star.Anchored = true
			star.CanCollide = false
			star.CanQuery = false
			star.CanTouch = false
			star.CastShadow = false
			star.Parent = Workspace
			stars[i] = star
		end
		giant.Stars = stars
	elseif not on and giant.Stars then
		for _, star in giant.Stars :: { BasePart } do
			star:Destroy()
		end
		giant.Stars = nil
	end
	if giant.Stars and head then
		local radius = head.Size.X * 0.75
		for i, star in giant.Stars :: { BasePart } do
			local a = t * 3 + i * math.pi / 2
			star.Position = head.Position + Vector3.new(math.cos(a) * radius, head.Size.X * 0.75, math.sin(a) * radius)
		end
	end
end

export type PoseInput = {
	Height: number,
	Abnormal: boolean,
	Phase: number, -- walk cycle
	Stride: number, -- 0 standing .. 1 full stride
	Breath: number,
	Time: number,
	Reach: number, -- the weights below ease between 0 and 1
	Hold: number,
	Kneel: number,
	Daze: number,
	Kick: number,
	Leap: number,
	SwatRaise: number,
	SwatSide: number, -- -1 left arm, 1 right arm
	Swing: number,
	Look: CFrame, -- where the head is turned
}

-- The whole pose from a giant's state, as Motor6D transforms by motor name.
-- Pure (no instances), so it can be checked outside Roblox.
function GiantAnimator.Pose(p: PoseInput): { [string]: CFrame }
	local pose: { [string]: CFrame } = {}
	local reach, hold, kneel, daze, kick, leap = p.Reach, p.Hold, p.Kneel, p.Daze, p.Kick, p.Leap
	local stride, t = p.Stride, p.Time
	local s = math.sin(p.Phase)
	local swing = s * (if p.Abnormal then 0.75 else 0.5) * stride

	-- Trunk: the slouch is baked into the rig; this sways, bobs, breathes,
	-- lunges, and hunches further for runners and stumbles.
	local bob = math.abs(math.cos(p.Phase)) * p.Height * 0.012 * stride
	local lean = math.sin(p.Breath) * 0.02 - reach * 0.22 - kneel * 0.35 + hold * 0.08 - leap * 0.2 + kick * 0.15
	if p.Abnormal then
		lean -= 0.3 * stride
	end
	local dazeSway = math.sin(t * 1.7) * 0.12 * daze
	pose.Waist = CFrame.new(0, bob, 0) * CFrame.Angles(lean, s * 0.06 * stride, s * 0.05 * stride + dazeSway)

	-- Legs: knees bend as each leg swings through; kneeling folds the shins
	-- back flat; a leap tucks both legs; the kick swings the right leg up.
	local leftHip, rightHip = swing, -swing
	local leftKnee, rightKnee = -math.max(s, 0) * 0.7 * stride, -math.max(-s, 0) * 0.7 * stride
	leftHip, rightHip = lerp(leftHip, 0.1, kneel), lerp(rightHip, 0.1, kneel)
	leftKnee, rightKnee = lerp(leftKnee, -1.5, kneel), lerp(rightKnee, -1.5, kneel)
	leftHip += 0.6 * leap
	rightHip += 0.6 * leap
	leftKnee -= 1.0 * leap
	rightKnee -= 1.0 * leap
	rightHip = lerp(rightHip, 1.25, kick)
	rightKnee = lerp(rightKnee, -0.15, kick)
	leftKnee = lerp(leftKnee, -0.35, kick)
	pose.LeftHip = CFrame.Angles(leftHip, 0, 0)
	pose.RightHip = CFrame.Angles(rightHip, 0, 0)
	pose.LeftKnee = CFrame.Angles(leftKnee, 0, 0)
	pose.RightKnee = CFrame.Angles(rightKnee, 0, 0)

	-- Arms. Shoulder angles: X swings forward, Z tilts out to the side
	-- (negative on the left, positive on the right).
	local flail = if p.Abnormal then 1.8 else 0.8
	local spread = if p.Abnormal then 0.35 * stride else 0
	local elbow = 0.25 + math.abs(s) * 0.2 * stride
	local arms: { Left: Arm, Right: Arm } = {
		Left = { X = -swing * flail, Z = -0.08 - spread, Elbow = elbow, Side = -1 },
		Right = { X = swing * flail, Z = 0.08 + spread, Elbow = elbow, Side = 1 },
	}
	for _, arm in { arms.Left, arms.Right } do
		local side = arm.Side
		-- Grab: both arms up and out in front.
		arm.X = lerp(arm.X, 1.45, reach)
		arm.Z += side * 0.25 * reach
		arm.Elbow *= 1 - reach
		-- Kneeling: hands forward to catch itself.
		arm.X = lerp(arm.X, 0.75, kneel)
		arm.Elbow = lerp(arm.Elbow, 0.2, kneel)
		-- Swat: wind up out to the side, then sweep across the front.
		if side == p.SwatSide then
			arm.X = lerp(arm.X, 0.5, p.SwatRaise)
			arm.Z = lerp(arm.Z, side * 1.5, p.SwatRaise)
			arm.X = lerp(arm.X, 1.3, p.Swing)
			arm.Z = lerp(arm.Z, -side * 0.6, p.Swing)
		end
		-- Dazed: hands up to its face.
		arm.X = lerp(arm.X, 2.3, daze)
		arm.Z = lerp(arm.Z, -side * 0.35, daze)
		arm.Elbow = lerp(arm.Elbow, 1.9, daze)
		-- Kick: arms out for balance.
		arm.Z += side * 0.6 * kick
	end
	-- Holding: the right hand holds you up in front of its face.
	arms.Right.X = lerp(arms.Right.X, 1.2, hold) + math.sin(t * 22) * 0.04 * hold
	arms.Right.Z = lerp(arms.Right.Z, -0.25, hold)
	arms.Right.Elbow = lerp(arms.Right.Elbow, 0.9, hold)
	arms.Left.X = lerp(arms.Left.X, 0.5, hold)
	pose.LeftShoulder = CFrame.Angles(arms.Left.X, 0, arms.Left.Z)
	pose.RightShoulder = CFrame.Angles(arms.Right.X, 0, arms.Right.Z)
	pose.LeftElbow = CFrame.Angles(arms.Left.Elbow, 0, 0)
	pose.RightElbow = CFrame.Angles(arms.Right.Elbow, 0, 0)

	local wobble = CFrame.Angles(math.sin(t * 2.6) * 0.15 * daze, math.sin(t * 2.3) * 0.35 * daze, math.sin(t * 3.1) * 0.2 * daze)
	pose.Neck = p.Look * wobble
	return pose
end

local function animate(giant: Animated, dt: number, t: number, herePosition: Vector3?)
	local model = giant.Model
	local height = giant.Height
	local velocity = giant.Root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	giant.Reach = ease(giant.Reach, if model:GetAttribute("Grabbing") then 1 else 0, 6, dt)
	giant.Hold = ease(giant.Hold, if model:GetAttribute("Holding") then 1 else 0, 5, dt)
	giant.Kneel = ease(giant.Kneel, if model:GetAttribute("Kneeling") then 1 else 0, 5, dt)
	local dazed = model:GetAttribute("Dazed") == true
	giant.Daze = ease(giant.Daze, if dazed then 1 else 0, 4, dt)
	giant.Kick = ease(giant.Kick, if model:GetAttribute("Kick") then 1 else 0, 7, dt)
	giant.Leap = ease(giant.Leap, if model:GetAttribute("Leap") then 1 else 0, 8, dt)
	local swatAttribute = (model:GetAttribute("Swat") :: string?) or ""
	if swatAttribute ~= "" then
		giant.SwatSide = if swatAttribute == "Right" then 1 else -1
	elseif giant.LastSwat ~= "" then
		giant.SwingTimer = 0.4 -- the wind-up just ended: sweep across
	end
	giant.LastSwat = swatAttribute
	giant.SwatRaise = ease(giant.SwatRaise, if swatAttribute ~= "" then 1 else 0, 8, dt)
	giant.SwingTimer = math.max(giant.SwingTimer - dt, 0)
	giant.Swing = ease(giant.Swing, if giant.SwingTimer > 0 then 1 else 0, 14, dt)
	updateStars(giant, dazed, t)

	-- The walk.
	giant.Phase += dt * speed / (height * (if giant.Abnormal then 0.08 else 0.11))
	local stride = math.clamp(speed / 6, 0, 1)
	local s = math.sin(giant.Phase)

	-- Footsteps: a thud each time a foot comes down.
	local stepSign = if s >= 0 then 1 else -1
	if stepSign ~= giant.LastStep and stride > 0.4 then
		local scale = math.clamp(height / 46, 0.35, 1)
		Effects.Play("Step", giant.Root, scale, math.sqrt(30 / height))
		if herePosition and height >= 40 and (giant.Root.Position - herePosition).Magnitude < 90 then
			Effects.Shake(0.25)
		end
	end
	giant.LastStep = stepSign

	giant.Breath += dt * 1.4

	-- Head: stares at you if you're close; looks down at whoever it's
	-- holding (the wobble when dazed is part of the pose).
	local want = CFrame.new()
	if giant.Hold > 0.5 then
		want = CFrame.Angles(0, 0.2, 0) * CFrame.Angles(-0.3, 0, 0)
	elseif herePosition and (herePosition - giant.Root.Position).Magnitude < STARE_DISTANCE then
		local headWorld = giant.Root.CFrame * CFrame.new(0, height * 0.5, 0)
		local localDir = headWorld:VectorToObjectSpace((herePosition - headWorld.Position).Unit)
		local yaw = math.clamp(math.atan2(-localDir.X, -localDir.Z), -1.1, 1.1)
		local pitch = math.clamp(math.asin(math.clamp(localDir.Y, -1, 1)), -0.6, 0.5)
		want = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	end
	giant.Look = giant.Look:Lerp(want, math.min(dt * 3, 1))

	local pose = GiantAnimator.Pose({
		Height = height,
		Abnormal = giant.Abnormal,
		Phase = giant.Phase,
		Stride = stride,
		Breath = giant.Breath,
		Time = t,
		Reach = giant.Reach,
		Hold = giant.Hold,
		Kneel = giant.Kneel,
		Daze = giant.Daze,
		Kick = giant.Kick,
		Leap = giant.Leap,
		SwatRaise = giant.SwatRaise,
		SwatSide = giant.SwatSide,
		Swing = giant.Swing,
		Look = giant.Look,
	})
	for name, transform in pose do
		set(giant.Motors, name, transform)
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
		local entry = animated[giant :: Model]
		if entry then
			updateStars(entry, false, 0)
		end
		animated[giant :: Model] = nil
	end)

	local player = Players.LocalPlayer
	local clock = 0
	RunService.RenderStepped:Connect(function(dt: number)
		clock += dt
		local character = player.Character
		local here = character and character:FindFirstChild("HumanoidRootPart")
		local herePosition = if here and here:IsA("BasePart") then here.Position else nil
		for model, giant in animated do
			if not model.Parent then
				updateStars(giant, false, 0)
				animated[model] = nil
				continue
			end
			if model:GetAttribute("Defeated") then
				updateStars(giant, false, 0)
				continue
			end
			if herePosition and (giant.Root.Position - herePosition).Magnitude > VISIBLE_DISTANCE then
				continue
			end
			animate(giant, dt, clock, herePosition)
		end
	end)
end

return GiantAnimator
