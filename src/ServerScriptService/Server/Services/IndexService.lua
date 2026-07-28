--!strict
-- Server side of the Collection Index. Discovery bookkeeping itself already
-- happens in DataService.AddBrainrot (profile.Index[id] += 1 on every grant
-- path), so this service is purely about:
--   1. Pushing Index_StateUpdated to the client whenever the profile changes.
--   2. Detecting the "new discovery" moment (undiscovered -> discovered) and
--      firing a toast for it.
--   3. Validating and paying out Index_ClaimMilestone requests.
--
-- Request/response contract (see Constants.REMOTE_NAMES.Index):
--   Server fires StateUpdated(player, { Index = {[id]=count}, Claimed = {[milestoneId]=true} })
--     on profile load and on every (throttled) profile change.
--   Client fires ClaimMilestone(milestoneId: string).
--   Server validates server-side (never trusts client claims of completion),
--     mutates profile.IndexMilestonesClaimed, pays out via EconomyService, and
--     toasts the result via Constants.REMOTE_NAMES.Shared.Notify.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local IndexConfig = require(ReplicatedStorage.Shared.Index.IndexConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

local IndexService = {}

-- The capstone milestone's permanent perk is granted through the *existing*
-- Luck2x boost mechanism (DataService.GrantBoost / EconomyService.BOOST_LUCK_2X)
-- rather than inventing a new perk name in DataService.SetPerk, per the
-- ownership contract (only "DoubleCoins"/"DoubleLuck" belong to the shop
-- system). A ~100 year duration reads as "permanent" for gameplay purposes
-- while still going through the normal boost expiry path, so it needs no new
-- persisted field of its own.
local PERMANENT_BOOST_SECONDS = 100 * 365 * 24 * 60 * 60

local stateUpdatedEvent: RemoteEvent
local claimMilestoneEvent: RemoteEvent

-- Per-player snapshot of which ids were discovered as of the last push, used
-- solely to detect the "just discovered" transition for the toast callout.
local previousDiscovered: { [Player]: { [string]: boolean } } = {}
local pushQueued: { [Player]: boolean } = {}

local function notify(player: Player, message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)
end

local function computeDiscoveredSet(indexTable: IndexConfig.IndexTable): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, entry in IndexConfig.AllEntries() do
		if IndexConfig.IsDiscovered(indexTable, entry.Id) then
			set[entry.Id] = true
		end
	end
	return set
end

local function pushState(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local indexCopy: { [string]: number } = {}
	for id, count in profile.Index do
		indexCopy[id] = count
	end

	local claimedCopy: { [string]: boolean } = {}
	for id, claimed in profile.IndexMilestonesClaimed do
		claimedCopy[id] = claimed
	end

	stateUpdatedEvent:FireClient(player, {
		Index = indexCopy,
		Claimed = claimedCopy,
	})
end

-- Diffs the profile's discovered set against the last-known snapshot and
-- fires a "NEW: <Name> discovered!" toast for anything that just flipped
-- from undiscovered to discovered.
local function detectNewDiscoveries(player: Player, profile: DataService.Profile)
	local previous = previousDiscovered[player]
	if not previous then
		previous = {}
		previousDiscovered[player] = previous
	end

	for _, entry in IndexConfig.AllEntries() do
		local discoveredNow = IndexConfig.IsDiscovered(profile.Index, entry.Id)
		if discoveredNow and not previous[entry.Id] then
			previous[entry.Id] = true
			notify(player, `NEW: {entry.Name} discovered!`, "Success")
		end
	end
end

local function onProfileLoaded(player: Player, profile: DataService.Profile)
	-- Seed the snapshot from what's already discovered so rejoining a session
	-- doesn't re-fire "new discovery" toasts for old finds.
	previousDiscovered[player] = computeDiscoveredSet(profile.Index)
	pushState(player)
end

-- Throttled: a x10 hatch fires ten DataService.Mutate/AddBrainrot calls in a
-- row, each of which fires ProfileChanged. Collapsing to one push per frame
-- (per player) avoids ten redundant Index_StateUpdated round-trips.
local function onProfileChanged(player: Player, profile: DataService.Profile)
	detectNewDiscoveries(player, profile)

	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		if player.Parent then
			pushState(player)
		end
	end)
end

local function onClaimMilestone(player: Player, milestoneIdRaw: unknown)
	if typeof(milestoneIdRaw) ~= "string" then
		return
	end
	local milestoneId = milestoneIdRaw

	local milestone = IndexConfig.GetMilestone(milestoneId)
	if not milestone then
		notify(player, "That milestone doesn't exist.", "Warning")
		return
	end

	local profile = DataService.Get(player)
	if not profile then
		notify(player, "Your data is still loading - try again in a moment.", "Warning")
		return
	end

	if profile.IndexMilestonesClaimed[milestoneId] then
		notify(player, "You already claimed that milestone.", "Warning")
		return
	end

	-- Re-evaluate server-side from the authoritative profile - never trust a
	-- client claim that a milestone is complete.
	if not IndexConfig.EvaluateMilestone(milestoneId, profile.Index) then
		notify(player, "You haven't unlocked that milestone yet.", "Warning")
		return
	end

	DataService.Mutate(player, function(mutableProfile)
		mutableProfile.IndexMilestonesClaimed[milestoneId] = true
	end)

	EconomyService.AwardBundle(player, milestone.Reward, milestone.Label)

	if milestone.PermanentLuckBoost then
		DataService.GrantBoost(player, EconomyService.BOOST_LUCK_2X, PERMANENT_BOOST_SECONDS)
	end

	notify(player, `Milestone claimed: {milestone.Label}!`, "Success")
	pushState(player)
end

local function onPlayerRemoving(player: Player)
	previousDiscovered[player] = nil
	pushQueued[player] = nil
end

function IndexService.Init()
	stateUpdatedEvent = Net.GetEvent(Constants.REMOTE_NAMES.Index.StateUpdated)
	claimMilestoneEvent = Net.GetEvent(Constants.REMOTE_NAMES.Index.ClaimMilestone)

	claimMilestoneEvent.OnServerEvent:Connect(onClaimMilestone)

	DataService.ProfileLoaded.Event:Connect(onProfileLoaded)
	DataService.ProfileChanged.Event:Connect(onProfileChanged)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile then
			task.spawn(onProfileLoaded, player, profile)
		end
	end
end

return IndexService
