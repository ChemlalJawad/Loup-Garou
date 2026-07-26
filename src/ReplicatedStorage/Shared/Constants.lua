--!strict
-- Global game constants. Single source of truth for names/ids shared by every
-- system. Adding a system? Add its remote names under REMOTE_NAMES with a
-- "<Domain>_<Action>" naming convention, and its tuning numbers here rather
-- than hardcoding them in a service.

local Constants = {}

Constants.GAME_NAME = "Brainrot Hatch Wars"
Constants.STUDIO_NAME = "Loup-Garou Studios"

Constants.CURRENCY = {
	SOFT = "Coins", -- earned in-game, spent on eggs / upgrades / cosmetics
	HARD = "Gems", -- premium currency, bought with Robux or rare drops
}

Constants.DEFAULT_INVENTORY_SLOTS = 50
Constants.STARTING_COINS = 500
Constants.STARTING_GEMS = 0

-- === Progression ============================================================

-- XP needed to go from level N to N+1 is BASE * (N ^ EXPONENT), rounded.
Constants.LEVEL_XP_BASE = 100
Constants.LEVEL_XP_EXPONENT = 1.45
Constants.MAX_LEVEL = 100

-- Rebirth: hard reset of level/coins in exchange for a permanent multiplier.
Constants.REBIRTH_MIN_LEVEL = 25
Constants.REBIRTH_COIN_MULTIPLIER_PER = 0.25 -- +25% coins per rebirth, additive
Constants.REBIRTH_MAX = 20

-- === Teams / CTF ============================================================

Constants.TEAMS = {
	{
		Id = "Red",
		Name = "Team Ember",
		Color = Color3.fromRGB(255, 71, 87),
		BaseSpawnName = "RedBaseSpawn",
		FlagStandName = "RedFlagStand",
	},
	{
		Id = "Blue",
		Name = "Team Frost",
		Color = Color3.fromRGB(46, 134, 255),
		BaseSpawnName = "BlueBaseSpawn",
		FlagStandName = "BlueFlagStand",
	},
}

Constants.CTF_ROUND_LENGTH_SECONDS = 300
Constants.CTF_SCORE_TO_WIN = 3
Constants.CTF_TAG_STUN_SECONDS = 4
Constants.CTF_INTERMISSION_SECONDS = 15

-- Coin/XP payouts for CTF actions. EconomyService applies multipliers on top.
Constants.CTF_REWARDS = {
	Capture = { Coins = 150, XP = 120 },
	Return = { Coins = 60, XP = 45 },
	Tag = { Coins = 35, XP = 25 },
	RoundWin = { Coins = 250, XP = 200 },
	RoundLoss = { Coins = 75, XP = 60 },
}

-- === Rarity =================================================================

Constants.RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Secret" }

-- Coins refunded when selling a duplicate Brainrot, by rarity.
Constants.SELL_VALUE = {
	Common = 40,
	Rare = 220,
	Epic = 900,
	Legendary = 4500,
	Secret = 25000,
}

-- Duplicates needed to merge up into one of the next rarity tier.
Constants.MERGE_COST = 5

-- === Idle income ============================================================

-- Your equipped Brainrot passively earns Coins. Base rate per second by
-- rarity; EconomyService applies level/rebirth/gamepass multipliers on top.
Constants.IDLE_COINS_PER_SECOND = {
	Common = 0.5,
	Rare = 2,
	Epic = 8,
	Legendary = 30,
	Secret = 120,
}
Constants.IDLE_TICK_SECONDS = 5

-- === Daily rewards ==========================================================

Constants.DAILY_REWARDS = {
	{ Day = 1, Coins = 500, Gems = 0 },
	{ Day = 2, Coins = 1200, Gems = 0 },
	{ Day = 3, Coins = 0, Gems = 25 },
	{ Day = 4, Coins = 3000, Gems = 0 },
	{ Day = 5, Coins = 0, Gems = 60 },
	{ Day = 6, Coins = 8000, Gems = 0 },
	{ Day = 7, Coins = 20000, Gems = 150 },
}
Constants.DAILY_STREAK_RESET_HOURS = 48

-- === Leaderboards ===========================================================

Constants.LEADERBOARD_KEYS = { "Coins", "FlagCaptures", "EggsHatched", "Level" }
Constants.LEADERBOARD_SIZE = 25
Constants.LEADERBOARD_REFRESH_SECONDS = 60

-- === Remotes ================================================================

Constants.REMOTE_NAMES = {
	Egg = {
		RequestHatch = "Egg_RequestHatch",
		HatchResult = "Egg_HatchResult",
		InventoryUpdated = "Egg_InventoryUpdated",
		EquipPet = "Egg_EquipPet",
		SellBrainrot = "Egg_SellBrainrot",
		SellDuplicates = "Egg_SellDuplicates",
		MergeBrainrots = "Egg_MergeBrainrots",
		SetAutoHatch = "Egg_SetAutoHatch",
	},
	Shop = {
		PromptGamePass = "Shop_PromptGamePass",
		PromptProduct = "Shop_PromptProduct",
		PurchaseResult = "Shop_PurchaseResult",
		CurrencyUpdated = "Shop_CurrencyUpdated",
		OwnedPassesUpdated = "Shop_OwnedPassesUpdated",
	},
	-- In-game-currency store: works fully offline from Robux, so it's the
	-- shop path that is testable in Studio today.
	Store = {
		RequestPurchase = "Store_RequestPurchase",
		PurchaseResult = "Store_PurchaseResult",
		StateUpdated = "Store_StateUpdated",
	},
	CTF = {
		RequestJoinTeam = "CTF_RequestJoinTeam",
		RequestLeaveTeam = "CTF_RequestLeaveTeam",
		TeamAssigned = "CTF_TeamAssigned",
		FlagStateUpdated = "CTF_FlagStateUpdated",
		ScoreUpdated = "CTF_ScoreUpdated",
		RoundStateUpdated = "CTF_RoundStateUpdated",
		UseAbility = "CTF_UseAbility",
		AbilityFeedback = "CTF_AbilityFeedback",
		MatchSummary = "CTF_MatchSummary",
		KillFeed = "CTF_KillFeed",
		PowerupCollected = "CTF_PowerupCollected",
	},
	Economy = {
		StateUpdated = "Economy_StateUpdated", -- coins, gems, xp, level, rebirths, multipliers
		RequestRebirth = "Economy_RequestRebirth",
		RebirthResult = "Economy_RebirthResult",
		RewardPopup = "Economy_RewardPopup", -- floating "+150 Coins" feedback
	},
	Quests = {
		StateUpdated = "Quests_StateUpdated",
		ClaimReward = "Quests_ClaimReward",
		ClaimResult = "Quests_ClaimResult",
	},
	Daily = {
		StateUpdated = "Daily_StateUpdated",
		ClaimReward = "Daily_ClaimReward",
		ClaimResult = "Daily_ClaimResult",
	},
	Index = {
		StateUpdated = "Index_StateUpdated",
		ClaimMilestone = "Index_ClaimMilestone",
	},
	Codes = {
		Redeem = "Codes_Redeem",
		RedeemResult = "Codes_RedeemResult",
	},
	Leaderboard = {
		Updated = "Leaderboard_Updated",
	},
	Pets = {
		EquippedChanged = "Pets_EquippedChanged",
	},
	Audio = {
		PlaySfx = "Audio_PlaySfx",
	},
	Shared = {
		Notify = "Shared_Notify",
	},
}

return Constants
