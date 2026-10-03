--!strict
-- Hunters: characters (spawned on the wall, respawned after a fall), the
-- leaderboard (giants, points, rank), the twin swords, blades and resupply,
-- every slash validated, combos and style points, signal flares, the cable
-- relay, and each round's top hunter.
--
-- Movement is simulated on each player's own client (it has to be, for a
-- grapple to feel responsive), but damage never is: a slash is just a
-- request, and the server checks the cooldown, the blades left, and the
-- hunter's real position against the giant before anything happens
-- (GiantService.TryHit).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GiantService = require(script.Parent.GiantService)
local WaveService = require(script.Parent.WaveService)
local Broadcast = require(script.Parent.Broadcast)
local ShifterService = require(script.Parent.ShifterService)
local HunterGear = require(script.Parent.HunterGear)

local HunterService = {}

type Hunter = {
	Blades: number,
	LastSlash: number,
	Combo: number,
	ComboUntil: number,
	RoundPoints: number,
	LastFlare: number,
}

local hunters: { [Player]: Hunter } = {}
local remotes: Folder

local function remote(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

local function stat(player: Player, name: string): ValueBase?
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(name)
	return if value and value:IsA("ValueBase") then value else nil
end

local function points(player: Player): number
	local value = stat(player, "Points")
	return if value and value:IsA("IntValue") then value.Value else 0
end

local function pushState(player: Player)
	local hunter = hunters[player]
	if hunter then
		remote(Config.Remotes.State):FireClient(player, {
			Blades = hunter.Blades,
			MaxBlades = Config.Blades.Max,
			Combo = hunter.Combo,
			ComboLeft = math.max(hunter.ComboUntil - os.clock(), 0),
			Points = points(player),
			Rank = Config.RankFor(points(player)),
		})
	end
end

local function award(player: Player, amount: number)
	local hunter = hunters[player]
	local value = stat(player, "Points")
	if not hunter or not value or not value:IsA("IntValue") or amount <= 0 then
		return
	end
	local before = Config.RankFor(value.Value)
	value.Value += amount
	hunter.RoundPoints += amount
	local after = Config.RankFor(value.Value)
	local rank = stat(player, "Rank")
	if rank and rank:IsA("StringValue") then
		rank.Value = after
	end
	if after ~= before then
		Broadcast.Announce(`RANK UP: {string.upper(after)}`, `{value.Value} points`, "Gold", player)
		Broadcast.Feed(`{player.DisplayName} is now a {after}!`, "Gold")
	end
	pushState(player)
end

-- === Twin blades =============================================================
-- A long, thin blade in each hand, built from parts on the server so every
-- player sees them: a pistol-grip handle with a trigger (it releases the
-- blade, so a fresh one can be slotted in from the box on the hip), a
-- squared hilt, and a blade scored with the snap lines between its
-- segments, cut off at an angle at the tip. Each carries a (disabled)
-- Trail the owner's client flashes on during a slash. Dull blades (none
-- left) turn grey.

local BLADE_LENGTH = 5.2
local TIP_LENGTH = 0.55
local SHARP = Color3.fromRGB(215, 225, 235)
local DULL = Color3.fromRGB(120, 115, 110)

local function bladePart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function attachSword(character: Model, hand: BasePart, side: number)
	local sword = Instance.new("Model")
	sword.Name = if side < 0 then "LeftSword" else "RightSword"
	local darkMetal = Color3.fromRGB(52, 54, 62)
	local brass = Color3.fromRGB(176, 160, 116)
	local grip = bladePart("Grip", Vector3.new(0.26, 0.34, 1), Color3.fromRGB(40, 34, 32), Enum.Material.Leather, sword)
	local pommel = bladePart("Pommel", Vector3.new(0.3, 0.4, 0.16), darkMetal, Enum.Material.Metal, sword)
	local triggerGuard = bladePart("TriggerGuard", Vector3.new(0.08, 0.06, 0.7), darkMetal, Enum.Material.Metal, sword)
	local trigger = bladePart("Trigger", Vector3.new(0.07, 0.2, 0.07), brass, Enum.Material.Metal, sword)
	local hilt = bladePart("Hilt", Vector3.new(0.34, 0.56, 0.42), darkMetal, Enum.Material.Metal, sword)
	local collar = bladePart("Collar", Vector3.new(0.38, 0.6, 0.08), brass, Enum.Material.Metal, sword)
	local blade = bladePart("Blade", Vector3.new(0.07, 0.42, BLADE_LENGTH - TIP_LENGTH), SHARP, Enum.Material.Metal, sword)
	blade.Reflectance = 0.35
	-- The angled tip: a wedge whose point carries the cutting edge on.
	local tip = Instance.new("WedgePart")
	tip.Name = "BladeTip"
	tip.Size = Vector3.new(0.07, 0.42, TIP_LENGTH)
	tip.Color = SHARP
	tip.Material = Enum.Material.Metal
	tip.Reflectance = 0.35
	tip.CanCollide = false
	tip.CanQuery = false
	tip.CanTouch = false
	tip.Massless = true
	tip.CastShadow = false
	tip.Parent = sword
	local edge = bladePart("Edge", Vector3.new(0.09, 0.05, BLADE_LENGTH - 0.15), Color3.fromRGB(240, 250, 255), Enum.Material.Neon, sword)

	-- Held forward: grip in the fist, blade pointing ahead of the hand and
	-- a little down, the ready stance.
	local gripOffset = CFrame.new(0, -0.25, -0.25) * CFrame.Angles(math.rad(-15), 0, 0)
	local function weldTo(p: BasePart, offset: CFrame)
		local w = Instance.new("Weld")
		w.Part0 = hand
		w.Part1 = p
		w.C0 = gripOffset * offset
		w.Parent = p
	end
	local bladeStart = -0.9 -- where the blade leaves the hilt
	local bladeMiddle = bladeStart - (BLADE_LENGTH - TIP_LENGTH) / 2
	weldTo(grip, CFrame.new())
	weldTo(pommel, CFrame.new(0, 0, 0.56))
	weldTo(triggerGuard, CFrame.new(0, -0.3, -0.05))
	weldTo(trigger, CFrame.new(0, -0.22, -0.22))
	weldTo(hilt, CFrame.new(0, 0.06, -0.66))
	weldTo(collar, CFrame.new(0, 0.06, -0.9))
	weldTo(blade, CFrame.new(0, 0, bladeMiddle))
	-- The wedge's tall face is its +Z: against the blade, sloping down to a
	-- point on the cutting edge (the blade's underside).
	weldTo(tip, CFrame.new(0, 0, bladeStart - (BLADE_LENGTH - TIP_LENGTH) - TIP_LENGTH / 2))
	weldTo(edge, CFrame.new(0, -0.2, bladeStart - (BLADE_LENGTH - 0.15) / 2))
	-- Snap lines: the blade is a stack of segments, broken off one by one.
	for s = 1, 6 do
		local line = bladePart(`SnapLine{s}`, Vector3.new(0.085, 0.36, 0.035), Color3.fromRGB(96, 104, 114), Enum.Material.Metal, sword)
		weldTo(line, CFrame.new(0, 0.02, bladeStart - s * (BLADE_LENGTH - TIP_LENGTH) / 7) * CFrame.Angles(math.rad(30), 0, 0))
	end

	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = Vector3.new(0, 0, (BLADE_LENGTH - TIP_LENGTH) / 2 - 0.2)
	base.Parent = blade
	local point = Instance.new("Attachment")
	point.Name = "TrailTip"
	point.Position = Vector3.new(0, -0.15, -(BLADE_LENGTH - TIP_LENGTH) / 2 - TIP_LENGTH)
	point.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "BladeTrail"
	trail.Attachment0 = base
	trail.Attachment1 = point
	trail.Lifetime = 0.18
	trail.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.LightEmission = 1
	trail.Enabled = false
	trail.Parent = blade

	sword.Parent = character
end

local function setBladesSharp(player: Player, sharp: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, name in { "LeftSword", "RightSword" } do
		local sword = character:FindFirstChild(name)
		local edge = sword and sword:FindFirstChild("Edge")
		for _, partName in { "Blade", "BladeTip" } do
			local blade = sword and sword:FindFirstChild(partName)
			if blade and blade:IsA("BasePart") then
				blade.Color = if sharp then SHARP else DULL
				blade.Reflectance = if sharp then 0.35 else 0
			end
		end
		if edge and edge:IsA("BasePart") then
			edge.Transparency = if sharp then 0 else 1
		end
	end
end

local function equipSwords(character: Model)
	-- R15 hands, or R6 arms.
	local left = character:WaitForChild("LeftHand", 5) or character:FindFirstChild("Left Arm")
	local right = character:WaitForChild("RightHand", 1) or character:FindFirstChild("Right Arm")
	if left and left:IsA("BasePart") then
		attachSword(character, left, -1)
	end
	if right and right:IsA("BasePart") then
		attachSword(character, right, 1)
	end
	HunterGear.Dress(character)
end

-- === Characters ==============================================================
-- CharacterAutoLoads is off (the map builds first); hunters spawn here, and
-- again a few seconds after a fall.

local function spawnCharacter(player: Player)
	if player.Parent then
		player:LoadCharacterAsync()
	end
end

local function onPlayerAdded(player: Player)
	hunters[player] = { Blades = Config.Blades.Max, LastSlash = 0, Combo = 0, ComboUntil = 0, RoundPoints = 0, LastFlare = 0 }
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in { "Giants", "Points" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = leaderstats
	end
	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Value = Config.RankFor(0)
	rank.Parent = leaderstats
	leaderstats.Parent = player
	player.CharacterAdded:Connect(function(character)
		-- A fresh set of blades every life.
		local hunter = hunters[player]
		if hunter then
			hunter.Blades = Config.Blades.Max
			pushState(player)
		end
		task.spawn(equipSwords, character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				task.delay(Players.RespawnTime, function()
					if player.Character == character then
						spawnCharacter(player)
					end
				end)
			end)
		end
	end)
	task.spawn(spawnCharacter, player)
end

-- === Slashing ================================================================

local function onSlash(player: Player)
	local hunter = hunters[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hunter or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	if GiantService.IsHeld(player) or (character :: Model):GetAttribute("Shifted") then
		return -- held: a slash is a wriggle; a titan punches instead (ShifterService)
	end
	local now = os.clock()
	if now - hunter.LastSlash < Config.Blades.SlashCooldown then
		return
	end
	hunter.LastSlash = now
	if hunter.Blades <= 0 then
		remote(Config.Remotes.SlashResult):FireClient(player, "Dull", {})
		return
	end
	local result: string, info: any = GiantService.TryHit(player, root)
	if result == "NoTarget" then
		-- A titan on the giants' side?
		local shifterResult, shifterInfo = ShifterService.TryHit(player, root)
		if shifterResult then
			result, info = shifterResult, shifterInfo
		end
	end
	if result == "NoTarget" then
		-- A training dummy: practice cuts, free (no blade used, no points).
		for _, target in CollectionService:GetTagged(Config.Tags.DummyNape) do
			if target:IsA("BasePart") and (target.Position - root.Position).Magnitude <= Config.Blades.SlashRange + target.Size.X / 2 then
				local toHunter = root.Position - target.Position
				if toHunter.Magnitude < 0.01 or toHunter.Unit:Dot(target.CFrame.LookVector) < Config.Cuts.EyesFrontDot then
					local speed = root.AssemblyLinearVelocity.Magnitude
					remote(Config.Remotes.SlashResult):FireClient(player, "Training", { Speed = speed, Clean = speed >= Config.Blades.CleanCutSpeed, Position = target.Position })
					return
				end
			end
		end
	end
	if result ~= "NoTarget" then
		hunter.Blades -= 1 -- blades only wear down on a real hit
		pushState(player)
		if hunter.Blades <= 0 then
			setBladesSharp(player, false)
		end
	end
	remote(Config.Remotes.SlashResult):FireClient(player, result, info)
end

local function onDefeated(player: Player, kindName: string, _clean: boolean, speed: number)
	local hunter = hunters[player]
	local kind = Config.GiantKinds[kindName]
	if not hunter or not kind then
		return
	end
	local now = os.clock()
	hunter.Combo = if now < hunter.ComboUntil then math.min(hunter.Combo + 1, Config.Hunters.MaxCombo) else 1
	hunter.ComboUntil = now + Config.Hunters.ComboWindow
	local giantsStat = stat(player, "Giants")
	if giantsStat and giantsStat:IsA("IntValue") then
		giantsStat.Value += 1
	end
	local bonus = if speed >= Config.Hunters.SpeedKill then 1 else 0
	award(player, kind.Points * hunter.Combo + bonus)
	if hunter.Combo >= 3 then
		Broadcast.Feed(`{player.DisplayName} is on a x{hunter.Combo} combo!`, "Gold")
	end
end

local ASSIST_POINTS = {
	Trip = Config.Hunters.TripPoints,
	Daze = Config.Hunters.DazePoints,
	Rescue = Config.Hunters.RescuePoints,
	Cannon = Config.Hunters.CannonPoints,
	Armor = 2,
}

-- === Flares ==================================================================
-- A green signal flare: a glowing shell climbs high above you trailing
-- smoke, then bursts into a cloud everyone can see. "Over here!"

local function fireFlare(player: Player)
	local hunter = hunters[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not hunter or not root or not root:IsA("BasePart") then
		return
	end
	local now = os.clock()
	if now - hunter.LastFlare < Config.Hunters.FlareCooldown then
		return
	end
	hunter.LastFlare = now
	local green = Color3.fromRGB(110, 240, 130)
	local start = root.Position + Vector3.new(0, 3, 0)
	local shell = Instance.new("Part")
	shell.Name = "Flare"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.one * 1.4
	shell.Color = green
	shell.Material = Enum.Material.Neon
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.Position = start
	shell.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = green
	light.Range = 30
	light.Brightness = 3
	light.Parent = shell
	local trail = Instance.new("ParticleEmitter")
	trail.Color = ColorSequence.new(green)
	trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = NumberRange.new(3, 5)
	trail.Speed = NumberRange.new(0, 1)
	trail.Rate = 60
	trail.Parent = shell
	TweenService:Create(shell, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = start + Vector3.new(0, 140, 0) }):Play()
	task.delay(2.2, function()
		trail.Rate = 0
		local cloud = Instance.new("ParticleEmitter")
		cloud.Color = ColorSequence.new(green)
		cloud.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 12), NumberSequenceKeypoint.new(1, 30) })
		cloud.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		cloud.Lifetime = NumberRange.new(6, 9)
		cloud.Speed = NumberRange.new(2, 6)
		cloud.SpreadAngle = Vector2.new(180, 180)
		cloud.Rate = 0
		cloud.Parent = shell
		cloud:Emit(36)
		shell.Transparency = 1
	end)
	Debris:AddItem(shell, 12)
	Broadcast.Feed(`{player.DisplayName} fired a flare!`, "Info")
end

-- === Resupply ================================================================

local function wireSupply(crate: Instance)
	if not crate:IsA("BasePart") or crate:FindFirstChildOfClass("ProximityPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Resupply"
	prompt.ObjectText = "Gas & Blades"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = crate
	prompt.Triggered:Connect(function(player)
		local hunter = hunters[player]
		if hunter then
			hunter.Blades = Config.Blades.Max
			pushState(player)
			setBladesSharp(player, true)
			remote(Config.Remotes.Resupplied):FireClient(player) -- client refills its gas
		end
	end)
end

function HunterService.Init()
	remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	Players.CharacterAutoLoads = false

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		hunters[player] = nil
	end)

	remote(Config.Remotes.Slash).OnServerEvent:Connect(onSlash)
	remote(Config.Remotes.Flare).OnServerEvent:Connect(fireFlare)

	-- Cable relay: tell everyone else where a hunter's hooks are, so they
	-- see the swing. Light sanity checks; cables are cosmetic for others.
	local hookRemote = remote(Config.Remotes.Hook)
	hookRemote.OnServerEvent:Connect(function(player: Player, side: unknown, part: unknown, localPos: unknown)
		if side ~= "Left" and side ~= "Right" then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if part ~= nil then
			if typeof(part) ~= "Instance" or not (part :: Instance):IsA("BasePart") or typeof(localPos) ~= "Vector3" then
				return
			end
			if not root or not root:IsA("BasePart") then
				return
			end
			local world = (part :: BasePart).CFrame:PointToWorldSpace(localPos :: Vector3)
			if (world - root.Position).Magnitude > Config.Grapple.Range + 60 then
				return
			end
		end
		for _, other in Players:GetPlayers() do
			if other ~= player then
				hookRemote:FireClient(other, player, side, part, localPos)
			end
		end
	end)

	for _, crate in CollectionService:GetTagged(Config.Tags.Supply) do
		wireSupply(crate)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Supply):Connect(wireSupply)

	GiantService.Defeated.Event:Connect(onDefeated)
	GiantService.Assist.Event:Connect(function(player: Player, reason: string)
		award(player, ASSIST_POINTS[reason] or 0)
	end)
	ShifterService.Scored.Event:Connect(function(player: Player, amount: number)
		award(player, amount)
	end)

	WaveService.RoundStarted.Event:Connect(function()
		for _, hunter in hunters do
			hunter.RoundPoints = 0
		end
	end)
	WaveService.RoundEnded.Event:Connect(function(round: number)
		local best: Player? = nil
		local bestPoints = 0
		for player, hunter in hunters do
			if hunter.RoundPoints > bestPoints then
				best, bestPoints = player, hunter.RoundPoints
			end
		end
		if best then
			Broadcast.Feed(`Top hunter of round {round}: {best.DisplayName} ({bestPoints} points)`, "Gold")
		end
	end)
end

return HunterService
