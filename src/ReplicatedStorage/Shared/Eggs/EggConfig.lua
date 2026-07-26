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

function EggConfig.GetEgg(eggId: string): EggDefinition?
	return eggs[eggId]
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
function EggConfig.RollOne(eggId: string, luckBoosted: boolean, rng: Random?): (string, string)
	local rarity = EggConfig.RollRarity(eggId, luckBoosted, rng)
	local species = EggConfig.RollSpecies(rarity, rng)
	return species, rarity
end

return EggConfig
