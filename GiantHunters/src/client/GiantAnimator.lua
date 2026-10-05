--!strict
-- Animates every giant on this client only, from the attributes the
-- server sets:
--   * the walk: stride length and cadence come from how fast the giant is
--     really moving (measured here from its position), so the planted foot
--     stays put; hips sway over the standing foot, shoulders counter-turn,
--     the head bobs a beat late, forearms follow through, footsteps thud
--     (and shake the ground under the big ones); it leans into quick turns
--     and shuffles its feet turning on the spot; breathes when idle;
--   * "Mood" changes the gait: Calm ambles with curious head bobs, Alert
--     stops with its head up, looking round, Hunting strides leaning in with
--     its arms swinging wide, Enraged runs heavily, arms flailing;
--   * "Mind": Mindless lumbers, arms dangling, head lolling, eyes drifting
--     apart; Abnormal twitches (head snaps, an uneven rhythm, arms trailing
--     when it sprints); Intelligent stands upright, steps evenly, tracks you
--     precisely with lowered brows, crouches to ambush when Alert and covers
--     its nape backing away. A "Cunning" one's eyes narrow and glint;
--   * "Action" (+ "ActionAt", "ActionDir"): one-shot moves (Stomp, Swipe,
--     Lunge, Climb, Shake, Search, Sniff, Flinch, Stagger, Taunt, Crouch,
--     Roar, Turn) played from when the server started them, blended in and
--     out over the walk (data in GiantActions, timings in Config);
--   * "LookAt": the head and eyes aim there (instead of the nearest hunter);
--   * Grabbing: the trunk lunges and both arms swing up and out (the
--     warning); Holding: one hand holds you up in front of its face;
--   * Swat: one arm winds up out to the side, then sweeps across;
--   * Kneeling (ankle cut): down on its knees, hands forward;
--   * Dazed (eyes, cannonball): hands to its face, head wobbling, stars;
--     both blend out whatever move was playing;
--   * Leap (runners): legs tucked; Kick (the Wallbreaker): a slow, heavy
--     wind-up and kick, after peeking over the wall ("Event");
--   * the stare: the head turns to follow the nearest hunter, the pupils
--     follow whoever is closest, and it blinks now and then;
--   * crawlers (Look.Pose "Crawl") walk on all fours, legs in a diagonal
--     sequence; heavy giants (chubby, stocky, ape-like, or 40+ tall) waddle;
--   * idling (standing still with nothing to do): now and then it scratches
--     its head, looks slowly round, or sniffs the air toward a hunter;
--   * Guarding (Sprinter): the right hand goes back over the nape and the
--     crystal GuardHand shows; Armor: the nape plate's cracks light up as
--     it takes hits; a titan shifter's eyes take its side's colour;
--   * titan powers (attributes set by ShifterService): Slam (both fists
--     overhead, then down into the ground), Pounce (a forward lunge, arms
--     out), Throw (a boulder wound up overhead, then thrown), Vent (arms
--     flung wide, chest out) and Frenzy (a flailing sprint).
-- Motor6D.Transform isn't replicated, so all of this is free network-wise.
-- Giants near the camera animate every frame, farther ones every third
-- frame, and very far ones not at all.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Parent.Effects)
local GiantActions = require(script.Parent.GiantActions)

local GiantAnimator = {}

-- One playing move (two slots: the current one and the one fading out).
type Slot = { Name: string, At: number, Weight: number, Dir: Vector3, Fired: boolean, Step: number }

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
	Heavy: boolean?, -- a waddling walk: wide sway, arms out, belly bounce
	Scratch: number?, -- 0..1: the right hand up scratching its head (idle)
	-- Titan powers (0..1 each):
	Slam: number?, -- both fists raised overhead (the wind-up)...
	SlamHit: number?, -- ...then down into the ground in front
	Pounce: number?, -- lunging forward, arms out, legs tucked
	Throw: number?, -- right arm wound up overhead with a boulder...
	ThrowRelease: number?, -- ...then flung forward
	Vent: number?, -- arms flung wide, chest out (steam)
	-- The walk, moods and minds:
	StepAmp: number?, -- hip swing, radians (foot planting; default from Stride)
	Turn: number?, -- how fast the body is turning, rad/s (+ left)
	Calm: number?, -- mood weights, 0..1 each
	Alert: number?,
	Hunt: number?,
	Rage: number?,
	Mind: string?, -- "Mindless" | "Abnormal" | "Intelligent"
	Backing: number?, -- 0..1 backing away (Intelligent: a hand over the nape)
	-- Moves (GiantActions): the current one and the one fading out.
	Action: string?,
	ActionTime: number?, -- seconds since it started
	ActionWeight: number?,
	ActionDir: Vector3?, -- toward the target / the hit, in the giant's frame
	Action2: string?,
	Action2Time: number?,
	Action2Weight: number?,
	Action2Dir: Vector3?,
	-- The face:
	EyeSpread: number?, -- studs the pupils drift apart (Mindless)
	Squint: number?, -- 0..1: the lids partly down (focused, cunning)
	Brow: number?, -- -1 raised .. 1 lowered (focused / angry)
	HeadSize: number?,
}

type Animated = {
	Model: Model,
	Root: BasePart,
	Head: BasePart?,
	Motors: { [string]: Motor6D },
	Height: number,
	HeadSize: number,
	Leg: number, -- leg length (hip to sole), studs
	Abnormal: boolean,
	Phase: number,
	Breath: number,
	Look: CFrame,
	Reach: number,
	Hold: number,
	Kneel: number,
	Daze: number,
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
	Heavy: boolean,
	Idle: string, -- "", "Scratch", "LookAround" or "Sniff"
	IdleUntil: number,
	NextIdle: number,
	Scratch: number,
	-- Titan powers.
	Slam: number,
	SlamHit: number,
	SlamTimer: number,
	Pounce: number,
	Throw: number,
	ThrowRelease: number,
	ThrowTimer: number,
	Vent: number,
	WasSlam: boolean,
	WasThrow: boolean,
	-- Measured motion.
	LastPos: Vector3,
	Vel: Vector3,
	Speed: number,
	LastYaw: number,
	Turn: number,
	-- Moods, minds, moves.
	Calm: number,
	Alert: number,
	Hunt: number,
	Rage: number,
	Backing: number,
	Cunning: boolean,
	SnapUntil: number,
	NextSnap: number,
	SnapLook: CFrame,
	Cur: Slot,
	Prev: Slot,
	WasKick: boolean,
	KickAt: number,
	Kicked: boolean,
	PeekAt: number,
	-- Level of detail: seconds saved up while skipping frames.
	Pending: number,
	Slot: number,
	Input: PoseInput,
	Out: { [string]: CFrame },
}

local animated: { [Model]: Animated } = {}
local NEAR_DISTANCE = 600 -- from the camera: animated every frame
local FAR_DISTANCE = 1400 -- every third frame up to here; frozen beyond
local STARE_DISTANCE = 140
local SNIFF_DISTANCE = 260
local HEAVY_BODIES = { Chubby = true, Stocky = true, Ape = true }
local CUNNING_GLINT = Color3.fromRGB(255, 214, 120)
local nextSlot = 0

local function newSlot(): Slot
	return { Name = "", At = 0, Weight = 0, Dir = Vector3.new(0, 0, -1), Fired = false, Step = -1 }
end

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
	local height = (instance:GetAttribute("Height") :: number?) or 20
	-- Leg length from the rig itself (hip to knee, x2 for the shin and foot).
	local leg = height * 0.41
	local hip, knee = motors.LeftHip, motors.LeftKnee
	if hip and knee then
		leg = math.max((knee.C0.Position - hip.C1.Position).Magnitude * 1.95, height * 0.15)
	end
	local lidShut = instance:GetAttribute("LidShut")
	local headSize = (instance:GetAttribute("HeadSize") :: number?) or 4
	local crawl = instance:GetAttribute("Pose") == "Crawl"
	nextSlot += 1
	local giant: Animated = {
		Model = instance,
		Root = root,
		Head = if head and head:IsA("BasePart") then head else nil,
		Motors = motors,
		Height = height,
		HeadSize = headSize,
		Leg = leg,
		Abnormal = instance:GetAttribute("Abnormal") == true,
		Phase = math.random() * 6,
		Breath = math.random() * 6,
		Look = CFrame.new(),
		Reach = 0,
		Hold = 0,
		Kneel = 0,
		Daze = 0,
		Leap = 0,
		SwatRaise = 0,
		SwatSide = 1,
		LastSwat = "",
		SwingTimer = 0,
		Swing = 0,
		LastStep = 0,
		Stars = nil,
		Crawl = crawl,
		Guard = 0,
		GuardHand = if guardHand and guardHand:IsA("BasePart") then guardHand else nil,
		Cracks = cracks,
		MaxArmor = if kind and kind.Armor then kind.Armor else 0,
		LidShut = if typeof(lidShut) == "Vector3" then lidShut else Vector3.zero,
		EyeRange = headSize * 0.04,
		Gaze = Vector3.zero,
		BlinkUntil = 0,
		NextBlink = os.clock() + 1 + math.random() * 4,
		Heavy = HEAVY_BODIES[(instance:GetAttribute("Body") :: string?) or ""] == true or height >= 40,
		Idle = "",
		IdleUntil = 0,
		NextIdle = os.clock() + 3 + math.random() * 5,
		Scratch = 0,
		Slam = 0,
		SlamHit = 0,
		SlamTimer = 0,
		Pounce = 0,
		Throw = 0,
		ThrowRelease = 0,
		ThrowTimer = 0,
		Vent = 0,
		WasSlam = false,
		WasThrow = false,
		LastPos = root.Position,
		Vel = Vector3.zero,
		Speed = 0,
		LastYaw = 0,
		Turn = 0,
		Calm = 0,
		Alert = 0,
		Hunt = 0,
		Rage = 0,
		Backing = 0,
		Cunning = false,
		SnapUntil = 0,
		NextSnap = os.clock() + 1,
		SnapLook = CFrame.new(),
		Cur = newSlot(),
		Prev = newSlot(),
		WasKick = false,
		KickAt = 0,
		Kicked = false,
		PeekAt = Workspace:GetServerTimeNow(),
		Pending = 0,
		Slot = nextSlot % 3,
		Input = {
			Height = height,
			Abnormal = false,
			Phase = 0,
			Stride = 0,
			Breath = 0,
			Time = 0,
			Reach = 0,
			Hold = 0,
			Kneel = 0,
			Daze = 0,
			Kick = 0,
			Leap = 0,
			SwatRaise = 0,
			SwatSide = 1,
			Swing = 0,
			Look = CFrame.new(),
			Crawl = crawl,
			LidShut = if typeof(lidShut) == "Vector3" then lidShut else Vector3.zero,
			HeadSize = headSize,
		},
		Out = {},
	}
	animated[instance] = giant
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

-- A cunning giant's tell: amber-tinted eyes with a faint glint (the pupils
-- themselves are left to SkyController's night glow).
local function showCunning(giant: Animated, on: boolean)
	giant.Cunning = on
	for i, name in { "Eye1", "Eye2" } do
		local eye = giant.Model:FindFirstChild(name)
		if eye and eye:IsA("BasePart") and eye.Material ~= Enum.Material.Neon then
			eye.Color = if on then Color3.fromRGB(255, 236, 178) else Color3.fromRGB(245, 245, 240)
		end
		local pupil = giant.Model:FindFirstChild(`Pupil{i}`)
		if pupil then
			local glint = pupil:FindFirstChild("CunningGlint")
			if on and not glint then
				local light = Instance.new("PointLight")
				light.Name = "CunningGlint"
				light.Color = CUNNING_GLINT
				light.Range = giant.HeadSize * 0.6
				light.Brightness = 1.2
				light.Shadows = false
				light.Parent = pupil
			elseif not on and glint then
				glint:Destroy()
			end
		end
	end
end

-- === The pose =================================================================

local CHANNELS = GiantActions.Count
local I = GiantActions.Index
local WX, WY, WZ, WUP, WFWD = I.WX, I.WY, I.WZ, I.WUp, I.WFwd
local NX, NY, NZ = I.NX, I.NY, I.NZ
local LHX, LHZ, LK, RHX, RHZ, RK = I.LHX, I.LHZ, I.LK, I.RHX, I.RHZ, I.RK
local LSX, LSY, LSZ, LE, RSX, RSY, RSZ, RE = I.LSX, I.LSY, I.LSZ, I.LE, I.RSX, I.RSY, I.RSZ, I.RE
local delta: { number } = table.create(CHANNELS, 0)

-- Eases an arm (shoulder X, Z, elbow) toward a pose given for the right arm
-- (Z is mirrored for the left); `te` nil leaves the elbow alone.
local function toward(x: number, z: number, e: number, side: number, tx: number, tz: number, te: number?, w: number): (number, number, number)
	if w <= 0 then
		return x, z, e
	end
	return x + (tx - x) * w, z + (side * tz - z) * w, if te then e + (te - e) * w else e
end

-- The whole pose from a giant's state, as Motor6D transforms by motor name.
-- Pure (no instances), so it can be checked outside Roblox. `into` is
-- reused when given (no new table each frame).
function GiantAnimator.Pose(p: PoseInput, into: { [string]: CFrame }?): { [string]: CFrame }
	local pose: { [string]: CFrame } = into or {}
	local reach, hold, kneel, daze, kick, leap = p.Reach, p.Hold, p.Kneel, p.Daze, p.Kick, p.Leap
	local stride, t, h = p.Stride, p.Time, p.Height
	local crawl = p.Crawl == true
	local guard = p.Guard or 0
	local slam, slamHit, pounce = p.Slam or 0, p.SlamHit or 0, p.Pounce or 0
	local throw, release, vent = p.Throw or 0, p.ThrowRelease or 0, p.Vent or 0
	local calm, alert, hunt, rage = p.Calm or 0, p.Alert or 0, p.Hunt or 0, p.Rage or 0
	local mindless, smart = p.Mind == "Mindless", p.Mind == "Intelligent"
	local abnormal = p.Abnormal or p.Mind == "Abnormal"
	local turn = math.clamp(p.Turn or 0, -2.5, 2.5)
	-- Grabbing, holding and kneeling lean the trunk by exact amounts the
	-- server mirrors (GiantService posedNape/heldHand): moods and moves stay
	-- out of the trunk while those are on.
	local free = 1 - math.max(reach, hold, kneel)

	-- Moves: deltas on every channel; stunned (dazed, on its knees), they
	-- give way. The walk shows through only as much as each move allows.
	local d = delta
	for c = 1, CHANNELS do
		d[c] = 0
	end
	local yielding = 1 - math.max(daze, kneel)
	local gait = 1
	if p.Action and p.Action ~= "" then
		local w = math.clamp(p.ActionWeight or 1, 0, 1) * yielding
		GiantActions.Add(p.Action, p.ActionTime or 0, w, p.ActionDir, d)
		gait -= w * (1 - GiantActions.Gait(p.Action))
	end
	if p.Action2 and p.Action2 ~= "" then
		local w = math.clamp(p.Action2Weight or 0, 0, 1) * yielding
		GiantActions.Add(p.Action2, p.Action2Time or 0, w, p.Action2Dir, d)
		gait -= w * (1 - GiantActions.Gait(p.Action2))
	end
	gait = math.clamp(gait, 0, 1)
	stride *= gait

	-- A pounce tucks the legs like a leap.
	leap = math.max(leap, pounce * 0.7)
	local phase = p.Phase
	local s, c = math.sin(phase), math.cos(phase)
	local amp = if p.StepAmp then p.StepAmp * gait else (if abnormal then 0.75 elseif crawl then 0.35 else 0.5) * stride
	local swing = s * amp

	-- Trunk: the slouch is baked into the rig; this sways, bobs, breathes,
	-- lunges, and hunches further for runners and stumbles. A crawler rears
	-- up to grab and flattens down when its legs are cut. Mid-stance (legs
	-- passing) is the top of the bob; the weight rolls over the standing foot.
	local heavy = (p.Heavy == true or mindless) and not crawl
	local bob = math.abs(c) * h * (if heavy then 0.018 else 0.012) * (1 + 0.6 * rage) * stride
	local breathe = math.sin(p.Breath)
	local lean = breathe * 0.02 - leap * 0.2 + kick * 0.15
	if crawl then
		lean += reach * 0.5 - kneel * 0.12 + hold * 0.35
	else
		lean += -reach * 0.22 - kneel * 0.35 + hold * 0.08
	end
	if abnormal then
		lean -= 0.3 * stride
	end
	-- Titan powers: rear back for a slam or a throw, then pitch into it;
	-- lunge into a pounce; chest out for the steam vent.
	lean += -0.2 * slam + 0.5 * slamHit + 0.4 * pounce - 0.15 * throw + 0.25 * release - 0.15 * vent
	-- Moods and minds: leaning into a hunt, low and heavy in a rage, chest up
	-- when alert; upright when clever, slack when mindless; a clever one
	-- crouches to ambush when alert and standing still.
	local ambush = if smart and not crawl then alert * (1 - stride) * free else 0
	if not crawl then
		lean += free * ((-0.12 * hunt - 0.28 * rage) * stride + 0.04 * alert + (if smart then 0.07 elseif mindless then -0.05 else 0) - 0.3 * ambush)
	end
	-- (a crawler's trunk is already pitched down flat: moves tip it less)
	lean += d[WX] * free * (if crawl then 0.3 else 1)
	local dazeSway = math.sin(t * 1.7) * 0.12 * daze
	local roll, shift, twist
	if crawl then
		roll = s * 0.05 * stride
		shift = 0
		twist = c * 0.04 * stride
	else
		roll = -c * (if heavy then 0.1 else 0.05) * stride
		shift = c * h * (if heavy then 0.012 else 0.005) * stride
		twist = s * 0.08 * (1 + 0.5 * hunt) * stride
	end
	-- Leaning into a turn, the shoulders leading.
	roll += turn * 0.06 * (0.4 + stride) * free
	twist += turn * 0.05 * free
	pose.Waist = CFrame.new(shift, bob + d[WUP] * h * free, -d[WFWD] * h * free)
		* CFrame.Angles(lean, twist + d[WY] * free, roll + dazeSway + d[WZ] * free)
	-- The belly (chubby and stocky giants) bounces a beat behind each step.
	pose.Belly = CFrame.new(0, math.sin(phase * 2 + 1.2) * h * 0.008 * stride + breathe * h * 0.002, 0)

	-- Legs: the leg swinging through bends its knee (most as it passes
	-- under), the standing one stays nearly straight; kneeling folds the
	-- shins back flat; a leap tucks both legs. A crawler's knees are already
	-- down: its thighs just paddle.
	local leftHip, rightHip = swing, -swing
	local leftKnee = -(math.max(c, 0) * 1.4 * amp + 0.06 * stride)
	local rightKnee = -(math.max(-c, 0) * 1.4 * amp + 0.06 * stride)
	if crawl then
		leftKnee, rightKnee = math.max(-s, 0) * 0.25 * stride, math.max(s, 0) * 0.25 * stride
	else
		leftHip, rightHip = leftHip + 0.25 * ambush, rightHip + 0.25 * ambush
		leftKnee, rightKnee = leftKnee - 0.5 * ambush, rightKnee - 0.5 * ambush
		leftHip, rightHip = lerp(leftHip, 0.1, kneel), lerp(rightHip, 0.1, kneel)
		leftKnee, rightKnee = lerp(leftKnee, -1.5, kneel), lerp(rightKnee, -1.5, kneel)
	end
	-- (a crawler's legs stay folded under it through any move)
	local legMove = if crawl then 0 else 1
	leftHip += 0.6 * leap + d[LHX] * legMove
	rightHip += 0.6 * leap + d[RHX] * legMove
	leftKnee += -1.0 * leap + d[LK] * legMove
	rightKnee += -1.0 * leap + d[RK] * legMove
	-- Slamming: down into a crouch as the fists hit the ground.
	leftHip, rightHip = leftHip + 0.4 * slamHit, rightHip + 0.4 * slamHit
	leftKnee, rightKnee = leftKnee - 0.7 * slamHit, rightKnee - 0.7 * slamHit
	rightHip = lerp(rightHip, 1.25, kick)
	rightKnee = lerp(rightKnee, -0.15, kick)
	leftKnee = lerp(leftKnee, -0.35, kick)
	pose.LeftHip = CFrame.Angles(leftHip, 0, d[LHZ] * legMove)
	pose.RightHip = CFrame.Angles(rightHip, 0, d[RHZ] * legMove)
	pose.LeftKnee = CFrame.Angles(leftKnee, 0, 0)
	pose.RightKnee = CFrame.Angles(rightKnee, 0, 0)

	-- Arms. Shoulder angles: X swings forward, Z tilts out to the side
	-- (negative on the left, positive on the right). Each arm swings with
	-- the opposite leg, the forearm following through a beat late.
	-- A crawler walks its arms like front legs, a quarter-step behind the
	-- opposite hind leg (a diagonal gait), elbows nearly straight.
	local flail = (if abnormal then 1.8 elseif crawl then 1.1 else 0.8)
		* (1 + 0.5 * hunt + 0.6 * rage + (if smart then -0.35 elseif mindless then 0.3 else 0))
	local spread = (if abnormal then 0.35 elseif heavy then 0.14 else 0) * stride + (0.15 * hunt + 0.3 * rage) * stride + (if smart then -0.04 else 0)
	local lX, lZ, lE, rX, rZ, rE
	if crawl then
		lX, rX = c * amp * flail, -c * amp * flail
		lZ, rZ = -0.08, 0.08
		lE, rE = 0.05 + math.max(-s, 0) * 0.35 * stride, 0.05 + math.max(s, 0) * 0.35 * stride
	else
		local lag = math.sin(phase - 0.7)
		local follow = (if mindless then 0.6 else 0.3) * stride
		lX, rX = -swing * flail, swing * flail
		lZ, rZ = -0.08 - spread, 0.08 + spread
		lE = 0.25 + math.abs(s) * 0.1 * stride + math.max(-lag, 0) * follow
		rE = 0.25 + math.abs(s) * 0.1 * stride + math.max(lag, 0) * follow
		-- Enraged: arms up and flailing all over the place.
		local flap = rage * stride
		if flap > 0 then
			lX += 0.3 * flap
			rX += 0.3 * flap
			lZ -= math.sin(t * 9 + 1.3) * 0.3 * flap
			rZ += math.sin(t * 9) * 0.3 * flap
			lE += (math.sin(t * 11) * 0.5 + 0.3) * flap
			rE += (math.sin(t * 11 + 2) * 0.5 + 0.3) * flap
		end
		-- An abnormal at a sprint: long arms trailing out behind.
		local trail = if abnormal then math.clamp((stride - 0.5) * 2, 0, 1) else 0
		if trail > 0 then
			lX = lerp(lX, -0.85 + lX * 0.2, trail)
			rX = lerp(rX, -0.85 + rX * 0.2, trail)
			lZ, rZ = lerp(lZ, -0.3, trail), lerp(rZ, 0.3, trail)
			lE, rE = lerp(lE, 0.12 + math.abs(s) * 0.15, trail), lerp(rE, 0.12 + math.abs(c) * 0.15, trail)
		end
		-- Ambush: hands low and ready.
		lX, rX, lE, rE = lX + 0.35 * ambush, rX + 0.35 * ambush, lE + 0.4 * ambush, rE + 0.4 * ambush
	end
	lX, lZ, lE = lX + d[LSX], lZ + d[LSZ], lE + d[LE]
	rX, rZ, rE = rX + d[RSX], rZ + d[RSZ], rE + d[RE]
	local lY, rY = d[LSY], d[RSY]
	-- Grab: both arms up and out in front.
	lX, lE = lerp(lX, 1.45, reach), lerp(lE, 0, reach)
	rX, rE = lerp(rX, 1.45, reach), lerp(rE, 0, reach)
	lZ -= 0.25 * reach
	rZ += 0.25 * reach
	-- Kneeling: hands forward to catch itself (a crawler's already are).
	if not crawl then
		lX, lE = lerp(lX, 0.75, kneel), lerp(lE, 0.2, kneel)
		rX, rE = lerp(rX, 0.75, kneel), lerp(rE, 0.2, kneel)
	end
	-- Swat: wind up out to the side, then sweep across the front.
	if p.SwatSide < 0 then
		lX, lZ, lE = toward(lX, lZ, lE, -1, 0.5, 1.5, nil, p.SwatRaise)
		lX, lZ, lE = toward(lX, lZ, lE, -1, 1.3, -0.6, nil, p.Swing)
	else
		rX, rZ, rE = toward(rX, rZ, rE, 1, 0.5, 1.5, nil, p.SwatRaise)
		rX, rZ, rE = toward(rX, rZ, rE, 1, 1.3, -0.6, nil, p.Swing)
	end
	-- Dazed: hands up to its face. Kick: arms out for balance.
	lX, lZ, lE = toward(lX, lZ, lE, -1, 2.3, -0.35, 1.9, daze)
	rX, rZ, rE = toward(rX, rZ, rE, 1, 2.3, -0.35, 1.9, daze)
	lZ -= 0.6 * kick
	rZ += 0.6 * kick
	-- Holding: the right hand holds you up in front of its face.
	rX = lerp(rX, 1.2, hold) + math.sin(t * 22) * 0.04 * hold
	rZ = lerp(rZ, -0.25, hold)
	rE = lerp(rE, 0.9, hold)
	lX = lerp(lX, 0.5, hold)
	-- Guarding (Sprinter): the right hand goes up and back over the nape.
	rX, rZ, rE = toward(rX, rZ, rE, 1, 2.75, -0.45, 1.7, guard)
	-- Backing away (Intelligent): the left hand over the nape, wary.
	lX, lZ, lE = toward(lX, lZ, lE, -1, 2.75, -0.45, 1.7, p.Backing or 0)
	-- Scratching its head (idle): the right hand up by its ear, fingers going.
	rX, rZ, rE = toward(rX, rZ, rE, 1, 2.5, 0.55, 2.15 + math.sin(t * 15) * 0.15, p.Scratch or 0)
	-- Titan powers. Slam: both fists high overhead, then down onto the
	-- ground in front. Pounce: both arms reaching forward. Vent: arms flung
	-- out wide, a little shaky.
	local shaky = 1.35 + math.sin(t * 18) * 0.05
	lX, lZ, lE = toward(lX, lZ, lE, -1, 2.85, -0.12, 0.5, slam)
	rX, rZ, rE = toward(rX, rZ, rE, 1, 2.85, -0.12, 0.5, slam)
	lX, lZ, lE = toward(lX, lZ, lE, -1, 0.75, -0.1, 0.05, slamHit)
	rX, rZ, rE = toward(rX, rZ, rE, 1, 0.75, -0.1, 0.05, slamHit)
	lX, lZ, lE = toward(lX, lZ, lE, -1, 1.5, 0.15, 0.15, pounce)
	rX, rZ, rE = toward(rX, rZ, rE, 1, 1.5, 0.15, 0.15, pounce)
	lX, lZ, lE = toward(lX, lZ, lE, -1, 0.35, shaky, 0.3, vent)
	rX, rZ, rE = toward(rX, rZ, rE, 1, 0.35, shaky, 0.3, vent)
	-- Throw: the right arm winds a boulder up over the head (the left one
	-- points the way), then flings it forward.
	rX, rZ, rE = toward(rX, rZ, rE, 1, 2.95, 0.25, 1.3, throw)
	lX = lerp(lX, 1.2, throw)
	rX, rZ, rE = toward(rX, rZ, rE, 1, 1.1, -0.1, 0.1, release)
	-- Breathing lifts the shoulders a little (not while holding: the server
	-- mirrors that arm).
	local lift = (breathe * 0.003 + alert * 0.004) * h * (1 - hold)
	pose.LeftShoulder = CFrame.new(0, lift, 0) * CFrame.Angles(lX, lY * (1 - hold), lZ)
	pose.RightShoulder = CFrame.new(0, lift, 0) * CFrame.Angles(rX, rY * (1 - hold), rZ)
	pose.LeftElbow = CFrame.Angles(lE, 0, 0)
	pose.RightElbow = CFrame.Angles(rE, 0, 0)

	-- The head undoes the trunk's lean first, so turning to look at you is a
	-- turn round the vertical (no drifting sideways when it leans). On top:
	-- a head bob a beat behind the steps, curious nods when calm, head up
	-- when alert, a glare from under the brows in a rage, lolling when
	-- mindless, twitchy snaps when abnormal; turning, the head leads.
	local nx, ny, nz = d[NX], d[NY], d[NZ]
	nx += -math.cos(2 * phase - 0.9) * (if crawl then 0.02 else 0.04) * stride
	nx += 0.12 * alert - 0.1 * rage + math.sin(t * 1.9) * 0.06 * calm
	ny += math.sin(t * 0.7) * 0.2 * calm + turn * 0.12
	if crawl then
		nz -= roll * 0.8
	end
	if mindless then
		nz += math.sin(t * 0.6) * 0.14 + 0.05
		nx -= 0.06 + math.sin(t * 1.1) * 0.04
	end
	if abnormal then
		local j = math.sin(t * 7.3) * math.sin(t * 2.9 + 1)
		local k = math.sin(t * 11)
		ny += j * j * j * 0.45
		nz += k * k * k * k * k * 0.18
	end
	local wobble = CFrame.Angles(math.sin(t * 2.6) * 0.15 * daze, math.sin(t * 2.3) * 0.35 * daze, math.sin(t * 3.1) * 0.2 * daze)
	pose.Neck = CFrame.Angles(-lean, 0, 0) * p.Look * CFrame.Angles(nx, ny, nz) * wobble

	-- Eyes: the pupils slide toward whoever it's looking at (drifting apart
	-- when mindless); blinks; lids part-way down when focused or cunning;
	-- brows down when focused or angry, up when alert.
	local gaze = p.Gaze or Vector3.zero
	local apart = p.EyeSpread or 0
	pose.LeftEye = CFrame.new(gaze.X - apart, gaze.Y, gaze.Z)
	pose.RightEye = CFrame.new(gaze.X + apart, gaze.Y, gaze.Z)
	local shut = (p.LidShut or Vector3.zero) * math.clamp(math.max(p.Blink or 0, p.Squint or 0), 0, 1)
	pose.LeftLid = CFrame.new(shut)
	pose.RightLid = CFrame.new(shut)
	local brow = math.clamp(p.Brow or 0, -1, 1)
	local drop = brow * (p.HeadSize or h * 0.17) * 0.035
	pose.LeftBrow = CFrame.new(0, -drop, 0) * CFrame.Angles(0, 0, -brow * 0.22)
	pose.RightBrow = CFrame.new(0, -drop, 0) * CFrame.Angles(0, 0, brow * 0.22)
	return pose
end

-- Shows a part only while `on` (writes only on a change).
local function show(p: BasePart, on: boolean, transparency: number)
	local want = if on then transparency else 1
	if p.Transparency ~= want then
		p.Transparency = want
	end
end

-- === Driving one giant ========================================================

local MOODS = { Calm = 1, Alert = 2, Hunting = 3, Enraged = 4 }

-- Where `target` is from the giant, flat, in its own frame (unit; ahead
-- when there's nothing to go on).
local function localDir(root: BasePart, offset: Vector3?): Vector3
	if offset then
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > 0.01 then
			return root.CFrame:VectorToObjectSpace(flat.Unit)
		end
	end
	return Vector3.new(0, 0, -1)
end

local function nearestTo(position: Vector3, hunters: { Vector3 }, range: number): Vector3?
	local nearest: Vector3? = nil
	local best = range
	for _, other in hunters do
		local d = (other - position).Magnitude
		if d < best then
			nearest, best = other, d
		end
	end
	return nearest
end

-- A move's big moment: dust and a shake where the foot lands, a roar...
local function impact(giant: Animated, name: string)
	local model = giant.Model
	if name == "Stomp" or name == "Kick" then
		local dir = giant.Cur.Dir
		local foot = model:FindFirstChild(if name == "Stomp" and dir.X < -0.05 then "LeftFoot" else "RightFoot")
		if foot and foot:IsA("BasePart") then
			Effects.Stomp(foot, giant.Height * (if name == "Kick" then 0.6 else 1))
		end
	elseif name == "Lunge" or name == "Crouch" then
		Effects.Play("Boom", giant.Root, math.clamp(giant.Height / 46, 0.3, 0.8), 1.3)
	end
end

-- Starts move `name` (from server time `at`) in the current slot; the one
-- playing fades out from the other slot.
local function start(giant: Animated, name: string, at: number, dir: Vector3, near: boolean)
	local old = giant.Prev
	giant.Prev = giant.Cur
	old.Name, old.At, old.Weight, old.Dir, old.Fired, old.Step = name, at, 0, dir, false, -1
	giant.Cur = old
	if name == "Roar" and near then
		local head = giant.Head
		Effects.Play("Roar", head or giant.Root, 1, math.sqrt(30 / giant.Height))
	end
end

local function animate(giant: Animated, dt: number, t: number, serverNow: number, herePosition: Vector3?, hunters: { Vector3 }, near: boolean)
	local model = giant.Model
	local height = giant.Height
	local root = giant.Root
	local rootFrame = root.CFrame
	local now = os.clock()

	-- Measured motion: velocity from how far the root really moved (what
	-- the feet have to keep up with), and how fast it's turning.
	local position = rootFrame.Position
	local moved = position - giant.LastPos
	giant.LastPos = position
	if dt > 0 then
		local v = Vector3.new(moved.X, 0, moved.Z) / dt
		if v.Magnitude > 400 then
			v = giant.Vel -- teleported
		end
		giant.Vel = giant.Vel:Lerp(v, math.min(dt * 8, 1))
		local look = rootFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		local turned = (yaw - giant.LastYaw + math.pi) % (2 * math.pi) - math.pi
		giant.LastYaw = yaw
		giant.Turn = ease(giant.Turn, math.clamp(turned / dt, -4, 4), 6, dt)
	end
	local speed = giant.Vel.Magnitude
	giant.Speed = speed

	giant.Reach = ease(giant.Reach, if model:GetAttribute("Grabbing") then 1 else 0, 6, dt)
	giant.Hold = ease(giant.Hold, if model:GetAttribute("Holding") then 1 else 0, 5, dt)
	giant.Kneel = ease(giant.Kneel, if model:GetAttribute("Kneeling") then 1 else 0, 5, dt)
	local dazed = model:GetAttribute("Dazed") == true
	giant.Daze = ease(giant.Daze, if dazed then 1 else 0, 4, dt)
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
	-- Titan powers: a wind-up while the attribute is on; when it goes off,
	-- the blow follows through for a moment.
	local slamming = model:GetAttribute("Slam") == true
	if giant.WasSlam and not slamming then
		giant.SlamTimer = 0.45
	end
	giant.WasSlam = slamming
	giant.SlamTimer = math.max(giant.SlamTimer - dt, 0)
	giant.Slam = ease(giant.Slam, if slamming then 1 else 0, 7, dt)
	giant.SlamHit = ease(giant.SlamHit, if giant.SlamTimer > 0 then 1 else 0, 16, dt)
	local throwing = model:GetAttribute("Throw") == true
	if giant.WasThrow and not throwing then
		giant.ThrowTimer = 0.4
	end
	giant.WasThrow = throwing
	giant.ThrowTimer = math.max(giant.ThrowTimer - dt, 0)
	giant.Throw = ease(giant.Throw, if throwing then 1 else 0, 7, dt)
	giant.ThrowRelease = ease(giant.ThrowRelease, if giant.ThrowTimer > 0 then 1 else 0, 16, dt)
	giant.Pounce = ease(giant.Pounce, if model:GetAttribute("Pounce") then 1 else 0, 10, dt)
	giant.Vent = ease(giant.Vent, if model:GetAttribute("Vent") then 1 else 0, 6, dt)
	-- The wind-up is the tell: the hand starts to rise before it covers.
	local guardGoal = if model:GetAttribute("Guarding") then 1 elseif model:GetAttribute("GuardWindup") then 0.4 else 0
	giant.Guard = ease(giant.Guard, guardGoal, 8, dt)
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

	-- Mood and mind.
	local mood = MOODS[(model:GetAttribute("Mood") :: string?) or ""] or 0
	giant.Calm = ease(giant.Calm, if mood == 1 then 1 else 0, 2.5, dt)
	giant.Alert = ease(giant.Alert, if mood == 2 then 1 else 0, 3, dt)
	giant.Hunt = ease(giant.Hunt, if mood == 3 then 1 else 0, 2.5, dt)
	giant.Rage = ease(giant.Rage, if mood == 4 then 1 else 0, 3, dt)
	local mind = (model:GetAttribute("Mind") :: string?) or ""
	local smart = mind == "Intelligent"
	local mindless = mind == "Mindless"
	local cunning = model:GetAttribute("Cunning") == true
	if cunning ~= giant.Cunning then
		showCunning(giant, cunning)
	end
	-- (a titan in a Frenzy runs flailing, like an abnormal)
	local abnormal = giant.Abnormal or mind == "Abnormal" or model:GetAttribute("Frenzy") == true
	local lookAt = model:GetAttribute("LookAt")
	local lookTarget: Vector3? = if typeof(lookAt) == "Vector3" then lookAt else nil

	-- Moves: the Wallbreaker's kick and peek are its own; everything else
	-- is the server's "Action".
	local kicking = model:GetAttribute("Kick") == true
	if kicking and not giant.WasKick then
		giant.KickAt = serverNow
		giant.Kicked = true
	end
	giant.WasKick = kicking
	local actionAttribute = (model:GetAttribute("Action") :: string?) or ""
	local wantName, wantAt = "", 0
	if kicking or (giant.Kicked and serverNow - giant.KickAt < Config.GiantActions.Kick.Duration) then
		wantName, wantAt = "Kick", giant.KickAt
	elseif model:GetAttribute("Event") and not giant.Kicked then
		wantName, wantAt = "Peek", giant.PeekAt
	elseif actionAttribute ~= "" and GiantActions.Has(actionAttribute) then
		wantName, wantAt = actionAttribute, (model:GetAttribute("ActionAt") :: number?) or serverNow
	end
	local cur = giant.Cur
	if wantName ~= "" and (wantName ~= cur.Name or wantAt ~= cur.At) then
		local hint = model:GetAttribute("ActionDir")
		local offset: Vector3? = if typeof(hint) == "Vector3" then hint elseif lookTarget then lookTarget - position else nil
		if not offset then
			local nearest = nearestTo(position, hunters, 300)
			offset = if nearest then nearest - position else nil
		end
		start(giant, wantName, wantAt, localDir(root, offset), near)
		cur = giant.Cur
	elseif cur.Name ~= "" and wantName ~= cur.Name and Config.GiantActions[cur.Name] and Config.GiantActions[cur.Name].Loop then
		-- A looped move ends when the attribute does: fade it out.
		start(giant, "", 0, cur.Dir, false)
		cur = giant.Cur
	end
	local prev = giant.Prev
	if cur.Name ~= "" then
		cur.Weight = ease(cur.Weight, 1, GiantActions.Blend(cur.Name), dt)
		local elapsed = serverNow - cur.At
		local spec = Config.GiantActions[cur.Name]
		if near and spec then
			if spec.Impact and not cur.Fired and elapsed >= spec.Impact then
				cur.Fired = true
				if elapsed < spec.Impact + 0.4 then
					impact(giant, cur.Name)
				end
			end
			if cur.Name == "Climb" then
				-- Bits of wall crumble where each hand grabs on.
				local step = math.floor(elapsed / (spec.Duration / 2))
				if step ~= cur.Step then
					local hand = model:FindFirstChild(if step % 2 == 0 then "RightHand" else "LeftHand")
					if cur.Step >= 0 and hand and hand:IsA("BasePart") then
						Effects.Crumble(hand.Position, math.clamp(height / 12, 1, 5))
					end
					cur.Step = step
				end
			end
		end
	end
	prev.Weight = ease(prev.Weight, 0, 9, dt)
	if prev.Weight < 0.01 then
		prev.Name = ""
	end

	-- The walk: step length grows with speed (longer when hunting or
	-- raging, shorter and quicker for abnormals, even for clever ones), the
	-- hip swing is set so a planted foot covers exactly that (no sliding),
	-- and the cadence follows. Turning on the spot shuffles the feet.
	local leg = giant.Leg
	local relative = speed / leg
	local stepLength = if abnormal
		then leg * math.clamp(0.45 + 0.2 * relative, 0.45, 0.95)
		else leg * math.clamp(0.5 + 0.35 * relative, 0.5, 1.25) * (1 + 0.15 * giant.Hunt + 0.25 * giant.Rage) * (if smart then 0.92 else 1)
	local stride = math.clamp(speed / math.max(leg * 0.35, 2.5), 0, 1)
	local amp = math.asin(math.clamp(stepLength / (2 * leg), 0, 0.68)) * stride
	local rate = math.pi * speed / stepLength
	if abnormal then
		rate *= 1 + 0.35 * math.sin(t * 1.7) * math.sin(t * 4.3) -- an uneven, lurching rhythm
	end
	local shuffle = if giant.Crawl then 0 else math.clamp((math.abs(giant.Turn) - 0.5) * 0.6, 0, 1) * (1 - stride)
	if shuffle > 0 then
		rate += math.abs(giant.Turn) * 2.2 * shuffle
		amp = math.max(amp, 0.16 * shuffle)
		stride = math.max(stride, 0.45 * shuffle)
	end
	giant.Phase += dt * rate

	-- Footsteps: a thud each time a foot comes down (the hip at the end of
	-- its swing); a mindless one stomps.
	local stepSign = if math.cos(giant.Phase) >= 0 then 1 else -1
	if near and stepSign ~= giant.LastStep and (stride > 0.4 or shuffle > 0.5) then
		local scale = math.clamp(height / 46, 0.35, 1) * (if mindless then 1.2 elseif shuffle > 0.5 then 0.6 else 1)
		Effects.Play("Step", root, scale, math.sqrt(30 / height))
		if herePosition and height >= 40 and (position - herePosition).Magnitude < 90 then
			Effects.Shake(0.25)
		end
	end
	giant.LastStep = stepSign

	giant.Breath += dt * (if smart then 1.1 else 1.4)

	-- Backing away (a clever one): wary, a hand over the nape.
	local backing = smart and speed > 2 and giant.Vel:Dot(rootFrame.LookVector) < -0.5 * speed
	giant.Backing = ease(giant.Backing, if backing then 1 else 0, 4, dt)

	-- Idling: standing still with nothing to do, now and then it scratches
	-- its head, looks slowly round, or sniffs the air toward a hunter.
	local busy = giant.Crawl or not not model:GetAttribute("Shifter") or stride > 0.2 or cur.Name ~= "" or giant.Alert > 0.5
		or giant.Reach + giant.Hold + giant.Kneel + giant.Daze + giant.Leap + giant.Guard + giant.SwatRaise + giant.Swing > 0.05
	local sniffAt: Vector3? = nil
	if busy then
		giant.Idle = ""
	elseif giant.Idle ~= "" and now >= giant.IdleUntil then
		giant.Idle = ""
		giant.NextIdle = now + 4 + math.random() * 6
	elseif giant.Idle == "" and now >= giant.NextIdle then
		local roll = math.random(1, 3)
		giant.Idle = if roll == 1 then "Scratch" elseif roll == 2 then "LookAround" else "Sniff"
		giant.IdleUntil = now + 2.5 + math.random() * 2
	end
	if giant.Idle == "Sniff" then
		sniffAt = nearestTo(position, hunters, SNIFF_DISTANCE)
		if not sniffAt then
			giant.Idle = "LookAround" -- nobody to sniff out
		end
	end
	giant.Scratch = ease(giant.Scratch, if giant.Idle == "Scratch" then 1 else 0, 5, dt)

	-- Head: aims at LookAt if the server set one, else stares at you if
	-- you're close; looks down at whoever it's holding (the wobble when
	-- dazed is part of the pose). Clever ones track fast and far, mindless
	-- ones slowly; abnormal ones snap their heads about.
	local want = CFrame.new()
	local lookRate = if smart then 7 elseif mindless then 1.5 else 3
	local stareAt: Vector3? = lookTarget
	if not stareAt and herePosition and not model:GetAttribute("Shifter") and (herePosition - position).Magnitude < STARE_DISTANCE then
		stareAt = herePosition
	end
	if giant.Hold > 0.5 then
		want = CFrame.Angles(0, 0.2, 0) * CFrame.Angles(-0.3, 0, 0)
	elseif stareAt then
		local headWorld = rootFrame * CFrame.new(0, height * 0.5, 0)
		local aim = headWorld:VectorToObjectSpace((stareAt - headWorld.Position).Unit)
		local reachYaw = if smart then 1.35 else 1.1
		local yaw = math.clamp(math.atan2(-aim.X, -aim.Z), -reachYaw, reachYaw)
		local pitch = math.clamp(math.asin(math.clamp(aim.Y, -1, 1)), -0.6, 0.5)
		want = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	elseif sniffAt then
		-- Nose up toward you, a quick little nodding sniff.
		local aim = rootFrame:VectorToObjectSpace(sniffAt - position)
		local yaw = math.clamp(math.atan2(-aim.X, -aim.Z), -1, 1)
		want = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0.28 + math.sin(t * 11) * 0.06, 0, 0)
	elseif giant.Idle == "LookAround" or giant.Alert > 0.5 then
		want = CFrame.Angles(0, math.sin(t * 0.8 + giant.Breath) * 0.85, 0) * CFrame.Angles(0.1, 0, 0)
	elseif giant.Idle == "Scratch" then
		want = CFrame.Angles(0, 0, -0.18 * giant.Scratch) -- leaning into the scratch
	end
	if abnormal and giant.Hold < 0.5 then
		if now >= giant.NextSnap then
			giant.SnapLook = CFrame.Angles(0, (math.random() * 2 - 1) * 1.0, 0) * CFrame.Angles((math.random() * 2 - 1) * 0.3, 0, (math.random() * 2 - 1) * 0.35)
			giant.SnapUntil = now + 0.15 + math.random() * 0.3
			giant.NextSnap = now + 0.7 + math.random() * 2.2
		end
		if now < giant.SnapUntil then
			want, lookRate = giant.SnapLook, 25
		end
	end
	giant.Look = giant.Look:Lerp(want, math.min(dt * lookRate, 1))

	-- Eyes: the pupils slide toward the LookAt point or the nearest hunter;
	-- a blink every few seconds (slow, deliberate ones when clever).
	local head = giant.Head
	local gaze = Vector3.zero
	if head and not model:GetAttribute("Shifter") then
		local target = lookTarget or nearestTo(head.Position, hunters, STARE_DISTANCE * 1.5)
		if target then
			local direction = head.CFrame:VectorToObjectSpace((target - head.Position).Unit)
			gaze = Vector3.new(math.clamp(direction.X * 1.6, -1, 1), math.clamp(direction.Y * 1.6, -1, 1), 0) * giant.EyeRange
		end
	end
	giant.Gaze = giant.Gaze:Lerp(gaze, math.min(dt * (if smart then 14 elseif mindless then 2 else 8), 1))
	if now >= giant.NextBlink then
		giant.BlinkUntil = now + (if smart then 0.3 else 0.16)
		giant.NextBlink = now + (if smart then 4 + math.random() * 4 elseif mindless then 2 + math.random() * 3 else 2.5 + math.random() * 4)
	end

	local input = giant.Input
	input.Abnormal = abnormal
	input.Phase = giant.Phase
	input.Stride = stride
	input.StepAmp = amp
	input.Breath = giant.Breath
	input.Time = t
	input.Reach = giant.Reach
	input.Hold = giant.Hold
	input.Kneel = giant.Kneel
	input.Daze = giant.Daze
	input.Kick = 0 -- (the Wallbreaker's kick is a move now)
	input.Leap = giant.Leap
	input.SwatRaise = giant.SwatRaise
	input.SwatSide = giant.SwatSide
	input.Swing = giant.Swing
	input.Look = giant.Look
	input.Guard = giant.Guard
	input.Gaze = giant.Gaze
	input.Blink = if now < giant.BlinkUntil then 1 else 0
	input.Heavy = giant.Heavy
	input.Scratch = giant.Scratch
	input.Slam = giant.Slam
	input.SlamHit = giant.SlamHit
	input.Pounce = giant.Pounce
	input.Throw = giant.Throw
	input.ThrowRelease = giant.ThrowRelease
	input.Vent = giant.Vent
	input.Turn = giant.Turn
	input.Calm = giant.Calm
	input.Alert = giant.Alert
	input.Hunt = giant.Hunt
	input.Rage = giant.Rage
	input.Mind = mind
	input.Backing = giant.Backing
	input.Action = cur.Name
	input.ActionTime = serverNow - cur.At
	input.ActionWeight = cur.Weight
	input.ActionDir = cur.Dir
	input.Action2 = prev.Name
	input.Action2Time = serverNow - prev.At
	input.Action2Weight = prev.Weight
	input.Action2Dir = prev.Dir
	input.EyeSpread = if mindless then giant.EyeRange * (0.35 + 0.25 * math.sin(t * 0.5)) else 0
	input.Squint = (if cunning then 0.4 elseif smart then 0.15 else 0) + 0.2 * giant.Rage
	input.Brow = (if smart then 0.7 elseif mindless then -0.3 else 0) + giant.Rage + 0.4 * giant.Hunt - 0.4 * giant.Alert

	local pose = GiantAnimator.Pose(input, giant.Out)
	local motors = giant.Motors
	for name, transform in pose do
		set(motors, name, transform)
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
	local frame = 0
	-- Everyone the pupils can follow (not titans: they hide inside one);
	-- refilled each frame, never reallocated.
	local hunters: { Vector3 } = {}
	RunService.RenderStepped:Connect(function(dt: number)
		clock += dt
		frame += 1
		local character = player.Character
		local here = character and character:FindFirstChild("HumanoidRootPart")
		local herePosition = if here and here:IsA("BasePart") then here.Position else nil
		local eye = Workspace.CurrentCamera.CFrame.Position
		local serverNow = Workspace:GetServerTimeNow()
		table.clear(hunters)
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
			-- Level of detail: every frame up close, every third frame
			-- (with the time saved up) further out, frozen beyond.
			local distance = (giant.Root.Position - eye).Magnitude
			giant.Pending += dt
			if distance > FAR_DISTANCE then
				giant.Pending = 0
				giant.LastPos = giant.Root.Position
				continue
			end
			local near = distance <= NEAR_DISTANCE
			if not near and (frame + giant.Slot) % 3 ~= 0 then
				continue
			end
			local step = math.min(giant.Pending, 0.25)
			giant.Pending = 0
			animate(giant, step, clock, serverNow, herePosition, hunters, near)
		end
	end)
end

return GiantAnimator
