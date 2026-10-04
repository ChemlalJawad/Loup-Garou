--!strict
-- A self-check that runs once when you press Play in Studio (never in a
-- live server). It looks over what was built and configured and prints a
-- PASS / WARN / FAIL list to the Output window, so the things that can only
-- be seen in Studio are quick to confirm:
--
--   * the map: spawn, wall, supply crates, dummies, cannons, boundary;
--   * the remotes, the DataStore access (saving), streaming;
--   * the shop: catalog and titan-form ids unique, prices and levels sane;
--   * every giant kind and titan form builds (Nape, Head, joints).

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GiantFactory = require(script.Parent.GiantFactory)

local StudioCheck = {}

type Line = { Level: string, Text: string }

function StudioCheck.Run(world: { Spawn: BasePart?, GiantSpawns: { Vector3 } })
	if not RunService:IsStudio() then
		return
	end
	local lines: { Line } = {}
	local function report(level: string, text: string)
		table.insert(lines, { Level = level, Text = text })
	end
	local function check(ok: boolean, text: string, failLevel: string?)
		report(if ok then "PASS" else failLevel or "FAIL", text)
	end

	-- The map.
	check(world.Spawn ~= nil and world.Spawn.Parent ~= nil, "hunter spawn on the wall")
	check(Workspace:FindFirstChild("Baseplate") == nil, "no stray Baseplate")
	check(#world.GiantSpawns > 0, `giant spawn points: {#world.GiantSpawns}`)
	local crates = #CollectionService:GetTagged(Config.Tags.Supply)
	check(crates >= 20, `supply crates: {crates}`, "WARN")
	check(#CollectionService:GetTagged(Config.Tags.DummyNape) > 0, `training dummies: {#CollectionService:GetTagged(Config.Tags.DummyNape)}`)
	check(#CollectionService:GetTagged(Config.Tags.Cannon) > 0, `wall cannons: {#CollectionService:GetTagged(Config.Tags.Cannon)}`)
	check(#CollectionService:GetTagged(Config.Tags.MapBoundary) > 0, "map boundary built")
	local parts = 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	check(parts < 16000, `parts in Workspace: {parts}`, "WARN")
	check(Workspace.StreamingEnabled, "StreamingEnabled is on", "WARN")

	-- Remotes.
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local missing = {}
	for _, name in Config.Remotes do
		if not (folder and folder:FindFirstChild(name :: string)) then
			table.insert(missing, name :: string)
		end
	end
	check(#missing == 0, if #missing == 0 then "all remotes created" else `missing remotes: {table.concat(missing, ", ")}`)

	-- Saving: needs "Enable Studio Access to API Services" in Game Settings.
	local ok, err = pcall(function()
		DataStoreService:GetDataStore("GH_StudioCheck"):GetAsync("probe")
	end)
	check(ok, if ok then "DataStore reachable: progress will be saved" else `DataStore not reachable (Game Settings > Security > API Services): {err}`, "WARN")

	-- The shop: ids unique across gear, techniques and titan forms.
	local seen: { [string]: string } = {}
	local catalog = (Config :: any).Catalog or {}
	local forms = (Config :: any).TitanForms or {}
	local maxLevel = Config.Leveling.MaxLevel
	for _, pair in { { "Catalog", catalog }, { "TitanForms", forms } } do
		local groupName: string, group: any = pair[1], pair[2]
		for id: string, item: any in group :: { [string]: any } do
			if seen[id] then
				report("FAIL", `shop id "{id}" is in both {seen[id]} and {groupName}`)
			end
			seen[id] = groupName
			if type(item.Price) ~= "number" or item.Price < 0 then
				report("FAIL", `{groupName}.{id}: bad Price`)
			end
			if type(item.LevelRequired) ~= "number" or item.LevelRequired < 1 or item.LevelRequired > maxLevel then
				report("FAIL", `{groupName}.{id}: LevelRequired out of 1..{maxLevel}`)
			end
		end
	end
	local count = 0
	for _ in seen do
		count += 1
	end
	report("INFO", `shop items: {count}`)

	-- Every giant kind and titan form builds, far away, then is removed.
	local rng = Random.new(1)
	local function tryBuild(label: string, kindName: string, form: any?)
		local built, rig = pcall(GiantFactory.Build, kindName, Vector3.new(0, -2000, 0), rng, form)
		if not built then
			report("FAIL", `{label}: {rig}`)
			return
		end
		local r = rig :: GiantFactory.Rig
		local parts = 0
		for _, d in r.Model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		local joints = r.Model:FindFirstChild("Waist", true) ~= nil and r.Model:FindFirstChild("Neck", true) ~= nil
		check((r :: any).Nape ~= nil and (r :: any).Head ~= nil and joints, `{label}: builds ({parts} parts)`)
		r.Model:Destroy()
	end
	for kindName in Config.GiantKinds do
		tryBuild(`giant {kindName}`, kindName)
	end
	for id, form in forms :: { [string]: any } do
		tryBuild(`titan form {id}`, "Shifter", form)
	end

	local failed, warned = 0, 0
	print(`[{Config.GAME_NAME}] Studio self-check:`)
	for _, line in lines do
		if line.Level == "FAIL" then
			failed += 1
		elseif line.Level == "WARN" then
			warned += 1
		end
		local text = `  {line.Level}  {line.Text}`
		if line.Level == "FAIL" then
			warn(text)
		else
			print(text)
		end
	end
	print(`[{Config.GAME_NAME}] self-check done: {failed} failed, {warned} warnings`)
end

return StudioCheck
