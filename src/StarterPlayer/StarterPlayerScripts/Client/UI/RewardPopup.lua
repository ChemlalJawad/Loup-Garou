--!strict
-- Floating "+150 Coins" reward feedback, anchored near the currency HUD in
-- the top bar. `EconomyController` feeds this module every
-- `Economy.RewardPopup` event it receives; this module owns rendering only.
--
-- The one design requirement that matters here: idle income fires an award
-- every `Constants.IDLE_TICK_SECONDS` forever, and CTF/quests/daily can also
-- fire several awards in a burst. An un-coalesced popup stream (one label per
-- award, all fighting for the same screen space) reads as noise, not as
-- juice. So same-currency awards that land within COALESCE_WINDOW of each
-- other accumulate into ONE growing label instead of spawning a new one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local Util = UIKit.Util

local RewardPopup = {}

export type RewardPopupPayload = {
	Currency: string, -- "Coins" | "Gems" | "XP"
	Amount: number,
	Reason: string?,
}

-- Same-currency awards landing within this window of the last one accumulate
-- into the same on-screen label instead of spawning a new one.
local COALESCE_WINDOW_SECONDS = 1

-- Fixed vertical slot per currency so labels never jump around as different
-- currencies come and go, and two different currencies never overlap.
local ROW_OFFSET: { [string]: number } = {
	Coins = 0,
	Gems = 28,
	XP = 56,
}

local CURRENCY_COLOR: { [string]: Color3 } = {
	Coins = Theme.Color.AccentPrimary,
	Gems = Theme.Color.AccentSecondary,
	XP = Theme.Color.AccentInfo,
}

local CURRENCY_PREFIX: { [string]: string } = {
	Coins = "+",
	Gems = "+",
	XP = "+",
}

type ActiveEntry = {
	Label: TextLabel,
	Amount: number,
	Deadline: number, -- os.clock() timestamp
	Alive: boolean, -- flips false once the finalize coroutine starts closing it
}

local container: Frame? = nil
local active: { [string]: ActiveEntry } = {}

local function formatText(currency: string, amount: number): string
	local prefix = CURRENCY_PREFIX[currency] or "+"
	local rounded = math.floor(amount + 0.5)
	local formatted = tostring(rounded)
	-- Thousands separators for large idle-income accumulations, matching the
	-- top-bar currency formatting.
	formatted = formatted:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return `{prefix}{formatted} {currency}`
end

local function buildLabel(currency: string): TextLabel
	assert(container, "RewardPopup.Init must be called before RewardPopup.Show")

	local color = CURRENCY_COLOR[currency] or Theme.Color.TextPrimary
	local yOffset = ROW_OFFSET[currency] or 0

	local label = Util.Create("TextLabel", {
		Name = "Popup_" .. currency,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, yOffset),
		Size = UDim2.new(0, 260, 0, 26),
		Text = "",
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Theme.Font.SubHeading,
		TextSize = 18,
		TextTransparency = 1,
		ZIndex = 30,
		Parent = container,
	}) :: TextLabel
	Util.Create("UIStroke", {
		Color = Color3.fromRGB(10, 10, 16),
		Transparency = 0.5,
		Thickness = Theme.Stroke.Thin,
		Parent = label,
	})

	return label
end

-- Waits out the coalescing window (which Show() may keep pushing back), then
-- plays the drift-up-and-fade exit and destroys the label. One of these runs
-- per currency per "burst" of awards, not per award.
local function finalizeAfterWindow(currency: string, entry: ActiveEntry)
	while true do
		local remaining = entry.Deadline - os.clock()
		if remaining <= 0 then
			break
		end
		task.wait(remaining)
	end

	entry.Alive = false
	if active[currency] == entry then
		active[currency] = nil
	end

	local label = entry.Label
	local startPosition = label.Position
	Util.Tween(label, {
		Position = startPosition - UDim2.new(0, 0, 0, 34),
		TextTransparency = 1,
	}, Theme.Motion.Slow)

	task.delay(Theme.Motion.Slow + 0.05, function()
		if label and label.Parent then
			label:Destroy()
		end
	end)
end

function RewardPopup.Init()
	if container then
		return
	end

	local ShellModule = script.Parent:FindFirstChild("Shell")
	if not ShellModule then
		warn("[RewardPopup] Shell.lua not found next to RewardPopup.lua; cannot mount popups")
		return
	end
	local Shell = require(ShellModule)
	local screenGui = Shell.GetScreenGui()

	-- Sits just under the top bar's currency row, right-aligned to match it.
	container = Util.Create("Frame", {
		Name = "RewardPopupLayer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 68),
		Size = UDim2.new(0, 260, 0, 120),
		ZIndex = 30,
		Parent = screenGui,
	}) :: Frame
end

-- Shows (or coalesces into) a floating reward popup. Safe to call rapidly and
-- repeatedly - that's the whole point.
function RewardPopup.Show(payload: RewardPopupPayload)
	if not container then
		return
	end
	if type(payload) ~= "table" or type(payload.Currency) ~= "string" or type(payload.Amount) ~= "number" then
		return
	end
	if payload.Amount <= 0 then
		return
	end

	local currency = payload.Currency
	local entry = active[currency]

	if entry and entry.Alive then
		entry.Amount += payload.Amount
		entry.Deadline = os.clock() + COALESCE_WINDOW_SECONDS
		entry.Label.Text = formatText(currency, entry.Amount)
		entry.Label.TextTransparency = 0
		-- Small pulse so an accumulating popup still reads as "something just
		-- happened" instead of a silently-updating counter.
		local label = entry.Label
		label.TextSize = 21
		Util.Tween(label, { TextSize = 18 }, Theme.Motion.Fast)
		return
	end

	local label = buildLabel(currency)
	label.Text = formatText(currency, payload.Amount)
	label.TextTransparency = 0
	label.Position = UDim2.new(1, 0, 0, ROW_OFFSET[currency] or 0)

	local newEntry: ActiveEntry = {
		Label = label,
		Amount = payload.Amount,
		Deadline = os.clock() + COALESCE_WINDOW_SECONDS,
		Alive = true,
	}
	active[currency] = newEntry

	task.spawn(finalizeAfterWindow, currency, newEntry)
end

return RewardPopup
