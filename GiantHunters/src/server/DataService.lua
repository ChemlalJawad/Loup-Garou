--!strict
-- Saving hunters between sessions: points (and so the rank), giants taken
-- down, the best round reached, and whether they've done the tutorial; and
-- the progression (ProgressService): Marks, upgrade levels, today's
-- challenges, lifetime totals, the chosen cape and title; and the level and
-- XP (LevelService).
--
-- Older saves simply lack the newer keys: every missing or bad key loads as
-- its default.
--
-- Everything is careful: every DataStore call is in a pcall and retried with
-- a growing pause, saves use UpdateAsync (they never blindly overwrite), the
-- whole server autosaves every minute and saves once more on shutdown. If
-- the DataStore can't be reached at all (a Studio place without API access,
-- say), the game runs on as normal and just doesn't save. If a hunter's data
-- couldn't be loaded, it's never saved over.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

export type Profile = {
	Points: number,
	Giants: number,
	BestRound: number,
	TutorialDone: boolean,
	-- Progression (ProgressService):
	Marks: number,
	Upgrades: { [string]: number }, -- track -> level
	Challenges: Challenges,
	ChallengesDone: number, -- lifetime
	CleanCuts: number, -- lifetime clean nape cuts
	Rescues: number, -- lifetime friends cut loose
	Cape: string, -- Config.Cosmetics.Capes id
	Title: string, -- Config.Cosmetics.Titles id, "" for none
	-- Levels (LevelService):
	Level: number, -- 1 to Config.Leveling.MaxLevel
	XP: number, -- progress within the level
}

-- Today's challenges: the UTC day they're for, progress and which are done.
export type Challenges = {
	Day: number,
	Progress: { [string]: number },
	Done: { [string]: boolean },
}

type Session = {
	Profile: Profile,
	Loaded: boolean, -- false: loading failed, so never save over the stored copy
	Dirty: boolean,
}

local store: DataStore? = nil
local sessions: { [Player]: Session } = {}

local function blank(): Profile
	return {
		Points = 0,
		Giants = 0,
		BestRound = 0,
		TutorialDone = false,
		Marks = 0,
		Upgrades = {},
		Challenges = { Day = 0, Progress = {}, Done = {} },
		ChallengesDone = 0,
		CleanCuts = 0,
		Rescues = 0,
		Cape = Config.Cosmetics.DefaultCape,
		Title = "",
		Level = 1,
		XP = 0,
	}
end

local function count(value: unknown): number?
	if type(value) == "number" and value == value and value >= 0 and value < math.huge then
		return math.floor(value)
	end
	return nil
end

-- A { [string]: number } (or boolean) table, keys and values checked.
local function cleanMap<T>(stored: unknown, check: (unknown) -> T?): { [string]: T }
	local out: { [string]: T } = {}
	if type(stored) == "table" then
		for key, value in stored :: { [unknown]: unknown } do
			local checked = check(value)
			if type(key) == "string" and #key <= 40 and checked ~= nil then
				out[key] = checked
			end
		end
	end
	return out
end

local function isTrue(value: unknown): boolean?
	return if value == true then true else nil
end

local function keyFor(player: Player): string
	return `Hunter_{player.UserId}`
end

-- Errors that no retry will fix: Studio without API access, an unpublished
-- place.
local function hopeless(err: unknown): boolean
	local text = tostring(err)
	return string.find(text, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(text, "publish", 1, true) ~= nil
		or string.find(text, "API Services", 1, true) ~= nil
end

-- Calls `fn` until it works, waiting 1, 2, 4... seconds between tries.
local function retry<T>(what: string, fn: () -> T): (boolean, T?)
	local delay = 1
	for attempt = 1, Config.Data.Retries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[DataService] {what} failed (try {attempt}): {result}`)
		if hopeless(result) then
			if store then
				store = nil
				warn("[DataService] no DataStore access here (Studio?); progress won't be saved this session")
			end
			return false, nil
		end
		if attempt < Config.Data.Retries then
			task.wait(delay)
			delay *= 2
		end
	end
	return false, nil
end

-- Anything stored is checked field by field: a bad value never breaks a join.
local function clean(stored: unknown): Profile
	local profile = blank()
	if type(stored) == "table" then
		local data = stored :: { [string]: unknown }
		for _, key in { "Points", "Giants", "BestRound", "Marks", "ChallengesDone", "CleanCuts", "Rescues", "XP" } do
			local value = count(data[key])
			if value then
				(profile :: any)[key] = value
			end
		end
		profile.TutorialDone = data.TutorialDone == true
		profile.Level = math.clamp(count(data.Level) or 1, 1, Config.Leveling.MaxLevel)
		profile.Upgrades = cleanMap(data.Upgrades, count)
		local challenges = data.Challenges
		if type(challenges) == "table" then
			local c = challenges :: { [string]: unknown }
			profile.Challenges = {
				Day = count(c.Day) or 0,
				Progress = cleanMap(c.Progress, count),
				Done = cleanMap(c.Done, isTrue),
			}
		end
		if type(data.Cape) == "string" then
			profile.Cape = data.Cape
		end
		if type(data.Title) == "string" then
			profile.Title = data.Title
		end
	end
	return profile
end

-- Loads (yields). Always returns a profile; a blank one if nothing could be
-- read.
function DataService.Load(player: Player): Profile
	local session: Session = { Profile = blank(), Loaded = store == nil, Dirty = false }
	sessions[player] = session
	local dataStore = store
	if dataStore then
		local ok, stored = retry(`load {player.Name}`, function()
			return dataStore:GetAsync(keyFor(player))
		end)
		if ok then
			session.Profile = clean(stored)
			session.Loaded = true
		else
			warn(`[DataService] {player.Name}'s data couldn't be loaded; this session won't be saved`)
		end
	end
	return session.Profile
end

function DataService.Get(player: Player): Profile?
	local session = sessions[player]
	return session and session.Profile
end

-- Changes one field (marks the profile for the next save).
function DataService.Set(player: Player, key: string, value: any)
	local session = sessions[player]
	if session then
		(session.Profile :: any)[key] = value
		session.Dirty = true
	end
end

-- Marks the profile for the next save after changing it in place (nested
-- tables: upgrades, challenges).
function DataService.Touch(player: Player)
	local session = sessions[player]
	if session then
		session.Dirty = true
	end
end

function DataService.Save(player: Player)
	local session = sessions[player]
	local dataStore = store
	if not session or not dataStore or not session.Loaded or not session.Dirty then
		return
	end
	session.Dirty = false
	-- (A deep enough copy: the nested tables can change while this yields.)
	local profile = table.clone(session.Profile)
	profile.Upgrades = table.clone(profile.Upgrades)
	profile.Challenges = {
		Day = profile.Challenges.Day,
		Progress = table.clone(profile.Challenges.Progress),
		Done = table.clone(profile.Challenges.Done),
	}
	local ok = retry(`save {player.Name}`, function()
		return dataStore:UpdateAsync(keyFor(player), function(stored: unknown)
			-- Keep the best of both for the things that only ever go up.
			local old = clean(stored)
			profile.BestRound = math.max(profile.BestRound, old.BestRound)
			profile.TutorialDone = profile.TutorialDone or old.TutorialDone
			if old.Level > profile.Level then -- (a level is never lost)
				profile.Level, profile.XP = old.Level, old.XP
			end
			return profile
		end)
	end)
	if not ok then
		session.Dirty = true -- try again at the next autosave
	end
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.Store)
	end)
	if ok then
		store = result
	else
		warn(`[DataService] no DataStore ({result}); progress won't be saved this session`)
	end

	Players.PlayerRemoving:Connect(function(player)
		DataService.Save(player)
		sessions[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveEvery)
			for player in sessions do
				task.spawn(DataService.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				DataService.Save(player)
				pending -= 1
			end)
		end
		local waited = 0
		while pending > 0 and waited < 25 do
			waited += task.wait(0.2)
		end
	end)
end

return DataService
