--!strict
-- Global game constants. Single source of truth for names/ids shared by every system.

local Constants = {}

Constants.GAME_NAME = "Brainrot Hatch Wars"
Constants.STUDIO_NAME = "Loup-Garou Studios"

Constants.CURRENCY = {
	SOFT = "Coins", -- earned in-game, spent on eggs / cosmetics
	HARD = "Gems", -- premium currency, bought with Robux or rare drops
}

Constants.DEFAULT_INVENTORY_SLOTS = 50
Constants.STARTING_COINS = 500
Constants.STARTING_GEMS = 0

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

Constants.RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Secret" }

Constants.REMOTE_NAMES = {
	Egg = {
		RequestHatch = "Egg_RequestHatch",
		HatchResult = "Egg_HatchResult",
		InventoryUpdated = "Egg_InventoryUpdated",
		EquipPet = "Egg_EquipPet",
	},
	Shop = {
		PromptGamePass = "Shop_PromptGamePass",
		PromptProduct = "Shop_PromptProduct",
		PurchaseResult = "Shop_PurchaseResult",
		CurrencyUpdated = "Shop_CurrencyUpdated",
		OwnedPassesUpdated = "Shop_OwnedPassesUpdated",
	},
	CTF = {
		RequestJoinTeam = "CTF_RequestJoinTeam",
		TeamAssigned = "CTF_TeamAssigned",
		FlagStateUpdated = "CTF_FlagStateUpdated",
		ScoreUpdated = "CTF_ScoreUpdated",
		RoundStateUpdated = "CTF_RoundStateUpdated",
		UseAbility = "CTF_UseAbility",
		AbilityFeedback = "CTF_AbilityFeedback",
	},
	Shared = {
		Notify = "Shared_Notify",
	},
}

return Constants
