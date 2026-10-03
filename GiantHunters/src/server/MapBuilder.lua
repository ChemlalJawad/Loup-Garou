--!strict
-- Builds the whole district from code, in layers:
--
--   World/Ground  Smooth Terrain: town paving, grass, fields, river, hills
--   World/Wall    the Great Wall ring, the breachable south gate, towers,
--                 cannons, and the hunters' post (spawn) on the north wall
--   World/Town    row houses, plaza, church, headquarters, market, bridges
--   World/Wilds   giant forest, farms and windmill, the road, the plains,
--                 and the invisible edge of the world
--
-- Everything is built into a folder outside the Workspace and parented in
-- one go at the end (much cheaper than ten thousand separate insertions).
-- Each layer is protected: one that fails is reported and the server goes
-- on without it. Big models stream to clients as whole units.
--
-- Returns where giants enter and the spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local Ground = require(script.Parent.World.Ground)
local Wall = require(script.Parent.World.Wall)
local Town = require(script.Parent.World.Town)
local Wilds = require(script.Parent.World.Wilds)

local MapBuilder = {}

export type World = {
	GiantSpawns: { Vector3 },
	Spawn: SpawnLocation,
}

-- Models that stream in and out whole, so a client never sees a tree
-- without its crown or half a house.
local ATOMIC = {
	GiantTree = true,
	Tree = true,
	Fir = true,
	SignalTower = true,
	TreePlatform = true,
	TrainingDummy = true,
	House = true,
	Warehouse = true,
	Church = true,
	Headquarters = true,
	Market = true,
	Cottage = true,
	Barn = true,
	Windmill = true,
	OldCastle = true,
	Bridge = true,
}

-- Runs one layer; a failure is reported and the build carries on.
local function layer(name: string, build: () -> ()): boolean
	local started = os.clock()
	local ok, err = pcall(build :: any)
	local ms = math.floor((os.clock() - started) * 1000)
	if ok then
		print(`[MapBuilder] {name}: {ms} ms`)
	else
		warn(`[MapBuilder] {name} failed after {ms} ms: {err}`)
	end
	return ok
end

-- If the wall didn't build, hunters still need somewhere to stand.
local function fallbackSpawn(map: Instance): SpawnLocation
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HunterSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 10)
	spawn.CFrame = CFrame.new(Geo.Polar(Config.World.GateAngle + math.pi, Config.World.WallRadius - 40, 0.5))
	spawn.Neutral = true
	spawn.Duration = 3
	spawn.Parent = map
	return spawn
end

function MapBuilder.Build(): World
	local started = os.clock()
	local existing = Workspace:FindFirstChild("GiantHuntersMap")
	if existing then
		existing:Destroy()
	end
	-- The template place's own floor and spawn would get in the way.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local stray = Workspace:FindFirstChild(name)
		if stray then
			stray:Destroy()
		end
	end
	local map = Instance.new("Folder")
	map.Name = "GiantHuntersMap"

	local rng = Random.new(1845)
	local grounded = layer("ground", function()
		Ground.Build(rng)
	end)
	if not grounded then
		-- Never leave the world without a floor.
		local plate = Instance.new("Part")
		plate.Name = "FallbackGround"
		plate.Anchored = true
		plate.Size = Vector3.new(Config.World.LandRadius * 2 + 200, 2, Config.World.LandRadius * 2 + 200)
		plate.Position = Vector3.new(0, -1, 0)
		plate.Color = Color3.fromRGB(98, 156, 70)
		plate.Material = Enum.Material.Grass
		plate.Parent = map
	end
	local spawn: SpawnLocation? = nil
	layer("wall", function()
		spawn = Wall.Build(map)
	end)
	layer("town", function()
		Town.Build(map, rng)
	end)
	layer("wilds", function()
		Wilds.Build(map, rng)
	end)
	layer("edge", function()
		Wilds.BuildBoundary(map)
	end)
	local hunterSpawn = spawn or fallbackSpawn(map)

	local parts = 0
	for _, item in map:GetDescendants() do
		if item:IsA("Model") and ATOMIC[item.Name] then
			item.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		elseif item:IsA("BasePart") then
			parts += 1
		end
	end
	local placed = os.clock()
	map.Parent = Workspace
	print(`[MapBuilder] parented {parts} parts in {math.floor((os.clock() - placed) * 1000)} ms; whole map {math.floor((os.clock() - started) * 1000)} ms`)

	local spawns = {}
	pcall(function()
		spawns = Wilds.GiantSpawns()
	end)
	if #spawns == 0 then
		spawns = { Geo.Polar(Config.World.GateAngle, Config.World.GiantSpawnRadius) }
	end
	return { GiantSpawns = spawns, Spawn = hunterSpawn }
end

return MapBuilder
