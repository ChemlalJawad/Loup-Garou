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

local TOAST_COLORS: { [string]: Color3 } = {
	Info = Theme.Color.AccentInfo,
	Success = Theme.Color.AccentPrimary,
	Warning = Theme.Color.AccentWarning,
	Error = Theme.Color.AccentDanger,
}

local function buildTopBar(parent: ScreenGui)
	local topBar = Util.Create("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 64),
		Parent = parent,
	}) :: Frame

	Util.Create("TextLabel", {
		Name = "GameTitle",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 20, 0, 0),
		Size = UDim2.new(0, 320, 1, 0),
		Text = "BRAINROT HATCH WARS",
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Heading,
		TextSize = 20,
		Parent = topBar,
	})

	local currencyRow = Util.Create("Frame", {
		Name = "CurrencyRow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.new(0, 320, 0, 40),
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

function Shell.RegisterNavButton(props: NavButtonProps)
	assert(navBar, "Shell.Init must be called before Shell.RegisterNavButton")

	local button = UIKit.Button.new({
		Text = if props.IconText then `{props.IconText}  {props.Label}` else props.Label,
		Variant = "Ghost",
		Size = UDim2.new(0, 130, 0, 40),
		Parent = navBar,
		OnClick = props.OnClick,
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
	local color = TOAST_COLORS[kind or "Info"] or Theme.Color.AccentInfo

	local toast = Util.Create("Frame", {
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = toastContainer,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = toast })
	Util.Create("UIStroke", { Color = color, Thickness = Theme.Stroke.Regular, Parent = toast })
	Util.Create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = toast,
	})
	local textLabel = Util.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = message,
		TextWrapped = true,
		TextTransparency = 1,
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.Body,
		TextSize = 15,
		Parent = toast,
	}) :: TextLabel

	Util.Tween(toast, { BackgroundTransparency = 0 }, Theme.Motion.Normal)
	Util.Tween(textLabel, { TextTransparency = 0 }, Theme.Motion.Normal)

	task.delay(3.2, function()
		if not toast.Parent then
			return
		end
		Util.Tween(toast, { BackgroundTransparency = 1 }, Theme.Motion.Normal)
		Util.Tween(textLabel, { TextTransparency = 1 }, Theme.Motion.Normal)
		task.delay(Theme.Motion.Normal, function()
			toast:Destroy()
		end)
	end)
end

return Shell
