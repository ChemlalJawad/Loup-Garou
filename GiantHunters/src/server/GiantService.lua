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
--
-- Cuts, through TryHit (HunterService checks cooldowns and blades first):
--   * the nape, from behind or the side: damage (on armoured giants, the
--     rock plate cracks first);
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
local Broadcast = require(script.Parent.Broadcast)

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
	Defeated: boolean,
}

export type HitResult = "NoTarget" | "Hit" | "Defeated" | "Armor" | "ArmorBroken" | "Trip" | "Daze"
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
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
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

-- === Moving ==================================================================

local function steer(giant: Giant, toward: Vector3?, speedScale: number?)
	local root = giant.Rig.Root
	local now = os.clock()
	local here = root.Position
	local goal = toward or here
	local y = giant.RestY
	if now < giant.KneelUntil then
		y -= giant.Rig.ShinLength * 0.95
	elseif now < giant.LeapUntil then
		y += giant.Kind.Height * 0.3
	end
	giant.Move.MaxVelocity = giant.Kind.WalkSpeed * (speedScale or 1)
	giant.Move.Position = Vector3.new(goal.X, y, goal.Z)
	local flat = Vector3.new(goal.X - here.X, 0, goal.Z - here.Z)
	if flat.Magnitude > 2 then
		giant.Face.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	end
end

local function wander(giant: Giant)
	local here = giant.Rig.Root.Position
	local breached = Wall.IsBreached()
	local inside = Geo.IsInside(here)
	local target = giant.WanderTarget
	local arrived = target and Geo.Flat((target :: Vector3) - here).Magnitude < 12
	-- Outside with the gate open, every giant wants in.
	local wantInside = inside or breached
	if not target or arrived or Geo.IsInside(target :: Vector3) ~= wantInside then
		if wantInside then
			target = Geo.Polar(rng:NextNumber(0, math.pi * 2), rng:NextNumber(30, Geo.INSIDE_LIMIT))
		else
			target = Geo.Polar(Config.World.GateAngle + rng:NextNumber(-1.2, 1.2), rng:NextNumber(Geo.OUTSIDE_LIMIT + 30, Geo.LAND_LIMIT - 80))
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
		if root and not held[player] and root.Position.Y < giant.Kind.Height * 1.05 then
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

local function holdFrame(giant: Giant, t: number): CFrame
	local rootFrame = giant.Rig.Root.CFrame
	local h = giant.Kind.Height
	local lift = giant.Rig.TorsoHeight * 0.75
	local point = rootFrame * CFrame.new(h * 0.06 + math.sin(t * 22) * h * 0.012, lift, -(giant.Rig.TorsoDepth * 0.5 + h * 0.13))
	return CFrame.lookAt(point.Position, rootFrame.Position + Vector3.new(0, lift, 0))
end

local function release(giant: Giant, reason: string)
	local player = giant.Holding
	if not player then
		return
	end
	giant.Holding = nil
	held[player] = nil
	giant.NextGrabAt = os.clock() + Config.Giants.GrabCooldown + 1
	giant.Rig.Model:SetAttribute("Holding", false)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = false
	end
	if player.Parent then
		remote(Config.Remotes.Held):FireClient(player, "Free", reason)
	end
end

local function startHold(giant: Giant, player: Player, root: BasePart)
	giant.Holding = player
	giant.HoldStarted = os.clock()
	giant.Struggles = 0
	held[player] = giant
	giant.Rig.Model:SetAttribute("Holding", true)
	root.Anchored = true
	root.CFrame = holdFrame(giant, os.clock())
	remote(Config.Remotes.Held):FireClient(player, "Grabbed", { Time = Config.Giants.HoldTime, Needed = Config.Giants.StruggleToEscape })
	Broadcast.Feed(`{player.DisplayName} was grabbed! Cut them loose!`, "Danger")
end

local function caught(giant: Giant)
	local player = giant.Holding
	if not player then
		return
	end
	release(giant, "Caught")
	remote(Config.Remotes.Caught):FireClient(player, giant.Kind.Display)
	Broadcast.Feed(`{player.DisplayName} was caught by a {giant.Kind.Display}`, "Info")
	task.spawn(function()
		if player.Parent then
			player:LoadCharacterAsync() -- back on the wall; no gore, just a "Caught!" screen
		end
	end)
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
		steer(giant, nil)
		return
	end
	local target = chooseTarget(giant)
	if target then
		local root = target.Root
		local inReach = (root.Position - chestPoint(giant)).Magnitude <= giant.Kind.GrabReach
		if inReach and not giant.Busy then
			tryGrab(giant, target.Player, root)
		elseif not giant.Busy and now >= giant.NextSwatAt then
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
	if not giant.Busy and now >= giant.NextSwatAt then
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
		Defeated = false,
	}
	if kind.Armor then
		rig.Model:SetAttribute("Armor", kind.Armor)
	end
	if kind.Abnormal then
		rig.Model:SetAttribute("Abnormal", true)
	end
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

local function defeat(giant: Giant, player: Player, clean: boolean, speed: number)
	giant.Defeated = true
	release(giant, "Rescued")
	local model = giant.Rig.Model
	model:SetAttribute("Defeated", true)
	GiantService.Defeated:Fire(player, giant.Kind.Name, clean, speed)
	Broadcast.Feed(`{player.DisplayName} took down a {giant.Kind.Display}!`, if giant.Kind.Name == "Armored" then "Gold" else "Good")

	-- Stop, anchor, and dissolve into steam: no ragdoll, nothing scary.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
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

local function trip(giant: Giant)
	local duration = Config.Cuts.TripTime
	giant.KneelUntil = os.clock() + duration
	giant.LeapUntil = 0
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

local function cutNape(giant: Giant, player: Player, root: BasePart): (HitResult, HitInfo)
	local speed = root.AssemblyLinearVelocity.Magnitude
	local clean = speed >= Config.Blades.CleanCutSpeed
	local damage = if clean then 1 else 0.5
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

-- In front of a giant's face (where its eyes are, and its nape isn't).
local function facing(giant: Giant, here: Vector3): boolean
	local toHunter = here - giant.Rig.Head.Position
	return toHunter.Magnitude > 0.01 and toHunter.Unit:Dot(giant.Rig.Root.CFrame.LookVector) > Config.Cuts.EyesFrontDot
end

-- Called by HunterService after it has validated the slash (cooldown,
-- blades). The nape comes first (from behind or the side); then the eyes
-- (from in front); then an ankle.
function GiantService.TryHit(player: Player, root: BasePart): (HitResult, HitInfo)
	local here = root.Position
	local reachBase = Config.Blades.SlashRange

	local best: Giant? = nil
	local bestDistance = math.huge
	for _, giant in giants do
		if not giant.Defeated and not facing(giant, here) then
			local nape = giant.Rig.Nape
			local d = (nape.Position - here).Magnitude
			if d <= reachBase + nape.Size.X / 2 and d < bestDistance then
				best, bestDistance = giant, d
			end
		end
	end
	if best then
		return cutNape(best, player, root)
	end

	for _, giant in giants do
		if not giant.Defeated and facing(giant, here) then
			local head = giant.Rig.Head
			if (here - head.Position).Magnitude <= reachBase + giant.Rig.HeadSize / 2 then
				local info: HitInfo = { Kind = giant.Kind.Display, Position = head.Position }
				info.Rescued = rescue(giant, player)
				daze(giant, Config.Cuts.DazeTime)
				GiantService.Assist:Fire(player, "Daze")
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
					trip(giant)
					GiantService.Assist:Fire(player, "Trip")
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
		daze(giant, Config.Cuts.DazeTime)
		steamBurst(giant.Rig.Head, giant.Kind.Height * 0.2, 20)
		rescue(giant, player)
		GiantService.Assist:Fire(player, "Cannon")
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

-- Everyone left: clear the field.
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

	-- Carry held hunters in the giant's hand; let go if anything vanishes.
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for player, giant in held do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") or not active(giant) or not player.Parent then
				release(giant, "Gone")
			else
				root.CFrame = holdFrame(giant, t)
			end
		end
	end)

	remote(Config.Remotes.Struggle).OnServerEvent:Connect(function(player)
		GiantService.Struggle(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local giant = held[player]
		if giant then
			release(giant, "Gone")
		end
		lastStruggle[player] = nil
	end)
end

return GiantService
