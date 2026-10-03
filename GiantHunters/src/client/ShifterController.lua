--!strict
-- The titan power on this client: picking a side when you take a crystal
-- (or letting the power go), the T key (and a "Titan" button) to
-- transform, and while you're a titan, click / F to punch and G to roar
-- (these override the hunter's slash and flare). A small panel shows the
-- time left, the cooldown, and how long until the power fades.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local TouchButtons = require(script.Parent.TouchButtons)

local ShifterController = {}

local player = Players.LocalPlayer

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

local function shifted(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("Shifted") == true
end

function ShifterController.Init()
	local shiftRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Shift) :: RemoteEvent
	local gui = new("ScreenGui", { Name = "TitanPower", ResetOnSpawn = false, Parent = player:WaitForChild("PlayerGui") })
	-- Scaled down to fit small screens, like the HUD.
	local uiScales: { UIScale } = {}
	local function fit()
		local viewport = Workspace.CurrentCamera.ViewportSize
		local s = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.55, 1)
		for _, scale in uiScales do
			scale.Scale = s
		end
	end
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	-- Choosing a side (or not).
	local chooser = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(560, 250), BackgroundColor3 = Color3.fromRGB(28, 24, 40), BackgroundTransparency = 0.1, Visible = false, Parent = gui })
	table.insert(uiScales, new("UIScale", { Parent = chooser }))
	new("UICorner", { CornerRadius = UDim.new(0, 14), Parent = chooser })
	new("UIStroke", { Color = Color3.fromRGB(190, 90, 255), Thickness = 2, Parent = chooser })
	new("TextLabel", { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Text = "YOU HAVE THE TITAN POWER", Font = Enum.Font.GothamBlack, TextSize = 28, TextColor3 = Color3.fromRGB(220, 170, 255), Parent = chooser })
	new("TextLabel", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = "Whose side is your titan on?", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.fromRGB(235, 235, 245), Parent = chooser })
	local function choice(x: number, title: string, line: string, color: Color3, side: string)
		local button = new("TextButton", { Position = UDim2.fromOffset(x, 88), Size = UDim2.fromOffset(250, 100), BackgroundColor3 = color, Text = `{title}\n{line}`, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(255, 255, 255), TextWrapped = true, Parent = chooser })
		new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = button })
		button.Activated:Connect(function()
			shiftRemote:FireServer("Choose", side)
		end)
	end
	choice(20, "HUNTERS' SIDE", "Crush giants with your fists", Color3.fromRGB(50, 100, 190), "Humans")
	choice(290, "GIANTS' SIDE", "Knock hunters out - but they can cut your nape!", Color3.fromRGB(170, 50, 50), "Giants")
	local decline = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 200), Size = UDim2.fromOffset(240, 34), BackgroundColor3 = Color3.fromRGB(70, 66, 84), Text = "No thanks - stay a hunter", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.fromRGB(235, 235, 245), Parent = chooser })
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = decline })
	decline.Activated:Connect(function()
		shiftRemote:FireServer("Decline")
	end)

	-- Status line.
	local status = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(600, 30), BackgroundColor3 = Color3.fromRGB(28, 24, 40), BackgroundTransparency = 0.25, Text = "", Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = Color3.fromRGB(230, 200, 255), Visible = false, Parent = gui })
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = status })
	table.insert(uiScales, new("UIScale", { Parent = status }))
	fit()

	-- Touch screens: our own buttons, in the same spots as the hunter's
	-- (Titan above the gas; Punch where Slash is, Roar where Gas is).
	local touch = TouchButtons.Enabled()
	if touch then
		TouchButtons.Init()
		TouchButtons.Add("Titan", "Titan", "TITAN", function()
			shiftRemote:FireServer("Transform")
		end)
		TouchButtons.Add("TitanPunch", "Slash", "PUNCH", function()
			shiftRemote:FireServer("Punch")
		end)
		TouchButtons.Add("TitanRoar", "Gas", "ROAR", function()
			shiftRemote:FireServer("Roar")
		end)
	end

	-- Transform: bound while you hold the power (with a touch button).
	local bound = false
	local function onTransform(_action: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			shiftRemote:FireServer("Transform")
		end
		return Enum.ContextActionResult.Sink
	end
	-- Punch and roar: bound only while you're a titan, on top of the
	-- hunter's slash and flare.
	local fighting = false
	local function onPunch(_action: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			shiftRemote:FireServer("Punch")
		end
		return Enum.ContextActionResult.Sink
	end
	local function onRoar(_action: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			shiftRemote:FireServer("Roar")
		end
		return Enum.ContextActionResult.Sink
	end

	RunService.Heartbeat:Connect(function()
		local power = player:GetAttribute("ShifterPower") == true
		local side = player:GetAttribute("ShifterSide")
		chooser.Visible = power and side == nil
		if power and side and not bound then
			bound = true
			ContextActionService:BindAction("TitanTransform", onTransform, false, Enum.KeyCode.T, Enum.KeyCode.DPadUp)
		elseif not (power and side) and bound then
			bound = false
			ContextActionService:UnbindAction("TitanTransform")
		end
		local isTitan = shifted()
		if isTitan and not fighting then
			fighting = true
			ContextActionService:BindAction("TitanPunch", onPunch, false, Enum.KeyCode.F, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)
			ContextActionService:BindAction("TitanRoar", onRoar, false, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
		elseif not isTitan and fighting then
			fighting = false
			ContextActionService:UnbindAction("TitanPunch")
			ContextActionService:UnbindAction("TitanRoar")
		end
		if touch then
			TouchButtons.Show("Titan", bound)
			TouchButtons.Show("TitanPunch", isTitan)
			TouchButtons.Show("TitanRoar", isTitan)
		end

		local now = Workspace:GetServerTimeNow()
		local untilTime = player:GetAttribute("ShiftUntil") :: number?
		local readyAt = player:GetAttribute("ShiftReadyAt") :: number?
		local powerUntil = player:GetAttribute("PowerUntil") :: number?
		local fades = if powerUntil then `   (power fades in {math.max(math.ceil(powerUntil - now), 0)}s)` else ""
		status.Visible = power and side ~= nil
		if isTitan and untilTime then
			status.Text = if touch
				then `TITAN  {math.max(math.ceil(untilTime - now), 0)}s   -   TITAN button to change back`
				else `TITAN  {math.max(math.ceil(untilTime - now), 0)}s   -   CLICK punch   G roar   T change back`
		elseif readyAt and readyAt > now then
			status.Text = `Titan power recharging... {math.ceil(readyAt - now)}s{fades}`
		else
			status.Text = `Titan power ready ({if side == "Humans" then "hunters' side" else "giants' side"}) - {if touch then "tap TITAN" else "press T"} to transform{fades}`
		end
	end)
end

return ShifterController
