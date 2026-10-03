--!strict
-- Titan shifters: players who can turn into a titan.
--
--   * Now and then a glowing crystal appears somewhere in town (never more
--     than Config.Shifters.Max shifters at once). Whoever takes it gets the
--     titan power and picks a side:
--       - the HUNTERS' side: your punches crush giants (they count as
--         takedowns), your roar dazes them;
--       - the GIANTS' side: your punches knock hunters out (back to the
--         wall), your roar blows them away - and hunters can cut your nape.
--     Titans on opposite sides can fight each other.
--   * T transforms (for Duration seconds, then a cooldown). The titan is a
--     part-built giant welded to your character, which is hidden and raised
--     to the titan's hip height, so you walk it with the normal controls.
--   * Lose all your nape health and you're thrown out of the titan, and the
--     power is gone.
-- Knockouts, not injuries: a knocked-out hunter just respawns on the wall.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local GiantFactory = require(script.Parent.GiantFactory)
local GiantService = require(script.Parent.GiantService)
local Broadcast = require(script.Parent.Broadcast)

local ShifterService = {}

ShifterService.Scored = Instance.new("BindableEvent") -- (player, points)

type Shifter = {
	Player: Player,
	Side: string?, -- "Humans" | "Giants"
	Rig: GiantFactory.Rig?,
	Health: number,
	Until: number,
	CooldownUntil: number,
	LastPunch: number,
	LastRoar: number,
	Hidden: { [Instance]: number },
	HipHeight: number,
	WalkSpeed: number,
	JumpPower: number,
}

local S = Config.Shifters
local shifters: { [Player]: Shifter } = {}
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

-- === Becoming a titan, and back ================================================

local function revert(shifter: Shifter)
	local rig = shifter.Rig
	if not rig then
		return
	end
	shifter.Rig = nil
	shifter.CooldownUntil = os.clock() + S.Cooldown
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
		end
	end
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 55
	player:SetAttribute("ShiftUntil", nil)
	player:SetAttribute("ShiftReadyAt", Workspace:GetServerTimeNow() + S.Cooldown)
end

local function transform(shifter: Shifter)
	local player = shifter.Player
	local character, humanoid, root = bodyOf(player)
	if not character or not humanoid or not root or not shifter.Side or shifter.Rig then
		return
	end
	if os.clock() < shifter.CooldownUntil or GiantService.IsHeld(player) then
		return
	end
	local ground = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local rig = GiantFactory.Build("Shifter", ground, rng)
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
	humanoid.HipHeight = math.max(legLength - root.Size.Y / 2, 2)
	humanoid.WalkSpeed = S.WalkSpeed
	humanoid.JumpPower = 0

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

	character:SetAttribute("Shifted", true)
	player.CameraMinZoomDistance = 30
	player.CameraMaxZoomDistance = 160
	shifter.Rig = rig
	shifter.Health = Config.GiantKinds.Shifter.NapeHealth
	shifter.Until = os.clock() + S.Duration
	player:SetAttribute("ShiftUntil", Workspace:GetServerTimeNow() + S.Duration)
	steam(root.Position, 18, 70)
	Broadcast.Shake(root.Position, 2)
	Broadcast.Feed(`{player.DisplayName} turned into a titan ({if side == "Humans" then "hunters' side" else "giants' side!"})`, if side == "Humans" then "Good" else "Danger")
end

-- === Fighting ==================================================================

local function removePower(shifter: Shifter)
	revert(shifter)
	local player = shifter.Player
	shifters[player] = nil
	player:SetAttribute("ShifterPower", nil)
	player:SetAttribute("ShifterSide", nil)
	player:SetAttribute("ShiftReadyAt", nil)
	nextOrbAt = math.max(nextOrbAt, os.clock() + S.OrbEvery)
end

local function defeatShifter(shifter: Shifter, by: Player)
	local player = shifter.Player
	Broadcast.Feed(`{by.DisplayName} cut down {player.DisplayName}'s titan!`, "Gold")
	ShifterService.Scored:Fire(by, Config.GiantKinds.Shifter.Points)
	removePower(shifter)
	remote(Config.Remotes.Knocked):FireClient(player, Vector3.new(0, 80, 0))
end

local function hurt(shifter: Shifter, by: Player, amount: number): boolean
	local rig = shifter.Rig
	if not rig then
		return false
	end
	shifter.Health -= amount
	rig.Model:SetAttribute("NapeHealth", math.max(shifter.Health, 0))
	if shifter.Health <= 0 then
		defeatShifter(shifter, by)
		return true
	end
	return false
end

local function knockout(victim: Player, by: Player)
	remote(Config.Remotes.Caught):FireClient(victim, "Titan")
	Broadcast.Feed(`{by.DisplayName}'s titan knocked out {victim.DisplayName}!`, "Danger")
	ShifterService.Scored:Fire(by, S.KnockoutPoints)
	task.spawn(function()
		if victim.Parent then
			victim:LoadCharacterAsync()
		end
	end)
end

local function punch(shifter: Shifter)
	local rig = shifter.Rig
	local _, _, root = bodyOf(shifter.Player)
	local now = os.clock()
	if not rig or not root or now - shifter.LastPunch < S.PunchCooldown then
		return
	end
	shifter.LastPunch = now
	local model = rig.Model
	model:SetAttribute("Swat", "Right") -- the animator swings the arm through
	task.delay(0.15, function()
		model:SetAttribute("Swat", "")
	end)
	local height = Config.GiantKinds.Shifter.Height
	local centre = root.Position + root.CFrame.LookVector * height * 0.35 + Vector3.new(0, height * 0.15, 0)
	local radius = height * S.PunchReach
	local player = shifter.Player
	if shifter.Side == "Humans" then
		GiantService.Punch(player, centre, radius)
	else
		for _, other in Players:GetPlayers() do
			local character, _, otherRoot = bodyOf(other)
			if other ~= player and character and otherRoot and not character:GetAttribute("Shifted") and (otherRoot.Position - centre).Magnitude <= radius then
				knockout(other, player)
			end
		end
	end
	-- Titans on the other side.
	for other, enemy in shifters do
		local enemyRig = enemy.Rig
		if other ~= player and enemyRig and enemy.Side ~= shifter.Side and (enemyRig.Torso.Position - centre).Magnitude <= radius + height * 0.3 then
			hurt(enemy, player, 1)
		end
	end
	Broadcast.Shake(centre, 0.6)
end

local function roar(shifter: Shifter)
	local rig = shifter.Rig
	local _, _, root = bodyOf(shifter.Player)
	local now = os.clock()
	if not rig or not root or now - shifter.LastRoar < S.RoarCooldown then
		return
	end
	shifter.LastRoar = now
	local model = rig.Model
	model:SetAttribute("Grabbing", true)
	task.delay(0.9, function()
		model:SetAttribute("Grabbing", false)
	end)
	steam(rig.Head.Position, 10, 30)
	Broadcast.Shake(root.Position, 1.4)
	if shifter.Side == "Humans" then
		GiantService.DazeAround(root.Position, S.RoarRadius)
	else
		for _, other in Players:GetPlayers() do
			local character, _, otherRoot = bodyOf(other)
			if other ~= shifter.Player and character and otherRoot and not character:GetAttribute("Shifted") and (otherRoot.Position - root.Position).Magnitude <= S.RoarRadius then
				local away = Geo.Flat(otherRoot.Position - root.Position)
				local push = (if away.Magnitude > 0.5 then away.Unit else Vector3.new(0, 0, 1)) + Vector3.new(0, 0.5, 0)
				remote(Config.Remotes.Knocked):FireClient(other, push.Unit * 110)
			end
		end
	end
end

-- Hunters' blades against a titan on the giants' side: its nape, from
-- behind or the side. Called by HunterService when no giant was in reach.
function ShifterService.TryHit(player: Player, root: BasePart): (string?, { [string]: any }?)
	local here = root.Position
	for other, shifter in shifters do
		local rig = shifter.Rig
		if other ~= player and rig and shifter.Side == "Giants" then
			local toHunter = here - rig.Head.Position
			local inFront = toHunter.Magnitude > 0.01 and toHunter.Unit:Dot(rig.Root.CFrame.LookVector) > Config.Cuts.EyesFrontDot
			local nape = rig.Nape
			if not inFront and (nape.Position - here).Magnitude <= Config.Blades.SlashRange + nape.Size.X / 2 then
				local speed = root.AssemblyLinearVelocity.Magnitude
				local clean = speed >= Config.Blades.CleanCutSpeed
				local info = { Kind = "Titan Shifter", Clean = clean, Speed = speed, Position = nape.Position }
				local down = hurt(shifter, player, if clean then 1 else 0.5)
				return if down then "Defeated" else "Hit", info
			end
		end
	end
	return nil, nil
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
	prompt.Parent = crystal
	prompt.Triggered:Connect(function(player)
		if shifters[player] or holders() >= S.Max or orb ~= model then
			return
		end
		orb = nil
		model:Destroy()
		shifters[player] = {
			Player = player,
			Side = nil,
			Rig = nil,
			Health = 0,
			Until = 0,
			CooldownUntil = 0,
			LastPunch = 0,
			LastRoar = 0,
			Hidden = {},
			HipHeight = 0,
			WalkSpeed = 0,
			JumpPower = 0,
		}
		player:SetAttribute("ShifterPower", true)
		nextOrbAt = os.clock() + S.OrbEvery
		Broadcast.Feed(`{player.DisplayName} took the titan power!`, "Gold")
		Broadcast.Announce("TITAN POWER", "Choose your side, then press T to transform", "Gold", player)
	end)
	CollectionService:AddTag(model, Config.Tags.PowerOrb)
	model.Parent = folder
	orb = model
	Broadcast.Feed("A titan crystal has appeared in town - whoever takes it can become a titan!", "Gold")
end

function ShifterService.Init()
	remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	folder = Instance.new("Folder")
	folder.Name = "Shifters"
	folder.Parent = Workspace
	nextOrbAt = os.clock() + 45

	remote(Config.Remotes.Shift).OnServerEvent:Connect(function(player: Player, action: unknown, arg: unknown)
		local shifter = shifters[player]
		if not shifter then
			return
		end
		if action == "Choose" then
			if not shifter.Rig and (arg == "Humans" or arg == "Giants") then
				shifter.Side = arg :: string
				player:SetAttribute("ShifterSide", arg :: string)
			end
		elseif action == "Transform" then
			if shifter.Rig then
				revert(shifter)
			else
				transform(shifter)
			end
		elseif action == "Punch" then
			punch(shifter)
		elseif action == "Roar" then
			roar(shifter)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local shifter = shifters[player]
		if shifter then
			removePower(shifter)
		end
	end)
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			local shifter = shifters[player]
			if shifter then
				revert(shifter)
			end
		end)
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
				if shifter.Rig and now >= shifter.Until then
					revert(shifter)
				end
			end
			if not orb and holders() < S.Max and now >= nextOrbAt and #Players:GetPlayers() > 0 then
				spawnOrb()
			end
		end
	end)
end

return ShifterService
