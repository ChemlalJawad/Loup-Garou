--!strict
-- New-player guide (see Shared/Tutorial/TutorialConfig). Owns
-- Profile.TutorialStep, checks each step's condition, pays the completion
-- reward, and tells the client which step to draw.
--
-- Step conditions:
--   * zone steps: the player's character is inside that WorldLayout zone
--     (polled twice a second, only for players currently on a zone step);
--   * HatchEgg: Stats.EggsHatched went above 0 (watched through
--     DataService.ProfileChanged, so EggService doesn't know this exists).
-- A step whose condition is already true is skipped straight past, so a
-- player who hatches before reaching the Hatchery isn't told to go there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TutorialConfig = require(ReplicatedStorage.Shared.Tutorial.TutorialConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

local TutorialService = {}

local POLL_INTERVAL = 0.5

local stateEvent: RemoteEvent

local function currentZone(player: Player): string?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return WorldLayout.ZoneAt(root.Position)
	end
	return nil
end

local function isStepSatisfied(player: Player, profile: DataService.Profile, stepIndex: number): boolean
	local step = TutorialConfig.Steps[stepIndex]
	if not step then
		return false
	end
	if step.Id == "HatchEgg" then
		return profile.Stats.EggsHatched > 0
	end
	if step.Id == "WalkToHatchery" and profile.Stats.EggsHatched > 0 then
		return true -- already did the thing the walk leads to
	end
	return step.Zone ~= nil and currentZone(player) == step.Zone
end

local function push(player: Player, stepIndex: number)
	stateEvent:FireClient(player, stepIndex)
end

local function finish(player: Player)
	DataService.Mutate(player, function(profile)
		profile.TutorialStep = TutorialConfig.DONE
	end)
	push(player, TutorialConfig.DONE)
	EconomyService.AwardBundle(player, TutorialConfig.Reward, "Tutorial complete")
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(
		player,
		`You're all set! +{TutorialConfig.Reward.Coins} Coins. Have fun!`,
		"Success"
	)
end

-- Advances past every step whose condition already holds.
local function evaluate(player: Player)
	local profile = DataService.Get(player)
	if not profile or profile.TutorialStep == TutorialConfig.DONE then
		return
	end
	local step = profile.TutorialStep
	local advanced = false
	while step <= #TutorialConfig.Steps and isStepSatisfied(player, profile, step) do
		step += 1
		advanced = true
	end
	if not advanced then
		return
	end
	if step > #TutorialConfig.Steps then
		finish(player)
	else
		DataService.Mutate(player, function(p)
			p.TutorialStep = step
		end)
		push(player, step)
	end
end

local function onProfileLoaded(player: Player, profile: DataService.Profile)
	-- Returning players from before the guide existed: if they've hatched
	-- anything they know the loop already; don't send them back to school.
	if profile.TutorialStep == 1 and profile.Stats.EggsHatched > 0 then
		DataService.Mutate(player, function(p)
			p.TutorialStep = TutorialConfig.DONE
		end)
	end
	push(player, profile.TutorialStep)
end

function TutorialService.Init()
	stateEvent = Net.GetEvent(Constants.REMOTE_NAMES.Tutorial.State)

	Net.GetEvent(Constants.REMOTE_NAMES.Tutorial.RequestState).OnServerEvent:Connect(function(player)
		local profile = DataService.Get(player)
		if profile then
			push(player, profile.TutorialStep)
		end
	end)

	-- Skipping gives no reward (otherwise "skip" is the fastest 250 Coins).
	Net.GetEvent(Constants.REMOTE_NAMES.Tutorial.Skip).OnServerEvent:Connect(function(player)
		local profile = DataService.Get(player)
		if profile and profile.TutorialStep ~= TutorialConfig.DONE then
			DataService.Mutate(player, function(p)
				p.TutorialStep = TutorialConfig.DONE
			end)
			push(player, TutorialConfig.DONE)
		end
	end)

	DataService.ProfileLoaded.Event:Connect(onProfileLoaded)
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile then
			task.spawn(onProfileLoaded, player, profile)
		end
	end

	-- The hatch step completes the moment the stat changes.
	DataService.ProfileChanged.Event:Connect(function(player: Player, profile: DataService.Profile)
		if profile.TutorialStep ~= TutorialConfig.DONE then
			local step = TutorialConfig.Steps[profile.TutorialStep]
			if step and step.Zone == nil then
				-- Deferred: we're inside someone else's Mutate right now.
				task.defer(evaluate, player)
			end
		end
	end)

	-- Zone steps: a cheap position check, only for players mid-guide.
	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if profile and profile.TutorialStep ~= TutorialConfig.DONE then
					evaluate(player)
				end
			end
		end
	end)
end

return TutorialService
