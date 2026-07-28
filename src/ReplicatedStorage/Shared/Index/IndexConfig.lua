--!strict
-- Pure data + pure helpers for the Collection Index. The canonical 16
-- Brainrots (sourced from docs/BRAINROT_ROSTER.md) and the milestone reward
-- ladder that turns "I got a duplicate" into "I need 3 more for Epic tier."
--
-- This module has zero side effects: no remotes, no DataService, no
-- randomness. IndexService (server) and IndexController (client) both read
-- it so they can never disagree about what's discovered or what a milestone
-- requires - there is exactly one place that logic lives.

local Constants = require(script.Parent.Parent.Constants)

local IndexConfig = {}

export type IndexEntry = {
	Id: string,
	Name: string,
	Rarity: string,
}

-- profile.Index shape: brainrotId -> total ever hatched. 0/absent = undiscovered.
export type IndexTable = { [string]: number }

export type RewardBundle = {
	Coins: number?,
	Gems: number?,
	XP: number?,
}

export type MilestoneKind = "RarityComplete" | "DiscoveryCount" | "FullCollection"

export type Milestone = {
	Id: string,
	Label: string,
	Description: string,
	Kind: MilestoneKind,
	Rarity: string?, -- required when Kind == "RarityComplete"
	Count: number?, -- required when Kind == "DiscoveryCount" or "FullCollection"
	Reward: RewardBundle,
	-- Capstone-only perk: grants EconomyService.BOOST_LUCK_2X for a very long
	-- duration instead of inventing a new perk name. See IndexService for the
	-- grant call and a note on why this shape was chosen.
	PermanentLuckBoost: boolean?,
}

-- === The 16 canonical Brainrots ============================================
-- Order matches docs/BRAINROT_ROSTER.md (rarity-grouped, roster order within
-- each rarity). Do not add/remove/rename entries here without updating the
-- roster doc first - Egg/CTF systems read the same ids.

local entries: { IndexEntry } = {
	-- Common (6)
	{ Id = "Spaghettoro", Name = "Spaghettoro", Rarity = "Common" },
	{ Id = "CannoliniVolpe", Name = "Cannolini Volpe", Rarity = "Common" },
	{ Id = "PolpoMotorino", Name = "Polpo Motorino", Rarity = "Common" },
	{ Id = "PinguinoMandolino", Name = "Pinguino Mandolino", Rarity = "Common" },
	{ Id = "BroccolinoTurbanti", Name = "Broccolino Turbanti", Rarity = "Common" },
	{ Id = "LucertolaFocaccina", Name = "Lucertola Focaccina", Rarity = "Common" },
	-- Rare (4)
	{ Id = "GirafferroEspressone", Name = "Girafferro Espressone", Rarity = "Rare" },
	{ Id = "RondineRavioli", Name = "Rondine Ravioli", Rarity = "Rare" },
	{ Id = "ScoiattoloCannoncino", Name = "Scoiattolo Cannoncino", Rarity = "Rare" },
	{ Id = "TartarugaVespaccia", Name = "Tartaruga Vespaccia", Rarity = "Rare" },
	-- Epic (3)
	{ Id = "FenicotteroPizzaiolo", Name = "Fenicottero Pizzaiolo", Rarity = "Epic" },
	{ Id = "PipistrelloMarinaro", Name = "Pipistrello Marinaro", Rarity = "Epic" },
	{ Id = "CannoloTrombonini", Name = "Cannolo Trombonini", Rarity = "Epic" },
	-- Legendary (2)
	{ Id = "CrocobrividoVulcanico", Name = "Crocobrivido Vulcanico", Rarity = "Legendary" },
	{ Id = "SqualezzaFerroviaria", Name = "Squalezza Ferroviaria", Rarity = "Legendary" },
	-- Secret (1)
	{ Id = "TralaleroAstrale", Name = "Tralalero Astrale", Rarity = "Secret" },
}
IndexConfig.Entries = entries

local entriesById: { [string]: IndexEntry } = {}
for _, entry in entries do
	entriesById[entry.Id] = entry
end

local entriesByRarity: { [string]: { IndexEntry } } = {}
for _, rarity in Constants.RARITY_ORDER do
	entriesByRarity[rarity] = {}
end
for _, entry in entries do
	local bucket = entriesByRarity[entry.Rarity]
	if bucket then
		table.insert(bucket, entry)
	end
end

function IndexConfig.AllEntries(): { IndexEntry }
	return entries
end

function IndexConfig.GetEntry(id: string): IndexEntry?
	return entriesById[id]
end

function IndexConfig.EntriesByRarity(rarity: string): { IndexEntry }
	return entriesByRarity[rarity] or {}
end

function IndexConfig.TotalCount(): number
	return #entries
end

function IndexConfig.RarityTotalCount(rarity: string): number
	return #(entriesByRarity[rarity] or {})
end

-- True when `indexTable[id]` shows at least one ever hatched.
function IndexConfig.IsDiscovered(indexTable: IndexTable, id: string): boolean
	local count = indexTable[id]
	return count ~= nil and count > 0
end

-- Counts only the canonical 16 ids, so stray/legacy keys in profile.Index
-- (e.g. a removed test id) never inflate the total.
function IndexConfig.DiscoveredCount(indexTable: IndexTable): number
	local count = 0
	for _, entry in entries do
		if IndexConfig.IsDiscovered(indexTable, entry.Id) then
			count += 1
		end
	end
	return count
end

function IndexConfig.DiscoveredCountForRarity(indexTable: IndexTable, rarity: string): number
	local count = 0
	for _, entry in entriesByRarity[rarity] or {} do
		if IndexConfig.IsDiscovered(indexTable, entry.Id) then
			count += 1
		end
	end
	return count
end

-- === Milestones ==============================================================
-- Per-rarity completion rewards scale steeply by tier, overall discovery
-- counts reward earlier partial progress, and the 16/16 capstone pays out big
-- plus a permanent Luck boost (granted by IndexService via the existing
-- EconomyService.BOOST_LUCK_2X boost name with a ~100 year duration - see
-- IndexService for the grant call).

local milestones: { Milestone } = {
	-- Per-rarity completion.
	{
		Id = "RarityComplete_Common",
		Label = "Common Collector",
		Description = "Discover all 6 Common Brainrots.",
		Kind = "RarityComplete",
		Rarity = "Common",
		Reward = { Coins = 5000, XP = 500 },
	},
	{
		Id = "RarityComplete_Rare",
		Label = "Rare Collector",
		Description = "Discover all 4 Rare Brainrots.",
		Kind = "RarityComplete",
		Rarity = "Rare",
		Reward = { Coins = 15000, Gems = 20, XP = 1200 },
	},
	{
		Id = "RarityComplete_Epic",
		Label = "Epic Collector",
		Description = "Discover all 3 Epic Brainrots.",
		Kind = "RarityComplete",
		Rarity = "Epic",
		Reward = { Coins = 50000, Gems = 60, XP = 3000 },
	},
	{
		Id = "RarityComplete_Legendary",
		Label = "Legendary Collector",
		Description = "Discover both Legendary Brainrots.",
		Kind = "RarityComplete",
		Rarity = "Legendary",
		Reward = { Coins = 150000, Gems = 150, XP = 8000 },
	},
	{
		Id = "RarityComplete_Secret",
		Label = "Secret Collector",
		Description = "Discover the Secret Brainrot.",
		Kind = "RarityComplete",
		Rarity = "Secret",
		Reward = { Coins = 300000, Gems = 300, XP = 15000 },
	},

	-- Overall discovery counts.
	{
		Id = "Discover_4",
		Label = "Getting Started",
		Description = "Discover 4 different Brainrots.",
		Kind = "DiscoveryCount",
		Count = 4,
		Reward = { Coins = 2000, XP = 300 },
	},
	{
		Id = "Discover_8",
		Label = "Halfway Hoarder",
		Description = "Discover 8 different Brainrots.",
		Kind = "DiscoveryCount",
		Count = 8,
		Reward = { Coins = 8000, Gems = 15, XP = 1000 },
	},
	{
		Id = "Discover_12",
		Label = "Almost There",
		Description = "Discover 12 different Brainrots.",
		Kind = "DiscoveryCount",
		Count = 12,
		Reward = { Coins = 25000, Gems = 40, XP = 2500 },
	},

	-- Capstone: the full 16/16 collection.
	{
		Id = "FullCollection",
		Label = "Index Complete",
		Description = "Discover all 16 Brainrots.",
		Kind = "FullCollection",
		Count = 16,
		Reward = { Coins = 500000, Gems = 500, XP = 20000 },
		PermanentLuckBoost = true,
	},
}
IndexConfig.Milestones = milestones

local milestonesById: { [string]: Milestone } = {}
for _, milestone in milestones do
	milestonesById[milestone.Id] = milestone
end

function IndexConfig.AllMilestones(): { Milestone }
	return milestones
end

function IndexConfig.GetMilestone(milestoneId: string): Milestone?
	return milestonesById[milestoneId]
end

-- Pure server/client-agreed check: is `milestoneId` satisfied by `indexTable`
-- right now? Does not consider whether it was already claimed - that's
-- profile.IndexMilestonesClaimed, which the caller checks separately.
function IndexConfig.EvaluateMilestone(milestoneId: string, indexTable: IndexTable): boolean
	local milestone = milestonesById[milestoneId]
	if not milestone then
		return false
	end

	if milestone.Kind == "RarityComplete" then
		local rarity = milestone.Rarity :: string
		return IndexConfig.DiscoveredCountForRarity(indexTable, rarity) >= IndexConfig.RarityTotalCount(rarity)
	elseif milestone.Kind == "DiscoveryCount" or milestone.Kind == "FullCollection" then
		local needed = milestone.Count :: number
		return IndexConfig.DiscoveredCount(indexTable) >= needed
	end

	return false
end

-- Progress pair (current, target) for UI meters - same semantics as
-- EvaluateMilestone but returned as numbers instead of a boolean.
function IndexConfig.MilestoneProgress(milestoneId: string, indexTable: IndexTable): (number, number)
	local milestone = milestonesById[milestoneId]
	if not milestone then
		return 0, 0
	end

	if milestone.Kind == "RarityComplete" then
		local rarity = milestone.Rarity :: string
		return IndexConfig.DiscoveredCountForRarity(indexTable, rarity), IndexConfig.RarityTotalCount(rarity)
	elseif milestone.Kind == "DiscoveryCount" or milestone.Kind == "FullCollection" then
		return IndexConfig.DiscoveredCount(indexTable), milestone.Count :: number
	end

	return 0, 0
end

return IndexConfig
