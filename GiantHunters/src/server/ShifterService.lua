--!strict
-- Titan shifters: players who can turn into a titan.
--
--   * Now and then a glowing crystal appears somewhere in town (never more
--     than Config.Shifters.Max shifters at once). Whoever takes it gets the
--     titan power and picks a side:
--       - the HUNTERS' side: your blows crush giants (they count as
--         takedowns), your powers daze them;
--       - the GIANTS' side: your punches knock hunters out (back to the
--         wall), your powers push them away - and hunters can cut your nape.
--     Titans on opposite sides can fight each other.
--   * Players who own a titan form (Config.TitanForms, bought in the shop,
--     equipped as the player attribute "Equip_Titan") also fill a Titan
--     Gauge with takedowns made on foot: full, T turns them into their
--     form once (hunters' side only, still within the Max).
--   * T transforms (for Duration seconds, then a cooldown) into the
--     equipped form. The titan is a part-built giant welded to your
--     character, which is hidden and raised to the titan's hip height, so
--     you walk it with the normal controls. Each form has two powers,
--     Primary (click / F) and Secondary (G), with their own cooldowns, all
--     checked here.
--   * Lose all your nape health and you're thrown out of the titan, and the
--     power is gone. It also fades when you're knocked out or caught, when
--     the round ends, or after Config.Shifters.PowerLasts - and you can
--     decline it when choosing a side.
-- Knockouts, not injuries: a knocked-out hunter just respawns on the wall
-- (no points for it, and a few seconds when it can't happen again). Giants
-- are dazed, knocked silly or steamed away - never hurt.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local GiantFactory = require(script.Parent.GiantFactory)
local GiantService = require(script.Parent.GiantService)
local Broadcast = require(script.Parent.Broadcast)
local Motion = require(script.Parent.Motion)
local Respawn = require(script.Parent.Respawn)

local ShifterService = {}

ShifterService.Scored = Instance.new("BindableEvent") -- (player, points)

type Shifter = {
	Player: Player,
	Side: string?, -- "Humans" | "Giants"
	Rig: GiantFactory.Rig?,
	Form: Config.TitanForm, -- the form of the titan now (set when transforming)
	Health: number,
	Until: number,
	CooldownUntil: number,
	LastUsed: { [string]: number }, -- power key -> os.clock()
	GuardUntil: number, -- Crystal Guard: the nape is covered
	FrenzyUntil: number,
	Hidden: { [Instance]: number },
	HipHeight: number,
	WalkSpeed: number,
	JumpPower: number,
	JumpHeight: number,
	PowerUntil: number, -- the power fades then, used or not
	Gauge: boolean, -- from a full Titan Gauge: one transformation, then gone
}

local S = Config.Shifters
local shifters: { [Player]: Shifter } = {}
local gauges: { [Player]: number } = {}
local immuneUntil: { [Player]: number } = {} -- knocked out a moment ago
local orb: Model? = nil
local nextOrbAt = 0
local folder: Folder
local remotes: Folder
local rng = Random.new()

local ORB_SPOTS = {
	Vector3.new(0, 0, -36), -- the plaza
	Geo.Polar(math.rad(90), 52), -- in front of the headquarters
	Geo.Polar(math.rad(270), 160), -- the market
	Geo.Polar(0, 240), -- the gate square
	Geo.Polar(math.rad(135), 160), -- the garden
}

local function remote(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

local function bodyOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

local function steam(at: Vector3, size: number, amount: number)
	local spot = Instance.new("Part")
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.Transparency = 1
	spot.Size = Vector3.one
	spot.Position = at
	spot.Parent = Workspace
	local puff = Instance.new("ParticleEmitter")
	puff.Color = ColorSequence.new(Color3.fromRGB(245, 245, 250))
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	puff.Lifetime = NumberRange.new(1.5, 2.5)
	puff.Speed = NumberRange.new(8, 18)
	puff.SpreadAngle = Vector2.new(70, 70)
	puff.Rate = 0
	puff.Parent = spot
	puff:Emit(amount)
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 230, 190)
	flash.Range = 50
	flash.Brightness = 6
	flash.Parent = spot
	Debris:AddItem(spot, 3)
end

local function holders(): number
	local count = 0
	for _ in shifters do
		count += 1
	end
	return count
end

local function newShifter(player: Player, gauge: boolean): Shifter
	return {
		Player = player,
		Side = if gauge then "Humans" else nil,
		Rig = nil,
		Form = Config.TitanForms.Default,
		Health = 0,
		Until = 0,
		CooldownUntil = 0,
		LastUsed = {},
		GuardUntil = 0,
		FrenzyUntil = 0,
		Hidden = {},
		HipHeight = 0,
		WalkSpeed = 0,
		JumpPower = 0,
		JumpHeight = 0,
		PowerUntil = os.clock() + (if gauge then S.GaugeDuration + 5 else S.PowerLasts),
		Gauge = gauge,
	}
end

-- The form this player would turn into now (equipped and allowed, else
-- the Default). Agent-owned attributes: "Equip_Titan" (shop), "Level".
local function formOf(player: Player): Config.TitanForm
	return Config.TitanFormFor(player:GetAttribute("Equip_Titan"), player:GetAttribute("Level"))
end

-- === Becoming a titan, and back ================================================

local function clearPowerAttributes(player: Player)
	player:SetAttribute("TitanForm", nil)
	player:SetAttribute("TitanPrimaryReadyAt", nil)
	player:SetAttribute("TitanSecondaryReadyAt", nil)
end

local function revert(shifter: Shifter)
	local rig = shifter.Rig
	if not rig then
		return
	end
	shifter.Rig = nil
	shifter.CooldownUntil = os.clock() + S.Cooldown
	shifter.GuardUntil = 0
	shifter.FrenzyUntil = 0
	local player = shifter.Player
	steam(rig.Torso.Position, 14, 50)
	rig.Model:Destroy()
	for instance, transparency in shifter.Hidden do
		if instance.Parent then
			(instance :: any).Transparency = transparency
		end
	end
	table.clear(shifter.Hidden)
	local character = player.Character
	if character then
		character:SetAttribute("Shifted", nil)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.HipHeight = shifter.HipHeight
			humanoid.WalkSpeed = shifter.WalkSpeed
			humanoid.JumpPower = shifter.JumpPower
			humanoid.JumpHeight = shifter.JumpHeight
		end
	end
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 55
	player:SetAttribute("ShiftUntil", nil)
	player:SetAttribute("ShiftReadyAt", Workspace:GetServerTimeNow() + S.Cooldown)
	clearPowerAttributes(player)
end

local function transform(shifter: Shifter): boolean
	local player = shifter.Player
	local character, humanoid, root = bodyOf(player)
	if not character or not humanoid or not root or not shifter.Side or shifter.Rig then
		return false
	end
	if os.clock() < shifter.CooldownUntil or GiantService.IsHeld(player) then
		return false
	end
	local form = formOf(player)
	shifter.Form = form
	local ground = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local rig = GiantFactory.Build("Shifter", ground, rng, form)
	-- No AI mover: the player walks this one.
	for _, name in { "Move", "Face", "Drive" } do
		local mover = rig.Root:FindFirstChild(name)
		if mover then
			mover:Destroy()
		end
	end
	local legLength = rig.Root.Position.Y - ground.Y
	rig.Root.Massless = true
	rig.Model:PivotTo(root.CFrame)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = rig.Root
	weld.Parent = rig.Root

	-- Hide the hunter inside (body, face, swords).
	for _, d in character:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Decal")) and (d :: any).Transparency < 1 then
			shifter.Hidden[d] = (d :: any).Transparency;
			(d :: any).Transparency = 1
		end
	end
	shifter.HipHeight = humanoid.HipHeight
	shifter.WalkSpeed = humanoid.WalkSpeed
	shifter.JumpPower = humanoid.JumpPower
	shifter.JumpHeight = humanoid.JumpHeight
	humanoid.HipHeight = math.max(legLength - root.Size.Y / 2, 2)
	humanoid.WalkSpeed = form.WalkSpeed
	-- Titans don't jump (whichever of the two the avatar uses; the client
	-- also switches the Jumping state off).
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	local side = shifter.Side :: string
	local model = rig.Model
	model.Name = `{player.Name}Titan`
	model:SetAttribute("Shifter", player.UserId)
	model:SetAttribute("Side", side)
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = if side == "Humans" then Color3.fromRGB(90, 160, 255) else Color3.fromRGB(255, 70, 60)
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model
	model.Parent = folder

	local duration = if shifter.Gauge then S.GaugeDuration else S.Duration
	character:SetAttribute("Shifted", true)
	player.CameraMinZoomDistance = math.max(form.Height * 0.9, 24)
	player.CameraMaxZoomDistance = math.max(form.Height * 4.7, 120)
	shifter.Rig = rig
	shifter.Health = form.NapeHealth
	shifter.Until = os.clock() + duration
	table.clear(shifter.LastUsed)
	player:SetAttribute("ShiftUntil", Workspace:GetServerTimeNow() + duration)
	player:SetAttribute("TitanForm", form.Id)
	steam(root.Position, form.Height * 0.5, 70)
	Broadcast.Shake(root.Position, 2)
	Broadcast.Feed(`{player.DisplayName} turned into {if form.Id == "Default" then "a titan" else `the {form.Display}`} ({if side == "Humans" then "hunters' side" else "giants' side!"})`, if side == "Humans" then "Good" else "Danger")
	return true
end

-- === Fighting ==================================================================

local function removePower(shifter: Shifter)
	revert(shifter)
	local player = shifter.Player
	shifters[player] = nil
	player:SetAttribute("ShifterPower", nil)
	player:SetAttribute("ShifterSide", nil)
	player:SetAttribute("ShiftReadyAt", nil)
	player:SetAttribute("PowerUntil", nil)
	clearPowerAttributes(player)
	if not shifter.Gauge then
		nextOrbAt = math.max(nextOrbAt, os.clock() + S.OrbEvery)
	end
end

local function defeatShifter(shifter: Shifter, by: Player)
	local player = shifter.Player
	Broadcast.Feed(`{by.DisplayName} cut down {player.DisplayName}'s titan!`, "Gold")
	ShifterService.Scored:Fire(by, Config.GiantKinds.Shifter.Points)
	removePower(shifter)
	remote(Config.Remotes.Knocked):FireClient(player, Vector3.new(0, 80, 0))
end

local function guarded(shifter: Shifter): boolean
	return os.clock() < shifter.GuardUntil
end

-- Nape damage to a titan (rock plates soak some of it). False when it
-- didn't take it (guarded) or survived.
local function hurt(shifter: Shifter, by: Player, amount: number): boolean
	local rig = shifter.Rig
	if not rig or guarded(shifter) then
		return false
	end
	shifter.Health -= amount * (shifter.Form.DamageTaken or 1)
	rig.Model:SetAttribute("NapeHealth", math.max(shifter.Health, 0))
	if shifter.Health <= 0 then
		defeatShifter(shifter, by)
		return true
	end
	return false
end

local function knockout(victim: Player, by: Player)
	local now = os.clock()
	if now < (immuneUntil[victim] or 0) then
		return -- just knocked out: give them a chance
	end
	immuneUntil[victim] = now + S.KnockoutImmunity
	remote(Config.Remotes.Caught):FireClient(victim, "Titan")
	Broadcast.Feed(`{by.DisplayName}'s titan knocked out {victim.DisplayName}!`, "Danger")
	if S.KnockoutPoints > 0 then
		ShifterService.Scored:Fire(by, S.KnockoutPoints)
	end
	Respawn.Load(victim)
end

-- Hunters on foot (not titans) within `radius` of `centre`, other than `except`.
local function huntersNear(centre: Vector3, radius: number, except: Player): { { Player: Player, Root: BasePart } }
	local found = {}
	for _, other in Players:GetPlayers() do
		local character, _, otherRoot = bodyOf(other)
		if other ~= except and character and otherRoot and not character:GetAttribute("Shifted") and (otherRoot.Position - centre).Magnitude <= radius then
			table.insert(found, { Player = other, Root = otherRoot })
		end
	end
	return found
end

-- Blows hunters near `centre` away from it (a push, never a knockout).
local function pushHunters(centre: Vector3, radius: number, except: Player, force: number)
	for _, hunter in huntersNear(centre, radius, except) do
		local away = Geo.Flat(hunter.Root.Position - centre)
		local push = (if away.Magnitude > 0.5 then away.Unit else Vector3.new(0, 0, 1)) + Vector3.new(0, 0.5, 0)
		remote(Config.Remotes.Knocked):FireClient(hunter.Player, push.Unit * force)
	end
end

-- Titans on the other side near `centre`.
local function enemyTitansNear(shifter: Shifter, centre: Vector3, radius: number): { Shifter }
	local found = {}
	for other, enemy in shifters do
		local enemyRig = enemy.Rig
		if other ~= shifter.Player and enemyRig and enemy.Side ~= shifter.Side and (enemyRig.Torso.Position - centre).Magnitude <= radius + enemy.Form.Height * 0.3 then
			table.insert(found, enemy)
		end
	end
	return found
end

-- Flashes a model attribute on for `seconds` (the animator poses from it).
local function flash(model: Model, name: string, seconds: number)
	model:SetAttribute(name, true)
	task.delay(seconds, function()
		model:SetAttribute(name, nil)
	end)
end

-- A punch landing at `centre`: giants stagger (hunters' side) or hunters
-- are knocked out (giants' side); enemy titans take a nape hit.
local function strike(shifter: Shifter, centre: Vector3, radius: number)
	local player = shifter.Player
	if shifter.Side == "Humans" then
		GiantService.Punch(player, centre, radius)
	else
		for _, hunter in huntersNear(centre, radius, player) do
			knockout(hunter.Player, player)
		end
	end
	for _, enemy in enemyTitansNear(shifter, centre, radius) do
		hurt(enemy, player, 1)
	end
	Broadcast.Shake(centre, 0.6 * math.clamp(shifter.Form.Height / 34, 0.7, 1.6))
end

-- Where a punch lands: in front of the titan, a little above the hips.
local function punchCentre(shifter: Shifter, root: BasePart, reach: number): (Vector3, number)
	local height = shifter.Form.Height
	return root.Position + root.CFrame.LookVector * height * 0.35 + Vector3.new(0, height * 0.15, 0), height * reach
end

-- === Powers ====================================================================
-- Each takes the shifter, its rig, the player's root and the power's
-- Config entry. The cooldown is already checked.

type PowerFn = (Shifter, GiantFactory.Rig, BasePart, Config.TitanPower) -> ()

local function punch(shifter: Shifter, rig: GiantFactory.Rig, root: BasePart, power: Config.TitanPower)
	local model = rig.Model
	model:SetAttribute("Swat", "Right") -- the animator swings the arm through
	task.delay(0.15, function()
		model:SetAttribute("Swat", "")
	end)
	local centre, radius = punchCentre(shifter, root, power.Reach or 0.5)
	strike(shifter, centre, radius)
end

-- Swiftfang: a leap forward (the client moves; the server only says how
-- fast), and a punch where it lands.
local function pounce(shifter: Shifter, rig: GiantFactory.Rig, root: BasePart, power: Config.TitanPower)
	local look = Geo.Flat(root.CFrame.LookVector)
	local forward = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	remote(Config.Remotes.Shift):FireClient(shifter.Player, "Dash", forward * S.PounceSpeed + Vector3.new(0, 30, 0))
	flash(rig.Model, "Pounce", 0.55)
	local thisRig = rig
	task.delay(0.45, function()
		local _, _, nowRoot = bodyOf(shifter.Player)
		if shifter.Rig ~= thisRig or not nowRoot then
			return
		end
		local centre, radius = punchCentre(shifter, nowRoot, power.Reach or 0.6)
		strike(shifter, centre, radius)
	end)
end

local function roar(shifter: Shifter, rig: GiantFactory.Rig, root: BasePart, power: Config.TitanPower)
	local radius = power.Radius or 70
	flash(rig.Model, "Grabbing", 0.9)
	steam(rig.Head.Position, 10, 30)
	Broadcast.Shake(root.Position, 1.4)
	if shifter.Side == "Humans" then
		GiantService.DazeAround(root.Position, radius)
	else
		pushHunters(root.Position, radius, shifter.Player, 110)
	end
end

-- Stoneguard: both fists up, then into the ground: a shockwave.
local function slam(shifter: Shifter, rig: GiantFactory.Rig, _root: BasePart, power: Config.TitanPower)
	local model = rig.Model
	model:SetAttribute("Slam", true)
	task.delay(0.5, function()
		model:SetAttribute("Slam", nil)
		local _, _, root = bodyOf(shifter.Player)
		if shifter.Rig ~= rig or not root then
			return
		end
		local height = shifter.Form.Height
		local radius = power.Radius or 30
		local at = root.Position + Geo.Flat(root.CFrame.LookVector) * height * 0.3 - Vector3.new(0, rig.Root.Position.Y - rig.Feet[1].Position.Y, 0)
		steam(at, height * 0.35, 60)
		Broadcast.Shake(at, 2.2)
		if shifter.Side == "Humans" then
			GiantService.DazeAround(at, radius)
		else
			pushHunters(at, radius, shifter.Player, S.PushForce)
		end
		for _, enemy in enemyTitansNear(shifter, at, radius) do
			hurt(enemy, shifter.Player, 0.5)
		end
	end)
end

-- Swiftfang: a burst of speed (and pounces recharge twice as fast).
local function frenzy(shifter: Shifter, rig: GiantFactory.Rig, _root: BasePart, power: Config.TitanPower)
	local _, humanoid = bodyOf(shifter.Player)
	if not humanoid then
		return
	end
	local duration = power.Duration or 5
	shifter.FrenzyUntil = os.clock() + duration
	humanoid.WalkSpeed = shifter.Form.WalkSpeed * (power.Boost or 1.5)
	rig.Model:SetAttribute("Frenzy", true)
	steam(rig.Head.Position, 6, 20)
	task.delay(duration, function()
		if shifter.Rig == rig then
			rig.Model:SetAttribute("Frenzy", nil)
			local _, nowHumanoid = bodyOf(shifter.Player)
			if nowHumanoid then
				nowHumanoid.WalkSpeed = shifter.Form.WalkSpeed
			end
		end
	end)
end

-- The nearest enemy ahead within range, for a thrown boulder: giants (and
-- rogue titans) for the hunters' side, hunters (and hunter titans) for the
-- giants' side.
local function boulderTarget(shifter: Shifter, root: BasePart, range: number): Vector3?
	local here = root.Position
	local look = Geo.Flat(root.CFrame.LookVector)
	local best: Vector3? = nil
	local bestDistance = range
	local function consider(at: Vector3)
		local offset = at - here
		local flat = Geo.Flat(offset)
		local distance = offset.Magnitude
		if distance < bestDistance and distance > 8 and (flat.Magnitude < 0.1 or look.Magnitude < 0.1 or flat.Unit:Dot(look.Unit) > 0.3) then
			best, bestDistance = at, distance
		end
	end
	if shifter.Side == "Humans" then
		for _, giant in CollectionService:GetTagged(Config.Tags.Giant) do
			local giantRoot = giant:FindFirstChild("Root")
			if giant:IsA("Model") and giantRoot and giantRoot:IsA("BasePart") and not giant:GetAttribute("Shifter") and not giant:GetAttribute("Defeated") then
				consider(giantRoot.Position)
			end
		end
	else
		for _, hunter in huntersNear(here, range, shifter.Player) do
			consider(hunter.Root.Position)
		end
	end
	for _, enemy in enemyTitansNear(shifter, here, range) do
		local enemyRig = enemy.Rig
		if enemyRig then
			consider(enemyRig.Torso.Position)
		end
	end
	return best
end

-- Boulderhurler: wind up, then lob a boulder at the nearest enemy ahead
-- (or straight ahead). Slow enough to see coming.
local function boulder(shifter: Shifter, rig: GiantFactory.Rig, _root: BasePart, power: Config.TitanPower)
	local model = rig.Model
	model:SetAttribute("Throw", true)
	task.delay(0.6, function()
		model:SetAttribute("Throw", nil)
		local _, _, root = bodyOf(shifter.Player)
		if shifter.Rig ~= rig or not root then
			return
		end
		local player = shifter.Player
		local side = shifter.Side
		local range = power.Range or 260
		local radius = power.Radius or 16
		local height = shifter.Form.Height
		local from = rig.Root.Position + Vector3.new(0, height * 0.65, 0)
		local to = boulderTarget(shifter, root, range) or (root.Position + Geo.Flat(root.CFrame.LookVector) * range * 0.5)
		local rock = Instance.new("Part")
		rock.Name = "TitanBoulder"
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.one * height * 0.16
		rock.Color = Color3.fromRGB(128, 118, 104)
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = false
		rock.CanQuery = false
		rock.Position = from
		rock.Parent = Workspace
		local apex = (from + to) / 2 + Vector3.new(0, 30 + (to - from).Magnitude * 0.12, 0)
		local start = os.clock()
		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function()
			local t = math.min((os.clock() - start) / S.BoulderFlight, 1)
			rock.CFrame = CFrame.new(from:Lerp(apex, t):Lerp(apex:Lerp(to, t), t)) * CFrame.Angles(t * 6, t * 4, 0)
			if t < 1 then
				return
			end
			connection:Disconnect()
			Broadcast.Shake(to, 1)
			steam(to, 10, 25)
			if side == "Humans" then
				GiantService.Punch(player, to, radius)
			else
				pushHunters(to, radius, player, 95)
			end
			if shifters[player] == shifter and side == shifter.Side then
				for _, enemy in enemyTitansNear(shifter, to, radius) do
					hurt(enemy, player, 1)
				end
			end
			rock.Transparency = 1
			Debris:AddItem(rock, 2)
		end)
	end)
end

-- Steamwarden: a blast of steam for a few seconds: giants close by stay
-- dazed and the nearest are scalded at the end (a hit); hunters are
-- pushed away.
local function vent(shifter: Shifter, rig: GiantFactory.Rig, _root: BasePart, power: Config.TitanPower)
	local model = rig.Model
	local radius = power.Radius or 45
	local duration = power.Duration or 4
	model:SetAttribute("Vent", true)
	task.spawn(function()
		local ticks = math.max(math.floor(duration), 1)
		for tick = 1, ticks do
			local _, _, root = bodyOf(shifter.Player)
			if shifter.Rig ~= rig or not root then
				break
			end
			local here = root.Position
			steam(rig.Torso.Position, shifter.Form.Height * 0.4, 45)
			Broadcast.Shake(here, 0.8)
			if shifter.Side == "Humans" then
				GiantService.DazeAround(here, radius)
				if tick == ticks then
					GiantService.Punch(shifter.Player, here, radius * 0.4)
				end
			else
				pushHunters(here, radius, shifter.Player, S.PushForce * 0.8)
			end
			if tick == ticks then
				for _, enemy in enemyTitansNear(shifter, here, radius * 0.6) do
					hurt(enemy, shifter.Player, 0.5)
				end
			end
			task.wait(1)
		end
		if model.Parent then
			model:SetAttribute("Vent", nil)
		end
	end)
end

-- Crystalcrown: crystals burst out of the ground round it (dazing giants
-- or pushing hunters) and the crystal hand covers its nape for a while.
local function crystalGuard(shifter: Shifter, rig: GiantFactory.Rig, root: BasePart, power: Config.TitanPower)
	local duration = power.Duration or 4
	local radius = power.Radius or 28
	shifter.GuardUntil = os.clock() + duration
	local model = rig.Model
	model:SetAttribute("Guarding", true)
	task.delay(duration, function()
		if shifter.Rig == rig then
			model:SetAttribute("Guarding", nil)
		end
	end)
	local floor = root.Position.Y - (rig.Root.Position.Y - rig.Feet[1].Position.Y)
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		local at = Vector3.new(root.Position.X + math.cos(angle) * radius * 0.6, floor, root.Position.Z + math.sin(angle) * radius * 0.6)
		local shard = Instance.new("Part")
		shard.Name = "CrystalShard"
		shard.Size = Vector3.new(2.5, 9, 2.5)
		shard.CFrame = CFrame.new(at) * CFrame.Angles(0, angle, 0) * CFrame.Angles(0.35, 0, 0) * CFrame.new(0, 3, 0)
		shard.Color = Color3.fromRGB(170, 225, 255)
		shard.Material = Enum.Material.Glass
		shard.Transparency = 0.2
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CastShadow = false
		shard.Parent = Workspace
		Debris:AddItem(shard, 1.6)
	end
	Broadcast.Shake(root.Position, 1.2)
	if shifter.Side == "Humans" then
		GiantService.DazeAround(root.Position, radius)
	else
		pushHunters(root.Position, radius, shifter.Player, S.PushForce)
	end
end

local POWERS: { [string]: PowerFn } = {
	Punch = punch,
	Pounce = pounce,
	Roar = roar,
	Slam = slam,
	Frenzy = frenzy,
	Boulder = boulder,
	Vent = vent,
	CrystalGuard = crystalGuard,
}

local function usePower(shifter: Shifter, key: string)
	local rig = shifter.Rig
	local _, _, root = bodyOf(shifter.Player)
	if not rig or not root or not Motion.Trusted(shifter.Player) then
		return
	end
	local power: Config.TitanPower? = nil
	for _, candidate in shifter.Form.Powers do
		if candidate.Key == key then
			power = candidate
		end
	end
	local fn = power and POWERS[power.Action]
	if not power or not fn then
		return
	end
	local now = os.clock()
	local cooldown = power.Cooldown
	if power.Action == "Pounce" and now < shifter.FrenzyUntil then
		cooldown /= 2
	end
	if now - (shifter.LastUsed[key] or -math.huge) < cooldown then
		return
	end
	shifter.LastUsed[key] = now
	shifter.Player:SetAttribute(`Titan{key}ReadyAt`, Workspace:GetServerTimeNow() + cooldown)
	fn(shifter, rig, root, power)
end

-- Hunters' blades against a titan on the giants' side: its nape, from
-- behind or the side. Called by HunterService when no giant was in reach,
-- with the server's own measure of the hunter's speed.
function ShifterService.TryHit(player: Player, root: BasePart, speed: number): (string?, { [string]: any }?)
	local here = root.Position
	for other, shifter in shifters do
		local rig = shifter.Rig
		if other ~= player and rig and shifter.Side == "Giants" then
			local toHunter = here - rig.Head.Position
			local inFront = toHunter.Magnitude > 0.01 and toHunter.Unit:Dot(rig.Root.CFrame.LookVector) > Config.Cuts.EyesFrontDot
			local nape = rig.Nape
			if not inFront and (nape.Position - here).Magnitude <= Config.Blades.SlashRange + nape.Size.X / 2 then
				if guarded(shifter) then
					return "Guarded", { Kind = shifter.Form.Display, Position = nape.Position }
				end
				local clean = speed >= Config.Blades.CleanCutSpeed
				local info = { Kind = "Titan Shifter", Clean = clean, Speed = speed, Position = nape.Position }
				local down = hurt(shifter, player, if clean then 1 else 0.5)
				return if down then "Defeated" else "Hit", info
			end
		end
	end
	return nil, nil
end

-- === The Titan Gauge ===========================================================

local function setGauge(player: Player, value: number)
	gauges[player] = value
	player:SetAttribute("TitanGauge", value)
end

-- Takedowns on foot fill the gauge of players with a form of their own.
local function onTakedown(player: Player, clean: boolean)
	local shifter = shifters[player]
	if shifter and shifter.Rig then
		return -- a titan's own punches don't count
	end
	if formOf(player).Id == "Default" then
		return
	end
	local gain = S.GaugeTakedown + (if clean then S.GaugeClean else 0)
	local before = gauges[player] or 0
	setGauge(player, math.min(before + gain, S.GaugeMax))
	if before < S.GaugeMax and (gauges[player] or 0) >= S.GaugeMax then
		Broadcast.Announce("TITAN GAUGE FULL", "Press T (or TITAN) to transform", "Gold", player)
	end
end

local function gaugeTransform(player: Player)
	if shifters[player] or (gauges[player] or 0) < S.GaugeMax or formOf(player).Id == "Default" then
		return
	end
	local character = bodyOf(player)
	if not character or GiantService.IsHeld(player) then
		return
	end
	if holders() >= S.Max then
		Broadcast.Announce("TOO MANY TITANS", "Wait for a titan to change back", "Info", player)
		return
	end
	local shifter = newShifter(player, true)
	shifters[player] = shifter
	player:SetAttribute("ShifterPower", true)
	player:SetAttribute("ShifterSide", "Humans")
	if transform(shifter) then
		setGauge(player, 0)
	else
		shifters[player] = nil
		player:SetAttribute("ShifterPower", nil)
		player:SetAttribute("ShifterSide", nil)
	end
end

-- === The crystal ===============================================================

local function spawnOrb()
	local at = ORB_SPOTS[rng:NextInteger(1, #ORB_SPOTS)] + Vector3.new(0, 4, 0)
	local model = Instance.new("Model")
	model.Name = "TitanCrystal"
	local crystal = Instance.new("Part")
	crystal.Name = "Crystal"
	crystal.Size = Vector3.new(2.6, 4.2, 2.6)
	crystal.CFrame = CFrame.new(at) * CFrame.Angles(0, math.rad(45), math.rad(45))
	crystal.Color = Color3.fromRGB(190, 90, 255)
	crystal.Material = Enum.Material.Neon
	crystal.Anchored = true
	crystal.CanCollide = false
	crystal.Parent = model
	local light = Instance.new("PointLight")
	light.Color = crystal.Color
	light.Range = 26
	light.Brightness = 3
	light.Parent = crystal
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Color3.fromRGB(220, 160, 255))
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(1, 2)
	sparkle.Speed = NumberRange.new(2, 5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Rate = 20
	sparkle.Parent = crystal
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Size = Vector3.new(1.2, 80, 1.2)
	beam.Position = at + Vector3.new(0, 42, 0)
	beam.Color = crystal.Color
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.55
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CastShadow = false
	beam.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take the titan power"
	prompt.ObjectText = "Titan crystal"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Config.Prompts.Key
	prompt.GamepadKeyCode = Config.Prompts.Gamepad
	prompt.Parent = crystal
	prompt.Triggered:Connect(function(player)
		if shifters[player] or holders() >= S.Max or orb ~= model then
			return
		end
		local character = bodyOf(player)
		if not character or GiantService.IsHeld(player) then
			return -- not from inside a giant's hand
		end
		orb = nil
		model:Destroy()
		shifters[player] = newShifter(player, false)
		player:SetAttribute("ShifterPower", true)
		player:SetAttribute("PowerUntil", Workspace:GetServerTimeNow() + S.PowerLasts)
		nextOrbAt = os.clock() + S.OrbEvery
		Broadcast.Feed(`{player.DisplayName} took the titan power!`, "Gold")
		Broadcast.Announce("TITAN POWER", "Choose your side, then press T to transform", "Gold", player)
	end)
	CollectionService:AddTag(model, Config.Tags.PowerOrb)
	model.Parent = folder
	orb = model
	Broadcast.Feed("A titan crystal has appeared in town - whoever takes it can become a titan!", "Gold")
end

-- The round is over: every titan power fades (a fresh crystal will come).
function ShifterService.ClearPowers()
	for _, shifter in shifters do
		removePower(shifter)
	end
end

function ShifterService.Init()
	remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	folder = Instance.new("Folder")
	folder.Name = "Shifters"
	folder.Parent = Workspace
	nextOrbAt = os.clock() + 45

	remote(Config.Remotes.Shift).OnServerEvent:Connect(function(player: Player, action: unknown, arg: unknown)
		if action == "Gauge" then
			gaugeTransform(player)
			return
		end
		local shifter = shifters[player]
		if not shifter then
			return
		end
		if action == "Choose" then
			if not shifter.Rig and not shifter.Gauge and (arg == "Humans" or arg == "Giants") then
				shifter.Side = arg :: string
				player:SetAttribute("ShifterSide", arg :: string)
			end
		elseif action == "Decline" then
			if not shifter.Rig and not shifter.Gauge then
				removePower(shifter)
				Broadcast.Feed(`{player.DisplayName} let the titan power go`, "Info")
			end
		elseif action == "Transform" then
			if shifter.Rig and shifter.Gauge then
				removePower(shifter) -- a gauge titan is a one-off
			elseif shifter.Rig then
				revert(shifter)
			else
				transform(shifter)
			end
		elseif action == "Primary" or action == "Punch" then
			usePower(shifter, "Primary")
		elseif action == "Secondary" or action == "Roar" then
			usePower(shifter, "Secondary")
		end
	end)

	GiantService.Defeated.Event:Connect(function(player: Player, _kindName: string, clean: boolean)
		onTakedown(player, clean == true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local shifter = shifters[player]
		if shifter then
			removePower(shifter)
		end
		immuneUntil[player] = nil
		gauges[player] = nil
	end)
	-- Knocked out, caught, fallen or reset: the power goes with the body.
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			local shifter = shifters[player]
			if shifter then
				removePower(shifter)
			end
		end)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					local shifter = shifters[player]
					if shifter and player.Character == character then
						removePower(shifter)
					end
				end)
			end
		end)
		setGauge(player, gauges[player] or 0)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, shifter in shifters do
				if now >= shifter.PowerUntil then
					if not shifter.Gauge then
						Broadcast.Feed(`{shifter.Player.DisplayName}'s titan power has faded`, "Info")
						Broadcast.Announce("THE TITAN POWER FADES", "", "Info", shifter.Player)
					end
					removePower(shifter)
				elseif shifter.Rig and now >= shifter.Until then
					if shifter.Gauge then
						removePower(shifter)
					else
						revert(shifter)
					end
				end
			end
			if not orb and holders() < S.Max and now >= nextOrbAt and #Players:GetPlayers() > 0 then
				spawnOrb()
			end
		end
	end)
end

return ShifterService
