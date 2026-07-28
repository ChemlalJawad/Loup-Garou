--!strict
-- Builds the promo Codes panel: a text box, a REDEEM button, and clear
-- in-panel success/failure feedback (in addition to the global toast, since a
-- player fixating on the text box may not glance up at the toast rail). Pure
-- UI construction only - all validation happens server-side in CodesService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local Util = UIKit.Util

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)

local CodesUI = {}

export type CodesUICallbacks = {
	OnRedeem: (code: string) -> (),
}

export type RedeemResultPayload = {
	Success: boolean,
	Code: string?,
	Reason: string?,
	Reward: { Coins: number?, Gems: number?, XP: number? }?,
}

local PANEL_SIZE = UDim2.new(0, 480, 0, 280)
local PANEL_ID = "NavCodes"
local MAX_CODE_LENGTH = 32

local FAILURE_MESSAGES: { [string]: string } = {
	InvalidCode = "That code isn't valid. Double-check the spelling.",
	AlreadyRedeemed = "You've already redeemed that code.",
	Expired = "That code has expired.",
}

local initialized = false
local callbacks: CodesUICallbacks? = nil
local textBox: TextBox? = nil
local redeemButton: TextButton? = nil
local feedbackLabel: TextLabel? = nil

CodesUI.Root = nil :: Frame?

local function setFeedback(text: string, color: Color3)
	if feedbackLabel then
		feedbackLabel.Text = text
		feedbackLabel.TextColor3 = color
	end
end

local function submit()
	local box = textBox
	if not box or not callbacks then
		return
	end
	local code = box.Text
	if #code == 0 then
		setFeedback("Type a code first.", Theme.Color.AccentWarning)
		return
	end
	if #code > MAX_CODE_LENGTH then
		setFeedback("That code is too long.", Theme.Color.AccentDanger)
		return
	end
	callbacks.OnRedeem(code)
end

function CodesUI.Init(props: CodesUICallbacks)
	if initialized then
		return
	end
	initialized = true
	callbacks = props

	local modal = UIKit.Modal.new({
		Title = "CODES",
		Subtitle = "Redeem promo codes from our videos and posts for free rewards.",
		Size = PANEL_SIZE,
		Parent = Shell.GetScreenGui(),
		OnClose = function()
			Shell.ClosePanel(PANEL_ID)
		end,
	})
	CodesUI.Root = modal.Root

	local box = Util.Create("TextBox", {
		Name = "CodeInput",
		BackgroundColor3 = Theme.Color.Background,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 46),
		Text = "",
		PlaceholderText = "Enter code here",
		TextColor3 = Theme.Color.TextPrimary,
		PlaceholderColor3 = Theme.Color.TextDisabled,
		Font = Theme.Font.SubHeading,
		TextSize = 18,
		ClearTextOnFocus = false,
		Parent = modal.Content,
	}) :: TextBox
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = box })
	Util.Create("UIStroke", {
		Color = Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Parent = box,
	})
	Util.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = box,
	})
	textBox = box

	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submit()
		end
	end)

	local button = UIKit.Button.new({
		Text = "REDEEM",
		Variant = "Primary",
		Size = UDim2.new(1, 0, 0, 48),
		Position = UDim2.new(0, 0, 0, 78),
		Parent = modal.Content,
		OnClick = submit,
	})
	redeemButton = button

	feedbackLabel = Util.Create("TextLabel", {
		Name = "Feedback",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 138),
		Size = UDim2.new(1, 0, 0, 60),
		Text = "",
		TextWrapped = true,
		TextColor3 = Theme.Color.TextSecondary,
		Font = Theme.Font.Body,
		TextSize = 14,
		Parent = modal.Content,
	}) :: TextLabel
end

function CodesUI.ShowResult(result: RedeemResultPayload)
	if result.Success then
		setFeedback(`Success! "{result.Code}" redeemed.`, Theme.Color.AccentPrimary)
		if textBox then
			textBox.Text = ""
		end
	else
		local reason = result.Reason or "InvalidCode"
		setFeedback(FAILURE_MESSAGES[reason] or "That code didn't work.", Theme.Color.AccentDanger)
	end
end

function CodesUI.Toggle()
	Shell.TogglePanel(PANEL_ID)
end

return CodesUI
