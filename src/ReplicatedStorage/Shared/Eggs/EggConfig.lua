--!strict
-- Egg + Brainrot pool definitions. Pure data plus pure-function helpers only
-- (no DataService/Net access here) so both server (EggService, authoritative
-- rolls) and client (EggUI, odds display) can require this safely.
--
-- The `Id` strings below MUST match docs/BRAINROT_ROSTER.md exactly - the CTF
-- ability system looks up abilities by these same ids.

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)

local EggConfig = {}

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Secret"

export type RarityWeights = { [string]: number }

export type EggId = "BasicEgg" | "GoldenEgg" | "SecretEgg"

export type CurrencyKey = "Coins" | "Gems"

export type EggDefinition = {
	Id: EggId,
	Name: string,
	Currency: CurrencyKey,
	Cost: number,
	-- Relative weights per rarity, matching docs/BRAINROT_ROSTER.md. Missing
	-- rarities are implicitly weight 0 (impossible from that egg).
	RarityWeights: RarityWeights,
}

-- Ordered rarity -> species pool, grouped from the canonical roster table.
local speciesByRarity: { [string]: { string } } = {
	Common = {
		"Spaghettoro",
		"CannoliniVolpe",
		"PolpoMotorino",
		"PinguinoMandolino",
		"BroccolinoTurbanti",
		"LucertolaFocaccina",
	},
	Rare = {
		"GirafferroEspressone",
		"RondineRavioli",
		"ScoiattoloCannoncino",
		"TartarugaVespaccia",
	},
	Epic = {
		"FenicotteroPizzaiolo",
		"PipistrelloMarinaro",
		"CannoloTrombonini",
	},
	Legendary = {
		"CrocobrividoVulcanico",
		"SqualezzaFerroviaria",
	},
	Secret = {
		"TralaleroAstrale",
	},
}
EggConfig.SpeciesByRarity = speciesByRarity

-- Display names, keyed by Id, for UI (hatch reveal cards, inventory grid).
local displayNames: { [string]: string } = {
	Spaghettoro = "Spaghettoro",
	CannoliniVolpe = "Cannolini Volpe",
	PolpoMotorino = "Polpo Motorino",
	PinguinoMandolino = "Pinguino Mandolino",
	BroccolinoTurbanti = "Broccolino Turbanti",
	LucertolaFocaccina = "Lucertola Focaccina",
	GirafferroEspressone = "Girafferro Espressone",
	RondineRavioli = "Rondine Ravioli",
	ScoiattoloCannoncino = "Scoiattolo Cannoncino",
	TartarugaVespaccia = "Tartaruga Vespaccia",
	FenicotteroPizzaiolo = "Fenicottero Pizzaiolo",
	PipistrelloMarinaro = "Pipistrello Marinaro",
	CannoloTrombonini = "Cannolo Trombonini",
	CrocobrividoVulcanico = "Crocobrivido Vulcanico",
	SqualezzaFerroviaria = "Squalezza Ferroviaria",
	TralaleroAstrale = "Tralalero Astrale",
}
EggConfig.DisplayNames = displayNames

-- Reverse index: species Id -> rarity. Built once so MergeBrainrots/Index/UI
-- code can look up "what rarity is this species" without re-scanning
-- speciesByRarity every call.
local rarityBySpecies: { [string]: string } = {}
for rarity, species in speciesByRarity do
	for _, id in species do
		rarityBySpecies[id] = rarity
	end
end
EggConfig.RarityBySpecies = rarityBySpecies

local eggs: { [string]: EggDefinition } = {
	BasicEgg = {
		Id = "BasicEgg",
		Name = "Basic Egg",
		Currency = Constants.CURRENCY.SOFT,
		Cost = 100,
		RarityWeights = {
			Common = 82,
			Rare = 15,
			Epic = 3,
		},
	},
	GoldenEgg = {
		Id = "GoldenEgg",
		Name = "Golden Egg",
		Currency = Constants.CURRENCY.SOFT,
		Cost = 1000,
		RarityWeights = {
			Common = 45,
			Rare = 35,
			Epic = 17,
			Legendary = 2.8,
			Secret = 0.2,
		},
	},
	SecretEgg = {
		Id = "SecretEgg",
		Name = "Secret Egg",
		Currency = Constants.CURRENCY.HARD,
		Cost = 75,
		RarityWeights = {
			Common = 10,
			Rare = 30,
			Epic = 35,
			Legendary = 20,
			Secret = 5,
		},
	},
}
EggConfig.Eggs = eggs

-- Ordered list of the 3 eggs for UI iteration (stable order regardless of
-- table iteration order).
local eggOrder: { string } = { "BasicEgg", "GoldenEgg", "SecretEgg" }
EggConfig.EggOrder = eggOrder

-- Valid hatch batch sizes the server will accept.
local hatchCounts: { number } = { 1, 3, 10 }
EggConfig.HatchCounts = hatchCounts

-- === Pity system =============================================================
--
-- Number of hatches (of that specific egg) since a player's last Epic-or-
-- better result, after which their *next* hatch from that egg is forced to
-- land Epic or better. Missing an entry means that egg has no pity floor.
--
-- This table is the only thing EggConfig owns for pity - the running counter
-- itself is NOT stored here (this module is pure data/functions, read by both
-- client and server) and is NOT persisted to the player profile. EggService
-- keeps it in a plain in-memory table keyed by Player. Tradeoff, documented
-- here so it isn't a mystery later: a player who rejoins loses their pity
-- progress for that egg and starts back at 0. That's an acceptable loss for a
-- soft-fairness mechanic (nobody is "owed" a pull), and it avoids adding a new
-- field to DataService.Profile for a number that's fine to occasionally reset.
local pityThreshold: { [string]: number } = {
	BasicEgg = 40,
	GoldenEgg = 25,
	SecretEgg = 12,
}
EggConfig.PityThreshold = pityThreshold

-- The tier pity forces a roll up to, inclusive.
EggConfig.PityFloorRarity = "Epic"

function EggConfig.GetEgg(eggId: string): EggDefinition?
	return eggs[eggId]
end

function EggConfig.RarityIndex(rarity: string): number?
	return table.find(Constants.RARITY_ORDER, rarity)
end

-- The next rarity tier up from `rarity`, or nil if it's already the top tier.
function EggConfig.NextRarity(rarity: string): string?
	local index = table.find(Constants.RARITY_ORDER, rarity)
	if not index then
		return nil
	end
	return Constants.RARITY_ORDER[index + 1]
end

-- Human-readable name for a species Id. Falls back to the raw id so a typo
-- never renders a blank label.
function EggConfig.DisplayName(brainrotId: string): string
	return displayNames[brainrotId] or brainrotId
end

-- Which rarity a species belongs to, or nil if the id is unknown.
function EggConfig.RarityOf(brainrotId: string): string?
	return rarityBySpecies[brainrotId]
end

-- Picks a single rarity from an egg's weight table using a weighted random
-- roll. `luckBoosted` re-rolls once and keeps whichever result lands on a
-- higher rarity tier (per Constants.RARITY_ORDER) - a simple, easy-to-reason
-- -about implementation of the DoubleLuck perk that never makes odds worse.
function EggConfig.RollRarity(eggId: string, luckBoosted: boolean, rng: Random?): string
	local egg = EggConfig.GetEgg(eggId)
	assert(egg, `EggConfig.RollRarity: unknown egg id "{eggId}"`)
	local nonNilEgg = egg :: EggDefinition

	local random = rng or Random.new()

	local function rollOnce(): string
		local total = 0
		for _, weight in nonNilEgg.RarityWeights do
			total += weight
		end

		local roll = random:NextNumber() * total
		local cumulative = 0
		for _, rarity in Constants.RARITY_ORDER do
			local weight = nonNilEgg.RarityWeights[rarity]
			if weight then
				cumulative += weight
				if roll <= cumulative then
					return rarity
				end
			end
		end

		-- Floating point safety net: fall back to the last defined rarity.
		for i = #Constants.RARITY_ORDER, 1, -1 do
			local rarity = Constants.RARITY_ORDER[i]
			if nonNilEgg.RarityWeights[rarity] then
				return rarity
			end
		end
		return "Common"
	end

	if not luckBoosted then
		return rollOnce()
	end

	local first = rollOnce()
	local second = rollOnce()

	local firstIndex = table.find(Constants.RARITY_ORDER, first) or 1
	local secondIndex = table.find(Constants.RARITY_ORDER, second) or 1

	return if secondIndex > firstIndex then second else first
end

-- Weighted roll restricted to rarities at or above `minRarity` (inclusive),
-- renormalized over just that slice of the egg's weight table so the pity
-- system still respects the *relative* odds between Epic/Legendary/Secret
-- instead of picking uniformly among them. If the egg has nothing at or above
-- minRarity (e.g. BasicEgg has no Legendary), falls back to the best rarity
-- the egg actually offers rather than erroring.
function EggConfig.RollRarityForced(eggId: string, minRarity: string, rng: Random?): string
	local egg = EggConfig.GetEgg(eggId)
	assert(egg, `EggConfig.RollRarityForced: unknown egg id "{eggId}"`)
	local nonNilEgg = egg :: EggDefinition

	local minIndex = table.find(Constants.RARITY_ORDER, minRarity) or 1
	local random = rng or Random.new()

	local total = 0
	for _, rarity in Constants.RARITY_ORDER do
		local index = table.find(Constants.RARITY_ORDER, rarity)
		local weight = nonNilEgg.RarityWeights[rarity]
		if index and index >= minIndex and weight then
			total += weight
		end
	end

	if total <= 0 then
		for i = #Constants.RARITY_ORDER, 1, -1 do
			local rarity = Constants.RARITY_ORDER[i]
			if nonNilEgg.RarityWeights[rarity] then
				return rarity
			end
		end
		return "Common"
	end

	local roll = random:NextNumber() * total
	local cumulative = 0
	for _, rarity in Constants.RARITY_ORDER do
		local index = table.find(Constants.RARITY_ORDER, rarity)
		local weight = nonNilEgg.RarityWeights[rarity]
		if index and index >= minIndex and weight then
			cumulative += weight
			if roll <= cumulative then
				return rarity
			end
		end
	end

	return Constants.RARITY_ORDER[minIndex] or "Common"
end

-- Picks a random species Id from the given rarity's pool.
function EggConfig.RollSpecies(rarity: string, rng: Random?): string
	local pool = speciesByRarity[rarity]
	assert(pool and #pool > 0, `EggConfig.RollSpecies: no species defined for rarity "{rarity}"`)
	local nonNilPool = pool :: { string }

	local random = rng or Random.new()
	local index = random:NextInteger(1, #nonNilPool)
	return nonNilPool[index]
end

-- Convenience: rolls both rarity and species for one hatch in a single call.
-- Does NOT apply pity - that's a per-player runtime counter EggService owns,
-- so pity-aware rolling composes EggConfig.RollRarityForced itself.
function EggConfig.RollOne(eggId: string, luckBoosted: boolean, rng: Random?): (string, string)
	local rarity = EggConfig.RollRarity(eggId, luckBoosted, rng)
	local species = EggConfig.RollSpecies(rarity, rng)
	return species, rarity
end

return EggConfig
