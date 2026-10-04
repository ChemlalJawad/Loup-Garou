--!strict
-- The season pass (Config.Season): season XP and its tiers.
--
--   * Season XP is a share (Config.Season.XPShare) of every XP gain
--     (LevelService.Gained, boosts included, and still at the top level).
--     Nothing more is earned once the season has ended (EndsUtc).
--   * Each tier has an optional Free and Premium reward: Marks, or a style
--     (Config.CosmeticItems id with Source = "Season"). Rewards are claimed
--     with a button, once each; Premium ones need the SeasonPremium game
--     pass (the "Pass_SeasonPremium" attribute, MonetizationService).
--   * Saved in the profile's "Season" ({ Id, XP, ClaimedFree,
--     ClaimedPremium }), which starts over when Config.Season.Id changes.
--
-- Client: Config.Remotes.Season ("Sync") | ("Claim", "Free" | "Premium",
-- tier); everything is checked here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local LevelService = require(script.Parent.LevelService)
local ProgressService = require(script.Parent.ProgressService)
local ShopService = require(script.Parent.ShopService)

local SeasonService = {}

local S = Config.Season

type State = { Ready: boolean, Pending: number, Fraction: number, NextAction: number }

local remote: RemoteEvent
local states: { [Player]: State } = {}
local dirty: { [Player]: boolean } = {}

local function seasonOf(player: Player): DataService.Season?
	local state = states[player]
	local profile = if state and state.Ready then DataService.Get(player) else nil
	if not profile then
		return nil
	end
	if type(profile.Season) ~= "table" or profile.Season.Id ~= S.Id then
		profile.Season = { Id = S.Id, XP = 0, ClaimedFree = {}, ClaimedPremium = {} }
		DataService.Touch(player)
	end
	return profile.Season
end

local function ended(): boolean
	return S.EndsUtc ~= nil and os.time() >= S.EndsUtc
end

local function premium(player: Player): boolean
	return player:GetAttribute("Pass_SeasonPremium") == true
end

-- The highest tier reached (0 for none).
local function tierFor(xp: number): number
	local reached = 0
	for i, tier in S.Tiers do
		if xp >= tier.XP then
			reached = i
		end
	end
	return reached
end

local function send(player: Player)
	dirty[player] = nil
	local season = seasonOf(player)
	if not season or not player.Parent then
		return
	end
	remote:FireClient(player, "State", {
		Id = S.Id,
		Name = S.Name,
		XP = season.XP,
		Tier = tierFor(season.XP),
		ClaimedFree = table.clone(season.ClaimedFree),
		ClaimedPremium = table.clone(season.ClaimedPremium),
		Premium = premium(player),
		EndsIn = if S.EndsUtc then math.max(S.EndsUtc - os.time(), 0) else nil,
	})
end

local function result(player: Player, ok: boolean, message: string)
	remote:FireClient(player, "Result", ok, message)
end

local function addXP(player: Player, amount: number)
	local state = states[player]
	if not state or amount <= 0 or ended() then
		return
	end
	local share = amount * S.XPShare + state.Fraction
	local whole = math.floor(share)
	state.Fraction = share - whole
	if whole <= 0 then
		return
	end
	local season = seasonOf(player)
	if season then
		season.XP += whole
		DataService.Touch(player)
		dirty[player] = true
	else
		state.Pending += whole
	end
end

local function styleExists(id: string): boolean
	local items = (Config :: any).CosmeticItems
	return type(items) == "table" and type(items[id]) == "table"
end

local function claim(player: Player, season: DataService.Season, track: string, tier: number)
	local spec = S.Tiers[tier]
	if not spec then
		return
	end
	local reward = if track == "Premium" then spec.Premium else spec.Free
	local claimed = if track == "Premium" then season.ClaimedPremium else season.ClaimedFree
	local key = tostring(tier)
	if not reward or claimed[key] then
		return
	end
	if season.XP < spec.XP then
		result(player, false, `Reach tier {tier} first`)
		return
	end
	if track == "Premium" and not premium(player) then
		result(player, false, "Premium rewards come with the Season Premium pass")
		return
	end
	if reward.Cosmetic then
		if not styleExists(reward.Cosmetic) then
			result(player, false, "This style is coming soon!")
			return
		end
		if not ShopService.GrantStyle(player, reward.Cosmetic) then
			return
		end
		claimed[key] = true
		result(player, true, "New style unlocked! Wear it in the STYLE tab.")
	elseif reward.Marks then
		if not ProgressService.GrantMarks(player, reward.Marks) then
			return
		end
		claimed[key] = true
		result(player, true, `+{reward.Marks} Marks!`)
	end
	DataService.Touch(player)
end

local function onRequest(player: Player, action: unknown, track: unknown, tier: unknown)
	local state = states[player]
	if not state then
		return
	end
	local now = os.clock()
	if now < state.NextAction then
		return
	end
	state.NextAction = now + Config.Shop.ActionCooldown
	local season = seasonOf(player)
	if not season then
		return
	end
	if action == "Claim" and (track == "Free" or track == "Premium") and type(tier) == "number" and tier == tier then
		claim(player, season, track :: string, math.floor(tier))
	elseif action ~= "Sync" then
		return
	end
	send(player)
end

local function onLoaded(player: Player)
	local state = states[player]
	if not state or state.Ready or not DataService.Get(player) then
		return
	end
	state.Ready = true
	local season = seasonOf(player)
	if season and state.Pending > 0 then
		season.XP += state.Pending
		state.Pending = 0
		DataService.Touch(player)
	end
	send(player)
end

local function onPlayerAdded(player: Player)
	states[player] = { Ready = false, Pending = 0, Fraction = 0, NextAction = 0 }
	player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if player:GetAttribute("DataLoaded") then
			onLoaded(player)
		end
	end)
	if player:GetAttribute("DataLoaded") then
		task.spawn(onLoaded, player)
	end
	player:GetAttributeChangedSignal("Pass_SeasonPremium"):Connect(function()
		dirty[player] = true
	end)
end

function SeasonService.Init()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Season) :: RemoteEvent
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		dirty[player] = nil
	end)
	remote.OnServerEvent:Connect(onRequest)
	LevelService.Gained.Event:Connect(addXP)

	-- Progress goes out at most once a second.
	task.spawn(function()
		while true do
			task.wait(1)
			for player in dirty do
				task.spawn(send, player)
			end
		end
	end)
end

return SeasonService
