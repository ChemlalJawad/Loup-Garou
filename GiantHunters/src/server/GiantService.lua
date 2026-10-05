--!strict
-- Giants: spawning, the AI, and everything they do to hunters (and that
-- hunters do to them).
--
-- AI: each giant thinks a few times a second (staggered), with one of three
-- minds (Config.GiantKinds[..].Mind, attribute "Mind"; Config.GiantAI):
--   * Mindless (most): the nearest hunter it can see (anything not behind
--     it), straight at them; loses them and forgets. Grab, Stomp, Swipe.
--   * Abnormal (Runners): an odd target (far, high, a group), zig-zags,
--     leaps, sudden turns, taunts.
--   * Intelligent (Sprinter, Beast, Armored, and "Cunning" normal giants
--     from round 3): a 110-degree sight cone, hearing (gas, flares,
--     cannons), memory and a search, pack roars, two at most on one
--     hunter; turns on hunters lingering behind it, backs up to walls,
--     ambushes, feints, retreats when hurt, shakes off hooks, climbs houses.
-- GiantBrain holds the mood / plan state machine (Calm, Alert, Hunting,
-- Enraged). Moves are told to the clients by attributes: "Mood", "Action"
-- + "ActionAt" (+ "ActionDir", "LookAt", "Climbing", "Ambush"). Every
-- attack has a wind-up and lands only at its Impact time:
--   * Grab (the plain one): arms up ("Grabbing"), then held in its hand:
--     wriggle free (mash a key), get cut loose by a friend, or after a few
--     seconds be caught and sent back to the wall.
--   * Swat: a hunter flying round its head in front: knocked away.
--   * Stomp (ground hunters by its feet: a small shove), Swipe (off a roof
--     at arm height), Lunge (a dive-grab at mid range), Crouch (a scoop at
--     its feet), Shake (hooks on its body come loose), Climb (up a house
--     facade, then a swipe), Roar (calls the pack).
--   * Sprinters now and then cover their nape: a hunter close behind them,
--     a short wind-up (attribute "GuardWindup", the hand starts to rise),
--     then the crystal hand sits over the nape for a moment ("Guarding").
-- Hit: "Flinch" (any cut), "Stagger" (a fast clean cut, a cannonball).

-- Cuts, through TryHit (HunterService checks cooldowns and blades first):
--   * the nape, from behind or the side: damage (on armoured giants, the
--     rock plate cracks first; a guarding Sprinter's hand blocks it);
--   * the eyes, from in front of the face: dazed for a few seconds;
--   * an ankle: down on its knees for a few seconds - nape within reach.
-- Any cut on a giant that is holding someone sets them free.
--
-- And the start of every round: the Wallbreaker (RunWallbreaker).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local Stats = require(ReplicatedStorage.Shared.Stats)
local GiantFactory = require(script.Parent.GiantFactory)
local Wall = require(script.Parent.World.Wall)
local Layout = require(script.Parent.World.Layout)
local Broadcast = require(script.Parent.Broadcast)
local DayNightService = require(script.Parent.DayNightService)
local Motion = require(script.Parent.Motion)
local Respawn = require(script.Parent.Respawn)
local GiantBrain = require(script.Parent.GiantBrain)

local GiantService = {}

type Giant = {
	Rig: GiantFactory.Rig,
	Kind: Config.GiantKind,
	Move: AlignPosition,
	Face: AlignOrientation,
	RestY: number, -- root height standing up
	NextGrabAt: number,
	NextSwatAt: number,
	Busy: boolean, -- winding up a grab or a swat
	Holding: Player?,
	HeldRoot: BasePart?, -- the exact body in its hand (a respawn is a new one)
	HoldStarted: number,
	Struggles: number,
	KneelUntil: number,
	DazeUntil: number,
	WanderTarget: Vector3?,
	Target: Player?, -- runners keep a target for a while
	TargetUntil: number,
	NextLeapAt: number,
	LeapUntil: number,
	Phase: number, -- runners' zig-zag
	Armor: number,
	NextThrowAt: number, -- Beast powers
	NextRoarAt: number,
	Defeated: boolean,
	StunStreak: number, -- trips and dazes in a row (diminishing returns)
	StunStreakUntil: number,
	Roamer: boolean, -- wanders the wilds (forests, training grounds, castle) first
	Hurry: boolean, -- the wave's time is up: straight into town, faster
	Joints: { [string]: Motor6D }, -- Waist, RightShoulder, RightElbow (for the posed hand and nape)
	Crawl: boolean, -- on all fours (Look.Pose "Crawl"): its trunk leans its own way
	NextGuardAt: number, -- Sprinters: when the hand can cover the nape again
	GuardUntil: number, -- the nape is covered until then (0: not guarding)
	GuardWinding: boolean, -- the hand is on its way up
	-- The mind (Config.GiantAI):
	Mind: string, -- "Mindless" | "Abnormal" | "Intelligent"
	Tune: Config.MindTuning,
	Brain: GiantBrain.State,
	Sense: GiantBrain.Sense,
	Facts: GiantBrain.Facts,
	NextAt: { [string]: number }, -- per-move cooldowns
	NextThinkAt: number,
	MoodShown: string,
	Point: Vector3?, -- where it last saw / heard someone
	HeardAt: number, -- a noise (GiantService.Noise) not yet acted on
	HeardPos: Vector3,
	-- This think's view of the hunters (perceive):
	Seen: Player?,
	SeenRoot: BasePart?,
	SeenFlat: number,
	SeenAbove: number,
	SeenDot: number,
	Circling: boolean, -- its target already has MaxPerHunter giants on them
	Loud: Vector3?, -- a hunter gassing nearby
	Behind: Player?,
	BehindPos: Vector3,
	BehindSince: number,
	Close: number, -- hunters close round it
	CloseAt: Vector3, -- their middle
	NearFeet: number,
	Perch: Player?, -- a hunter perched out of reach on a house
	PerchRoot: BasePart?,
	PerchPos: Vector3,
	PerchSince: number,
	-- Actions:
	ActionName: string,
	ActionToken: number,
	ActionBusy: boolean, -- an attack holds Busy
	RecoilUntil: number, -- flinching / staggering
	MoveTo: Vector3?, -- a lunge's dive
	MoveFrom: number,
	MoveUntil: number,
	MoveSpeed: number,
	FaceAt: Vector3?, -- stand facing this
	Lift: number, -- studs up a facade (Climb)
	ClimbPlayer: Player?,
	ClimbRoot: BasePart?,
	BracePos: Vector3?,
	WantRoar: boolean,
	LookShown: Vector3?,
	HotSpots: { Vector3 }, -- (intelligent) where it was hurt lately
	HotTimes: { number },
	HotNext: number,
}

export type HitResult = "NoTarget" | "Hit" | "Defeated" | "Armor" | "ArmorBroken" | "Trip" | "Daze" | "Guarded"
export type HitInfo = {
	Kind: string?, -- the giant's display name
	Clean: boolean?,
	Speed: number?,
	Remaining: number?, -- armour hits left
	Position: Vector3?, -- where the cut landed, for effects
	Rescued: string?, -- a hunter this cut set free
}

GiantService.Defeated = Instance.new("BindableEvent") -- (player, kindName, clean, speed)
GiantService.Assist = Instance.new("BindableEvent") -- (player, reason: "Trip" | "Daze" | "Rescue" | "Cannon" | "Armor")
GiantService.Grabbed = Instance.new("BindableEvent") -- (player, "Grab" | "Caught"): the district takes a hit

local giants: { [Model]: Giant } = {}
local held: { [Player]: Giant } = {}
local lastStruggle: { [Player]: number } = {}
local spawnPoints: { Vector3 } = {}
local rng = Random.new()
local folder: Folder
local remotes: Folder

local AI = Config.GiantAI
local COOLDOWNS: { [string]: number } = AI.Cooldowns :: any
local NAPE_SLACK: { [string]: number } = AI.ActionNapeSlack :: any
local MOOD_SPEED: { [string]: number } = AI.MoodSpeed :: any
local playerList: { Player } = {} -- kept up to date (no table per think)
local difficulty = 0 -- 0 in round 1 .. 1 from Config.GiantAI.RoundsToFull on
local roundNow = 1

-- Which giant each hunter's hooks are biting (HunterService's cable relay
-- tells us: GiantService.NoteHook), for the Shake.
type HookNote = { Left: Model?, Right: Model?, Since: number }
local hooked: { [Player]: HookNote } = {}

-- Action timings: Config.GiantActions (the animation side's) when it has
-- them, else these. Impact never comes before the wind-up ends.
type Timing = { Duration: number, Windup: number?, Impact: number? }
local DEFAULT_ACTIONS: { [string]: Timing } = {
	Stomp = { Duration = 1.2, Windup = 0.45, Impact = 0.6 },
	Swipe = { Duration = 1.0, Windup = 0.4, Impact = 0.55 },
	Lunge = { Duration = 1.1, Windup = 0.5, Impact = 0.65 },
	Shake = { Duration = 1.0, Windup = 0.2, Impact = 0.5 },
	Crouch = { Duration = 1.0, Windup = 0.35, Impact = 0.6 },
	Roar = { Duration = 1.4, Windup = 0.3, Impact = 0.6 },
	Search = { Duration = 2.5 },
	Sniff = { Duration = 1.5 },
	Flinch = { Duration = 0.4 },
	Stagger = { Duration = 0.9 },
	Taunt = { Duration = 1.5 },
	Turn = { Duration = 0.6 },
	Climb = { Duration = 1.5 }, -- (looped while set; this is the climb up)
}

local function timingField(entry: any, key: string): number?
	local value = if type(entry) == "table" then entry[key] else nil
	return if type(value) == "number" then value else nil
end

-- (duration, windup, impact) in seconds from the action's start.
local function timing(name: string): (number, number, number)
	local configured = (Config :: any).GiantActions
	local entry = if type(configured) == "table" then configured[name] else nil
	local base = DEFAULT_ACTIONS[name]
	local windup = timingField(entry, "Windup") or base.Windup or 0
	local impact = math.max(timingField(entry, "Impact") or base.Impact or windup, windup)
	local duration = math.max(timingField(entry, "Duration") or base.Duration, impact)
	return duration, windup, impact
end

local function remote(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	-- Titan shifters are giants themselves: the others leave them alone.
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and not (character :: Model):GetAttribute("Shifted") then
		return root
	end
	return nil
end

local function stunned(giant: Giant): boolean
	local now = os.clock()
	return now < giant.KneelUntil or now < giant.DazeUntil
end

local function active(giant: Giant): boolean
	return not giant.Defeated and giant.Rig.Model.Parent ~= nil
end

local function chestPoint(giant: Giant): Vector3
	local root = giant.Rig.Root
	return root.Position + Vector3.new(0, giant.Rig.TorsoHeight * 0.6, 0) + root.CFrame.LookVector * giant.Rig.TorsoDepth
end

local function inFront(giant: Giant, point: Vector3, from: Vector3): boolean
	local flat = Geo.Flat(point - from)
	if flat.Magnitude < 1 then
		return true
	end
	local forward = Geo.Flat(giant.Rig.Root.CFrame.LookVector).Unit
	return forward:Dot(flat.Unit) > Config.Giants.BehindDot
end

-- How high a hunter is above the land under them (the terrain, not roofs:
-- a rooftop above a giant's head is still safe, and the castle hill isn't a
-- free safe zone just for being 50 studs up). Cached for a moment.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { Workspace.Terrain }
groundParams.IgnoreWater = false
local heightCache: { [Player]: { Time: number, Height: number } } = {}

local function heightAboveGround(player: Player, root: BasePart): number
	local now = os.clock()
	local cached = heightCache[player]
	if cached and now - cached.Time < 0.25 then
		return cached.Height
	end
	local position = root.Position
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -600, 0), groundParams)
	local height = if hit then position.Y - hit.Position.Y else position.Y
	if cached then
		cached.Time, cached.Height = now, height -- (reused: no table per check)
	else
		heightCache[player] = { Time = now, Height = height }
	end
	return height
end

-- The castle hill (west) is no place for a giant: they walk round it.
local CASTLE_CENTRE = Geo.CastleCentre()
local CASTLE_KEEP = Layout.Castle.HillRadius + 15

local function avoidCastle(here: Vector3, goal: Vector3): Vector3
	local from = Geo.Flat(here) - CASTLE_CENTRE
	if from.Magnitude < CASTLE_KEEP then
		-- On the slope somehow: straight back out.
		local out = if from.Magnitude > 1 then from.Unit else Vector3.new(1, 0, 0)
		return CASTLE_CENTRE + out * (CASTLE_KEEP + 25)
	end
	local a, b = Geo.Flat(here), Geo.Flat(goal)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1 then
		return goal
	end
	local t = math.clamp((CASTLE_CENTRE - a):Dot(ab) / lengthSq, 0, 1)
	local closest = a + ab * t
	local side = closest - CASTLE_CENTRE
	if side.Magnitude >= CASTLE_KEEP then
		return goal
	end
	-- The line would cross the hill: aim for a point beside it instead.
	if side.Magnitude < 1 then
		side = Vector3.new(ab.Z, 0, -ab.X)
	end
	return CASTLE_CENTRE + side.Unit * (CASTLE_KEEP + 30)
end

local function steamBurst(parent: BasePart, size: number, amount: number)
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Color3.fromRGB(245, 245, 250))
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(1.5, 2.5)
	steam.Speed = NumberRange.new(6, 14)
	steam.SpreadAngle = Vector2.new(50, 50)
	steam.Rate = 0
	steam.Parent = parent
	steam:Emit(amount)
	Debris:AddItem(steam, 3)
end

-- === Moving ==================================================================

-- Walk toward `toward` (nil: stand), at `speedScale` x its walk speed,
-- facing where it goes - or `faceAt` (or, standing, giant.FaceAt).
local function steer(giant: Giant, toward: Vector3?, speedScale: number?, faceAt: Vector3?)
	local root = giant.Rig.Root
	local now = os.clock()
	local here = root.Position
	local goal = if toward then avoidCastle(here, toward) else here
	local y = giant.RestY + giant.Lift
	if now < giant.KneelUntil then
		y -= giant.Rig.ShinLength * 0.95
	elseif now < giant.LeapUntil then
		y += giant.Kind.Height * 0.3
	end
	local hurry = if giant.Hurry then Config.Waves.HurrySpeed else 1
	giant.Move.MaxVelocity = giant.Kind.WalkSpeed * (speedScale or 1) * hurry * DayNightService.GiantSpeed()
	giant.Move.Position = Vector3.new(goal.X, y, goal.Z)
	local look = faceAt or (if toward then nil else giant.FaceAt)
	local flat = if look then Vector3.new(look.X - here.X, 0, look.Z - here.Z) else Vector3.new(goal.X - here.X, 0, goal.Z - here.Z)
	if flat.Magnitude > 2 then
		giant.Face.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	end
end

-- Places out in the wilds a roaming giant wanders between (the castle's
-- sector stops short of its hill; avoidCastle keeps them off it anyway).
local ROAM_ZONES = {
	Layout.GreatForest,
	Layout.Training,
	{ Angle = Layout.Castle.Angle, Spread = math.rad(14), Inner = 640, Outer = Layout.Castle.Radius + 160 },
}

local function roamPoint(): Vector3
	local zone = ROAM_ZONES[rng:NextInteger(1, #ROAM_ZONES)]
	local radius = math.min(rng:NextNumber(zone.Inner, zone.Outer), Geo.LAND_LIMIT - 80)
	return avoidCastle(Vector3.zero, Geo.Polar(zone.Angle + rng:NextNumber(-zone.Spread, zone.Spread), radius))
end

local function wander(giant: Giant)
	local here = giant.Rig.Root.Position
	local breached = Wall.IsBreached()
	local inside = Geo.IsInside(here)
	local target = giant.WanderTarget
	local arrived = target and Geo.Flat((target :: Vector3) - here).Magnitude < 12
	-- Outside with the gate open, every giant wants in (roamers take the
	-- long way round first, until the wave's time runs out).
	local roaming = giant.Roamer and not giant.Hurry and not inside
	local wantInside = inside or giant.Hurry or (breached and not roaming)
	if not target or arrived or Geo.IsInside(target :: Vector3) ~= wantInside then
		if wantInside then
			target = Geo.Polar(rng:NextNumber(0, math.pi * 2), rng:NextNumber(30, Geo.INSIDE_LIMIT))
		elseif roaming then
			target = roamPoint()
		else
			-- (They keep to the plains near the town, not the far wilds.)
			target = Geo.Polar(Config.World.GateAngle + rng:NextNumber(-1.2, 1.2), rng:NextNumber(Geo.OUTSIDE_LIMIT + 30, math.min(Geo.LAND_LIMIT - 80, 650)))
		end
		giant.WanderTarget = target
	end
	-- (Ambling: a little slower than a chase, unless the wave's time is up.)
	steer(giant, Geo.NextWaypoint(here, target :: Vector3, breached), if giant.Hurry then 1 else MOOD_SPEED.Calm)
end

-- === Grabs: held, wriggle free, rescued or caught ============================

-- The trunk as the clients pose it: the rig's rest pose (what the server
-- has; Motor6D transforms don't replicate) leaned by `lean` at the waist,
-- the same angle GiantAnimator gives it. nil if the rig has no waist motor.
local function posedTorso(giant: Giant, lean: number): CFrame?
	local waist = giant.Joints.Waist
	if not waist then
		return nil
	end
	return giant.Rig.Root.CFrame * waist.C0 * CFrame.Angles(lean, 0, 0) * waist.C1:Inverse()
end

-- Where the right hand is while holding someone, following GiantAnimator's
-- hold pose (trunk leaned back a little; right arm raised in front, elbow
-- bent), by walking down the rig's own joints. nil if a joint is missing.
local function heldHand(giant: Giant, t: number): Vector3?
	local shoulder, elbow = giant.Joints.RightShoulder, giant.Joints.RightElbow
	local hand = giant.Rig.Model:FindFirstChild("RightHand")
	local fore = elbow and elbow.Part1
	if not shoulder or not elbow or not fore or not hand or not hand:IsA("BasePart") then
		return nil
	end
	-- The trunk eases back as the client's does (a crawler rears up further).
	local weight = 1 - math.exp(-5 * math.max(t - giant.HoldStarted, 0))
	local torso = posedTorso(giant, (if giant.Crawl then 0.35 else 0.08) * weight)
	if not torso then
		return nil
	end
	local upper = torso * shoulder.C0 * CFrame.Angles(1.2, 0, -0.25) * shoulder.C1:Inverse()
	local foreFrame = upper * elbow.C0 * CFrame.Angles(0.9, 0, 0) * elbow.C1:Inverse()
	return (foreFrame * fore.CFrame:ToObjectSpace(hand.CFrame)).Position
end

local function holdFrame(giant: Giant, t: number): CFrame
	local rootFrame = giant.Rig.Root.CFrame
	local h = giant.Kind.Height
	local lift = giant.Rig.TorsoHeight * 0.75
	local point = heldHand(giant, t)
		or (rootFrame * CFrame.new(h * 0.06 + math.sin(t * 22) * h * 0.012, lift, -(giant.Rig.TorsoDepth * 0.5 + h * 0.13))).Position
	return CFrame.lookAt(point, giant.Rig.Head.Position)
end

local function release(giant: Giant, reason: string)
	local player = giant.Holding
	if not player then
		return
	end
	local root = giant.HeldRoot
	giant.Holding = nil
	giant.HeldRoot = nil
	held[player] = nil
	giant.NextGrabAt = os.clock() + Config.Giants.GrabCooldown + 1
	giant.Rig.Model:SetAttribute("Holding", false)
	if root and root.Parent then
		root.Anchored = false
		-- Anchoring took the body off its owner's client: hand it back, or
		-- the hunter's own movement would stutter from now on.
		if root:IsDescendantOf(Workspace) then
			pcall(root.SetNetworkOwner, root, player)
		end
	end
	Motion.Reset(player)
	if player.Parent then
		remote(Config.Remotes.Held):FireClient(player, "Free", reason)
	end
end

local function startHold(giant: Giant, player: Player, root: BasePart)
	giant.Holding = player
	giant.HeldRoot = root
	giant.HoldStarted = os.clock()
	giant.Struggles = 0
	held[player] = giant
	giant.Rig.Model:SetAttribute("Holding", true)
	root.Anchored = true
	root.CFrame = holdFrame(giant, os.clock())
	remote(Config.Remotes.Held):FireClient(player, "Grabbed", { Time = Config.Giants.HoldTime, Needed = Config.Giants.StruggleToEscape })
	Broadcast.Feed(`{player.DisplayName} was grabbed! Cut them loose!`, "Danger")
	GiantService.Grabbed:Fire(player, "Grab")
end

local function caught(giant: Giant)
	local player = giant.Holding
	if not player then
		return
	end
	release(giant, "Caught")
	remote(Config.Remotes.Caught):FireClient(player, giant.Kind.Display)
	Broadcast.Feed(`{player.DisplayName} was caught by a {giant.Kind.Display}`, "Info")
	GiantService.Grabbed:Fire(player, "Caught")
	Respawn.Load(player) -- back on the wall; no gore, just a "Caught!" screen
end

local function tryGrab(giant: Giant, player: Player, root: BasePart)
	local now = os.clock()
	if giant.Busy or now < giant.NextGrabAt then
		return
	end
	giant.Busy = true
	local model = giant.Rig.Model
	model:SetAttribute("Grabbing", true) -- clients raise its arms: the warning
	task.delay(Config.Giants.GrabWindup, function()
		giant.Busy = false
		giant.NextGrabAt = os.clock() + Config.Giants.GrabCooldown
		model:SetAttribute("Grabbing", false)
		if not active(giant) or stunned(giant) or giant.Holding then
			return
		end
		local stillThere = aliveRoot(player)
		if stillThere == root and not held[player] and (root.Position - chestPoint(giant)).Magnitude <= giant.Kind.GrabReach * 1.15 then
			startHold(giant, player, root)
		end
	end)
end

-- === Swats ===================================================================

local function swatReach(giant: Giant): number
	return giant.Kind.Height * Config.Giants.SwatReach
end

local function swatTarget(giant: Giant): (Player?, BasePart?)
	local head = giant.Rig.Head.Position
	local best, bestRoot, bestDistance = nil, nil, swatReach(giant)
	for _, player in playerList do
		local root = aliveRoot(player)
		if root and not held[player] and root.Position.Y > giant.RestY then
			local distance = (root.Position - head).Magnitude
			if distance < bestDistance and inFront(giant, root.Position, head) then
				best, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	return best, bestRoot
end

local function swat(giant: Giant, player: Player, root: BasePart)
	giant.Busy = true
	local model = giant.Rig.Model
	local right = giant.Rig.Root.CFrame.RightVector
	model:SetAttribute("Swat", if (root.Position - giant.Rig.Root.Position):Dot(right) >= 0 then "Right" else "Left")
	task.delay(Config.Giants.SwatWindup, function()
		giant.Busy = false
		giant.NextSwatAt = os.clock() + Config.Giants.SwatCooldown
		model:SetAttribute("Swat", "") -- clients play the swing as the arm comes down
		if not active(giant) or stunned(giant) or giant.Holding then
			return
		end
		if aliveRoot(player) ~= root or held[player] then
			return
		end
		local head = giant.Rig.Head.Position
		if (root.Position - head).Magnitude <= swatReach(giant) * 1.2 and inFront(giant, root.Position, head) then
			local flat = Geo.Flat(root.Position - head)
			local away = if flat.Magnitude > 0.5 then flat.Unit else Geo.Flat(giant.Rig.Root.CFrame.LookVector).Unit
			remote(Config.Remotes.Knocked):FireClient(player, (away + Vector3.new(0, 0.55, 0)).Unit * Config.Giants.SwatForce)
		end
	end)
end

-- === The Sprinter's guard ====================================================
-- A hunter close behind her: now and then a short wind-up (the hand starts
-- to rise, attribute "GuardWindup"), then the crystal hand covers the nape
-- for a moment ("Guarding") and nape cuts are blocked. Then a cooldown.

local function guarding(giant: Giant): boolean
	return os.clock() < giant.GuardUntil
end

-- Hand down at once (dazed, tripped).
local function endGuard(giant: Giant)
	if not giant.GuardWinding and giant.GuardUntil == 0 then
		return
	end
	giant.GuardWinding = false
	giant.GuardUntil = 0
	local model = giant.Rig.Model
	model:SetAttribute("GuardWindup", false)
	model:SetAttribute("Guarding", false)
end

local function hunterBehind(giant: Giant): boolean
	local nape = giant.Rig.Nape.Position
	local range = giant.Kind.Height * Config.Giants.GuardRange
	local body = giant.Rig.Root.Position
	for _, player in playerList do
		local root = aliveRoot(player)
		if root and not held[player] and (root.Position - nape).Magnitude < range and not inFront(giant, root.Position, body) then
			return true
		end
	end
	return false
end

-- `force`: no hunter check, no dice (an intelligent giant backing off).
local function guard(giant: Giant, now: number, force: boolean?)
	local G = Config.Giants
	if not force and not hunterBehind(giant) then
		return
	end
	if not force and rng:NextNumber() > G.GuardChance then
		giant.NextGuardAt = now + 1.5 -- not this time
		return
	end
	giant.NextGuardAt = now + G.GuardWindup + G.GuardTime + G.GuardCooldown
	giant.GuardWinding = true
	local model = giant.Rig.Model
	model:SetAttribute("GuardWindup", true) -- clients start raising the hand: the tell
	task.delay(G.GuardWindup, function()
		if not giant.GuardWinding then
			return -- called off (dazed, tripped)
		end
		giant.GuardWinding = false
		model:SetAttribute("GuardWindup", false)
		if not active(giant) or stunned(giant) or giant.Holding then
			return
		end
		giant.GuardUntil = os.clock() + G.GuardTime
		model:SetAttribute("Guarding", true)
		task.delay(G.GuardTime, function()
			if giant.GuardUntil ~= 0 and os.clock() >= giant.GuardUntil - 0.05 then
				giant.GuardUntil = 0
				if model.Parent then
					model:SetAttribute("Guarding", false)
				end
			end
		end)
	end)
end

-- === Actions =================================================================
-- One move at a time, told to the clients by "Action" + "ActionAt". An
-- attack plants the giant's feet (Busy) for its whole length, and its effect
-- lands at its Impact time - unless a cut, a stun or a newer move cut it
-- short (ActionToken moved on). Every attack is told first: a still stare
-- (longer in early rounds), then its own wind-up.

local function lookAt(giant: Giant, point: Vector3?)
	local shown = giant.LookShown
	if point == shown or (point and shown and (point - shown).Magnitude < 3) then
		return
	end
	giant.LookShown = point
	giant.Rig.Model:SetAttribute("LookAt", point)
end

local function syncMood(giant: Giant)
	local mood = giant.Brain.Mood
	if mood ~= giant.MoodShown then
		giant.MoodShown = mood
		giant.Rig.Model:SetAttribute("Mood", mood)
	end
end

local function setAction(giant: Giant, name: string, dir: Vector3?): number
	giant.ActionToken += 1
	giant.ActionName = name
	local model = giant.Rig.Model
	model:SetAttribute("ActionDir", dir)
	model:SetAttribute("ActionAt", Workspace:GetServerTimeNow())
	model:SetAttribute("Action", name)
	return giant.ActionToken
end

-- Back to nothing in particular (if `token` is still the current move).
local function endAction(giant: Giant, token: number)
	if giant.ActionToken ~= token then
		return
	end
	giant.ActionToken += 1
	giant.ActionName = ""
	if giant.ActionBusy then
		giant.ActionBusy = false
		giant.Busy = false
	end
	giant.MoveTo = nil
	local model = giant.Rig.Model
	if giant.Lift ~= 0 then
		giant.Lift = 0
		model:SetAttribute("Climbing", false)
	end
	if model.Parent then
		model:SetAttribute("Action", "")
	end
end

-- Whatever it was doing, stop (stunned, or a cut).
local function cancelAction(giant: Giant)
	if giant.ActionName ~= "" or giant.ActionBusy then
		endAction(giant, giant.ActionToken)
	end
end

-- A move that only shows (Search, Sniff, Turn, Taunt, Flinch, Stagger).
local function flavour(giant: Giant, name: string, dir: Vector3?)
	local duration = timing(name)
	local token = setAction(giant, name, dir)
	task.delay(duration, endAction, giant, token)
end

local function cooldown(giant: Giant, name: string): number
	local scale = GiantBrain.Lerp(AI.CooldownScale, difficulty) * giant.Tune.CooldownScale
	if giant.Brain.Mood == "Enraged" then
		scale *= AI.EnragedCooldown
	end
	return (COOLDOWNS[name] or 5) * scale
end

local function offCooldown(giant: Giant, name: string, now: number): boolean
	return now >= (giant.NextAt[name] or 0)
end

-- An attack: Busy for its length; `onImpact` at its Impact time. `at`:
-- where it's aimed ("ActionDir" points there).
local function startAttack(giant: Giant, name: string, onImpact: ((Giant) -> ())?, at: Vector3?): number
	local duration, _, impact = timing(name)
	giant.Busy = true
	giant.ActionBusy = true
	giant.FaceAt = nil
	local dir = if at then at - giant.Rig.Root.Position else nil
	local token = setAction(giant, name, if dir and dir.Magnitude > 0.01 then dir else nil)
	giant.NextAt[name] = os.clock() + duration + cooldown(giant, name)
	if onImpact then
		task.delay(impact, function()
			if giant.ActionToken == token and active(giant) and not stunned(giant) and not giant.Holding then
				onImpact(giant)
			end
		end)
	end
	task.delay(duration, endAction, giant, token)
	return token
end

-- The tell before an attack: it stops and stares at `at`, then `go`.
local function tellThen(giant: Giant, at: Vector3, go: (Giant) -> ())
	giant.Busy = true
	giant.ActionBusy = true
	giant.ActionToken += 1
	local token = giant.ActionToken
	giant.FaceAt = at
	lookAt(giant, at)
	local tell = GiantBrain.Lerp(AI.TellTime, difficulty) * (if giant.Brain.Mood == "Enraged" then 0.5 else 1)
	task.delay(tell, function()
		if giant.ActionToken ~= token then
			return
		end
		if active(giant) and not stunned(giant) and not giant.Holding then
			go(giant)
		else
			endAction(giant, token)
		end
	end)
end

-- A shove (never damage): away from the giant, a little up.
local function knock(player: Player, away: Vector3, up: number, force: number)
	local flat = Geo.Flat(away)
	local push = (if flat.Magnitude > 0.5 then flat.Unit else Vector3.new(0, 0, 1)) + Vector3.new(0, up, 0)
	remote(Config.Remotes.Knocked):FireClient(player, push.Unit * force)
end

-- Stomp: a foot comes down; hunters on the ground round its feet are
-- shoved away. Jump, hook up or step back.
local function stomp(giant: Giant, at: Vector3?)
	startAttack(giant, "Stomp", function(g)
		local here = g.Rig.Root.Position
		local radius = g.Kind.Height * AI.Stomp.Radius * 1.2 + 4
		Broadcast.Shake(here, math.clamp(g.Kind.Height / 30, 0.5, 1.4))
		for _, player in playerList do
			local root = aliveRoot(player)
			if root and not held[player] then
				local away = root.Position - here
				if Geo.Flat(away).Magnitude <= radius and heightAboveGround(player, root) <= AI.Stomp.MaxAbove + 2 then
					knock(player, away, 0.6, AI.Stomp.Force)
				end
			end
		end
	end, at)
end

-- Swipe: a sweep at arm height in front; a hunter still on that roof is
-- knocked off it. Move or jump off before the arm comes round.
local function swipe(giant: Giant, player: Player, root: BasePart)
	startAttack(giant, "Swipe", function(g)
		if aliveRoot(player) ~= root or held[player] then
			return
		end
		local h = g.Kind.Height
		local here = g.Rig.Root.Position
		local top = h * 1.1 + g.Lift + (if g.Lift > 0 then h * AI.Climb.Reach else 0) + 4
		if Geo.Flat(root.Position - here).Magnitude <= h * AI.Swipe.Reach * 1.2 + 4 and heightAboveGround(player, root) <= top and inFront(g, root.Position, here) then
			knock(player, root.Position - here, 0.35, AI.Swipe.Force)
		end
	end, root.Position)
end

-- Lunge: a dive at where the hunter WAS when it wound up; it grabs them
-- if they're still there. Dodge sideways.
local function lunge(giant: Giant, player: Player, root: BasePart)
	local _, windup, impact = timing("Lunge")
	local here = giant.Rig.Root.Position
	local toward = Geo.Flat(root.Position - here)
	local reach = math.clamp(toward.Magnitude - giant.Kind.GrabReach * 0.5, 0, giant.Kind.GrabReach + giant.Kind.Height * AI.Lunge.Reach)
	local token = startAttack(giant, "Lunge", function(g)
		g.MoveTo = nil
		if aliveRoot(player) == root and not held[player] and (root.Position - chestPoint(g)).Magnitude <= g.Kind.GrabReach * 1.15 then
			g.NextGrabAt = os.clock() + Config.Giants.GrabCooldown
			startHold(g, player, root)
		end
	end, root.Position)
	if toward.Magnitude > 1 and reach > 1 and giant.ActionToken == token then
		local now = os.clock()
		local window = math.max(impact - windup * 0.5, 0.1)
		giant.MoveTo = here + toward.Unit * reach
		giant.MoveFrom = now + windup * 0.5
		giant.MoveUntil = now + impact
		giant.MoveSpeed = math.min(reach / window, AI.Lunge.Speed) / giant.Kind.WalkSpeed
	end
end

-- (Intelligent) a feint: a Swipe wind-up that turns into a Lunge (which
-- has its own full wind-up).
local function feint(giant: Giant, player: Player, root: BasePart)
	local _, windup = timing("Swipe")
	local token = startAttack(giant, "Swipe", nil, root.Position)
	task.delay(windup, function()
		if giant.ActionToken == token and active(giant) and not stunned(giant) and not giant.Holding then
			lunge(giant, player, root)
		end
	end)
end

-- Crouch: it squats and scoops at its feet. Get off the ground or away.
local function crouch(giant: Giant, player: Player, root: BasePart)
	startAttack(giant, "Crouch", function(g)
		if aliveRoot(player) ~= root or held[player] then
			return
		end
		local h = g.Kind.Height
		local here = g.Rig.Root.Position
		if Geo.Flat(root.Position - here).Magnitude <= h * AI.Crouch.Reach * 1.2 + 3 and heightAboveGround(player, root) <= h * AI.Crouch.MaxAbove + 3 and inFront(g, root.Position, here) then
			g.NextGrabAt = os.clock() + Config.Giants.GrabCooldown
			startHold(g, player, root)
		end
	end, root.Position)
end

-- Someone has been hooked onto it for a while (and is still close).
local function hookedOnto(giant: Giant, now: number): boolean
	local model = giant.Rig.Model
	local range = giant.Kind.Height * AI.Shake.Range + 20
	for player, note in hooked do
		if (note.Left == model or note.Right == model) and now - note.Since >= AI.Shake.After then
			local root = aliveRoot(player)
			if root and not held[player] and (root.Position - giant.Rig.Root.Position).Magnitude <= range then
				return true
			end
		end
	end
	return false
end

-- Shake: it shudders; every hook in its body comes loose ("ShakenOffAt"
-- on the hunter: their GrappleController lets go) with a small push.
local function shake(giant: Giant)
	startAttack(giant, "Shake", function(g)
		local model = g.Rig.Model
		local here = g.Rig.Root.Position
		local range = g.Kind.Height * AI.Shake.Range + 20
		local stamp = Workspace:GetServerTimeNow()
		for player, note in hooked do
			if note.Left == model or note.Right == model then
				if note.Left == model then
					note.Left = nil
				end
				if note.Right == model then
					note.Right = nil
				end
				local root = aliveRoot(player)
				if root and not held[player] and (root.Position - here).Magnitude <= range then
					player:SetAttribute("ShakenOffAt", stamp)
					knock(player, root.Position - here, 0.5, AI.Shake.Force)
				end
			end
		end
		steamBurst(g.Rig.Torso, g.Kind.Height * 0.15, 15)
	end)
end

-- (Intelligent) a roar calls every friend close by to its target.
local function packCall(giant: Giant)
	local point = giant.Point
	if not point or not giant.Tune.Pack then
		return
	end
	local here = giant.Rig.Root.Position
	local now = os.clock()
	for _, other in giants do
		if other ~= giant and active(other) and (other.Rig.Root.Position - here).Magnitude <= AI.PackRadius then
			other.Point = point
			GiantBrain.Called(other.Brain, other.Tune, now)
			syncMood(other)
		end
	end
end

local function roarCall(giant: Giant)
	startAttack(giant, "Roar", function(g)
		steamBurst(g.Rig.Head, g.Kind.Height * 0.2, 25)
		packCall(g)
	end, giant.Point)
end

-- Climb: up a house facade a few studs ("Climb", "Climbing"), a pause at
-- the top (the tell), then a Swipe from up there; then back down.
local function climb(giant: Giant, player: Player, root: BasePart)
	local C = AI.Climb
	local h = giant.Kind.Height
	local up = timing("Climb")
	local swipeTime = timing("Swipe")
	local now = os.clock()
	local hold = C.Hold + GiantBrain.Lerp(AI.TellTime, difficulty)
	giant.Busy = true
	giant.ActionBusy = true
	giant.ClimbPlayer, giant.ClimbRoot = nil, nil -- (one climb per approach)
	local token = setAction(giant, "Climb", root.Position - giant.Rig.Root.Position)
	giant.Lift = math.clamp(h * C.Rise, C.MinRise, C.MaxRise)
	giant.Rig.Model:SetAttribute("Climbing", true)
	giant.FaceAt = root.Position
	lookAt(giant, root.Position)
	giant.NextAt.Climb = now + cooldown(giant, "Climb")
	GiantBrain.SetPlan(giant.Brain, "Climb", now + up + hold + swipeTime + 0.3)
	task.delay(up + hold, function()
		if giant.ActionToken ~= token then
			return
		end
		if active(giant) and not stunned(giant) and not giant.Holding then
			swipe(giant, player, root) -- (it stays up until the swipe ends)
		else
			endAction(giant, token)
		end
	end)
end

local braceParams = RaycastParams.new()
braceParams.FilterType = Enum.RaycastFilterType.Exclude

-- (Intelligent) two or more hunters close: back up against the nearest
-- wall behind it (if any) and face them.
local function brace(giant: Giant, now: number)
	local root = giant.Rig.Root
	local away = Geo.Flat(root.Position - giant.CloseAt)
	if away.Magnitude < 1 then
		away = -Geo.Flat(root.CFrame.LookVector)
	end
	away = away.Unit
	local from = root.Position + Vector3.new(0, giant.Rig.TorsoHeight * 0.5, 0)
	local hit = Workspace:Raycast(from, away * AI.Brace.Probe, braceParams)
	local wall = hit and not (hit.Instance:FindFirstAncestorWhichIsA("Model") and (hit.Instance:FindFirstAncestorWhichIsA("Model") :: Model):FindFirstChildOfClass("Humanoid"))
	giant.BracePos = if hit and wall then hit.Position - away * (giant.Rig.TorsoDepth + 3) else nil
	giant.NextAt.Brace = now + AI.Brace.Time + cooldown(giant, "Brace")
	GiantBrain.SetPlan(giant.Brain, "Brace", now + AI.Brace.Time)
	giant.FaceAt = giant.CloseAt
	lookAt(giant, giant.CloseAt)
end

-- Remember where it got hurt (intelligent ones keep clear for a while).
local function noteHotSpot(giant: Giant)
	if not giant.Tune.AvoidHot then
		return
	end
	local i = giant.HotNext
	giant.HotSpots[i] = Geo.Flat(giant.Rig.Root.Position)
	giant.HotTimes[i] = os.clock()
	giant.HotNext = i % #giant.HotSpots + 1
end

local function avoidHot(giant: Giant, goal: Vector3): Vector3
	if not giant.Tune.AvoidHot or giant.Armor > 0 then
		return goal -- (armour on: it just charges through)
	end
	local H = AI.HotSpot
	local now = os.clock()
	for i, spot in giant.HotSpots do
		if now - giant.HotTimes[i] < H.Memory then
			local off = Geo.Flat(goal) - spot
			if off.Magnitude < H.Radius then
				goal = spot + (if off.Magnitude > 1 then off.Unit else Vector3.new(1, 0, 0)) * H.Radius
			end
		end
	end
	return goal
end

local function enraged(giant: Giant)
	syncMood(giant)
	if giant.Tune.Pack and giant.Kind.Height >= AI.RoarMinHeight and rng:NextNumber() < AI.RoarChance then
		giant.WantRoar = true -- (at its next think, once it's free)
	end
end

local function enrage(giant: Giant)
	if GiantBrain.Enrage(giant.Brain, os.clock(), rng:NextNumber(AI.EnrageTime[1], AI.EnrageTime[2])) then
		enraged(giant)
	end
end

-- A cut or a cannonball landed and it's still standing: it flinches or
-- staggers ("ActionDir": toward whoever did it; any attack it was making
-- is called off), may get angry, and if it thinks, looks that way.
local function hurt(giant: Giant, from: Vector3, how: string?)
	local now = os.clock()
	noteHotSpot(giant)
	local brain = giant.Brain
	if GiantBrain.Hit(brain, now, AI.EnrageHits, AI.EnrageWindow, rng:NextNumber(AI.EnrageTime[1], AI.EnrageTime[2])) then
		enraged(giant)
	end
	if giant.Tune.Memory > 0 and brain.Plan ~= "Chase" and not GiantBrain.IsOverride(brain.Plan) then
		giant.Point = from
		brain.Memory = true
		brain.LastSeenAt = now
		GiantBrain.SetPlan(brain, "Listen", now + giant.Tune.ListenTime)
	end
	syncMood(giant)
	if how and not stunned(giant) then
		local dir = from - giant.Rig.Nape.Position
		cancelAction(giant)
		giant.RecoilUntil = now + (timing(how))
		flavour(giant, how, if dir.Magnitude > 0.01 then dir.Unit else nil)
	end
end

-- === The Beast Giant's powers ================================================
-- Boulders for hunters who think they're safe up high (slow enough to
-- dodge), and a roar that blows away anyone close.

local function throwBoulder(giant: Giant, player: Player, root: BasePart)
	local model = giant.Rig.Model
	model:SetAttribute("Swat", "Right") -- wind up the throwing arm
	task.delay(0.6, function()
		model:SetAttribute("Swat", "")
		if not active(giant) or stunned(giant) then
			return
		end
		local B = Config.Beast
		local from = giant.Rig.Root.Position + Vector3.new(0, giant.Kind.Height * 0.7, 0)
		local to = root.Position -- where you were: keep moving!
		local rock = Instance.new("Part")
		rock.Name = "Boulder"
		rock.Size = Vector3.one * 6
		rock.Color = Color3.fromRGB(120, 112, 100)
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = false
		rock.CanQuery = false
		rock.Position = from
		rock.Parent = Workspace
		local apex = (from + to) / 2 + Vector3.new(0, 40, 0)
		local start = os.clock()
		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function()
			local t = math.min((os.clock() - start) / B.ThrowFlight, 1)
			rock.CFrame = CFrame.new(from:Lerp(apex, t):Lerp(apex:Lerp(to, t), t)) * CFrame.Angles(t * 6, t * 4, 0)
			if t >= 1 then
				connection:Disconnect()
				Broadcast.Shake(to, 1)
				steamBurst(rock, 8, 20)
				for _, other in playerList do
					local otherRoot = aliveRoot(other)
					if otherRoot and not held[other] and (otherRoot.Position - to).Magnitude < B.ImpactRadius then
						local away = Geo.Flat(otherRoot.Position - to)
						local push = (if away.Magnitude > 0.5 then away.Unit else Vector3.new(1, 0, 0)) + Vector3.new(0, 0.8, 0)
						remote(Config.Remotes.Knocked):FireClient(other, push.Unit * 95)
					end
				end
				rock.Transparency = 1
				Debris:AddItem(rock, 3)
			end
		end)
	end)
end

local function roar(giant: Giant)
	local B = Config.Beast
	-- ("Roar": the clients play the wind-up, the sound and the blast; it
	-- lands at the roar's Impact time.)
	startAttack(giant, "Roar", function(g)
		local here = g.Rig.Root.Position
		steamBurst(g.Rig.Head, g.Kind.Height * 0.25, 40)
		Broadcast.Shake(here, 1.6)
		for _, player in playerList do
			local root = aliveRoot(player)
			if root and not held[player] and (root.Position - here).Magnitude < B.RoarRadius then
				knock(player, root.Position - here, 0.5, 110)
			end
		end
		packCall(g)
	end)
end

local function powers(giant: Giant, now: number)
	local B = Config.Beast
	local here = giant.Rig.Root.Position
	if now >= giant.NextRoarAt then
		for _, player in playerList do
			local root = aliveRoot(player)
			if root and (root.Position - here).Magnitude < B.RoarRadius * 0.8 then
				giant.NextRoarAt = now + B.RoarEvery
				roar(giant)
				return
			end
		end
	end
	if now >= giant.NextThrowAt then
		-- Someone out of reach: up high, or far away.
		local best, bestRoot, bestDistance = nil, nil, B.ThrowRange
		for _, player in playerList do
			local root = aliveRoot(player)
			if root and not held[player] then
				local distance = (root.Position - here).Magnitude
				local outOfReach = heightAboveGround(player, root) >= giant.Kind.Height * 1.05 or distance > 90
				if outOfReach and distance < bestDistance then
					best, bestRoot, bestDistance = player, root, distance
				end
			end
		end
		if best and bestRoot then
			giant.NextThrowAt = now + rng:NextNumber(B.ThrowEvery[1], B.ThrowEvery[2])
			throwBoulder(giant, best, bestRoot)
		end
	end
end

-- === The brain ===============================================================

-- Other hunters within IsolatedRadius of `pos`.
local function crowd(player: Player, pos: Vector3): number
	local count = 0
	for _, other in playerList do
		if other ~= player then
			local root = aliveRoot(other)
			if root and (root.Position - pos).Magnitude < AI.IsolatedRadius then
				count += 1
			end
		end
	end
	return count
end

-- Close to a grabbed friend (about to cut them loose).
local function rescuer(pos: Vector3): boolean
	for _, holder in held do
		local root = holder.HeldRoot
		if root and (root.Position - pos).Magnitude < AI.RescueRadius then
			return true
		end
	end
	return false
end

-- Other giants already chasing `player`.
local function attackers(giant: Giant, player: Player): number
	local count = 0
	for _, other in giants do
		if other ~= giant and other.Target == player and other.Brain.Plan == "Chase" and not other.Circling and not other.Defeated then
			count += 1
		end
	end
	return count
end

-- One look round (and listen): who it sees and would go for, who's behind
-- it, round its feet, perched out of reach, or gassing about nearby. Only
-- locals and the giant's own fields: nothing allocated.
local function perceive(giant: Giant, now: number)
	local tune = giant.Tune
	local body = giant.Rig.Root
	local here = body.Position
	local h = giant.Kind.Height
	local look = body.CFrame.LookVector
	local lookFlat = math.sqrt(look.X * look.X + look.Z * look.Z)
	local fx, fz = 0, 1
	if lookFlat > 1e-3 then
		fx, fz = look.X / lookFlat, look.Z / lookFlat
	end
	local C = AI.Climb
	local sight = tune.SightBase + tune.SightPerHeight * h
	local maxAbove = h * tune.MaxAbove + giant.Lift
	local behindRange = h * AI.BehindRange + 8
	local feet = h * AI.Stomp.Radius
	local climbTop = h * 1.05 + math.clamp(h * C.Rise, C.MinRise, C.MaxRise) + h * C.Reach
	local breached = Wall.IsBreached()
	local abnormal = giant.Mind == "Abnormal"
	local sticky = abnormal and giant.Target ~= nil and now < giant.TargetUntil
	local maxAttackers = if tune.Coordinate then AI.MaxPerHunter else math.huge
	local best: Player?, bestRoot: BasePart?, bestScore = nil, nil, math.huge
	local bestFlat, bestAbove, bestDot = 0, 0, 0
	local behind: Player?, behindPos, behindFlat = nil, here, math.huge
	local close, closeSum = 0, Vector3.zero
	local nearFeet = 0
	local loud: Vector3?, loudFlat = nil, if tune.Hearing then tune.HearBase + tune.HearPerHeight * h else 0
	local perch: Player?, perchRoot: BasePart?, perchFlat = nil, nil, h * C.Range
	for _, player in playerList do
		local root = aliveRoot(player)
		if root and not held[player] then
			local pos = root.Position
			local dx, dz = pos.X - here.X, pos.Z - here.Z
			local flat = math.sqrt(dx * dx + dz * dz)
			if flat < sight then
				local dot = if flat > 1 then (dx * fx + dz * fz) / flat else 1
				local above = heightAboveGround(player, root)
				if flat < behindRange then
					close += 1
					closeSum += pos
					if dot <= Config.Giants.BehindDot and flat < behindFlat then
						behind, behindPos, behindFlat = player, pos, flat
					end
				end
				if above <= AI.Stomp.MaxAbove and flat <= feet then
					nearFeet += 1
				end
				if flat < loudFlat and Motion.Velocity(player).Magnitude >= AI.LoudSpeed then
					loud, loudFlat = pos, flat
				end
				if dot > tune.ConeDot then
					if above <= maxAbove then
						local score
						if abnormal then
							-- Anyone: high up, far off, in a group - not the nearest.
							score = if sticky and player == giant.Target then -math.huge else rng:NextNumber(0, 100) - above * 1.5 - flat * 0.3 - crowd(player, pos) * 25
						elseif tune.Smart then
							score = GiantBrain.TargetScore(flat, true, crowd(player, pos) == 0, rescuer(pos), player == giant.Target, attackers(giant, player), maxAttackers, AI.TargetBonus)
						else
							score = flat -- the nearest, always
						end
						if score < bestScore and Geo.NextWaypoint(here, pos, breached) then
							best, bestRoot, bestScore = player, root, score
							bestFlat, bestAbove, bestDot = flat, above, dot
						end
					elseif tune.Climb and flat < perchFlat and above <= climbTop and Geo.RadiusOf(pos) < Geo.INSIDE_LIMIT - 8 and Geo.IsInside(here) and Motion.Velocity(player).Magnitude < 6 then
						-- Perched on a house just out of reach (never the Great Wall).
						perch, perchRoot, perchFlat = player, root, flat
					end
				end
			end
		end
	end
	giant.Seen, giant.SeenRoot = best, bestRoot
	giant.SeenFlat, giant.SeenAbove, giant.SeenDot = bestFlat, bestAbove, bestDot
	giant.Circling = tune.Coordinate and bestScore >= 50000
	if abnormal then
		if best ~= giant.Target and not sticky then
			giant.Target = best
			giant.TargetUntil = now + rng:NextNumber(6, 10)
		end
	else
		giant.Target = best
	end
	if behind ~= giant.Behind then
		giant.Behind = behind
		giant.BehindSince = now
	end
	giant.BehindPos = behindPos
	giant.Close = close
	giant.CloseAt = if close > 0 then closeSum / close else here
	giant.NearFeet = nearFeet
	giant.Loud = loud
	if perch ~= giant.Perch or (perchRoot and (perchRoot.Position - giant.PerchPos).Magnitude > 10) then
		giant.Perch = perch
		giant.PerchRoot = perchRoot
		giant.PerchSince = now
		if perchRoot then
			giant.PerchPos = perchRoot.Position
		end
	end
end

-- Show what a new plan means (a turn, a look round, a sniff, a crouch).
local function planChanged(giant: Giant, before: string)
	local plan = giant.Brain.Plan
	local model = giant.Rig.Model
	if before == "Ambush" then
		model:SetAttribute("Ambush", false)
	elseif before == "Brace" then
		giant.BracePos = nil
	end
	giant.FaceAt = nil
	local point = giant.Point
	local free = not giant.Busy and giant.ActionName == ""
	if plan == "Notice" or plan == "Listen" then
		giant.FaceAt = point
		lookAt(giant, point)
		if point and free then
			local toward = Geo.Flat(point - giant.Rig.Root.Position)
			if toward.Magnitude > 1 and toward.Unit:Dot(Geo.Flat(giant.Rig.Root.CFrame.LookVector).Unit) < 0.6 then
				flavour(giant, "Turn")
			end
		end
	elseif plan == "Search" then
		lookAt(giant, nil)
		if free then
			flavour(giant, "Search")
		end
	elseif plan == "Sniff" then
		lookAt(giant, point)
		if free then
			flavour(giant, "Sniff")
		end
	elseif plan == "Ambush" then
		model:SetAttribute("Ambush", true) -- crouched and still: the clients pose it
		giant.FaceAt = point
		lookAt(giant, point)
	elseif plan == "Wander" or plan == "Chase" then
		lookAt(giant, nil)
	end
end

-- Off cooldown and in this mind's repertoire.
local function can(giant: Giant, name: string, now: number): boolean
	return giant.Tune.Attacks[name] == true and offCooldown(giant, name, now)
end

-- Pick a move, if any (it's free: not Busy, hand not guarding).
local function decide(giant: Giant, now: number)
	local tune, brain = giant.Tune, giant.Brain
	local plan = brain.Plan
	local h = giant.Kind.Height
	if giant.WantRoar then
		giant.WantRoar = false
		if offCooldown(giant, "Roar", now) then
			roarCall(giant)
			return
		end
	end
	if tune.Shake and offCooldown(giant, "Shake", now) and hookedOnto(giant, now) then
		shake(giant)
		return
	end
	-- Badly hurt: back away from the hunters, facing them (and the hand
	-- over the nape, if it has one). Armour on: it doesn't.
	if tune.Retreat > 0 and plan ~= "Retreat" and giant.Close > 0 and offCooldown(giant, "Retreat", now) then
		local full = giant.Kind.NapeHealth
		local napeNow = giant.Rig.Model:GetAttribute("NapeHealth")
		local armourOff = giant.Kind.Armor == nil or (giant.Armor <= 0 and rng:NextNumber() < 0.4)
		if type(napeNow) == "number" and full >= 2 and napeNow > 0 and napeNow <= full * tune.Retreat and armourOff then
			giant.NextAt.Retreat = now + AI.Retreat.Time + cooldown(giant, "Retreat")
			GiantBrain.SetPlan(brain, "Retreat", now + AI.Retreat.Time)
			syncMood(giant)
			if giant.Rig.GuardHand and not giant.GuardWinding and not guarding(giant) then
				guard(giant, now, true)
			end
			return
		end
	end
	if tune.Brace and plan ~= "Brace" and plan ~= "Retreat" and giant.Close >= 2 and offCooldown(giant, "Brace", now) then
		brace(giant, now)
		syncMood(giant)
		return
	end
	-- Someone has stayed close behind it too long: it may turn round.
	local turnAfter = GiantBrain.Lerp(tune.TurnAfter, difficulty)
	if turnAfter > 0 and giant.Behind and now - giant.BehindSince >= turnAfter and offCooldown(giant, "Turn", now) then
		giant.NextAt.Turn = now + cooldown(giant, "Turn")
		giant.BehindSince = now
		if rng:NextNumber() < tune.TurnChance then
			giant.Point = giant.BehindPos
			brain.Memory = true
			brain.LastSeenAt = now
			GiantBrain.SetPlan(brain, "Notice", now + GiantBrain.Lerp(tune.Reaction, difficulty))
			syncMood(giant)
			giant.FaceAt = giant.BehindPos
			lookAt(giant, giant.BehindPos)
			flavour(giant, "Turn")
			return
		end
	end
	-- Abnormals: a sudden change of mind (and of zig-zag).
	if tune.TwitchChance > 0 and giant.ActionName == "" and rng:NextNumber() < tune.TwitchChance * AI.ThinkInterval then
		giant.Phase += math.pi
		flavour(giant, "Turn")
	end
	if tune.Climb and giant.Perch and giant.PerchRoot and plan ~= "Climb" and not giant.Crawl and not giant.Kind.Powers and now - giant.PerchSince >= AI.Climb.After and offCooldown(giant, "Climb", now) then
		giant.ClimbPlayer, giant.ClimbRoot = giant.Perch, giant.PerchRoot
		giant.NextAt.Climb = now + cooldown(giant, "Climb")
		GiantBrain.SetPlan(brain, "Climb", now + 12) -- walk over; move() starts the climb
		syncMood(giant)
		return
	end
	if plan == "Climb" then
		return
	end
	local seen, seenRoot = giant.Seen, giant.SeenRoot
	if seen and seenRoot and (plan == "Chase" or plan == "Ambush") then
		local position = seenRoot.Position
		if tune.TauntChance > 0 and plan == "Chase" and giant.SeenFlat > 40 and giant.SeenFlat < 140 and offCooldown(giant, "Taunt", now) then
			giant.NextAt.Taunt = now + cooldown(giant, "Taunt")
			if rng:NextNumber() < tune.TauntChance then
				GiantBrain.SetPlan(brain, "Taunt", now + (timing("Taunt")))
				giant.FaceAt = position
				flavour(giant, "Taunt")
				return
			end
		end
		local f = giant.Facts
		f.Size = h
		f.GrabReach = giant.Kind.GrabReach
		f.Flat, f.Above, f.Dot = giant.SeenFlat, giant.SeenAbove, giant.SeenDot
		f.Perched = Motion.Velocity(seen).Magnitude < 8
		f.ChestDist = (position - chestPoint(giant)).Magnitude
		f.NearFeet = giant.NearFeet
		f.Lift = giant.Lift
		local ambush = plan == "Ambush"
		f.Grab = tune.Attacks.Grab == true and now >= giant.NextGrabAt
		f.Stomp = not ambush and can(giant, "Stomp", now)
		f.Swipe = not ambush and can(giant, "Swipe", now)
		f.Crouch = not ambush and can(giant, "Crouch", now)
		f.Lunge = can(giant, "Lunge", now)
		local pick = GiantBrain.PickAttack(f, AI)
		if pick then
			if ambush then
				GiantBrain.SetPlan(brain, "Chase", now)
				syncMood(giant)
			end
			if pick == "Grab" then
				tryGrab(giant, seen, seenRoot)
			elseif pick == "Swipe" then
				tellThen(giant, position, function(g)
					swipe(g, seen, seenRoot)
				end)
			elseif pick == "Lunge" then
				local fake = rng:NextNumber() < tune.FeintChance
				tellThen(giant, position, function(g)
					if fake then
						feint(g, seen, seenRoot)
					else
						lunge(g, seen, seenRoot)
					end
				end)
			elseif pick == "Crouch" then
				tellThen(giant, position, function(g)
					crouch(g, seen, seenRoot)
				end)
			elseif pick == "Stomp" then
				tellThen(giant, position, function(g)
					stomp(g, position)
				end)
			end
			return
		end
	end
	-- Anyone flying round its head in front: a swat.
	if now >= giant.NextSwatAt then
		local swatPlayer, swatRoot = swatTarget(giant)
		if swatPlayer and swatRoot then
			swat(giant, swatPlayer, swatRoot)
		end
	end
end

-- A small mindless giant tags along with a big one close by.
local function flockLeader(giant: Giant): Giant?
	local F = AI.Flock
	if giant.Mind ~= "Mindless" or giant.Kind.Height > F.MaxHeight or giant.Roamer or giant.Hurry then
		return nil
	end
	local here = giant.Rig.Root.Position
	local best, bestDistance = nil, F.Radius
	for _, other in giants do
		if other ~= giant and not other.Defeated and other.Kind.Height >= F.LeaderHeight then
			local d = (other.Rig.Root.Position - here).Magnitude
			if d < bestDistance and Geo.IsInside(other.Rig.Root.Position) == Geo.IsInside(here) then
				best, bestDistance = other, d
			end
		end
	end
	return best
end

local function move(giant: Giant, now: number)
	local brain = giant.Brain
	local plan = brain.Plan
	local here = giant.Rig.Root.Position
	if giant.Busy or now < giant.RecoilUntil then
		local to = giant.MoveTo
		if to and now >= giant.MoveFrom and now < giant.MoveUntil then
			steer(giant, to, giant.MoveSpeed, to) -- a lunge's dive
		else
			steer(giant, nil) -- feet planted while it winds up
		end
		return
	end
	local h = giant.Kind.Height
	local speed = MOOD_SPEED[brain.Mood] or 1
	local breached = Wall.IsBreached()
	if plan == "Chase" then
		local seenRoot = giant.SeenRoot
		local goal = if seenRoot then seenRoot.Position else giant.Point
		if not goal then
			steer(giant, nil)
			return
		end
		if giant.Circling then
			-- Two friends are on that one already: circle round, waiting.
			local away = Geo.Flat(here - goal)
			local out = if away.Magnitude > 1 then away.Unit else Vector3.new(1, 0, 0)
			local side = Vector3.new(out.Z, 0, -out.X)
			goal += (out * 0.6 + side * 0.8).Unit * (h * AI.CircleRadius + 20)
		end
		local waypoint = Geo.NextWaypoint(here, goal, breached)
		if not waypoint then
			steer(giant, nil)
			return
		end
		if giant.Kind.Armor and giant.Armor > 0 then
			speed *= 1.1 -- armour on: it charges
		end
		if giant.Kind.Abnormal then
			-- Zig-zag while far off, leap now and then.
			local toward = Geo.Flat(waypoint - here)
			if toward.Magnitude > 40 then
				local across = Vector3.new(toward.Z, 0, -toward.X).Unit
				waypoint += across * math.sin(now * 1.7 + giant.Phase) * 22
			end
			if now >= giant.NextLeapAt then
				giant.NextLeapAt = now + rng:NextNumber(Config.Giants.RunnerLeap[1], Config.Giants.RunnerLeap[2])
				giant.LeapUntil = now + 0.45
				giant.Rig.Model:SetAttribute("Leap", true)
				task.delay(0.9, function()
					giant.Rig.Model:SetAttribute("Leap", false)
				end)
			end
			if now < giant.LeapUntil then
				speed = 2.2
			end
		end
		steer(giant, waypoint, speed)
	elseif plan == "Investigate" then
		local goal = giant.Point
		local waypoint = goal and Geo.NextWaypoint(here, avoidHot(giant, goal), breached)
		if waypoint then
			steer(giant, waypoint, speed)
		else
			wander(giant)
		end
	elseif plan == "Retreat" then
		local from = if giant.Close > 0 then giant.CloseAt else (giant.Point or here)
		local away = Geo.Flat(here - from)
		local out = if away.Magnitude > 1 then away.Unit else -Geo.Flat(giant.Rig.Root.CFrame.LookVector).Unit
		local waypoint = Geo.NextWaypoint(here, avoidHot(giant, here + out * AI.Retreat.Distance), breached)
		steer(giant, waypoint, speed, from) -- backing off, facing them
	elseif plan == "Brace" then
		if giant.Close > 0 then
			giant.FaceAt = giant.CloseAt
		end
		steer(giant, giant.BracePos, 0.6, giant.FaceAt)
	elseif plan == "Climb" then
		local player, root = giant.ClimbPlayer, giant.ClimbRoot
		if not player or not root or aliveRoot(player) ~= root or held[player] then
			brain.PlanUntil = now -- gone: give up
			steer(giant, nil)
		elseif Geo.Flat(root.Position - here).Magnitude > h * AI.Climb.Approach then
			steer(giant, Geo.NextWaypoint(here, root.Position, breached), speed)
		else
			steer(giant, nil, nil, root.Position)
			climb(giant, player, root)
		end
	elseif plan == "Wander" then
		local leader = flockLeader(giant)
		if leader then
			local slot = Geo.Flat(leader.Rig.Root.Position) + Geo.Polar(giant.Phase, AI.Flock.Spacing)
			if Geo.Flat(slot - here).Magnitude > 10 then
				steer(giant, Geo.NextWaypoint(here, slot, breached), speed)
			else
				steer(giant, nil)
			end
		else
			wander(giant)
		end
	else
		-- Notice, Listen, Search, Sniff, Ambush, Taunt: stand (and look).
		if plan == "Notice" and giant.SeenRoot then
			giant.FaceAt = giant.SeenRoot.Position
		end
		steer(giant, nil)
	end
end

local function think(giant: Giant)
	if not active(giant) then
		return
	end
	local now = os.clock()
	if giant.Holding then
		steer(giant, nil)
		if now - giant.HoldStarted >= Config.Giants.HoldTime then
			caught(giant)
		end
		return
	end
	if stunned(giant) then
		endGuard(giant)
		if giant.ActionBusy then
			cancelAction(giant)
		end
		steer(giant, nil)
		return
	end
	local brain, sense, tune = giant.Brain, giant.Sense, giant.Tune
	local here = giant.Rig.Root.Position
	perceive(giant, now)
	local seenRoot = giant.SeenRoot
	local heard = false
	if seenRoot then
		giant.Point = seenRoot.Position
	elseif tune.Hearing then
		if giant.HeardAt > 0 then
			heard = true
			giant.Point = giant.HeardPos
		elseif giant.Loud then
			heard = true
			giant.Point = giant.Loud
		end
	end
	giant.HeardAt = 0
	local point = giant.Point
	local h = giant.Kind.Height
	sense.Sees = seenRoot ~= nil
	sense.Heard = heard
	sense.Arrived = point ~= nil and Geo.Flat(point - here).Magnitude < 14 + h * 0.2
	sense.InStrike = brain.Plan == "Ambush" and seenRoot ~= nil and giant.SeenDot > AI.Lunge.FrontDot and giant.SeenFlat <= giant.Kind.GrabReach + h * AI.Lunge.Reach
	sense.Reaction = GiantBrain.Lerp(tune.Reaction, difficulty)
	sense.Roll = rng:NextNumber()
	local before = brain.Plan
	GiantBrain.Update(brain, sense, tune, now)
	syncMood(giant)
	if brain.Plan ~= before then
		planChanged(giant, before)
	end
	if giant.Kind.Powers and not giant.Busy then
		powers(giant, now)
	end
	local look = giant.Kind.Look
	if look and look.Guard and not giant.Busy and not giant.GuardWinding and now >= giant.NextGuardAt then
		guard(giant, now)
	end
	-- (The guarding hand is busy: no attacks with it up.)
	if not giant.Busy and now >= giant.RecoilUntil and not giant.GuardWinding and not guarding(giant) then
		decide(giant, now)
	end
	move(giant, now)
end

-- === Spawning and takedowns ==================================================

-- Returns the new giant's model (the Golden Giant, WorldEventService,
-- dresses it up).
function GiantService.SpawnGiant(kindName: string): Model
	local point = spawnPoints[rng:NextInteger(1, #spawnPoints)] + Vector3.new(rng:NextNumber(-25, 25), 0, rng:NextNumber(-25, 25))
	local rig = GiantFactory.Build(kindName, point, rng)
	-- Face the gate (the rig is built facing -Z).
	local pivot = rig.Model:GetPivot().Position
	local facing = Geo.Flat(Geo.GateOuter() - pivot)
	if facing.Magnitude > 1 then
		rig.Model:PivotTo(CFrame.lookAt(pivot, pivot + facing.Unit))
	end
	rig.Model.Parent = folder
	rig.Root:SetNetworkOwner(nil) -- server-simulated, never handed to a nearby client
	local move = rig.Root:FindFirstChild("Move") :: AlignPosition
	local face = rig.Root:FindFirstChild("Face") :: AlignOrientation
	move.Position = rig.Root.Position
	face.CFrame = rig.Root.CFrame - rig.Root.Position
	local kind = Config.GiantKinds[kindName]
	local now = os.clock()
	-- Its mind; now and then (from round 3) a plain giant comes out Cunning.
	local mind: string = kind.Mind or "Mindless"
	local C = AI.Cunning
	local cunningKinds: { [string]: boolean } = C.Kinds :: any
	local cunning = false
	if cunningKinds[kindName] and roundNow >= C.FromRound and rng:NextNumber() < (if roundNow >= C.LateRound then C.LateChance else C.Chance) then
		cunning = true
		mind = "Intelligent"
	end
	local tune = AI.Minds[mind] or AI.Minds.Mindless
	local joints: { [string]: Motor6D } = {}
	for _, d in rig.Model:GetDescendants() do
		if d:IsA("Motor6D") then
			joints[d.Name] = d
		end
	end
	giants[rig.Model] = {
		Rig = rig,
		Kind = kind,
		Move = move,
		Face = face,
		RestY = rig.Root.Position.Y,
		NextGrabAt = now + 3,
		NextSwatAt = now + 3,
		Busy = false,
		Holding = nil,
		HeldRoot = nil,
		HoldStarted = 0,
		Struggles = 0,
		KneelUntil = 0,
		DazeUntil = 0,
		WanderTarget = nil,
		Target = nil,
		TargetUntil = 0,
		NextLeapAt = now + rng:NextNumber(2, 5),
		LeapUntil = 0,
		Phase = rng:NextNumber(0, 6),
		Armor = kind.Armor or 0,
		NextThrowAt = now + 4,
		NextRoarAt = now + 6,
		Defeated = false,
		StunStreak = 0,
		StunStreakUntil = 0,
		-- (The wave's big ones always head straight for town.)
		Roamer = not kind.Armor and not kind.Powers and rng:NextNumber() < Config.Waves.RoamChance,
		Hurry = false,
		Joints = joints,
		Crawl = rig.Model:GetAttribute("Pose") == "Crawl",
		NextGuardAt = now + 3,
		GuardUntil = 0,
		GuardWinding = false,
		Mind = mind,
		Tune = tune,
		Brain = GiantBrain.New(now),
		Sense = GiantBrain.NewSense(),
		Facts = {
			Size = kind.Height,
			GrabReach = kind.GrabReach,
			Flat = 0,
			Above = 0,
			Dot = 0,
			Perched = false,
			ChestDist = 0,
			NearFeet = 0,
			Lift = 0,
			Grab = false,
			Stomp = false,
			Swipe = false,
			Lunge = false,
			Crouch = false,
		},
		NextAt = {},
		NextThinkAt = now + rng:NextNumber(0, AI.ThinkInterval), -- (staggered)
		MoodShown = "Calm",
		Point = nil,
		HeardAt = 0,
		HeardPos = Vector3.zero,
		Seen = nil,
		SeenRoot = nil,
		SeenFlat = 0,
		SeenAbove = 0,
		SeenDot = 0,
		Circling = false,
		Loud = nil,
		Behind = nil,
		BehindPos = Vector3.zero,
		BehindSince = now,
		Close = 0,
		CloseAt = Vector3.zero,
		NearFeet = 0,
		Perch = nil,
		PerchRoot = nil,
		PerchPos = Vector3.zero,
		PerchSince = now,
		ActionName = "",
		ActionToken = 0,
		ActionBusy = false,
		RecoilUntil = 0,
		MoveTo = nil,
		MoveFrom = 0,
		MoveUntil = 0,
		MoveSpeed = 1,
		FaceAt = nil,
		Lift = 0,
		ClimbPlayer = nil,
		ClimbRoot = nil,
		BracePos = nil,
		WantRoar = false,
		LookShown = nil,
		HotSpots = { Vector3.zero, Vector3.zero, Vector3.zero },
		HotTimes = { -math.huge, -math.huge, -math.huge },
		HotNext = 1,
	}
	local model = rig.Model
	model:SetAttribute("Mind", mind)
	model:SetAttribute("Mood", "Calm")
	model:SetAttribute("Action", "")
	if cunning then
		model:SetAttribute("Cunning", true)
		Broadcast.Feed("A cunning giant is among them — it guards its nape!", "Danger")
	end
	if kind.Armor then
		rig.Model:SetAttribute("Armor", kind.Armor)
	end
	if kind.Abnormal then
		rig.Model:SetAttribute("Abnormal", true)
	end
	if kind.Powers then
		Broadcast.Announce("THE BEAST GIANT", "It throws boulders - nowhere is safe. Keep moving!", "Danger")
		Broadcast.Feed("A Beast Giant has appeared!", "Danger")
	elseif kind.Look and kind.Look.Guard then
		Broadcast.Feed("A Sprinter is coming! She can cover her nape - wait for the hand to drop", "Danger")
	end
	return rig.Model
end


-- Stop and dissolve into steam: no ragdoll, nothing scary. Only the root is
-- anchored (that holds the whole assembly still), so the motors keep the
-- pose the clients last gave it instead of snapping back to the rest pose.
local function dissolve(giant: Giant)
	giant.Defeated = true
	local model = giant.Rig.Model
	model:SetAttribute("Defeated", true)
	giant.Rig.Root.Anchored = true
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanQuery = false
			TweenService:Create(descendant, TweenInfo.new(Config.Giants.DefeatFadeTime), { Transparency = 1 }):Play()
		elseif descendant:IsA("PointLight") then
			descendant.Enabled = false
		end
	end
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Color3.fromRGB(245, 245, 250))
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, giant.Kind.Height * 0.15), NumberSequenceKeypoint.new(1, giant.Kind.Height * 0.4) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(2, 3.5)
	steam.Speed = NumberRange.new(8, 16)
	steam.SpreadAngle = Vector2.new(40, 40)
	steam.Rate = 40
	steam.Parent = giant.Rig.Torso
	task.delay(Config.Giants.DefeatFadeTime, function()
		steam.Enabled = false
	end)
	task.delay(Config.Giants.DefeatFadeTime + 3.5, function()
		model:Destroy()
		giants[model] = nil
	end)
end

local function defeat(giant: Giant, player: Player, clean: boolean, speed: number)
	release(giant, "Rescued")
	dissolve(giant)
	-- A friend falling close by may make the others angry.
	local here = giant.Rig.Root.Position
	for _, other in giants do
		if other ~= giant and active(other) and (other.Rig.Root.Position - here).Magnitude <= AI.FriendFallRadius and rng:NextNumber() < AI.FriendFallChance then
			enrage(other)
		end
	end
	GiantService.Defeated:Fire(player, giant.Kind.Name, clean, speed)
	local special = giant.Kind.Armor or giant.Kind.Powers or (giant.Kind.Look and giant.Kind.Look.Guard)
	Broadcast.Feed(`{player.DisplayName} took down a {giant.Kind.Display}!`, if special then "Gold" else "Good")
end

-- Diminishing returns on stuns: how long this trip or daze lasts, and
-- whether it still scores (only the first in a row does).
local function stunFor(giant: Giant, base: number): (number, boolean)
	local now = os.clock()
	if now >= giant.StunStreakUntil then
		giant.StunStreak = 0
	end
	local duration = math.max(base * Config.Cuts.RepeatFactor ^ giant.StunStreak, Config.Cuts.MinStun)
	local scores = giant.StunStreak == 0
	giant.StunStreak += 1
	giant.StunStreakUntil = now + Config.Cuts.RepeatWindow
	return duration, scores
end

local function breakArmor(giant: Giant, player: Player)
	local plate = giant.Rig.ArmorPlate
	giant.Rig.Model:SetAttribute("Armor", 0)
	if plate then
		for _, joint in plate:GetChildren() do
			if joint:IsA("WeldConstraint") then
				joint:Destroy()
			end
		end
		for _, other in giant.Rig.Model:GetDescendants() do
			if other:IsA("WeldConstraint") and other.Part1 == plate then
				other:Destroy()
			end
		end
		plate.CanQuery = false
		plate.CanCollide = true
		plate.Massless = false
		plate.AssemblyLinearVelocity = Vector3.new(0, 20, 0) + giant.Rig.Root.CFrame.LookVector * -25
		Debris:AddItem(plate, 6)
	end
	GiantService.Assist:Fire(player, "Armor")
	Broadcast.Feed(`{player.DisplayName} cracked an Armored Giant's plate!`, "Gold")
end

local function trip(giant: Giant, duration: number)
	giant.KneelUntil = os.clock() + duration
	giant.LeapUntil = 0
	endGuard(giant)
	local model = giant.Rig.Model
	model:SetAttribute("Kneeling", true)
	task.delay(duration, function()
		if os.clock() >= giant.KneelUntil - 0.05 and model.Parent then
			model:SetAttribute("Kneeling", false)
		end
	end)
end

local function daze(giant: Giant, duration: number)
	giant.DazeUntil = math.max(giant.DazeUntil, os.clock() + duration)
	endGuard(giant)
	local model = giant.Rig.Model
	model:SetAttribute("Dazed", true)
	task.delay(duration, function()
		if os.clock() >= giant.DazeUntil - 0.05 and model.Parent then
			model:SetAttribute("Dazed", false)
		end
	end)
end

-- Frees whoever the giant is holding, crediting the hunter who cut them loose.
local function rescue(giant: Giant, player: Player): string?
	local captive = giant.Holding
	if not captive or captive == player then
		return nil
	end
	release(giant, "Rescued")
	GiantService.Assist:Fire(player, "Rescue")
	Broadcast.Feed(`{player.DisplayName} cut {captive.DisplayName} loose!`, "Good")
	return captive.DisplayName
end

-- `damage`: 1 for a full hit, 0.5 for a slow one. Armour plates crack by
-- hits; the nape itself takes `damage` x `napeMult` (a hunter's level and
-- gear: Stats.DamageMult). Nape health is fractional (kept to thousandths so
-- rounding never leaves a sliver).
local function applyDamage(giant: Giant, player: Player, damage: number, clean: boolean, speed: number, napeMult: number?): (HitResult, HitInfo)
	local info: HitInfo = { Kind = giant.Kind.Display, Clean = clean, Speed = speed, Position = giant.Rig.Nape.Position }
	info.Rescued = rescue(giant, player)
	if giant.Armor > 0 then
		giant.Armor = math.max(giant.Armor - damage, 0)
		giant.Rig.Model:SetAttribute("Armor", giant.Armor)
		if giant.Armor <= 0 then
			breakArmor(giant, player)
			return "ArmorBroken", info
		end
		info.Remaining = math.ceil(giant.Armor)
		return "Armor", info
	end
	local model = giant.Rig.Model
	local before = model:GetAttribute("NapeHealth")
	local health = (if type(before) == "number" then before else 0) - damage * (napeMult or 1)
	health = math.floor(health * 1000 + 0.5) / 1000
	model:SetAttribute("NapeHealth", math.max(health, 0))
	if health <= 0 then
		defeat(giant, player, clean, speed)
		return "Defeated", info
	end
	return "Hit", info
end

local function cutNape(giant: Giant, player: Player, speed: number): (HitResult, HitInfo)
	local clean = speed >= Config.Blades.CleanCutSpeed
	return applyDamage(giant, player, if clean then 1 else 0.5, clean, speed, Stats.For(player).DamageMult)
end

-- A titan shifter's punch (on the hunters' side): every giant within
-- `radius` of `centre` takes a full hit and staggers.
function GiantService.Punch(player: Player, centre: Vector3, radius: number): number
	local count = 0
	for _, giant in giants do
		if not giant.Defeated then
			local reach = radius + giant.Rig.TorsoWidth / 2
			local body = giant.Rig.Root.Position + Vector3.new(0, giant.Rig.TorsoHeight * 0.5, 0)
			if (body - centre).Magnitude <= reach or (giant.Rig.Head.Position - centre).Magnitude <= reach then
				count += 1
				rescue(giant, player)
				daze(giant, 1.5)
				applyDamage(giant, player, 1, true, 0)
			end
		end
	end
	return count
end

-- A titan shifter's roar (hunters' side): daze every giant close by.
function GiantService.DazeAround(centre: Vector3, radius: number)
	for _, giant in giants do
		if not giant.Defeated and (giant.Rig.Root.Position - centre).Magnitude <= radius then
			daze(giant, Config.Cuts.DazeTime)
		end
	end
end

function GiantService.HasKind(kindName: string): boolean
	for _, giant in giants do
		if not giant.Defeated and giant.Kind.Name == kindName then
			return true
		end
	end
	return false
end

-- In front of a giant's face (where its eyes are, and its nape isn't).
local function facing(giant: Giant, here: Vector3): boolean
	local toHunter = here - giant.Rig.Head.Position
	return toHunter.Magnitude > 0.01 and toHunter.Unit:Dot(giant.Rig.Root.CFrame.LookVector) > Config.Cuts.EyesFrontDot
end

-- Where the nape is drawn while a giant lunges, holds or kneels (the
-- clients lean its trunk; the server only has the rest pose), or nil when
-- it's standing normally.
local function posedNape(giant: Giant): Vector3?
	local model = giant.Rig.Model
	local reach = if model:GetAttribute("Grabbing") then 1 else 0
	local hold = if model:GetAttribute("Holding") then 1 else 0
	local kneel = if model:GetAttribute("Kneeling") then 1 else 0
	if reach + hold + kneel == 0 then
		return nil
	end
	-- (The same lean as GiantAnimator.Pose: a crawler rears up to grab and
	-- flattens down when its legs are cut; its rest pose is in Waist.C0.)
	local lean = if giant.Crawl then reach * 0.5 - kneel * 0.12 + hold * 0.35 else -reach * 0.22 - kneel * 0.35 + hold * 0.08
	local rest = posedTorso(giant, 0)
	local posed = posedTorso(giant, lean)
	if not rest or not posed then
		return nil
	end
	return posed:PointToWorldSpace(rest:PointToObjectSpace(giant.Rig.Nape.Position))
end

-- Called by HunterService after it has validated the slash (cooldown,
-- blades, a believable position). `speed` is the server's own measure of the
-- hunter's speed (Motion.CutSpeed). The nape comes first (from behind or the
-- side; a guarding Sprinter's hand blocks it, no blade used); then the eyes
-- (from in front); then an ankle.
function GiantService.TryHit(player: Player, root: BasePart, speed: number): (HitResult, HitInfo)
	local here = root.Position
	local reachBase = Config.Blades.SlashRange

	local best: Giant? = nil
	local bestDistance = math.huge
	local blocked: Giant? = nil -- the nearest nape in reach behind a guarding hand
	local blockedDistance = math.huge
	for _, giant in giants do
		if not giant.Defeated and not facing(giant, here) then
			local nape = giant.Rig.Nape
			local reach = reachBase + nape.Size.X / 2
			local d = (nape.Position - here).Magnitude
			local posed = posedNape(giant)
			if posed then
				-- Lunging, holding or kneeling: wherever the nape is drawn.
				d = math.min(d, (posed - here).Magnitude)
				reach += Config.Cuts.PosedNapeSlack
			end
			-- The new moves (a dive, a crouch, a climb...) move it too.
			local slack = NAPE_SLACK[giant.ActionName] or 0
			if giant.Brain.Plan == "Ambush" then
				slack = math.max(slack, NAPE_SLACK.Crouch or 0)
			end
			reach += slack
			if d <= reach then
				if guarding(giant) then
					if d < blockedDistance then
						blocked, blockedDistance = giant, d
					end
				elseif d < bestDistance then
					best, bestDistance = giant, d
				end
			end
		end
	end
	if best then
		local result: HitResult, info = cutNape(best, player, speed)
		if result ~= "Defeated" then
			local hard = result == "ArmorBroken" or (info.Clean == true and speed >= AI.StaggerSpeed)
			hurt(best, here, if hard then "Stagger" else "Flinch")
		end
		return result, info
	end
	if blocked then
		local hand = blocked.Rig.GuardHand or blocked.Rig.Nape
		return "Guarded", { Kind = blocked.Kind.Display, Position = hand.Position }
	end

	for _, giant in giants do
		if not giant.Defeated and facing(giant, here) then
			local head = giant.Rig.Head
			if (here - head.Position).Magnitude <= reachBase + giant.Rig.HeadSize / 2 then
				local info: HitInfo = { Kind = giant.Kind.Display, Position = head.Position }
				info.Rescued = rescue(giant, player)
				local duration, scores = stunFor(giant, Config.Cuts.DazeTime)
				daze(giant, duration)
				hurt(giant, here, nil)
				if scores then
					GiantService.Assist:Fire(player, "Daze")
				end
				return "Daze", info
			end
		end
	end

	for _, giant in giants do
		if not giant.Defeated and os.clock() >= giant.KneelUntil then
			for _, foot in giant.Rig.Feet do
				if (foot.Position - here).Magnitude <= reachBase + foot.Size.Z / 2 then
					local info: HitInfo = { Kind = giant.Kind.Display, Position = foot.Position }
					info.Rescued = rescue(giant, player)
					local duration, scores = stunFor(giant, Config.Cuts.TripTime)
					trip(giant, duration)
					hurt(giant, here, nil)
					if scores then
						GiantService.Assist:Fire(player, "Trip")
					end
					return "Trip", info
				end
			end
		end
	end
	return "NoTarget", {}
end

-- A held hunter mashing to get free.
function GiantService.Struggle(player: Player)
	local giant = held[player]
	if not giant then
		return
	end
	local now = os.clock()
	if now - (lastStruggle[player] or 0) < 1 / Config.Hunters.StruggleRate then
		return
	end
	lastStruggle[player] = now
	giant.Struggles += 1
	if giant.Struggles >= Config.Giants.StruggleToEscape then
		release(giant, "Escaped")
	else
		-- The wriggle bar follows this count, not the client's own.
		remote(Config.Remotes.Held):FireClient(player, "Wriggle", { Count = giant.Struggles, Needed = Config.Giants.StruggleToEscape })
	end
end

function GiantService.IsHeld(player: Player): boolean
	return held[player] ~= nil
end

-- For the wall cannons: the nearest giant whose head is in range.
function GiantService.CannonTarget(from: Vector3, range: number): (Model?, BasePart?)
	local best, bestHead, bestDistance = nil, nil, range
	for model, giant in giants do
		if not giant.Defeated then
			local d = (giant.Rig.Head.Position - from).Magnitude
			if d < bestDistance then
				best, bestHead, bestDistance = model, giant.Rig.Head, d
			end
		end
	end
	return best, bestHead
end

function GiantService.CannonHit(model: Model, player: Player)
	local giant = giants[model]
	if giant and not giant.Defeated then
		-- It staggers (then the daze), and the shot is heard round about.
		local shooter = aliveRoot(player)
		local from = if shooter then shooter.Position else giant.Rig.Head.Position
		hurt(giant, from, "Stagger")
		GiantService.Noise(from, AI.Noise.Cannon)
		local duration, scores = stunFor(giant, Config.Cuts.DazeTime)
		daze(giant, duration)
		steamBurst(giant.Rig.Head, giant.Kind.Height * 0.2, 20)
		rescue(giant, player)
		if scores then
			GiantService.Assist:Fire(player, "Cannon")
		end
	end
end

function GiantService.AliveCount(): number
	local count = 0
	for _, giant in giants do
		if not giant.Defeated then
			count += 1
		end
	end
	return count
end

-- How hard the giants inside the wall are pressing on the district: one per
-- 30 studs of giant.
function GiantService.InsideWeight(): number
	local weight = 0
	for _, giant in giants do
		if active(giant) and Geo.IsInside(giant.Rig.Root.Position) then
			weight += giant.Kind.Height / 30
		end
	end
	return weight
end

-- The wave's time is up: every giant storms into town, faster, and any
-- straggler further out than `radius` steams away (no points).
function GiantService.Hurry(radius: number): number
	local gone = 0
	for _, giant in giants do
		if active(giant) then
			giant.Hurry = true
			giant.Roamer = false
			giant.WanderTarget = nil
			local brain = giant.Brain
			if brain.Plan ~= "Chase" and not giant.Busy then
				-- No more dawdling: straight into town.
				brain.Memory = false
				GiantBrain.SetPlan(brain, "Wander", os.clock())
			end
			if Geo.RadiusOf(giant.Rig.Root.Position) > radius and not giant.Holding then
				gone += 1
				dissolve(giant)
			end
		end
	end
	return gone
end

-- Everyone left (or the district fell): clear the field.
function GiantService.ClearAll()
	for model, giant in giants do
		release(giant, "Gone")
		giant.Defeated = true
		model:Destroy()
	end
	table.clear(giants)
end

-- === Hooks, noise and the round ==============================================

-- HunterService's cable relay: `player`'s `side` hook now bites `part` (nil:
-- let go). The Shake needs to know who is hooked onto which giant.
function GiantService.NoteHook(player: Player, side: string, part: BasePart?)
	if side ~= "Left" and side ~= "Right" then
		return
	end
	local note = hooked[player]
	if not note then
		note = { Left = nil, Right = nil, Since = 0 }
		hooked[player] = note
	end
	local model: Model? = nil
	if part then
		local found = part:FindFirstAncestorWhichIsA("Model")
		while found and not giants[found] do
			found = found:FindFirstAncestorWhichIsA("Model")
		end
		model = found
	end
	local entry = note :: HookNote
	local was = entry.Left or entry.Right
	if side == "Left" then
		entry.Left = model
	else
		entry.Right = model
	end
	local on = entry.Left or entry.Right
	if on and on ~= was then
		entry.Since = os.clock()
	end
end

-- A loud noise (a flare going up, a cannon shot): giants that can hear,
-- within `radius`, turn to look and come to see.
function GiantService.Noise(position: Vector3, radius: number)
	local now = os.clock()
	for _, giant in giants do
		if active(giant) and giant.Tune.Hearing and (giant.Rig.Root.Position - position).Magnitude <= radius then
			giant.HeardAt = now
			giant.HeardPos = position
		end
	end
end

-- The round number (WaveService): reactions and cooldowns sharpen, and
-- Cunning giants appear from Config.GiantAI.Cunning.FromRound.
function GiantService.SetRound(round: number)
	roundNow = round
	difficulty = GiantBrain.Difficulty(round, AI.RoundsToFull)
end

-- === The Wallbreaker =========================================================
-- A giant taller than the wall appears outside the south gate in a burst of
-- light and steam, peers over, kicks the gate in, and steams away. Yields
-- until it's gone.

function GiantService.RunWallbreaker()
	local W = Config.World
	local kind = Config.GiantKinds.Wallbreaker
	local outward = Geo.Polar(W.GateAngle, 1)
	local at = Geo.Polar(W.GateAngle, W.WallRadius + W.WallThickness + kind.Height * 0.3)
	local rig = GiantFactory.Build("Wallbreaker", at, rng)
	local model = rig.Model
	local pivot = model:GetPivot().Position
	model:PivotTo(CFrame.lookAt(pivot, pivot - outward))
	rig.Root.Anchored = true -- an anchored root anchors the assembly; its motors still animate
	model:SetAttribute("Event", true)
	local fades: { [BasePart]: number } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= rig.Root then
			fades[d] = d.Transparency
			d.Transparency = 1
			d.CanQuery = false
		end
	end
	model.Parent = folder

	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 230, 190)
	flash.Range = 60
	flash.Brightness = 12
	flash.Parent = rig.Torso
	TweenService:Create(flash, TweenInfo.new(1.6), { Brightness = 0 }):Play()
	steamBurst(rig.Torso, kind.Height * 0.25, 60)
	for part, transparency in fades do
		TweenService:Create(part, TweenInfo.new(1.2), { Transparency = transparency }):Play()
	end
	Broadcast.Shake(at, 1.5)
	Broadcast.Announce("THE WALLBREAKER", "It's going to kick the gate in!", "Danger")
	task.wait(2.8)
	model:SetAttribute("Kick", true)
	task.wait(0.75)
	Wall.Breach()
	Broadcast.Shake(Geo.Polar(W.GateAngle, W.WallRadius), 2.4)
	Broadcast.Announce("THE GATE IS BREACHED!", "Giants are coming through - hold the district!", "Danger")
	Broadcast.Feed("The south gate has been breached!", "Danger")
	task.wait(1.6)
	model:SetAttribute("Kick", false)
	task.wait(1)
	steamBurst(rig.Torso, kind.Height * 0.3, 90)
	for part in fades do
		TweenService:Create(part, TweenInfo.new(2.5), { Transparency = 1 }):Play()
	end
	task.wait(2.8)
	model:Destroy()
end

function GiantService.Init(points: { Vector3 })
	spawnPoints = points
	folder = Instance.new("Folder")
	folder.Name = "Giants"
	folder.Parent = Workspace
	remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder

	braceParams.FilterDescendantsInstances = { folder }
	for _, player in Players:GetPlayers() do
		table.insert(playerList, player)
	end
	Players.PlayerAdded:Connect(function(player)
		table.insert(playerList, player)
	end)

	-- Each giant thinks every ThinkInterval, its turn staggered from the
	-- others' so the work spreads over the frames.
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, giant in giants do
			if now >= giant.NextThinkAt then
				giant.NextThinkAt = now + AI.ThinkInterval
				local ok, err = pcall(think :: any, giant)
				if not ok then
					warn("[GiantService] think failed:", err)
				end
			end
		end
	end)

	-- Carry held hunters in the giant's hand; let go if anything vanishes,
	-- or if the body in its hand is no longer the hunter's live character
	-- (they died, reset or respawned).
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for player, giant in held do
			local root = giant.HeldRoot
			if not root or aliveRoot(player) ~= root or not active(giant) or not player.Parent then
				release(giant, "Gone")
			else
				root.CFrame = holdFrame(giant, t)
			end
		end
	end)

	remote(Config.Remotes.Struggle).OnServerEvent:Connect(function(player)
		GiantService.Struggle(player)
	end)
	local function letGo(player: Player)
		local giant = held[player]
		if giant then
			release(giant, "Gone")
		end
	end
	-- A held hunter who dies or respawns is let go at once.
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			letGo(player)
		end)
		player.CharacterAdded:Connect(function(character)
			letGo(player)
			hooked[player] = nil
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					letGo(player)
				end)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		letGo(player)
		lastStruggle[player] = nil
		heightCache[player] = nil
		hooked[player] = nil
		local index = table.find(playerList, player)
		if index then
			table.remove(playerList, index)
		end
	end)
end

return GiantService
