--!strict
-- Global cross-server leaderboards, backed by one OrderedDataStore per key in
-- Constants.LEADERBOARD_KEYS. Two independent cadences:
--
--   READS  every Constants.LEADERBOARD_REFRESH_SECONDS: GetSortedAsync the
--          top Constants.LEADERBOARD_SIZE for each key, resolve display
--          names, cache in memory, broadcast to every client.
--   WRITES on PlayerRemoving, on BindToClose, and on a slow periodic timer
--          (PUBLISH_INTERVAL_SECONDS). Deliberately NOT on every
--          DataService.ProfileChanged: Coins mutates dozens of times a
--          minute for an idle-income game, and OrderedDataStore SetAsync has
--          a per-key write budget (roughly 60 + 10*playerCount calls per
--          minute). Publishing on every profile change would blow through
--          that budget almost immediately with more than a handful of
--          players; a slow periodic sweep plus "flush on leave" keeps
--          published values fresh enough for a leaderboard (which is
--          inherently an eventually-consistent, minutes-old view) without
--          risking throttled/dropped writes.
--
-- Physical boards: LeaderboardStand1..4 (named parts, built by the Plaza
-- zone) get a SurfaceGui each, one leaderboard key per stand. Those parts are
-- owned and placed by a different system entirely, so they are found by name
-- via a recursive search and may legitimately never appear - the service
-- must keep working (UI panel, GetCached) either way.
--
-- Studio has no DataStore access by default: every DataStore call is
-- pcall'd, GetOrderedDataStore failures degrade to "boards stay empty",
-- never to an error that stops the server from booting.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.Theme)
local DataService = require(ServerScriptService.Server.Services.DataService)

export type LeaderboardEntry = {
	Rank: number,
	UserId: number,
	Name: string,
	Value: number,
}

export type BoardCache = {
	Entries: { LeaderboardEntry },
	UpdatedAt: number,
}

export type OwnEntry = {
	Value: number,
	Rank: number?,
}

export type LeaderboardPayload = {
	Boards: { [string]: BoardCache },
	Own: { [string]: OwnEntry },
}

local LeaderboardService = {}

-- === Tuning ==================================================================

local READ_INTERVAL_SECONDS = Constants.LEADERBOARD_REFRESH_SECONDS
-- Deliberately much slower than reads; see file header for the write-budget
-- reasoning. 180s keeps total writes/min well under the OrderedDataStore
-- budget even at a few dozen concurrent players, since we also stagger
-- individual SetAsync calls below.
local PUBLISH_INTERVAL_SECONDS = 180
local MAX_RETRIES = 3
local RETRY_BASE_DELAY = 1.5
local WRITE_STAGGER_SECONDS = 0.15 -- spread per-player-per-key writes out
local BOARD_DISPLAY_COUNT = 10 -- physical stands show fewer rows than the UI
local STAND_FIND_ATTEMPTS = 8
local STAND_FIND_WAIT_SECONDS = 2

local STORE_NAME_PREFIX = "Leaderboard_v1_"

-- === State ===================================================================

local orderedStores: { [string]: OrderedDataStore } = {}
local storeAvailable = true

local cache: { [string]: BoardCache } = {}
for _, key in Constants.LEADERBOARD_KEYS do
	cache[key] = { Entries = {}, UpdatedAt = 0 }
end

local nameCache: { [number]: string } = {}

local updatedEvent: RemoteEvent

-- key -> stand part index (1-based) -> { Part, Rows: {Frame}, ValueLabels }
local standDisplays: { { Key: string, Container: Frame, Rows: { { Rank: TextLabel, Name: TextLabel, Value: TextLabel } } } } = {}

-- === Helpers ==================================================================

local function valueForKey(profile: DataService.Profile, key: string): number
	if key == "Coins" then
		return profile.Coins
	elseif key == "FlagCaptures" then
		return profile.Stats.FlagCaptures
	elseif key == "EggsHatched" then
		return profile.Stats.EggsHatched
	elseif key == "Level" then
		return profile.Level
	end
	return 0
end

-- GetNameFromUserIdAsync yields, can throw, and is rate-limited. Resolve once
-- per userId ever (successes cached indefinitely), retry a few times on
-- failure, and always fall back to a readable placeholder rather than letting
-- one bad lookup break an entire leaderboard refresh.
local function resolveName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end

	local inGame = Players:GetPlayerByUserId(userId)
	if inGame then
		nameCache[userId] = inGame.Name
		return inGame.Name
	end

	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if ok and type(result) == "string" and #result > 0 then
			nameCache[userId] = result
			return result
		end
		task.wait(RETRY_BASE_DELAY * attempt)
	end

	return "Player " .. tostring(userId)
end

-- === Reading (GetSortedAsync) =================================================

local function fetchTop(store: OrderedDataStore): { { UserId: number, Value: number } }?
	for attempt = 1, MAX_RETRIES do
		local ok, pagesOrErr = pcall(function()
			return store:GetSortedAsync(false, Constants.LEADERBOARD_SIZE)
		end)
		if ok then
			local okPage, page = pcall(function()
				return (pagesOrErr :: DataStorePages):GetCurrentPage()
			end)
			if okPage then
				local list = {}
				for _, entry in page :: { any } do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(list, { UserId = userId, Value = entry.value })
					end
				end
				return list
			end
			warn("[LeaderboardService] GetCurrentPage failed:", page)
		else
			warn(string.format("[LeaderboardService] GetSortedAsync attempt %d/%d failed: %s", attempt, MAX_RETRIES, tostring(pagesOrErr)))
		end
		task.wait(RETRY_BASE_DELAY * attempt)
	end
	return nil
end

local function refreshStandsForKey(key: string)
	local boardCache = cache[key]
	if not boardCache then
		return
	end
	for _, display in standDisplays do
		if display.Key == key then
			for index, row in display.Rows do
				local entry = boardCache.Entries[index]
				if entry then
					row.Rank.Text = `#{entry.Rank}`
					row.Name.Text = entry.Name
					row.Value.Text = tostring(math.floor(entry.Value))
					row.Rank.Visible = true
					row.Name.Visible = true
					row.Value.Visible = true
				else
					row.Rank.Visible = false
					row.Name.Visible = false
					row.Value.Visible = false
				end
			end
		end
	end
end

local function ownEntryFor(player: Player, key: string): OwnEntry
	local profile = DataService.Get(player)
	local value = if profile then valueForKey(profile, key) else 0

	local rank: number? = nil
	local boardCache = cache[key]
	if boardCache then
		for _, entry in boardCache.Entries do
			if entry.UserId == player.UserId then
				rank = entry.Rank
				break
			end
		end
	end

	return { Value = value, Rank = rank }
end

local function payloadForPlayer(player: Player): LeaderboardPayload
	local own: { [string]: OwnEntry } = {}
	for _, key in Constants.LEADERBOARD_KEYS do
		own[key] = ownEntryFor(player, key)
	end
	return { Boards = cache, Own = own }
end

local function broadcastToAll()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(function()
			updatedEvent:FireClient(player, payloadForPlayer(player))
		end)
		if not ok then
			warn("[LeaderboardService] failed to push update to", player.Name, ":", err)
		end
	end
end

local function refreshKey(key: string)
	local store = orderedStores[key]
	if not store then
		return
	end

	local raw = fetchTop(store)
	if not raw then
		-- Degrade gracefully: keep whatever we cached last (possibly empty on
		-- the very first refresh) rather than clobbering it with nothing.
		return
	end

	local entries: { LeaderboardEntry } = {}
	for rank, item in raw do
		table.insert(entries, {
			Rank = rank,
			UserId = item.UserId,
			Name = resolveName(item.UserId),
			Value = item.Value,
		})
	end

	cache[key] = { Entries = entries, UpdatedAt = os.time() }
	refreshStandsForKey(key)
end

local function refreshAll()
	if not storeAvailable then
		return
	end
	for _, key in Constants.LEADERBOARD_KEYS do
		refreshKey(key)
	end
	broadcastToAll()
end

-- === Writing (SetAsync) ======================================================

local function publishPlayerKey(player: Player, key: string, value: number)
	local store = orderedStores[key]
	if not store then
		return
	end
	local userKey = tostring(player.UserId)
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			store:SetAsync(userKey, value)
		end)
		if ok then
			return
		end
		warn(string.format("[LeaderboardService] publish %s for %s attempt %d/%d failed: %s", key, player.Name, attempt, MAX_RETRIES, tostring(err)))
		task.wait(RETRY_BASE_DELAY * attempt)
	end
end

local function publishPlayer(player: Player)
	if not storeAvailable then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	for _, key in Constants.LEADERBOARD_KEYS do
		publishPlayerKey(player, key, valueForKey(profile, key))
	end
end

local function publishAllOnline()
	if not storeAvailable then
		return
	end
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile then
			for _, key in Constants.LEADERBOARD_KEYS do
				publishPlayerKey(player, key, valueForKey(profile, key))
				task.wait(WRITE_STAGGER_SECONDS)
			end
		end
	end
end

-- === Physical boards ==========================================================

local function buildStandGui(part: BasePart, key: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 42
	gui.LightInfluence = 0
	gui.Parent = part

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.BackgroundColor3 = Theme.Color.Background
	background.BorderSizePixel = 0
	background.Size = UDim2.fromScale(1, 1)
	background.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundColor3 = Theme.Color.Surface
	title.BorderSizePixel = 0
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Text = string.upper(key)
	title.TextColor3 = Theme.Color.AccentPrimary
	title.Font = Theme.Font.Heading
	title.TextScaled = true
	title.Parent = background

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.new(0, 0, 0, 60)
	list.Size = UDim2.new(1, 0, 1, -60)
	list.Parent = background

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local rows = {}
	for i = 1, BOARD_DISPLAY_COUNT do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundTransparency = if i % 2 == 0 then 1 else 0.85
		row.BackgroundColor3 = Theme.Color.Surface
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 44)
		row.LayoutOrder = i
		row.Parent = list

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Name = "Rank"
		rankLabel.BackgroundTransparency = 1
		rankLabel.Position = UDim2.new(0, 10, 0, 0)
		rankLabel.Size = UDim2.new(0, 60, 1, 0)
		rankLabel.Text = ""
		rankLabel.TextColor3 = Theme.Color.AccentWarning
		rankLabel.Font = Theme.Font.SubHeading
		rankLabel.TextScaled = true
		rankLabel.TextXAlignment = Enum.TextXAlignment.Left
		rankLabel.Visible = false
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, 80, 0, 0)
		nameLabel.Size = UDim2.new(1, -220, 1, 0)
		nameLabel.Text = ""
		nameLabel.TextColor3 = Theme.Color.TextPrimary
		nameLabel.Font = Theme.Font.Body
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Visible = false
		nameLabel.Parent = row

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "Value"
		valueLabel.BackgroundTransparency = 1
		valueLabel.AnchorPoint = Vector2.new(1, 0)
		valueLabel.Position = UDim2.new(1, -10, 0, 0)
		valueLabel.Size = UDim2.new(0, 130, 1, 0)
		valueLabel.Text = ""
		valueLabel.TextColor3 = Theme.Color.AccentPrimary
		valueLabel.Font = Theme.Font.Mono
		valueLabel.TextScaled = true
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.Visible = false
		valueLabel.Parent = row

		table.insert(rows, { Rank = rankLabel, Name = nameLabel, Value = valueLabel })
	end

	table.insert(standDisplays, { Key = key, Container = list, Rows = rows })
end

-- Stands are built by a different (world-design) system and may not exist
-- yet - or ever, if that zone fails to build. Retry a few times, then warn
-- and move on; the leaderboard UI panel works completely independently of
-- these physical boards.
local function attachStands()
	for attempt = 1, STAND_FIND_ATTEMPTS do
		local foundAny = false
		for index, key in Constants.LEADERBOARD_KEYS do
			local standName = "LeaderboardStand" .. tostring(index)
			local alreadyBuilt = false
			for _, display in standDisplays do
				if display.Key == key then
					alreadyBuilt = true
					break
				end
			end
			if not alreadyBuilt then
				local part = Workspace:FindFirstChild(standName, true)
				if part and part:IsA("BasePart") then
					local ok, err = pcall(buildStandGui, part, key)
					if ok then
						foundAny = true
						refreshStandsForKey(key)
					else
						warn(`[LeaderboardService] failed to build SurfaceGui for {standName}: {err}`)
					end
				end
			end
		end

		if #standDisplays >= #Constants.LEADERBOARD_KEYS then
			return
		end

		task.wait(STAND_FIND_WAIT_SECONDS)
	end

	if #standDisplays == 0 then
		warn("[LeaderboardService] no LeaderboardStand parts found after retrying - physical boards skipped, UI panel still works")
	elseif #standDisplays < #Constants.LEADERBOARD_KEYS then
		warn(`[LeaderboardService] only found {#standDisplays}/{#Constants.LEADERBOARD_KEYS} LeaderboardStand parts - remaining boards skipped`)
	end
end

-- === Public API ===============================================================

function LeaderboardService.GetCached(key: string): BoardCache?
	return cache[key]
end

function LeaderboardService.Init()
	updatedEvent = Net.GetEvent(Constants.REMOTE_NAMES.Leaderboard.Updated)

	for _, key in Constants.LEADERBOARD_KEYS do
		local ok, storeOrErr = pcall(function()
			return DataStoreService:GetOrderedDataStore(STORE_NAME_PREFIX .. key)
		end)
		if ok then
			orderedStores[key] = storeOrErr
		else
			storeAvailable = false
			warn(`[LeaderboardService] OrderedDataStore unavailable for {key}, boards will stay cached/empty: {storeOrErr}`)
		end
	end

	task.spawn(attachStands)

	-- Push whatever we already have to a player as soon as their profile is
	-- ready, so joining mid-cycle doesn't mean waiting up to a full refresh
	-- interval to see anything (own value in particular should be instant).
	DataService.ProfileLoaded.Event:Connect(function(player: Player)
		task.defer(function()
			if player.Parent then
				local ok, err = pcall(function()
					updatedEvent:FireClient(player, payloadForPlayer(player))
				end)
				if not ok then
					warn("[LeaderboardService] initial push failed for", player.Name, ":", err)
				end
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		publishPlayer(player)
	end)

	game:BindToClose(function()
		if not storeAvailable then
			return
		end
		publishAllOnline()
	end)

	-- Reads: refresh + broadcast on a steady cadence.
	task.spawn(function()
		while true do
			task.wait(READ_INTERVAL_SECONDS)
			refreshAll()
		end
	end)

	-- Writes: slow periodic sweep of everyone currently online. See file
	-- header for why this isn't tied to ProfileChanged.
	task.spawn(function()
		while true do
			task.wait(PUBLISH_INTERVAL_SECONDS)
			publishAllOnline()
		end
	end)
end

return LeaderboardService
