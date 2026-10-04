--!strict
-- Giants: spawning, the AI, and everything they do to hunters (and that
-- hunters do to them).
--
-- AI, four decisions a second each:
--   * Chase the nearest hunter it can reach (on the ground, or low on a
--     building), walking round the wall and through the gate only once it
--     has been breached. Nobody in reach: amble about town, or from
--     outside, head through the breach.
--   * A hunter in grabbing distance: arms up (the warning), then the grab.
--     The hunter is HELD in its hand: wriggle free (mash a key), get cut
--     loose by a friend, or after a few seconds be caught and sent back to
--     the wall.
--   * A hunter flying round its head, in front or to the side: a swat that
--     knocks them away. It never sees behind it - that's where you attack.
--   * Runners (abnormals) sprint, zig-zag, leap, and pick their own prey.
--   * Sprinters now and then cover their nape: a hunter close behind them,
--     a short wind-up (attribute "GuardWindup", the hand starts to rise),
--     then the crystal hand sits over the nape for a moment ("Guarding").
--
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
local GiantFactory = require(script.Parent.GiantFactory)
local Wall = require(script.Parent.World.Wall)
local Layout = require(script.Parent.World.Layout)
local Broadcast = require(script.Parent.Broadcast)
local DayNightService = require(script.Parent.DayNightService)
local Motion = require(script.Parent.Motion)
local Respawn = require(script.Parent.Respawn)

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
	heightCache[player] = { Time = now, Height = height }
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

local function steer(giant: Giant, toward: Vector3?, speedScale: number?)
	local root = giant.Rig.Root
	local now = os.clock()
	local here = root.Position
	local goal = if toward then avoidCastle(here, toward) else here
	local y = giant.RestY
	if now < giant.KneelUntil then
		y -= giant.Rig.ShinLength * 0.95
	elseif now < giant.LeapUntil then
		y += giant.Kind.Height * 0.3
	end
	local hurry = if giant.Hurry then Config.Waves.HurrySpeed else 1
	giant.Move.MaxVelocity = giant.Kind.WalkSpeed * (speedScale or 1) * hurry * DayNightService.GiantSpeed()
	giant.Move.Position = Vector3.new(goal.X, y, goal.Z)
	local flat = Vector3.new(goal.X - here.X, 0, goal.Z - here.Z)
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
	steer(giant, Geo.NextWaypoint(here, target :: Vector3, breached))
end

-- === Targets =================================================================

type Candidate = { Player: Player, Root: BasePart, Waypoint: Vector3, Distance: number }

local function candidates(giant: Giant): { Candidate }
	local here = giant.Rig.Root.Position
	local breached = Wall.IsBreached()
	local list: { Candidate } = {}
	for _, player in Players:GetPlayers() do
		local root = aliveRoot(player)
		-- Hunters perched above the giant's head are safe (and should be!).
		if root and not held[player] and heightAboveGround(player, root) < giant.Kind.Height * 1.05 then
			local distance = Geo.Flat(root.Position - here).Magnitude
			if distance < Config.Giants.SightRange then
				local waypoint = Geo.NextWaypoint(here, root.Position, breached)
				if waypoint then
					table.insert(list, { Player = player, Root = root, Waypoint = waypoint, Distance = distance })
				end
			end
		end
	end
	return list
end

local function chooseTarget(giant: Giant): Candidate?
	local list = candidates(giant)
	if #list == 0 then
		return nil
	end
	if giant.Kind.Abnormal then
		-- Runners pick someone (anyone) and stick with them for a while.
		local now = os.clock()
		if giant.Target and now < giant.TargetUntil then
			for _, c in list do
				if c.Player == giant.Target then
					return c
				end
			end
		end
		local pick = list[rng:NextInteger(1, #list)]
		giant.Target = pick.Player
		giant.TargetUntil = now + rng:NextNumber(6, 10)
		return pick
	end
	table.sort(list, function(a, b)
		return a.Distance < b.Distance
	end)
	return list[1]
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
	for _, player in Players:GetPlayers() do
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
	for _, player in Players:GetPlayers() do
		local root = aliveRoot(player)
		if root and not held[player] and (root.Position - nape).Magnitude < range and not inFront(giant, root.Position, body) then
			return true
		end
	end
	return false
end

local function guard(giant: Giant, now: number)
	local G = Config.Giants
	if not hunterBehind(giant) then
		return
	end
	if rng:NextNumber() > G.GuardChance then
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
				for _, other in Players:GetPlayers() do
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
	local model = giant.Rig.Model
	local here = giant.Rig.Root.Position
	model:SetAttribute("Grabbing", true) -- the lunge pose, head thrown forward
	steamBurst(giant.Rig.Head, giant.Kind.Height * 0.25, 40)
	Broadcast.Shake(here, 1.6)
	for _, player in Players:GetPlayers() do
		local root = aliveRoot(player)
		if root and not held[player] and (root.Position - here).Magnitude < B.RoarRadius then
			local away = Geo.Flat(root.Position - here)
			local push = (if away.Magnitude > 0.5 then away.Unit else Vector3.new(0, 0, 1)) + Vector3.new(0, 0.5, 0)
			remote(Config.Remotes.Knocked):FireClient(player, push.Unit * 110)
		end
	end
	task.delay(0.9, function()
		model:SetAttribute("Grabbing", false)
	end)
end

local function powers(giant: Giant, now: number)
	local B = Config.Beast
	local here = giant.Rig.Root.Position
	if now >= giant.NextRoarAt then
		for _, player in Players:GetPlayers() do
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
		for _, player in Players:GetPlayers() do
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
		steer(giant, nil)
		return
	end
	if giant.Kind.Powers and not giant.Busy then
		powers(giant, now)
	end
	local look = giant.Kind.Look
	if look and look.Guard and not giant.Busy and not giant.GuardWinding and now >= giant.NextGuardAt then
		guard(giant, now)
	end
	-- (The guarding hand is busy: no grabs or swats with it up.)
	local handFree = not giant.GuardWinding and not guarding(giant)
	local target = chooseTarget(giant)
	if target then
		local root = target.Root
		local inReach = (root.Position - chestPoint(giant)).Magnitude <= giant.Kind.GrabReach
		if inReach and not giant.Busy and handFree then
			tryGrab(giant, target.Player, root)
		elseif not giant.Busy and handFree and now >= giant.NextSwatAt then
			local swatPlayer, swatRoot = swatTarget(giant)
			if swatPlayer and swatRoot then
				swat(giant, swatPlayer, swatRoot)
			end
		end
		if giant.Busy then
			steer(giant, nil) -- plant its feet while it winds up
			return
		end
		local waypoint = target.Waypoint
		local speed = 1
		if giant.Kind.Abnormal then
			-- Zig-zag while far off, leap now and then.
			local here = giant.Rig.Root.Position
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
		return
	end
	-- Nobody to chase: still swat at anyone buzzing its head.
	if not giant.Busy and handFree and now >= giant.NextSwatAt then
		local swatPlayer, swatRoot = swatTarget(giant)
		if swatPlayer and swatRoot then
			swat(giant, swatPlayer, swatRoot)
			steer(giant, nil)
			return
		end
	end
	if giant.Busy then
		steer(giant, nil)
		return
	end
	wander(giant)
end

-- === Spawning and takedowns ==================================================

function GiantService.SpawnGiant(kindName: string)
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
	}
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

local function applyDamage(giant: Giant, player: Player, damage: number, clean: boolean, speed: number): (HitResult, HitInfo)
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
	local health = (model:GetAttribute("NapeHealth") :: number) - damage
	model:SetAttribute("NapeHealth", math.max(health, 0))
	if health <= 0 then
		defeat(giant, player, clean, speed)
		return "Defeated", info
	end
	return "Hit", info
end

local function cutNape(giant: Giant, player: Player, speed: number): (HitResult, HitInfo)
	local clean = speed >= Config.Blades.CleanCutSpeed
	return applyDamage(giant, player, if clean then 1 else 0.5, clean, speed)
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
		return cutNape(best, player, speed)
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

	task.spawn(function()
		while true do
			task.wait(Config.Giants.ThinkInterval)
			for _, giant in giants do
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
	end)
end

return GiantService
