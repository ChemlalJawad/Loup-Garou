--!strict
-- Hunters: leaderstats, blades, resupply, and validating every slash.
--
-- Movement is simulated on each player's own client (it has to be, for a
-- grapple to feel responsive), but damage never is: a slash is just a
-- request, and the server checks the cooldown, the blades left, and the
-- hunter's real position against the giant's weak spot before anything
-- happens (GiantService.TryHitNape).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GiantService = require(script.Parent.GiantService)

local HunterService = {}

type Hunter = {
	Blades: number,
	LastSlash: number,
}

local hunters: { [Player]: Hunter } = {}
local remotes: Folder

local function remote(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

local function pushState(player: Player)
	local hunter = hunters[player]
	if hunter then
		remote(Config.Remotes.State):FireClient(player, { Blades = hunter.Blades, MaxBlades = Config.Blades.Max })
	end
end

-- === Twin blades =============================================================
-- A long, thin blade in each hand, built from parts on the server so every
-- player sees them. Each carries a (disabled) Trail the owner's client
-- flashes on during a slash. Dull blades (none left) turn grey and cracked.

local BLADE_LENGTH = 4.6

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
	local grip = bladePart("Grip", Vector3.new(0.28, 0.28, 1.1), Color3.fromRGB(45, 45, 55), Enum.Material.Metal, sword)
	local guard = bladePart("Guard", Vector3.new(0.7, 0.18, 0.2), Color3.fromRGB(160, 150, 120), Enum.Material.Metal, sword)
	local blade = bladePart("Blade", Vector3.new(0.08, 0.42, BLADE_LENGTH), Color3.fromRGB(215, 225, 235), Enum.Material.Metal, sword)
	blade.Reflectance = 0.35
	local edge = bladePart("Edge", Vector3.new(0.1, 0.06, BLADE_LENGTH), Color3.fromRGB(240, 250, 255), Enum.Material.Neon, sword)

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
	weldTo(grip, CFrame.new())
	weldTo(guard, CFrame.new(0, 0, -0.6))
	weldTo(blade, CFrame.new(0, 0, -0.7 - BLADE_LENGTH / 2))
	weldTo(edge, CFrame.new(0, -0.22, -0.7 - BLADE_LENGTH / 2))

	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = Vector3.new(0, 0, BLADE_LENGTH / 2 - 0.2)
	base.Parent = blade
	local tip = Instance.new("Attachment")
	tip.Name = "TrailTip"
	tip.Position = Vector3.new(0, 0, -BLADE_LENGTH / 2)
	tip.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "BladeTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
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
		local blade = sword and sword:FindFirstChild("Blade")
		local edge = sword and sword:FindFirstChild("Edge")
		if blade and blade:IsA("BasePart") then
			blade.Color = if sharp then Color3.fromRGB(215, 225, 235) else Color3.fromRGB(120, 115, 110)
			blade.Reflectance = if sharp then 0.35 else 0
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
end

local function stat(player: Player, name: string): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(name)
	return if value and value:IsA("IntValue") then value else nil
end

local function onPlayerAdded(player: Player)
	hunters[player] = { Blades = Config.Blades.Max, LastSlash = 0 }
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in { "Giants", "Points" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = leaderstats
	end
	leaderstats.Parent = player
	player.CharacterAdded:Connect(function(character)
		-- A fresh set of blades every life.
		local hunter = hunters[player]
		if hunter then
			hunter.Blades = Config.Blades.Max
			pushState(player)
		end
		task.spawn(equipSwords, character)
	end)
end

local function onSlash(player: Player)
	local hunter = hunters[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hunter or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if now - hunter.LastSlash < Config.Blades.SlashCooldown then
		return
	end
	hunter.LastSlash = now
	if hunter.Blades <= 0 then
		remote(Config.Remotes.SlashResult):FireClient(player, "Dull", nil)
		return
	end

	local result, info = GiantService.TryHitNape(player, root)
	if result ~= "NoTarget" then
		hunter.Blades -= 1 -- blades only wear down on a real hit
		pushState(player)
		if hunter.Blades <= 0 then
			setBladesSharp(player, false)
		end
	end
	remote(Config.Remotes.SlashResult):FireClient(player, result, info)
end

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

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		hunters[player] = nil
	end)

	remote(Config.Remotes.Slash).OnServerEvent:Connect(onSlash)

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

	GiantService.Defeated.Event:Connect(function(player: Player, _kindName: string, points: number)
		local giantsStat = stat(player, "Giants")
		local pointsStat = stat(player, "Points")
		if giantsStat then
			giantsStat.Value += 1
		end
		if pointsStat then
			pointsStat.Value += points
		end
	end)
end

return HunterService
