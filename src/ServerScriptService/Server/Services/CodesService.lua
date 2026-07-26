--!strict
-- Server-authoritative promo code redemption. Codes are announced in
-- YouTube/TikTok videos, so this is a public text box every player can mash -
-- validation, rate limiting and input sanitation all happen here, never on
-- the client.
--
-- Request/response contract (see Constants.REMOTE_NAMES.Codes):
--   Client fires Redeem(codeString: string)
--   Server fires RedeemResult({ Success, Code?, Reason?, Reward? })
--     Reason (only present when Success is false): "InvalidCode" | "AlreadyRedeemed" | "Expired"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local CodesConfig = require(ReplicatedStorage.Shared.Codes.CodesConfig)
local DataService = require(ServerScriptService.Server.Services.DataService)
local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

local CodesService = {}

type RedeemFailureReason = "InvalidCode" | "AlreadyRedeemed" | "Expired"

-- Input sanitation: real codes in CodesConfig are short (<20 chars); this is
-- a generous ceiling that still rejects someone pasting a huge string.
local MAX_CODE_LENGTH = 32

-- Rate limiting: a code box is a brute-force oracle for guessing unreleased
-- codes if left unthrottled. Base interval between attempts, plus an
-- escalating backoff per consecutive *invalid-code* guess (not for
-- already-redeemed/expired, which aren't guessing attempts) so a bot mashing
-- the box slows to a crawl instead of getting free retries every second.
local BASE_ATTEMPT_INTERVAL = 1 -- seconds
local MAX_BACKOFF_SECONDS = 10

local redeemResultEvent: RemoteEvent

local lastAttemptAt: { [Player]: number } = {}
local invalidStreak: { [Player]: number } = {}

local FAILURE_MESSAGES: { [RedeemFailureReason]: string } = {
	InvalidCode = "That code isn't valid.",
	AlreadyRedeemed = "You've already redeemed that code.",
	Expired = "That code has expired.",
}

local function notify(player: Player, message: string, kind: string)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)
end

local function fail(player: Player, code: string?, reason: RedeemFailureReason)
	redeemResultEvent:FireClient(player, { Success = false, Code = code, Reason = reason })
	notify(player, FAILURE_MESSAGES[reason], "Warning")
end

local function requiredWait(player: Player): number
	local streak = invalidStreak[player] or 0
	return math.min(MAX_BACKOFF_SECONDS, BASE_ATTEMPT_INTERVAL + streak)
end

local function isRateLimited(player: Player): boolean
	local last = lastAttemptAt[player]
	if not last then
		return false
	end
	return (os.clock() - last) < requiredWait(player)
end

local function onRedeem(player: Player, rawCode: unknown)
	-- Reject non-string / malformed payloads before touching anything else.
	if typeof(rawCode) ~= "string" then
		return
	end
	if #rawCode == 0 or #rawCode > MAX_CODE_LENGTH then
		fail(player, nil, "InvalidCode")
		return
	end

	if isRateLimited(player) then
		-- Drop silently: this path is hit by someone mashing the button faster
		-- than a human types, not a legitimate retry. No RedeemResult fired so
		-- the client doesn't flash a misleading error for its own throttled
		-- click; ordinary client-side throttling already prevents this in the
		-- honest case.
		return
	end
	lastAttemptAt[player] = os.clock()

	local profile = DataService.Get(player)
	if not profile then
		-- Profile not loaded yet: treat as a normal invalid attempt rather than
		-- exposing a distinct reason the client contract doesn't define.
		fail(player, nil, "InvalidCode")
		return
	end

	local normalized = string.upper(rawCode)
	local def = CodesConfig.Find(normalized)
	if not def then
		invalidStreak[player] = (invalidStreak[player] or 0) + 1
		fail(player, normalized, "InvalidCode")
		return
	end

	if profile.CodesRedeemed[normalized] then
		fail(player, normalized, "AlreadyRedeemed")
		return
	end

	if def.ExpiresAt and os.time() > def.ExpiresAt then
		fail(player, normalized, "Expired")
		return
	end

	invalidStreak[player] = 0
	DataService.Mutate(player, function(p)
		p.CodesRedeemed[normalized] = true
	end)

	EconomyService.AwardBundle(player, def.Reward, `Code: {normalized}`)
	if def.BoostName and def.BoostSeconds then
		DataService.GrantBoost(player, def.BoostName, def.BoostSeconds)
	end

	redeemResultEvent:FireClient(player, { Success = true, Code = normalized, Reward = def.Reward })
	notify(player, `Code "{normalized}" redeemed!`, "Success")
end

local function onPlayerRemoving(player: Player)
	lastAttemptAt[player] = nil
	invalidStreak[player] = nil
end

function CodesService.Init()
	redeemResultEvent = Net.GetEvent(Constants.REMOTE_NAMES.Codes.RedeemResult)

	Net.GetEvent(Constants.REMOTE_NAMES.Codes.Redeem).OnServerEvent:Connect(onRedeem)

	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return CodesService
