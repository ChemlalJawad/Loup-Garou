--!strict
-- Discovering the land's named places, and what the big map needs to know.
--
--   * Named places are BaseParts tagged Config.Tags.POI by the map builders,
--     with the attributes PoiId (unique), PoiName and PoiKind ("Town" |
--     "Wilds"). Tagged later or removed: the list follows.
--   * Every Config.Discovery.CheckEvery seconds the server looks at where
--     each hunter really is (their HumanoidRootPart, and only while Motion
--     trusts them): within Radius of a place not found yet, it's
--     DISCOVERED (a banner, XP and Marks). Not before the hunter's save has
--     loaded, nor during their tutorial.
--   * Saved in the profile's "Discovered" ({ [PoiId] = true }). Every place
--     found: a bonus and the profile's "Pathfinder" = 1, which unlocks the
--     Pathfinder title (Config.Cosmetics.Titles).
--   * Config.Remotes.Explore: the client asks ("Sync"); the server sends
--     ("State", { Pois, Found, Journals, JournalCount, Map }): the places
--     (Id, Name, Kind, X, Z), the ones this hunter found, their Lost
--     Journal pages (JournalService), and the roads and regions from
--     World/Layout for drawing the map (the client can't see the server's
--     Layout).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Motion = require(script.Parent.Motion)
local LevelService = require(script.Parent.LevelService)
local ProgressService = require(script.Parent.ProgressService)
local Broadcast = require(script.Parent.Broadcast)

local DiscoveryService = {}

export type Poi = { Id: string, Name: string, Kind: string, Part: BasePart }

local D = Config.Discovery

local pois: { [string]: Poi } = {}
local poiCount = 0
local remote: RemoteEvent
local mapData: { [string]: any } = { Roads = {}, Regions = {} }
local nextSync: { [Player]: number } = {}

local function register(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local id = instance:GetAttribute("PoiId")
	if type(id) ~= "string" or id == "" or #id > 40 then
		warn(`[DiscoveryService] a {Config.Tags.POI} part without a good PoiId: {instance:GetFullName()}`)
		return
	end
	if pois[id] and pois[id].Part ~= instance then
		warn(`[DiscoveryService] PoiId "{id}" is used twice; keeping the first`)
		return
	end
	local name = instance:GetAttribute("PoiName")
	local kind = instance:GetAttribute("PoiKind")
	if not pois[id] then
		poiCount += 1
	end
	pois[id] = {
		Id = id,
		Name = if type(name) == "string" and name ~= "" then name else id,
		Kind = if kind == "Town" then "Town" else "Wilds",
		Part = instance,
	}
end

local function unregister(instance: Instance)
	for id, poi in pois do
		if poi.Part == instance then
			pois[id] = nil
			poiCount -= 1
		end
	end
end

-- "GreatForest" -> "Great Forest".
local function spaced(name: string): string
	return (string.gsub(name, "(%l)(%u)", "%1 %2"))
end

-- The roads and regions of the land, from World/Layout (read defensively:
-- the map builders own it). Roads are flat polylines { x1, z1, x2, z2... }.
local function buildMapData(): { [string]: any }
	local data = { Roads = {} :: { { number } }, Regions = {} :: { { [string]: any } } }
	local ok, layout = pcall(function(): any
		return require(script.Parent.World.Layout)
	end)
	if not ok or type(layout) ~= "table" then
		return data
	end
	local function addLine(points: { Vector3 })
		local flat = {}
		for _, p in points do
			table.insert(flat, math.round(p.X))
			table.insert(flat, math.round(p.Z))
		end
		if #flat >= 4 then
			table.insert(data.Roads, flat)
		end
	end
	if type(layout.Roads) == "table" then
		for _, road in layout.Roads do
			if type(road) == "table" and typeof(road[1]) == "Vector3" then
				addLine(road)
			end
		end
	end
	-- The road south from the gate.
	if type(layout.RoadX) == "function" then
		local W = Config.World
		local points = {}
		for z = W.WallRadius + W.WallThickness, W.LandRadius - 80, 60 do
			local okX, x = pcall(layout.RoadX, z)
			if okX and type(x) == "number" then
				table.insert(points, Vector3.new(x, 0, z))
			end
		end
		addLine(points)
	end
	-- Regions: any polar sector the layout names (Angle, Spread, Inner, Outer).
	for key, value in layout do
		if type(key) == "string" and type(value) == "table" then
			local v = value :: { [string]: any }
			if type(v.Angle) == "number" and type(v.Spread) == "number" and type(v.Inner) == "number" and type(v.Outer) == "number" then
				table.insert(data.Regions, { Name = spaced(key), Angle = v.Angle, Spread = v.Spread, Inner = v.Inner, Outer = v.Outer })
			end
		end
	end
	table.sort(data.Regions, function(a, b)
		return a.Name < b.Name
	end)
	return data
end

local function ready(player: Player): DataService.Profile?
	if player:GetAttribute("DataLoaded") ~= true then
		return nil
	end
	return DataService.Get(player)
end

-- The named places, for the map (and other services).
function DiscoveryService.Pois(): { [string]: Poi }
	return pois
end

function DiscoveryService.Count(): number
	return poiCount
end

-- Sends a hunter the map's state (after a discovery or a journal page).
function DiscoveryService.Send(player: Player)
	local profile = ready(player)
	if not profile or not player.Parent then
		return
	end
	local list = {}
	local found = {}
	for id, poi in pois do
		local p = poi.Part.Position
		table.insert(list, { Id = id, Name = poi.Name, Kind = poi.Kind, X = math.round(p.X), Z = math.round(p.Z) })
		if profile.Discovered[id] then
			found[id] = true
		end
	end
	remote:FireClient(player, "State", {
		Pois = list,
		Found = found,
		Journals = table.clone(profile.Journals),
		JournalCount = #Config.Journals.Pages,
		Map = mapData,
	})
end

-- Every place found? (Only counts places that exist on this map.)
local function checkAll(player: Player, profile: DataService.Profile)
	if poiCount == 0 or profile.Pathfinder >= 1 then
		return
	end
	for id in pois do
		if not profile.Discovered[id] then
			return
		end
	end
	profile.Pathfinder = 1
	DataService.Touch(player)
	LevelService.Add(player, D.AllXP, "Pathfinder")
	ProgressService.GrantMarks(player, D.AllMarks)
	ProgressService.Refresh(player)
	Broadcast.Announce("PATHFINDER!", `Every place found: +{D.AllMarks} Marks and the Pathfinder title`, "Gold", player)
	Broadcast.Feed(`{player.DisplayName} has found every place in the land!`, "Gold")
end

local function discover(player: Player, profile: DataService.Profile, poi: Poi)
	profile.Discovered[poi.Id] = true
	DataService.Touch(player)
	LevelService.Add(player, D.XP, "Discovery")
	ProgressService.GrantMarks(player, D.Marks)
	local found = 0
	for id in pois do
		if profile.Discovered[id] then
			found += 1
		end
	end
	Broadcast.Announce(`DISCOVERED: {string.upper(poi.Name)}`, `+{D.Marks} Marks  -  {found}/{poiCount} places found (M for the map)`, "Gold", player)
	checkAll(player, profile)
	DiscoveryService.Send(player)
end

local function step()
	local radiusSq = D.Radius * D.Radius
	for _, player in Players:GetPlayers() do
		local profile = ready(player)
		if not profile or player:GetAttribute("TutorialDone") ~= true or not Motion.Trusted(player) then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end
		local p = root.Position
		for id, poi in pois do
			if not profile.Discovered[id] then
				local a = poi.Part.Position
				local dx, dz = p.X - a.X, p.Z - a.Z
				if dx * dx + dz * dz <= radiusSq and math.abs(p.Y - a.Y) <= D.Rise then
					discover(player, profile, poi)
				end
			end
		end
	end
end

function DiscoveryService.Init()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Explore) :: RemoteEvent
	mapData = buildMapData()

	for _, part in CollectionService:GetTagged(Config.Tags.POI) do
		register(part)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.POI):Connect(register)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.POI):Connect(unregister)

	remote.OnServerEvent:Connect(function(player: Player, action: unknown)
		local now = os.clock()
		if action ~= "Sync" or now < (nextSync[player] or 0) then
			return
		end
		nextSync[player] = now + 1
		DiscoveryService.Send(player)
	end)

	local function onPlayer(player: Player)
		player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
			DiscoveryService.Send(player)
			-- (A place added since this hunter found all the others: no
			-- title lost; a new title only when everything is found.)
			local profile = ready(player)
			if profile then
				checkAll(player, profile)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		nextSync[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(D.CheckEvery)
			step()
		end
	end)
end

return DiscoveryService
