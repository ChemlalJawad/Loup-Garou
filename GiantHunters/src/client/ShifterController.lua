--!strict
-- The titan power on this client: picking a side when you take a crystal,
-- the T key (and a "Titan" button) to transform, and while you're a titan,
-- click / F to punch and G to roar (these override the hunter's slash and
-- flare). A small panel shows the time left and the cooldown.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

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

	-- Choosing a side.
	local chooser = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(560, 210), BackgroundColor3 = Color3.fromRGB(28, 24, 40), BackgroundTransparency = 0.1, Visible = false, Parent = gui })
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

	-- Status line.
	local status = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(560, 30), BackgroundColor3 = Color3.fromRGB(28, 24, 40), BackgroundTransparency = 0.25, Text = "", Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = Color3.fromRGB(230, 200, 255), Visible = false, Parent = gui })
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = status })

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
			ContextActionService:BindAction("TitanTransform", onTransform, true, Enum.KeyCode.T, Enum.KeyCode.DPadUp)
			ContextActionService:SetTitle("TitanTransform", "Titan")
		elseif not (power and side) and bound then
			bound = false
			ContextActionService:UnbindAction("TitanTransform")
		end
		local isTitan = shifted()
		if isTitan and not fighting then
			fighting = true
			ContextActionService:BindAction("TitanPunch", onPunch, true, Enum.KeyCode.F, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)
			ContextActionService:SetTitle("TitanPunch", "Punch")
			ContextActionService:BindAction("TitanRoar", onRoar, true, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
			ContextActionService:SetTitle("TitanRoar", "Roar")
		elseif not isTitan and fighting then
			fighting = false
			ContextActionService:UnbindAction("TitanPunch")
			ContextActionService:UnbindAction("TitanRoar")
		end

		local now = Workspace:GetServerTimeNow()
		local untilTime = player:GetAttribute("ShiftUntil") :: number?
		local readyAt = player:GetAttribute("ShiftReadyAt") :: number?
		status.Visible = power and side ~= nil
		if isTitan and untilTime then
			status.Text = `TITAN  {math.max(math.ceil(untilTime - now), 0)}s   -   CLICK punch   G roar   T change back`
		elseif readyAt and readyAt > now then
			status.Text = `Titan power recharging... {math.ceil(readyAt - now)}s`
		else
			status.Text = `Titan power ready ({if side == "Humans" then "hunters' side" else "giants' side"}) - press T to transform`
		end
	end)
end

return ShifterController
