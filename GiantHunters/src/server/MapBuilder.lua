--!strict
-- Builds the whole district from code, in four layers:
--
--   World/Ground  Smooth Terrain: town paving, grass, fields, river, hills
--   World/Wall    the Great Wall ring, the breachable south gate, towers,
--                 cannons, and the hunters' post (spawn) on the north wall
--   World/Town    row houses, plaza, church, headquarters, market, bridges
--   World/Wilds   giant forest, farms and windmill, the road, the plains
--
-- Returns where giants enter and the spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(script.Parent.World.Ground)
local Wall = require(script.Parent.World.Wall)
local Town = require(script.Parent.World.Town)
local Wilds = require(script.Parent.World.Wilds)

local MapBuilder = {}

export type World = {
	GiantSpawns: { Vector3 },
	Spawn: SpawnLocation,
}

function MapBuilder.Build(): World
	local existing = Workspace:FindFirstChild("GiantHuntersMap")
	if existing then
		existing:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "GiantHuntersMap"
	map.Parent = Workspace

	local rng = Random.new(1845)
	local ok, err = pcall(Ground.Build :: any, rng)
	if not ok then
		-- Never leave the world without a floor.
		warn(`[MapBuilder] terrain failed, using a flat part instead: {err}`)
		local plate = Instance.new("Part")
		plate.Name = "FallbackGround"
		plate.Anchored = true
		plate.Size = Vector3.new(Config.World.LandRadius * 2 + 200, 2, Config.World.LandRadius * 2 + 200)
		plate.Position = Vector3.new(0, -1, 0)
		plate.Color = Color3.fromRGB(98, 156, 70)
		plate.Material = Enum.Material.Grass
		plate.Parent = map
	end
	local spawn = Wall.Build(map)
	Town.Build(map, rng)
	Wilds.Build(map, rng)
	return { GiantSpawns = Wilds.GiantSpawns(), Spawn = spawn }
end

return MapBuilder
