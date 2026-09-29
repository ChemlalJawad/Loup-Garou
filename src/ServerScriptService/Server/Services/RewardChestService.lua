--!strict
-- Reward chests placed around the world (WorldKit.RewardChest). Finds every
-- part tagged Constants.TAGS.RewardChest, gives it a server-side
-- ProximityPrompt, and pays out on claim - once per cooldown per player.
--
-- Cooldowns are persisted in profile.Cooldowns, so leaving and rejoining
-- doesn't reset them. Payout grows gently with level so a chest stays worth
-- the climb for players at every stage, and goes through EconomyService so
-- the Double Coins pass and boosts apply.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)
local AudioService = require(ServerScriptService.Server.Services.AudioService)

local RewardChestService = {}

-- Server-side reach check, looser than the prompt's own distance to absorb
-- latency. ProximityPrompt.Triggered alone isn't proof of proximity.
local CLAIM_RADIUS = 16
local PROMPT_DISTANCE = 10
local LEVEL_BONUS_PER_LEVEL = 0.06 -- +6% per level

local wired: { [Instance]: boolean } = {}

local function notify(player: Player, message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)
end

local function formatDuration(seconds: number): string
	local minutes = math.floor(seconds / 60)
	local rest = seconds % 60
	if minutes > 0 then
		return `{minutes}m {rest}s`
	end
	return `{rest}s`
end

local function onClaim(chest: BasePart, player: Player)
	local chestId = chest:GetAttribute("ChestId")
	if type(chestId) ~= "string" then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - chest.Position).Magnitude > CLAIM_RADIUS then
		return
	end

	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local cooldownValue = chest:GetAttribute("CooldownSeconds")
	local cooldown = if type(cooldownValue) == "number" then cooldownValue else 600
	local key = `Chest:{chestId}`
	local now = os.time()
	local lastClaim = profile.Cooldowns[key]
	if lastClaim and now - lastClaim < cooldown then
		notify(player, `This chest refills in {formatDuration(cooldown - (now - lastClaim))}.`, "Info")
		return
	end

	DataService.Mutate(player, function(p)
		p.Cooldowns[key] = now
	end)

	local coinsValue = chest:GetAttribute("RewardCoins")
	local xpValue = chest:GetAttribute("RewardXP")
	local levelMultiplier = 1 + (profile.Level - 1) * LEVEL_BONUS_PER_LEVEL
	local coins = math.floor((if type(coinsValue) == "number" then coinsValue else 0) * levelMultiplier)
	local xp = if type(xpValue) == "number" then xpValue else 0

	local label = chest:GetAttribute("Label")
	local labelText = if type(label) == "string" then label else "Chest"
	EconomyService.AwardBundle(player, { Coins = coins, XP = xp }, labelText)
	notify(player, `You opened the {labelText}!`, "Success")
	AudioService.PlayAt(chest.Position, "ChestOpen")
end

local function wireChest(instance: Instance)
	if wired[instance] or not instance:IsA("BasePart") then
		return
	end
	wired[instance] = true
	local chest = instance :: BasePart

	local label = chest:GetAttribute("Label")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = if type(label) == "string" then label else "Treasure Chest"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = chest
	prompt.Triggered:Connect(function(player)
		onClaim(chest, player)
	end)

	chest.Destroying:Connect(function()
		wired[chest] = nil
	end)
end

function RewardChestService.Init()
	for _, chest in CollectionService:GetTagged(Constants.TAGS.RewardChest) do
		wireChest(chest)
	end
	CollectionService:GetInstanceAddedSignal(Constants.TAGS.RewardChest):Connect(wireChest)
end

return RewardChestService
