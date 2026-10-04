--!strict
-- Progression: a reason to come back.
--
--   * Marks, a saved currency earned in play (never bought): one per point,
--     plus bonuses for clean takedowns, rescues and rounds (Config.Marks).
--   * Upgrades bought with Marks (Config.Upgrades). Levels are published as
--     player attributes "Up_<Track>" (Upgrades.lua turns them into values):
--     the server uses them for blades (HunterService), each client for its
--     grapple. "Marks" is a player attribute too.
--   * Three daily challenges (Config.Challenges), the same for everyone, with
--     saved progress; finishing one pays out its Marks.
--   * Cosmetics without asset ids: cape colours (player attributes
--     "CapeColor" and "EmblemColor", read by HunterGear) and a title over the
--     head ("Veteran • Giant Slayer"), unlocked by rank, totals or
--     challenges.
--   * An end-of-round summary for each hunter (Config.Remotes.RoundSummary).
--   * XP for rounds and challenges (the rest of the XP, levels and their
--     Marks rewards are LevelService's; level-up Marks are paid here).
--
-- Hooks for the Robux shop (MonetizationService): the "MarksMult" player
-- attribute (Double Marks pass) multiplies Marks from play;
-- ProgressService.GrantMarks pays a bag of Marks, ProgressService.Reroll
-- swaps one daily challenge, ProgressService.Refresh re-checks the look
-- (titles unlocked by a pass).
--
-- Every shop request goes through Config.Remotes.Progress and is checked
-- here: data loaded, a known track, the level cap, the price, and a short
-- cooldown between requests. The client only ever asks.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local DataService = require(script.Parent.DataService)
local GiantService = require(script.Parent.GiantService)
local WaveService = require(script.Parent.WaveService)
local HunterService = require(script.Parent.HunterService)
local HunterGear = require(script.Parent.HunterGear)
local Broadcast = require(script.Parent.Broadcast)
local LevelService = require(script.Parent.LevelService)

local ProgressService = {}

type RoundStats = {
	Takedowns: number,
	CleanCuts: number,
	BestSpeed: number,
	Points: number,
	Marks: number,
}

type State = {
	Ready: boolean, -- the saved profile is loaded
	PendingMarks: number, -- earned while it was loading
	Round: RoundStats,
	NextAction: number, -- shop requests are ignored until then
}

local M = Config.Marks
local NAPE_RESULTS = { Hit = true, Defeated = true, Armor = true, ArmorBroken = true }

local states: { [Player]: State } = {}
local dirty: { [Player]: boolean } = {} -- snapshots to send at the next flush
local remote: RemoteEvent
local summaryRemote: RemoteEvent

local function freshRound(): RoundStats
	return { Takedowns = 0, CleanCuts = 0, BestSpeed = 0, Points = 0, Marks = 0 }
end

local function profileOf(player: Player): DataService.Profile?
	local state = states[player]
	if not state or not state.Ready then
		return nil
	end
	return DataService.Get(player)
end

-- === Daily challenges ========================================================

local function today(): number
	return os.time() // 86400 -- UTC days
end

local picks: { [number]: { Config.Challenge } } = {}

-- The day's challenges: picked from the pool by the date, so every server
-- (and every hunter) gets the same three.
local function challengesFor(day: number): { Config.Challenge }
	local cached = picks[day]
	if cached then
		return cached
	end
	local pool = Config.Challenges.Pool
	local order = {}
	for i = 1, #pool do
		order[i] = i
	end
	local rng = Random.new(day * 7919 + 31)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local chosen = {}
	for i = 1, math.min(Config.Challenges.PerDay, #order) do
		table.insert(chosen, pool[order[i]])
	end
	picks = { [day] = chosen } -- (only ever today's)
	return chosen
end

-- This hunter's challenges today: the day's, with any rerolls swapped in.
local function listFor(profile: DataService.Profile): { Config.Challenge }
	local day = challengesFor(profile.Challenges.Day)
	local swaps = profile.Challenges.Swaps
	if not swaps or next(swaps) == nil then
		return day
	end
	local list = {}
	for _, c in day do
		local swapped = swaps[c.Id]
		local found = c
		if swapped then
			for _, other in Config.Challenges.Pool do
				if other.Id == swapped then
					found = other
				end
			end
		end
		table.insert(list, found)
	end
	return list
end

-- A new day: a fresh set, from zero.
local function rollDay(player: Player, profile: DataService.Profile)
	local day = today()
	if profile.Challenges.Day ~= day then
		profile.Challenges = { Day = day, Progress = {}, Done = {} }
		DataService.Touch(player)
		dirty[player] = true
	end
end

-- === Marks ===================================================================

local function addMarks(player: Player, amount: number)
	local state = states[player]
	-- (The Double Marks pass: MonetizationService sets "MarksMult".)
	local mult = player:GetAttribute("MarksMult")
	amount = math.floor(amount * (if type(mult) == "number" then math.clamp(mult, 1, 3) else 1))
	if not state or amount <= 0 then
		return
	end
	state.Round.Marks += amount
	local profile = profileOf(player)
	if profile then
		profile.Marks += amount
		DataService.Touch(player)
		player:SetAttribute("Marks", profile.Marks)
		dirty[player] = true
	else
		state.PendingMarks += amount
	end
end

-- === Cosmetics ===============================================================

local function rankIndex(name: string): number
	for i, rank in Config.Ranks do
		if rank.Name == name then
			return i
		end
	end
	return 1
end

local function playerRank(player: Player): string
	local leaderstats = player:FindFirstChild("leaderstats")
	local rank = leaderstats and leaderstats:FindFirstChild("Rank")
	return if rank and rank:IsA("StringValue") then rank.Value else Config.Ranks[1].Name
end

local function unlocked(player: Player, profile: DataService.Profile, unlock: Config.Unlock?): boolean
	if not unlock then
		return true
	end
	if unlock.Pass and player:GetAttribute(`Pass_{unlock.Pass}`) ~= true then
		return false
	end
	if unlock.Rank and rankIndex(playerRank(player)) < rankIndex(unlock.Rank) then
		return false
	end
	if unlock.Stat then
		local value = (profile :: any)[unlock.Stat]
		if type(value) ~= "number" or value < (unlock.At or 0) then
			return false
		end
	end
	return true
end

local function findCape(id: string): Config.Cape?
	for _, cape in Config.Cosmetics.Capes do
		if cape.Id == id then
			return cape
		end
	end
	return nil
end

local function findTitle(id: string): Config.Title?
	for _, title in Config.Cosmetics.Titles do
		if title.Id == id then
			return title
		end
	end
	return nil
end

-- "Veteran • Giant Slayer" (or just the rank).
local function titleText(player: Player): string
	local rank = playerRank(player)
	local profile = profileOf(player)
	local title = profile and findTitle(profile.Title)
	if profile and title and unlocked(player, profile, title.Unlock) then
		return `{rank} • {title.Display}`
	end
	return rank
end

-- The small title over a hunter's head, seen from up to TitleDistance.
local function updateBillboard(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local board = head:FindFirstChild("HunterTitle")
	if not board then
		local gui = Instance.new("BillboardGui")
		gui.Name = "HunterTitle"
		gui.Size = UDim2.fromScale(7, 0.7) -- studs: stays small on screen
		gui.StudsOffset = Vector3.new(0, 2.3, 0)
		gui.MaxDistance = Config.Cosmetics.TitleDistance
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.Adornee = head
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.TextScaled = true
		text.Font = Enum.Font.GothamBold
		text.TextColor3 = Color3.fromRGB(240, 226, 180)
		text.TextStrokeTransparency = 0.4
		text.Parent = gui
		gui.Parent = head
		board = gui
	end
	local label = (board :: Instance):FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = titleText(player)
	end
end

-- The chosen cape (falling back to the corps' green if it's not unlocked)
-- onto the player's attributes and their current cape.
local function applyLook(player: Player)
	local profile = profileOf(player)
	if not profile then
		return
	end
	local cape = findCape(profile.Cape)
	if not cape or not unlocked(player, profile, cape.Unlock) then
		cape = findCape(Config.Cosmetics.DefaultCape)
	end
	if cape then
		player:SetAttribute("CapeColor", cape.Color)
		player:SetAttribute("EmblemColor", cape.Emblem)
	end
	local character = player.Character
	if character then
		HunterGear.RecolorCape(character)
	end
	updateBillboard(player)
end

-- === Snapshot for the shop ===================================================

local function snapshot(player: Player): { [string]: any }?
	local profile = profileOf(player)
	if not profile then
		return nil
	end
	rollDay(player, profile)
	local challenges = {}
	for _, c in listFor(profile) do
		table.insert(challenges, {
			Id = c.Id,
			Text = c.Text,
			Goal = c.Goal,
			Reward = c.Reward,
			Progress = profile.Challenges.Progress[c.Id] or 0,
			Done = profile.Challenges.Done[c.Id] == true,
		})
	end
	local capes, titles = {}, {}
	for _, cape in Config.Cosmetics.Capes do
		capes[cape.Id] = unlocked(player, profile, cape.Unlock)
	end
	for _, title in Config.Cosmetics.Titles do
		titles[title.Id] = unlocked(player, profile, title.Unlock)
	end
	local levels = {}
	for _, name in Config.Upgrades.Order do
		levels[name] = profile.Upgrades[name] or 0
	end
	return {
		Marks = profile.Marks,
		Upgrades = levels,
		Challenges = challenges,
		ResetIn = (today() + 1) * 86400 - os.time(),
		Capes = capes,
		Cape = profile.Cape,
		Titles = titles,
		Title = profile.Title,
		Stats = {
			Giants = profile.Giants,
			CleanCuts = profile.CleanCuts,
			Rescues = profile.Rescues,
			ChallengesDone = profile.ChallengesDone,
			BestRound = profile.BestRound,
		},
	}
end

local function send(player: Player)
	dirty[player] = nil
	local data = snapshot(player)
	if data and player.Parent then
		remote:FireClient(player, "State", data)
	end
end

-- === Challenge progress ======================================================

-- `amount` adds to the count, or (`atLeast`) raises it to at least that.
local function progress(player: Player, event: string, amount: number, filter: { Kind: string?, Reason: string? }?, atLeast: boolean?)
	local profile = profileOf(player)
	if not profile then
		return
	end
	rollDay(player, profile)
	local daily = profile.Challenges
	for _, c in listFor(profile) do
		local matches = c.Event == event
			and (c.Kind == nil or (filter ~= nil and filter.Kind == c.Kind))
			and (c.Reason == nil or (filter ~= nil and filter.Reason == c.Reason))
		if matches and not daily.Done[c.Id] then
			local current = daily.Progress[c.Id] or 0
			local new = math.min(if atLeast then math.max(current, amount) else current + amount, c.Goal)
			if new ~= current then
				daily.Progress[c.Id] = new
				DataService.Touch(player)
				dirty[player] = true
			end
			if new >= c.Goal then
				daily.Done[c.Id] = true
				profile.ChallengesDone += 1
				addMarks(player, c.Reward)
				local X = Config.Leveling.XP
				LevelService.Add(player, math.max(c.Reward * X.ChallengePerMark, X.ChallengeMin), "Challenge")
				remote:FireClient(player, "Challenge", c.Text, c.Reward)
				Broadcast.Feed(`{player.DisplayName} finished a daily challenge!`, "Good")
				applyLook(player) -- (may unlock a cape or a title)
			end
		end
	end
end

-- === The round summary =======================================================

local function sendSummary(player: Player, round: number, won: boolean)
	local state = states[player]
	if not state then
		return
	end
	local stats = state.Round
	local profile = profileOf(player)
	summaryRemote:FireClient(player, {
		Round = round,
		Won = won,
		Takedowns = stats.Takedowns,
		CleanCuts = stats.CleanCuts,
		BestSpeed = math.floor(stats.BestSpeed + 0.5),
		Points = stats.Points,
		Marks = stats.Marks,
		TotalMarks = if profile then profile.Marks else nil,
	})
end

local function endRound(round: number, won: boolean)
	for player, state in states do
		-- Only for hunters who took part (no Marks for standing about).
		if state.Round.Points > 0 then
			addMarks(player, if won then M.RoundWon + M.RoundWonPerRound * round else M.DistrictFallen)
			local X = Config.Leveling.XP
			LevelService.Add(player, if won then X.RoundWon + X.RoundWonPerRound * round else X.DistrictFallen, "Round")
			if won then
				progress(player, "RoundWon", 1)
			end
		end
		sendSummary(player, round, won)
	end
end

-- === Shop requests ===========================================================

local function result(player: Player, ok: boolean, message: string)
	remote:FireClient(player, "Result", ok, message)
end

local function buy(player: Player, profile: DataService.Profile, name: string)
	local track = Config.Upgrades.Tracks[name]
	if not track then
		return
	end
	local level = profile.Upgrades[name] or 0
	local cost = Upgrades.Cost(name, level)
	if not cost then
		result(player, false, `{track.Display} is already at its best!`)
		return
	end
	if profile.Marks < cost then
		result(player, false, `You need {cost - profile.Marks} more Marks`)
		return
	end
	profile.Marks -= cost
	profile.Upgrades[name] = level + 1
	DataService.Touch(player)
	player:SetAttribute("Marks", profile.Marks)
	player:SetAttribute(Upgrades.Attribute(name), level + 1)
	if name == "BladeCount" then
		HunterService.Refresh(player) -- (the new box size; filled at the next resupply)
	end
	result(player, true, `{track.Display} upgraded to level {level + 1}!`)
end

local function onRequest(player: Player, action: unknown, arg: unknown)
	local state = states[player]
	if not state then
		return
	end
	local now = os.clock()
	if now < state.NextAction then
		return
	end
	state.NextAction = now + Config.Upgrades.ActionCooldown
	local profile = profileOf(player)
	if not profile then
		if action ~= "Sync" then
			result(player, false, "Still loading your progress...")
		end
		return
	end
	if action == "Buy" and type(arg) == "string" then
		buy(player, profile, arg)
	elseif action == "Cape" and type(arg) == "string" then
		local cape = findCape(arg)
		if cape and unlocked(player, profile, cape.Unlock) then
			profile.Cape = cape.Id
			DataService.Touch(player)
			applyLook(player)
		end
	elseif action == "Title" and type(arg) == "string" then
		local title = findTitle(arg)
		if arg == "" or (title and unlocked(player, profile, title.Unlock)) then
			profile.Title = arg
			DataService.Touch(player)
			updateBillboard(player)
		end
	elseif action ~= "Sync" then
		return
	end
	send(player)
end

-- === Players =================================================================

-- Once the saved profile is in (HunterService loads it, then sets
-- "DataLoaded"): attributes, Marks earned meanwhile, the look.
local function onLoaded(player: Player)
	local state = states[player]
	local profile = DataService.Get(player)
	if not state or state.Ready or not profile then
		return
	end
	state.Ready = true
	-- Levels above a track's cap (a track made shorter) are trimmed.
	for name, level in profile.Upgrades do
		if Config.Upgrades.Tracks[name] then
			profile.Upgrades[name] = math.clamp(level, 0, Upgrades.MaxLevel(name))
		else
			profile.Upgrades[name] = nil
		end
	end
	for _, name in Config.Upgrades.Order do
		player:SetAttribute(Upgrades.Attribute(name), profile.Upgrades[name] or 0)
	end
	if state.PendingMarks > 0 then
		profile.Marks += state.PendingMarks
		state.PendingMarks = 0
		DataService.Touch(player)
	end
	player:SetAttribute("Marks", profile.Marks)
	rollDay(player, profile)
	applyLook(player)
	HunterService.Refresh(player)
	send(player)
end

local function onPlayerAdded(player: Player)
	states[player] = { Ready = false, PendingMarks = 0, Round = freshRound(), NextAction = 0 }
	player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if player:GetAttribute("DataLoaded") then
			onLoaded(player)
		end
	end)
	if player:GetAttribute("DataLoaded") then
		task.spawn(onLoaded, player)
	end
	player.CharacterAdded:Connect(function(character)
		local head = character:WaitForChild("Head", 10)
		if head and player.Character == character then
			updateBillboard(player)
		end
	end)
	-- A new rank can unlock a cape, and always changes the title line.
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 30)
		local rank = leaderstats and leaderstats:WaitForChild("Rank", 10)
		if rank and rank:IsA("StringValue") then
			rank.Changed:Connect(function()
				applyLook(player)
				dirty[player] = true
			end)
		end
	end)
end

-- === Robux shop hooks (MonetizationService) =================================

-- Pays Marks straight into the saved balance (no multiplier, not part of
-- the round's tally). False if the profile isn't loaded yet.
function ProgressService.GrantMarks(player: Player, amount: number): boolean
	local profile = profileOf(player)
	amount = math.floor(amount)
	if not profile or amount <= 0 then
		return false
	end
	profile.Marks += amount
	DataService.Touch(player)
	player:SetAttribute("Marks", profile.Marks)
	dirty[player] = true
	return true
end

-- Swaps one of today's challenges (`id`, else the first one not done, else
-- the first) for one from the pool that isn't on the list. False if the
-- profile isn't loaded or there's nothing to swap in.
function ProgressService.Reroll(player: Player, id: string?): boolean
	local profile = profileOf(player)
	if not profile then
		return false
	end
	rollDay(player, profile)
	local daily = profile.Challenges
	local day = challengesFor(daily.Day)
	local current = listFor(profile)
	local slot: number? = nil
	for i, c in current do
		if c.Id == id and not daily.Done[c.Id] then
			slot = i
		end
	end
	if not slot then
		for i, c in current do
			if not slot and not daily.Done[c.Id] then
				slot = i
			end
		end
	end
	local index = slot or 1
	if not day[index] then
		return false
	end
	local taken: { [string]: boolean } = {}
	for _, c in current do
		taken[c.Id] = true
	end
	for _, c in day do
		taken[c.Id] = true
	end
	local choices = {}
	for _, c in Config.Challenges.Pool do
		if not taken[c.Id] and not daily.Done[c.Id] then
			table.insert(choices, c)
		end
	end
	if #choices == 0 then
		return false
	end
	local pick = choices[math.random(1, #choices)]
	local swaps = daily.Swaps or {}
	daily.Swaps = swaps
	swaps[day[index].Id] = pick.Id
	daily.Progress[pick.Id] = nil
	DataService.Touch(player)
	remote:FireClient(player, "Result", true, `New challenge: {pick.Text}`)
	send(player)
	return true
end

-- Re-checks the cape and title (a pass bought or found on join).
function ProgressService.Refresh(player: Player)
	if profileOf(player) then
		applyLook(player)
		dirty[player] = true
	end
end

-- === Upgrade boards ==========================================================
-- A notice board (and a ProximityPrompt, key R like the other prompts)
-- where hunters open the upgrade shop: on the side of the headquarters, and
-- next to the spawn post on the wall. Each is kept well clear of the supply
-- crates so its prompt never competes with "Resupply" on the same key.

local function clearOfCrates(position: Vector3): boolean
	local clearance = Config.Upgrades.PromptDistance + 14
	for _, crate in CollectionService:GetTagged(Config.Tags.Supply) do
		if crate:IsA("BasePart") and (crate.Position - position).Magnitude < clearance then
			return false
		end
	end
	return true
end

-- `frame`: the board's centre, facing out (LookVector) toward the hunters.
local function board(parent: Instance, frame: CFrame)
	local model = Instance.new("Model")
	model.Name = "UpgradeBoard"
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Parent = model
		return p
	end
	local panel = part("Board", Vector3.new(5, 3.4, 0.3), frame, Color3.fromRGB(120, 86, 54), Enum.Material.WoodPlanks)
	part("Frame", Vector3.new(5.5, 3.9, 0.2), frame * CFrame.new(0, 0, 0.2), Color3.fromRGB(70, 48, 34), Enum.Material.Wood)
	for _, x in { -2.4, 2.4 } do
		part("Post", Vector3.new(0.35, 6, 0.35), frame * CFrame.new(x, -1.6, 0.3), Color3.fromRGB(70, 48, 34), Enum.Material.Wood)
	end
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0.6
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "UPGRADES\nspend your Marks"
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = Color3.fromRGB(245, 230, 190)
	text.Parent = surface
	surface.Parent = panel

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Upgrades"
	prompt.ObjectText = "Quartermaster"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Upgrades.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Config.Prompts.Key
	prompt.GamepadKeyCode = Config.Prompts.Gamepad
	prompt.Parent = panel
	prompt.Triggered:Connect(function(player)
		remote:FireClient(player, "Open")
		send(player)
	end)
	model.Parent = parent
end

-- Tries each spot in turn; the first clear one gets a board.
local function placeBoard(parent: Instance, frames: { CFrame }): boolean
	for _, frame in frames do
		if clearOfCrates(frame.Position) then
			board(parent, frame)
			return true
		end
	end
	return false
end

local function buildBoards(spawn: BasePart?)
	local map = Workspace:FindFirstChild("GiantHuntersMap")
	if not map then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "UpgradeBoards"
	folder.Parent = map
	-- The headquarters: on a side wall, at eye height.
	local hq = map:FindFirstChild("Headquarters", true)
	local body = hq and hq:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		local s = body.Size
		local low = -s.Y / 2 + 4.2
		placeBoard(folder, {
			body.CFrame * CFrame.new(s.X / 2 + 0.6, low, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			body.CFrame * CFrame.new(-s.X / 2 - 0.6, low, 0) * CFrame.Angles(0, math.pi / 2, 0),
			body.CFrame * CFrame.new(0, low, s.Z / 2 + 0.6) * CFrame.Angles(0, math.pi, 0),
		})
	else
		warn("[ProgressService] no headquarters found; the upgrade shop is on its button only there")
	end
	-- The spawn post on the wall, where everyone starts.
	if spawn then
		local s = spawn.Size
		local up = s.Y / 2 + 3.4
		placeBoard(folder, {
			spawn.CFrame * CFrame.new(s.X / 2 + 3, up, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			spawn.CFrame * CFrame.new(-s.X / 2 - 3, up, 0) * CFrame.Angles(0, math.pi / 2, 0),
			spawn.CFrame * CFrame.new(0, up, s.Z / 2 + 3) * CFrame.Angles(0, math.pi, 0),
			spawn.CFrame * CFrame.new(0, up, -s.Z / 2 - 3),
		})
	end
end

-- === Init ====================================================================

-- `spawn`: the hunters' post on the wall (a board goes next to it).
function ProgressService.Init(spawn: BasePart?)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remote = remotes:WaitForChild(Config.Remotes.Progress) :: RemoteEvent
	summaryRemote = remotes:WaitForChild(Config.Remotes.RoundSummary) :: RemoteEvent

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		dirty[player] = nil
	end)
	remote.OnServerEvent:Connect(onRequest)

	-- Points: Marks one for one, and the round's tally.
	HunterService.Awarded.Event:Connect(function(player: Player, points: number)
		local state = states[player]
		if state then
			state.Round.Points += points
		end
		addMarks(player, points * M.PerPoint)
	end)

	-- Level-ups pay Marks (LevelService).
	LevelService.LeveledUp.Event:Connect(function(player: Player, _level: number, marks: number)
		addMarks(player, marks)
	end)

	HunterService.Slashed.Event:Connect(function(player: Player, outcome: string, info: any)
		local state = states[player]
		if not state or type(info) ~= "table" then
			return
		end
		if outcome == "Training" then
			progress(player, "Dummy", 1)
		elseif NAPE_RESULTS[outcome] then
			if type(info.Speed) == "number" then
				state.Round.BestSpeed = math.max(state.Round.BestSpeed, info.Speed)
			end
			if info.Clean == true then
				state.Round.CleanCuts += 1
				local profile = profileOf(player)
				if profile then
					profile.CleanCuts += 1
					DataService.Touch(player)
				end
				progress(player, "CleanCut", 1)
			end
		end
	end)

	GiantService.Defeated.Event:Connect(function(player: Player, kindName: string, clean: boolean, speed: number)
		local state = states[player]
		if not state then
			return
		end
		state.Round.Takedowns += 1
		if clean then
			addMarks(player, M.CleanTakedown)
		end
		progress(player, "Takedown", 1, { Kind = kindName })
		if speed >= Config.Hunters.SpeedKill then
			progress(player, "FastTakedown", 1)
		end
	end)

	GiantService.Assist.Event:Connect(function(player: Player, reason: string)
		if reason == "Rescue" then
			addMarks(player, M.Rescue)
			local profile = profileOf(player)
			if profile then
				profile.Rescues += 1
				DataService.Touch(player)
			end
		end
		progress(player, "Assist", 1, { Reason = reason })
	end)

	WaveService.RoundStarted.Event:Connect(function()
		for _, state in states do
			state.Round = freshRound()
		end
	end)
	WaveService.WaveStarted.Event:Connect(function(_round: number, wave: number)
		for player in states do
			progress(player, "Wave", wave, nil, true)
		end
	end)
	WaveService.RoundEnded.Event:Connect(function(round: number)
		endRound(round, true)
	end)
	WaveService.DistrictFallen.Event:Connect(function(round: number)
		endRound(round, false)
	end)

	-- Snapshots go out at most twice a second (points come in bursts).
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player in dirty do
				task.spawn(send, player)
			end
		end
	end)

	task.spawn(buildBoards, spawn)
end

return ProgressService
