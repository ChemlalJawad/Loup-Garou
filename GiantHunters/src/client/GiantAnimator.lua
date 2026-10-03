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
--   * the stare: the head turns to follow the nearest hunter, the pupils
--     follow whoever is closest, and it blinks now and then;
--   * crawlers (Look.Pose "Crawl") walk on all fours;
--   * Guarding (Sprinter): the right hand goes back over the nape and the
--     crystal GuardHand shows; Armor: the nape plate's cracks light up as
--     it takes hits; a titan shifter's eyes take its side's colour.
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
	Crawl: boolean,
	Guard: number,
	GuardHand: BasePart?,
	Cracks: { BasePart },
	MaxArmor: number,
	LidShut: Vector3,
	EyeRange: number,
	Gaze: Vector3,
	BlinkUntil: number,
	NextBlink: number,
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
	local guardHand = instance:FindFirstChild("GuardHand")
	local cracks: { BasePart } = {}
	for i = 1, 3 do
		local crack = instance:FindFirstChild(`NapeCrack{i}`)
		if crack and crack:IsA("BasePart") then
			table.insert(cracks, crack)
		end
	end
	local kind = Config.GiantKinds[(instance:GetAttribute("Kind") :: string?) or ""]
	-- A titan shifter's eyes glow in its side's colour.
	local side = instance:GetAttribute("Side")
	if side == "Humans" or side == "Giants" then
		for _, name in { "Eye1", "Eye2" } do
			local eye = instance:FindFirstChild(name)
			if eye and eye:IsA("BasePart") then
				eye.Color = if side == "Humans" then Color3.fromRGB(110, 180, 255) else Color3.fromRGB(255, 80, 70)
				eye.Material = Enum.Material.Neon
			end
		end
	end
	local lidShut = instance:GetAttribute("LidShut")
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
		Crawl = instance:GetAttribute("Pose") == "Crawl",
		Guard = 0,
		GuardHand = if guardHand and guardHand:IsA("BasePart") then guardHand else nil,
		Cracks = cracks,
		MaxArmor = if kind and kind.Armor then kind.Armor else 0,
		LidShut = if typeof(lidShut) == "Vector3" then lidShut else Vector3.zero,
		EyeRange = ((instance:GetAttribute("HeadSize") :: number?) or 4) * 0.04,
		Gaze = Vector3.zero,
		BlinkUntil = 0,
		NextBlink = os.clock() + 1 + math.random() * 4,
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
	Crawl: boolean?, -- on all fours (Look.Pose "Crawl"): a four-legged gait
	Guard: number?, -- the right hand reaching back over the nape (Sprinter)
	Gaze: Vector3?, -- pupil offset in the head's frame, studs
	Blink: number?, -- 0 open .. 1 shut
	LidShut: Vector3?, -- how far a lid moves to shut (model attribute "LidShut")
}

-- The whole pose from a giant's state, as Motor6D transforms by motor name.
-- Pure (no instances), so it can be checked outside Roblox.
function GiantAnimator.Pose(p: PoseInput): { [string]: CFrame }
	local pose: { [string]: CFrame } = {}
	local reach, hold, kneel, daze, kick, leap = p.Reach, p.Hold, p.Kneel, p.Daze, p.Kick, p.Leap
	local stride, t = p.Stride, p.Time
	local crawl = p.Crawl == true
	local guard = p.Guard or 0
	local s = math.sin(p.Phase)
	local swing = s * (if p.Abnormal then 0.75 elseif crawl then 0.35 else 0.5) * stride

	-- Trunk: the slouch is baked into the rig; this sways, bobs, breathes,
	-- lunges, and hunches further for runners and stumbles. A crawler rears
	-- up to grab and flattens down when its legs are cut.
	local bob = math.abs(math.cos(p.Phase)) * p.Height * 0.012 * stride
	local lean = math.sin(p.Breath) * 0.02 - leap * 0.2 + kick * 0.15
	if crawl then
		lean += reach * 0.5 - kneel * 0.12 + hold * 0.35
	else
		lean += -reach * 0.22 - kneel * 0.35 + hold * 0.08
	end
	if p.Abnormal then
		lean -= 0.3 * stride
	end
	local dazeSway = math.sin(t * 1.7) * 0.12 * daze
	pose.Waist = CFrame.new(0, bob, 0) * CFrame.Angles(lean, s * 0.06 * stride, s * 0.05 * stride + dazeSway)

	-- Legs: knees bend as each leg swings through; kneeling folds the shins
	-- back flat; a leap tucks both legs; the kick swings the right leg up.
	-- A crawler's knees are already down: its thighs just paddle.
	local leftHip, rightHip = swing, -swing
	local leftKnee, rightKnee = -math.max(s, 0) * 0.7 * stride, -math.max(-s, 0) * 0.7 * stride
	if crawl then
		leftKnee, rightKnee = math.max(-s, 0) * 0.25 * stride, math.max(s, 0) * 0.25 * stride
	else
		leftHip, rightHip = lerp(leftHip, 0.1, kneel), lerp(rightHip, 0.1, kneel)
		leftKnee, rightKnee = lerp(leftKnee, -1.5, kneel), lerp(rightKnee, -1.5, kneel)
	end
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
	-- A crawler walks its arms like front legs: each one with the opposite
	-- leg (left arm with right leg), elbows nearly straight.
	local flail = if p.Abnormal then 1.8 elseif crawl then 1.1 else 0.8
	local spread = if p.Abnormal then 0.35 * stride else 0
	local elbow = if crawl then 0.05 + math.max(s, 0) * 0.25 * stride else 0.25 + math.abs(s) * 0.2 * stride
	local arms: { Left: Arm, Right: Arm } = {
		Left = { X = -swing * flail, Z = -0.08 - spread, Elbow = elbow, Side = -1 },
		Right = { X = swing * flail, Z = 0.08 + spread, Elbow = if crawl then 0.05 + math.max(-s, 0) * 0.25 * stride else elbow, Side = 1 },
	}
	for _, arm in { arms.Left, arms.Right } do
		local side = arm.Side
		-- Grab: both arms up and out in front.
		arm.X = lerp(arm.X, 1.45, reach)
		arm.Z += side * 0.25 * reach
		arm.Elbow *= 1 - reach
		-- Kneeling: hands forward to catch itself (a crawler's already are).
		if not crawl then
			arm.X = lerp(arm.X, 0.75, kneel)
			arm.Elbow = lerp(arm.Elbow, 0.2, kneel)
		end
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
	-- Guarding (Sprinter): the right hand goes up and back over the nape.
	arms.Right.X = lerp(arms.Right.X, 2.75, guard)
	arms.Right.Z = lerp(arms.Right.Z, -0.45, guard)
	arms.Right.Elbow = lerp(arms.Right.Elbow, 1.7, guard)
	pose.LeftShoulder = CFrame.Angles(arms.Left.X, 0, arms.Left.Z)
	pose.RightShoulder = CFrame.Angles(arms.Right.X, 0, arms.Right.Z)
	pose.LeftElbow = CFrame.Angles(arms.Left.Elbow, 0, 0)
	pose.RightElbow = CFrame.Angles(arms.Right.Elbow, 0, 0)

	-- The head undoes the trunk's lean first, so turning to look at you is a
	-- turn round the vertical (no drifting sideways when it leans).
	local wobble = CFrame.Angles(math.sin(t * 2.6) * 0.15 * daze, math.sin(t * 2.3) * 0.35 * daze, math.sin(t * 3.1) * 0.2 * daze)
	pose.Neck = CFrame.Angles(-lean, 0, 0) * p.Look * wobble

	-- Eyes: the pupils slide toward whoever it's looking at; blinks.
	local gaze = p.Gaze or Vector3.zero
	pose.LeftEye = CFrame.new(gaze)
	pose.RightEye = CFrame.new(gaze)
	local shut = (p.LidShut or Vector3.zero) * math.clamp(p.Blink or 0, 0, 1)
	pose.LeftLid = CFrame.new(shut)
	pose.RightLid = CFrame.new(shut)
	return pose
end

-- Shows a part only while `on` (writes only on a change).
local function show(p: BasePart, on: boolean, transparency: number)
	local want = if on then transparency else 1
	if p.Transparency ~= want then
		p.Transparency = want
	end
end

local function animate(giant: Animated, dt: number, t: number, herePosition: Vector3?, hunters: { Vector3 })
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
	giant.Guard = ease(giant.Guard, if model:GetAttribute("Guarding") then 1 else 0, 8, dt)
	if giant.GuardHand then
		show(giant.GuardHand, giant.Guard > 0.6, 0.2)
	end
	if #giant.Cracks > 0 and giant.MaxArmor > 0 then
		-- The nape plate cracks a little more with every hit.
		local armor = (model:GetAttribute("Armor") :: number?) or giant.MaxArmor
		local broken = 1 - armor / giant.MaxArmor
		for i, crack in giant.Cracks do
			show(crack, broken >= (i - 0.5) / #giant.Cracks, 0)
		end
	end

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
	elseif herePosition and not model:GetAttribute("Shifter") and (herePosition - giant.Root.Position).Magnitude < STARE_DISTANCE then
		local headWorld = giant.Root.CFrame * CFrame.new(0, height * 0.5, 0)
		local localDir = headWorld:VectorToObjectSpace((herePosition - headWorld.Position).Unit)
		local yaw = math.clamp(math.atan2(-localDir.X, -localDir.Z), -1.1, 1.1)
		local pitch = math.clamp(math.asin(math.clamp(localDir.Y, -1, 1)), -0.6, 0.5)
		want = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	end
	giant.Look = giant.Look:Lerp(want, math.min(dt * 3, 1))

	-- Eyes: the pupils slide toward the nearest hunter; a blink every few
	-- seconds.
	local head = giant.Head
	local gaze = Vector3.zero
	if head and not model:GetAttribute("Shifter") then
		local nearest: Vector3? = nil
		local best = STARE_DISTANCE * 1.5
		for _, position in hunters do
			local d = (position - head.Position).Magnitude
			if d < best then
				nearest, best = position, d
			end
		end
		if nearest then
			local direction = head.CFrame:VectorToObjectSpace((nearest - head.Position).Unit)
			gaze = Vector3.new(math.clamp(direction.X * 1.6, -1, 1), math.clamp(direction.Y * 1.6, -1, 1), 0) * giant.EyeRange
		end
	end
	giant.Gaze = giant.Gaze:Lerp(gaze, math.min(dt * 8, 1))
	local now = os.clock()
	if now >= giant.NextBlink then
		giant.BlinkUntil = now + 0.16
		giant.NextBlink = now + 2.5 + math.random() * 4
	end

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
		Crawl = giant.Crawl,
		Guard = giant.Guard,
		Gaze = giant.Gaze,
		Blink = if now < giant.BlinkUntil then 1 else 0,
		LidShut = giant.LidShut,
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
		-- Everyone the pupils can follow (not titans: they hide inside one).
		local hunters: { Vector3 } = {}
		for _, other in Players:GetPlayers() do
			local body = other.Character
			local otherRoot = body and body:FindFirstChild("HumanoidRootPart")
			if body and otherRoot and otherRoot:IsA("BasePart") and not body:GetAttribute("Shifted") then
				table.insert(hunters, otherRoot.Position)
			end
		end
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
			animate(giant, dt, clock, herePosition, hunters)
		end
	end)
end

return GiantAnimator
