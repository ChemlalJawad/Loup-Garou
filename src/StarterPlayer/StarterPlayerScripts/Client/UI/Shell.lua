--!strict
-- The persistent HUD shell: top bar (currency), nav bar, and toast
-- notifications. Every other screen (Eggs, Shop, CTF HUD) mounts into the
-- ScreenGui this module owns and registers its own nav button here — this
-- module does not know those systems exist.
--
-- Public contract (do not change signatures without updating every consumer):
--   Shell.Init()
--   Shell.GetScreenGui(): ScreenGui
--   Shell.RegisterNavButton({ Id, Label, IconText?, OnClick })
--   Shell.SetCurrency(currencyKey: "Coins" | "Gems", amount: number)
--   Shell.Notify(message: string, kind: "Info" | "Success" | "Warning" | "Error"?)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local Util = UIKit.Util

local Shell = {}

export type NavButtonProps = {
	Id: string,
	Label: string,
	IconText: string?,
	OnClick: () -> (),
}

export type ToastKind = "Info" | "Success" | "Warning" | "Error"

local screenGui: ScreenGui? = nil
local navBar: Frame? = nil
local toastContainer: Frame? = nil
local currencyLabels: { [string]: TextLabel } = {}
local navButtons: { [string]: TextButton } = {}
local selectedNavId: string? = nil

-- Fakes a soft drop shadow for a rounded panel-like GuiObject: we have no
-- shadow image asset to work with (no import pipeline in this project), so
-- a slightly larger, darker, semi-transparent duplicate sits just behind
-- and below it. Returns the shadow Frame in case a caller wants to tidy it
-- up later.
local function addDropShadow(target: GuiObject, cornerRadius: UDim): Frame
	target.ZIndex = 2
	local shadow = Util.Create("Frame", {
		Name = target.Name .. "Shadow",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		AnchorPoint = target.AnchorPoint,
		Position = target.Position + UDim2.new(0, 0, 0, 4),
		Size = target.Size + UDim2.new(0, 10, 0, 10),
		ZIndex = 1,
		Parent = target.Parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = cornerRadius, Parent = shadow })
	return shadow
end

local function buildTopBar(parent: ScreenGui)
	local topBar = Util.Create("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 64),
		Parent = parent,
	}) :: Frame

	-- Glassy translucent backdrop behind the whole bar, so the HUD reads as
	-- one surface instead of text floating directly over gameplay. A true
	-- Gaussian blur isn't available without a post-effect over the whole
	-- viewport, so this approximates "glassy" with translucency + a subtle
	-- vertical gradient instead.
	local background = Util.Create("Frame", {
		Name = "Background",
		BackgroundColor3 = Theme.Color.Background,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 1,
		Parent = topBar,
	}) :: Frame
	Util.Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Color.SurfaceRaised),
			ColorSequenceKeypoint.new(1, Theme.Color.Background),
		}),
		Rotation = 90,
		Parent = background,
	})
	-- Thin glowing seam separating the HUD from the world below it.
	Util.Create("Frame", {
		Name = "BottomSeam",
		BackgroundColor3 = Theme.Color.AccentPrimary,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2),
		ZIndex = 1,
		Parent = topBar,
	})

	-- Small diamond logomark + gradient wordmark, instead of a single flat
	-- TextLabel, so the top-left reads as a brand lockup.
	local logoMark = Util.Create("Frame", {
		Name = "LogoMark",
		BackgroundColor3 = Theme.Color.AccentPrimary,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.5, 0),
		Size = UDim2.new(0, 14, 0, 14),
		Rotation = 45,
		ZIndex = 2,
		Parent = topBar,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = logoMark })

	local title = Util.Create("TextLabel", {
		Name = "GameTitle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 44, 0.5, 0),
		Size = UDim2.new(0, 300, 1, 0),
		Text = "BRAINROT HATCH WARS",
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Heading,
		TextSize = 20,
		ZIndex = 2,
		Parent = topBar,
	}) :: TextLabel
	Util.Create("UIGradient", {
		Color = ColorSequence.new(Theme.Color.TextPrimary, Theme.Color.AccentPrimary),
		Parent = title,
	})

	local currencyRow = Util.Create("Frame", {
		Name = "CurrencyRow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.new(0, 320, 0, 40),
		ZIndex = 2,
		Parent = topBar,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = currencyRow,
	})

	local _coinsPill, coinsLabel = UIKit.CurrencyPill.new({
		Parent = currencyRow,
		Label = "0",
		IconText = "C",
		AccentColor = Theme.Color.AccentPrimary,
		LayoutOrder = 1,
	})
	coinsLabel.Name = "CoinsAmount"
	currencyLabels.Coins = coinsLabel

	local _gemsPill, gemsLabel = UIKit.CurrencyPill.new({
		Parent = currencyRow,
		Label = "0",
		IconText = "G",
		AccentColor = Theme.Color.AccentSecondary,
		LayoutOrder = 2,
	})
	gemsLabel.Name = "GemsAmount"
	currencyLabels.Gems = gemsLabel
end

local function buildNavBar(parent: ScreenGui)
	local bar = Util.Create("Frame", {
		Name = "NavBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(0, 0, 0, 56),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = bar })
	Util.Create("UIStroke", {
		Color = Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Transparency = 0.4,
		Parent = bar,
	})
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = bar,
	})
	Util.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = bar,
	})
	addDropShadow(bar, Theme.CornerRadius.Pill)
	navBar = bar
end

local function buildToastContainer(parent: ScreenGui)
	local container = Util.Create("Frame", {
		Name = "ToastContainer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.new(0, 380, 0, 400),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = container,
	})
	toastContainer = container
end

function Shell.Init()
	if screenGui then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Util.Create("ScreenGui", {
		Name = "MainUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	screenGui = gui

	buildTopBar(gui)
	buildNavBar(gui)
	buildToastContainer(gui)
end

function Shell.GetScreenGui(): ScreenGui
	assert(screenGui, "Shell.Init must be called before Shell.GetScreenGui")
	return screenGui :: ScreenGui
end

-- Best-effort visual highlight for whichever nav button was most recently
-- clicked. This is cosmetic only (Shell has no way to know if a screen was
-- later closed by some other means), so it never gates or changes what
-- `OnClick` actually does - it just makes the nav bar feel less static.
local function setSelectedNav(id: string)
	selectedNavId = id
	for buttonId, button in navButtons do
		local isSelected = buttonId == id
		button.TextColor3 = if isSelected then Theme.Color.AccentPrimary else Theme.Color.TextSecondary
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if isSelected then Theme.Color.AccentPrimary else Theme.Color.Stroke
			stroke.Thickness = if isSelected then Theme.Stroke.Regular else Theme.Stroke.Thin
		end
	end
end

function Shell.RegisterNavButton(props: NavButtonProps)
	assert(navBar, "Shell.Init must be called before Shell.RegisterNavButton")

	local button = UIKit.Button.new({
		Text = if props.IconText then `{props.IconText}  {props.Label}` else props.Label,
		Variant = "Ghost",
		Size = UDim2.new(0, 130, 0, 40),
		Parent = navBar,
		OnClick = function()
			setSelectedNav(props.Id)
			props.OnClick()
		end,
	})
	button.Name = props.Id
	navButtons[props.Id] = button
end

function Shell.SetCurrency(currencyKey: string, amount: number)
	local label = currencyLabels[currencyKey]
	if label then
		label.Text = string.format("%d", amount)
	end
end

function Shell.Notify(message: string, kind: ToastKind?)
	assert(toastContainer, "Shell.Init must be called before Shell.Notify")
	UIKit.Toast.new({
		Parent = toastContainer :: Frame,
		Message = message,
		Kind = kind,
	})
end

return Shell
