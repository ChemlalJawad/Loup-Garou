--!strict
-- Landscaping for the open ground *between* zones: trees, bushes, flower
-- beds, rocks, balloons and giant mushrooms scattered over the grass, plus a
-- few treasure chests hidden out in the wilds.
--
-- Not a WorldLayout zone - it owns no rectangle. It fills the space no zone
-- owns, staying clear of every zone rect (plus a margin) and every path
-- (PathRegistry, filled in by MapBuilder before any zone builds). Named
-- "...Zone" only so MapBuilder's auto-discovery picks it up; Order puts it
-- after every real zone.
--
-- Deterministic: a fixed seed means every server (and every Studio test)
-- gets the same park, so players can learn it and tell each other where
-- things are ("the chest by the big mushrooms").
--
-- Part budget: ~190 props x ~2.7 parts = ~510 parts. The TiledFloor rework
-- in WorldKit saved ~400 floor parts, so the map gains all of this for
-- roughly the part count it had before.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local WorldKit = require(script.Parent.WorldKit)
local PathRegistry = require(script.Parent.PathRegistry)

local LandscapeZone = {}
LandscapeZone.Order = 200

local SEED = 20260929
local PROP_COUNT = 190
local MAX_ATTEMPTS = PROP_COUNT * 25
local MIN_SPACING = 9 -- studs between props, so it reads as a park, not a pile
local ZONE_MARGIN = 7
local PATH_MARGIN = 4
local EDGE_MARGIN = 6

type Kind = "RoundTree" | "PineTree" | "CandyTree" | "Bush" | "FlowerBed" | "Rock" | "Balloons" | "Mushroom"

local KIND_WEIGHTS: { { Kind: Kind, Weight: number } } = {
	{ Kind = "RoundTree", Weight = 24 },
	{ Kind = "PineTree", Weight = 12 },
	{ Kind = "CandyTree", Weight = 12 },
	{ Kind = "Bush", Weight = 18 },
	{ Kind = "FlowerBed", Weight = 14 },
	{ Kind = "Rock", Weight = 9 },
	{ Kind = "Balloons", Weight = 5 },
	{ Kind = "Mushroom", Weight = 6 },
}

-- Treasure out in the wilds, far from any sign. Positions were picked to sit
-- on open grass; each is still checked at build time and skipped (with a
-- warning) if a future layout change ever puts it inside a zone or on a path.
local HIDDEN_CHESTS = {
	{ Id = "WildsNorthWest", Position = Vector3.new(-290, 0, 420), Label = "Forgotten Chest", Coins = 220 },
	{ Id = "WildsSouthEast", Position = Vector3.new(295, 0, -318), Label = "Lost Explorer's Chest", Coins = 220 },
	{ Id = "WildsWest", Position = Vector3.new(-250, 0, 250), Label = "Mushroom Grove Chest", Coins = 180 },
}

local function insideAnyZone(position: Vector3, margin: number): boolean
	for _, zone in WorldLayout.Zones :: { [string]: WorldLayout.ZoneRect } do
		if
			math.abs(position.X - zone.Center.X) <= zone.Size.X / 2 + margin
			and math.abs(position.Z - zone.Center.Z) <= zone.Size.Z / 2 + margin
		then
			return true
		end
	end
	return false
end

local function isFree(position: Vector3): boolean
	return not insideAnyZone(position, ZONE_MARGIN) and not PathRegistry.IsNearPath(position, PATH_MARGIN)
end

local function pickKind(rng: Random): Kind
	local total = 0
	for _, entry in KIND_WEIGHTS do
		total += entry.Weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in KIND_WEIGHTS do
		roll -= entry.Weight
		if roll < 0 then
			return entry.Kind
		end
	end
	return "Bush"
end

local function buildProp(kind: Kind, position: Vector3, rng: Random, parent: Instance)
	if kind == "RoundTree" then
		WorldKit.Tree({ Position = position, Height = rng:NextNumber(10, 16), Style = "Round", Parent = parent })
	elseif kind == "PineTree" then
		WorldKit.Tree({ Position = position, Height = rng:NextNumber(12, 18), Style = "Pine", Parent = parent })
	elseif kind == "CandyTree" then
		WorldKit.Tree({ Position = position, Height = rng:NextNumber(9, 13), Style = "Candy", Parent = parent })
	elseif kind == "Bush" then
		WorldKit.Bush({ Position = position, Size = rng:NextNumber(3, 5), Parent = parent })
	elseif kind == "FlowerBed" then
		WorldKit.FlowerBed({ Position = position, Parent = parent })
	elseif kind == "Rock" then
		WorldKit.Rock({ Position = position, Size = rng:NextNumber(2, 4.5), Yaw = rng:NextNumber(0, math.pi), Parent = parent })
	elseif kind == "Balloons" then
		WorldKit.BalloonCluster({ Position = position, Parent = parent })
	elseif kind == "Mushroom" then
		WorldKit.Mushroom({ Position = position, Height = rng:NextNumber(4, 8), Parent = parent })
	end
end

function LandscapeZone.Build(parent: Instance)
	local folder = WorldKit.Group("Landscape", parent)
	local rng = Random.new(SEED)
	local plate = WorldLayout.GroundPlate
	local halfX = plate.Size.X / 2 - EDGE_MARGIN
	local halfZ = plate.Size.Z / 2 - EDGE_MARGIN
	local groundY = WorldLayout.GroundY

	-- Chest spots are reserved first so no tree or rock lands on a chest.
	local placed: { Vector3 } = {}
	for _, chest in HIDDEN_CHESTS do
		table.insert(placed, chest.Position)
	end

	local propCount = 0
	local attempts = 0
	while propCount < PROP_COUNT and attempts < MAX_ATTEMPTS do
		attempts += 1
		local position = Vector3.new(
			plate.Center.X + rng:NextNumber(-halfX, halfX),
			groundY,
			plate.Center.Z + rng:NextNumber(-halfZ, halfZ)
		)
		if isFree(position) then
			local tooClose = false
			for _, other in placed do
				if (other - position).Magnitude < MIN_SPACING then
					tooClose = true
					break
				end
			end
			if not tooClose then
				table.insert(placed, position)
				propCount += 1
				-- Each prop gets its own folder so the Explorer stays readable.
				local propFolder = WorldKit.Group(`Prop{propCount}`, folder)
				buildProp(pickKind(rng), position, rng, propFolder)
			end
		end
	end

	for _, chest in HIDDEN_CHESTS do
		if isFree(chest.Position) then
			WorldKit.RewardChest({
				ChestId = chest.Id,
				Label = chest.Label,
				RewardCoins = chest.Coins,
				RewardXP = 50,
				CooldownSeconds = 15 * 60,
				Position = chest.Position,
				Parent = folder,
			})
		else
			warn(`[LandscapeZone] hidden chest "{chest.Id}" is inside a zone or on a path - skipped`)
		end
	end
end

return LandscapeZone
