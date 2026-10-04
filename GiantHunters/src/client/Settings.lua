--!strict
-- The settings panel: a gear button (top right) opens a small card of
-- toggles. Session-only (nothing is saved): aim assist, camera roll, screen
-- shake strength, FOV effects strength, speed lines, the hook marker and
-- bigger text. Laid out in scale, so it fits a phone as well as a monitor.
--
-- Other modules read a value with Settings.Get(name) (always safe, even
-- before Init) and can listen to Settings.Changed (name, value).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local Settings = {}

local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Steps for the "strength" settings: Off, Low, Normal, Strong.
local STRENGTHS = { 0, 0.5, 1, 1.5 }
local STRENGTH_NAMES = { "OFF", "LOW", "NORMAL", "STRONG" }

type Option = {
	Key: string,
	Label: string,
	Kind: "Toggle" | "Strength",
}

local OPTIONS: { Option } = {
	{ Key = "AimAssist", Label = "Aim assist (hooks)", Kind = "Toggle" },
	{ Key = "HookMarker", Label = "Hook landing marker", Kind = "Toggle" },
	{ Key = "CameraRoll", Label = "Camera roll in swings", Kind = "Toggle" },
	{ Key = "SpeedLines", Label = "Speed lines", Kind = "Toggle" },
	{ Key = "Shake", Label = "Screen shake", Kind = "Strength" },
	{ Key = "Fov", Label = "Speed / FOV effects", Kind = "Strength" },
	{ Key = "BigText", Label = "Bigger text", Kind = "Toggle" },
}

local values: { [string]: any } = {
	AimAssist = Config.Feel.AimAssistDefault,
	HookMarker = true,
	CameraRoll = true,
	SpeedLines = true,
	Shake = 1,
	Fov = 1,
	BigText = touch,
}

Settings.Changed = Instance.new("BindableEvent")

function Settings.Get(key: string): any
	return values[key]
end

function Settings.Set(key: string, value: any)
	if values[key] == value then
		return
	end
	values[key] = value
	Settings.Changed:Fire(key, value)
end

-- Extra text scale for the HUD's text (bigger on phones by default).
function Settings.TextBoost(): number
	return if values.BigText then Config.Feel.BigTextScale else 1
end

local function new(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

local function valueText(option: Option): string
	local value = values[option.Key]
	if option.Kind == "Toggle" then
		return if value then "ON" else "OFF"
	end
	for i, strength in STRENGTHS do
		if strength == value then
			return STRENGTH_NAMES[i]
		end
	end
	return tostring(value)
end

local function nextValue(option: Option): any
	local value = values[option.Key]
	if option.Kind == "Toggle" then
		return not value
	end
	for i, strength in STRENGTHS do
		if strength == value then
			return STRENGTHS[i % #STRENGTHS + 1]
		end
	end
	return 1
end

function Settings.Init()
	local gui = new("ScreenGui", { Name = "HunterSettings", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
	local ink = Color3.fromRGB(28, 30, 40)
	local brass = Color3.fromRGB(190, 170, 120)

	-- The gear button, in the top bar's right-hand corner.
	local gear = new("TextButton", {
		Name = "Gear",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(if touch then 46 else 38, if touch then 46 else 38),
		BackgroundColor3 = ink,
		BackgroundTransparency = 0.25,
		Text = "⚙",
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(235, 240, 250),
		AutoButtonColor = true,
		Parent = gui,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = gear })
	new("UIStroke", { Color = brass, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = gear })

	-- The card: a column of rows, sized as a share of the screen (capped on
	-- big monitors, square-ish on phones).
	local card = new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(if touch then 0.62 else 0.34, if touch then 0.86 else 0.6),
		BackgroundColor3 = ink,
		BackgroundTransparency = 0.08,
		Visible = false,
		Parent = gui,
	})
	new("UICorner", { CornerRadius = UDim.new(0.04, 0), Parent = card })
	new("UIStroke", { Color = brass, Thickness = 2, Parent = card })
	new("UISizeConstraint", { MaxSize = Vector2.new(520, 560), MinSize = Vector2.new(260, 240), Parent = card })
	new("UIPadding", {
		PaddingTop = UDim.new(0.03, 0),
		PaddingBottom = UDim.new(0.03, 0),
		PaddingLeft = UDim.new(0.05, 0),
		PaddingRight = UDim.new(0.05, 0),
		Parent = card,
	})
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0.015, 0), Parent = card })
	local rowHeight = 1 / (#OPTIONS + 2) - 0.017
	new("TextLabel", {
		LayoutOrder = 0,
		Size = UDim2.fromScale(1, rowHeight),
		BackgroundTransparency = 1,
		Text = "SETTINGS",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 215, 110),
		Parent = card,
	})

	local refreshers: { () -> () } = {}
	for i, option in OPTIONS do
		local row = new("Frame", { LayoutOrder = i, Size = UDim2.fromScale(1, rowHeight), BackgroundTransparency = 1, Parent = card })
		new("TextLabel", {
			Size = UDim2.fromScale(0.62, 0.8),
			Position = UDim2.fromScale(0, 0.1),
			BackgroundTransparency = 1,
			Text = option.Label,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(235, 240, 250),
			Parent = row,
		})
		local button = new("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0.05),
			Size = UDim2.fromScale(0.34, 0.9),
			BackgroundColor3 = Color3.fromRGB(50, 54, 68),
			Text = "",
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Parent = row,
		})
		new("UICorner", { CornerRadius = UDim.new(0.3, 0), Parent = button })
		new("UIPadding", { PaddingTop = UDim.new(0.15, 0), PaddingBottom = UDim.new(0.15, 0), Parent = button })
		local function refresh()
			button.Text = valueText(option)
			local on = values[option.Key] ~= false and values[option.Key] ~= 0
			-- Blue for on, grey for off: readable for every kind of colour
			-- vision, and the word says it anyway.
			button.BackgroundColor3 = if on then Color3.fromRGB(0, 114, 178) else Color3.fromRGB(70, 72, 84)
		end
		refresh()
		table.insert(refreshers, refresh)
		button.Activated:Connect(function()
			Settings.Set(option.Key, nextValue(option))
			refresh()
		end)
	end
	local close = new("TextButton", {
		LayoutOrder = #OPTIONS + 1,
		Size = UDim2.fromScale(1, rowHeight),
		BackgroundColor3 = brass,
		Text = "CLOSE",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = ink,
		Parent = card,
	})
	new("UICorner", { CornerRadius = UDim.new(0.3, 0), Parent = close })
	new("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0), Parent = close })

	local function toggle(open: boolean)
		card.Visible = open
		if open then
			for _, refresh in refreshers do
				refresh()
			end
		end
	end
	gear.Activated:Connect(function()
		toggle(not card.Visible)
	end)
	close.Activated:Connect(function()
		toggle(false)
	end)
end

return Settings
