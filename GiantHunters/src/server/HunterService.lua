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
	player.CharacterAdded:Connect(function()
		-- A fresh set of blades every life.
		local hunter = hunters[player]
		if hunter then
			hunter.Blades = Config.Blades.Max
			pushState(player)
		end
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
