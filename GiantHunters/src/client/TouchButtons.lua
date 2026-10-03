--!strict
-- On-screen buttons for phones and tablets, laid out round the jump button
-- (bottom right) so the right thumb reaches all of them and none overlap,
-- whatever the screen. Sized from the screen's short side, and re-laid out
-- when it changes (rotating a tablet).
--
-- Each button is pressed and released like a key: `onDown` on touch,
-- `onUp` when that finger lifts (even if it slid off the button).
-- Nothing is created on devices without a touch screen.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local TouchButtons = {}

-- Slots: centre offsets from the bottom-right corner, and diameters, in
-- units of the screen's short side (see layout). The jump button sits in
-- the corner itself.
type Slot = { X: number, Y: number, Size: number }
local SLOTS: { [string]: Slot } = {
	Slash = { X = -2.55, Y = -0.95, Size = 1.2 },
	HookLeft = { X = -3.9, Y = -1.35, Size = 1 },
	HookRight = { X = -3.4, Y = -2.55, Size = 1 },
	Gas = { X = -2.1, Y = -2.45, Size = 1 },
	Dash = { X = -0.85, Y = -2.85, Size = 0.9 },
	Flare = { X = -0.85, Y = -3.95, Size = 0.75 },
	Titan = { X = -2.05, Y = -3.7, Size = 0.85 },
}

type Button = { Gui: TextButton, Slot: Slot, Shown: boolean }

local gui: ScreenGui? = nil
local buttons: { [string]: Button } = {}

local function layout()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	-- One unit: a comfortable thumb target on a phone, not huge on a tablet.
	local unit = math.clamp(math.min(viewport.X, viewport.Y) * 0.135, 44, 92)
	for _, button in buttons do
		local slot = button.Slot
		button.Gui.Size = UDim2.fromOffset(unit * slot.Size, unit * slot.Size)
		button.Gui.Position = UDim2.new(1, unit * slot.X, 1, unit * slot.Y)
		button.Gui.TextSize = math.floor(unit * 0.24)
	end
end

function TouchButtons.Enabled(): boolean
	return UserInputService.TouchEnabled
end

-- Adds a button in `slot` (one of SLOTS; a slot can hold several buttons
-- as long as only one is shown at a time).
function TouchButtons.Add(name: string, slotName: string, title: string, onDown: () -> (), onUp: (() -> ())?)
	local screen = gui
	local slot = SLOTS[slotName]
	if not screen or not slot then
		return
	end
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	button.BackgroundTransparency = 0.35
	button.Text = title
	button.TextColor3 = Color3.fromRGB(235, 240, 250)
	button.Font = Enum.Font.GothamBlack
	button.TextWrapped = true
	button.AutoButtonColor = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(190, 170, 120)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	button.Parent = screen

	local pressing: InputObject? = nil
	button.InputBegan:Connect(function(input)
		if pressing or (input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1) then
			return
		end
		pressing = input
		button.BackgroundTransparency = 0.1
		onDown()
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == pressing then
			pressing = nil
			button.BackgroundTransparency = 0.35
			if onUp then
				onUp()
			end
		end
	end)
	buttons[name] = { Gui = button, Slot = slot, Shown = true }
	layout()
end

function TouchButtons.Show(name: string, shown: boolean)
	local button = buttons[name]
	if button and button.Shown ~= shown then
		button.Shown = shown
		button.Gui.Visible = shown
	end
end

function TouchButtons.Init()
	if not UserInputService.TouchEnabled or gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "TouchButtons"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 5
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
end

return TouchButtons
