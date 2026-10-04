--!strict
-- The titan power on this client: picking a side when you take a crystal
-- (or letting the power go), the T key (and a "Titan" button) to
-- transform, and while you're a titan, click / F for the form's Primary
-- power and G for its Secondary (these override the hunter's slash and
-- flare). A small panel shows the time left, the cooldown, and how long
-- until the power fades; two power tiles show each power's cooldown; and
-- players with a titan form of their own (Config.TitanForms) see their
-- Titan Gauge fill with takedowns - full, T transforms them.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local TouchButtons = require(script.Parent.TouchButtons)

local ShifterController = {}

local player = Players.LocalPlayer
local S = Config.Shifters

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

-- The form you're in now, or the one you'd turn into.
local function currentForm(): Config.TitanForm
	local now = player:GetAttribute("TitanForm")
	if type(now) == "string" and Config.TitanForms[now] then
		return Config.TitanForms[now]
	end
	return Config.TitanFormFor(player:GetAttribute("Equip_Titan"), player:GetAttribute("Level"))
end

local function powerOf(form: Config.TitanForm, key: string): Config.TitanPower?
	for _, power in form.Powers do
		if power.Key == key then
			return power
		end
	end
	return nil
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
	local subtitle = new("TextLabel", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = "Whose side is your titan on?", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.fromRGB(235, 235, 245), Parent = chooser })
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

	-- Power tiles (while a titan): the key, the power's name, and a shade
	-- that drains away as it recharges.
	local tiles = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -158), Size = UDim2.fromOffset(330, 52), BackgroundTransparency = 1, Visible = false, Parent = gui })
	table.insert(uiScales, new("UIScale", { Parent = tiles }))
	type Tile = { Name: TextLabel, Shade: Frame, Time: TextLabel }
	local function tile(x: number, key: string): Tile
		local box = new("Frame", { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(160, 52), BackgroundColor3 = Color3.fromRGB(28, 24, 40), BackgroundTransparency = 0.2, ClipsDescendants = true, Parent = tiles })
		new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = box })
		new("UIStroke", { Color = Color3.fromRGB(190, 90, 255), Thickness = 1.5, Parent = box })
		local shade = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = box })
		new("TextLabel", { Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 18), BackgroundTransparency = 1, Text = key, Font = Enum.Font.GothamBlack, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 170, 240), Parent = box })
		local name = new("TextLabel", { Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -16, 0, 24), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(240, 235, 255), Parent = box })
		local time = new("TextLabel", { Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 18), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBlack, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(255, 220, 120), Parent = box })
		return { Name = name, Shade = shade, Time = time }
	end
	local touch = TouchButtons.Enabled()
	local primaryTile = tile(0, if touch then "HIT" else "CLICK / F")
	local secondaryTile = tile(170, if touch then "POWER" else "G")

	-- The Titan Gauge: for players with a titan form of their own.
	local gauge = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -170), Size = UDim2.fromOffset(220, 46), BackgroundColor3 = Color3.fromRGB(28, 24, 40), BackgroundTransparency = 0.2, Visible = false, Parent = gui })
	table.insert(uiScales, new("UIScale", { Parent = gauge }))
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = gauge })
	local gaugeStroke = new("UIStroke", { Color = Color3.fromRGB(190, 90, 255), Thickness = 1.5, Parent = gauge })
	local gaugeTitle = new("TextLabel", { Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -20, 0, 18), BackgroundTransparency = 1, Text = "TITAN GAUGE", Font = Enum.Font.GothamBlack, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 190, 255), Parent = gauge })
	local track = new("Frame", { Position = UDim2.fromOffset(10, 25), Size = UDim2.new(1, -20, 0, 12), BackgroundColor3 = Color3.fromRGB(60, 54, 76), BorderSizePixel = 0, Parent = gauge })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(190, 90, 255), BorderSizePixel = 0, Parent = track })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })
	fit()

	-- Touch screens: our own buttons, in the same spots as the hunter's
	-- (Titan above the gas; Primary where Slash is, Secondary where Gas is).
	local touchGui: Instance? = nil
	local function onTitanButton()
		if player:GetAttribute("ShifterPower") == true then
			shiftRemote:FireServer("Transform")
		else
			shiftRemote:FireServer("Gauge")
		end
	end
	if touch then
		TouchButtons.Init()
		TouchButtons.Add("Titan", "Titan", "TITAN", onTitanButton)
		TouchButtons.Add("TitanPunch", "Slash", "PUNCH", function()
			shiftRemote:FireServer("Primary")
		end)
		TouchButtons.Add("TitanRoar", "Gas", "ROAR", function()
			shiftRemote:FireServer("Secondary")
		end)
		touchGui = player:WaitForChild("PlayerGui"):FindFirstChild("TouchButtons")
	end
	local function touchLabel(name: string, text: string)
		local button = touchGui and touchGui:FindFirstChild(name)
		if button and button:IsA("TextButton") and button.Text ~= text then
			button.Text = text
		end
	end

	-- Pounce: the server says how fast; we leap (the character is ours).
	shiftRemote.OnClientEvent:Connect(function(action: unknown, velocity: unknown)
		if action ~= "Dash" or typeof(velocity) ~= "Vector3" or not shifted() then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and velocity.Magnitude < 250 then
			root.AssemblyLinearVelocity = velocity
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end)

	-- Transform: bound while you hold the power or your gauge is full.
	local bound = false
	local function onTransform(_action: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			onTitanButton()
		end
		return Enum.ContextActionResult.Sink
	end
	-- Powers: bound only while you're a titan, on top of the hunter's slash
	-- and flare.
	local fighting = false
	local function onPrimary(_action: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			shiftRemote:FireServer("Primary")
		end
		return Enum.ContextActionResult.Sink
	end
	local function onSecondary(_action: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			shiftRemote:FireServer("Secondary")
		end
		return Enum.ContextActionResult.Sink
	end

	local function showCooldown(t: Tile, power: Config.TitanPower?, readyAt: number?, now: number): string
		local name = if power then power.Name else "-"
		t.Name.Text = name
		local left = if readyAt then math.max(readyAt - now, 0) else 0
		local total = if power then power.Cooldown else 1
		t.Shade.Size = UDim2.fromScale(1, math.clamp(left / math.max(total, 0.1), 0, 1))
		t.Time.Text = if left > 0.05 then string.format("%.1fs", left) else "READY"
		return if left > 0.05 then `{math.ceil(left)}s` else string.upper(name)
	end

	RunService.Heartbeat:Connect(function()
		local power = player:GetAttribute("ShifterPower") == true
		local side = player:GetAttribute("ShifterSide")
		local isTitan = shifted()
		local form = currentForm()
		local hasForm = form.Id ~= "Default"
		local gaugeValue = (player:GetAttribute("TitanGauge") :: number?) or 0
		local gaugeReady = not power and hasForm and gaugeValue >= S.GaugeMax
		chooser.Visible = power and side == nil
		if chooser.Visible then
			subtitle.Text = `Whose side is your {form.Display} on?`
		end
		local canTransform = (power and side ~= nil) or gaugeReady
		if canTransform and not bound then
			bound = true
			ContextActionService:BindAction("TitanTransform", onTransform, false, Enum.KeyCode.T, Enum.KeyCode.DPadUp)
		elseif not canTransform and bound then
			bound = false
			ContextActionService:UnbindAction("TitanTransform")
		end
		if isTitan and not fighting then
			fighting = true
			ContextActionService:BindAction("TitanPunch", onPrimary, false, Enum.KeyCode.F, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)
			ContextActionService:BindAction("TitanRoar", onSecondary, false, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
		elseif not isTitan and fighting then
			fighting = false
			ContextActionService:UnbindAction("TitanPunch")
			ContextActionService:UnbindAction("TitanRoar")
		end

		local now = Workspace:GetServerTimeNow()
		local primary, secondary = powerOf(form, "Primary"), powerOf(form, "Secondary")
		tiles.Visible = isTitan
		if isTitan then
			local a = showCooldown(primaryTile, primary, player:GetAttribute("TitanPrimaryReadyAt") :: number?, now)
			local b = showCooldown(secondaryTile, secondary, player:GetAttribute("TitanSecondaryReadyAt") :: number?, now)
			if touch then
				touchLabel("TitanPunch", a)
				touchLabel("TitanRoar", b)
			end
		end
		if touch then
			TouchButtons.Show("Titan", bound)
			TouchButtons.Show("TitanPunch", isTitan)
			TouchButtons.Show("TitanRoar", isTitan)
		end

		-- The gauge: only for a form of your own, and not while you hold
		-- the crystal's power.
		gauge.Visible = hasForm and not power
		if gauge.Visible then
			local ratio = math.clamp(gaugeValue / S.GaugeMax, 0, 1)
			fill.Size = UDim2.fromScale(ratio, 1)
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 6)
			fill.BackgroundColor3 = if gaugeReady then Color3.fromRGB(190, 90, 255):Lerp(Color3.fromRGB(255, 230, 140), pulse) else Color3.fromRGB(190, 90, 255)
			gaugeStroke.Color = if gaugeReady then Color3.fromRGB(255, 230, 140) else Color3.fromRGB(190, 90, 255)
			gaugeTitle.Text = if gaugeReady
				then `{string.upper(form.Display)} READY - {if touch then "tap TITAN" else "press T"}`
				else `TITAN GAUGE  {math.floor(ratio * 100)}%  ({form.Display})`
		end

		local untilTime = player:GetAttribute("ShiftUntil") :: number?
		local readyAt = player:GetAttribute("ShiftReadyAt") :: number?
		local powerUntil = player:GetAttribute("PowerUntil") :: number?
		local fades = if powerUntil then `   (power fades in {math.max(math.ceil(powerUntil - now), 0)}s)` else ""
		status.Visible = power and side ~= nil
		if isTitan and untilTime then
			local left = math.max(math.ceil(untilTime - now), 0)
			status.Text = if touch
				then `{string.upper(form.Display)}  {left}s   -   TITAN button to change back`
				else `{string.upper(form.Display)}  {left}s   -   CLICK {if primary then primary.Name else ""}   G {if secondary then secondary.Name else ""}   T change back`
		elseif readyAt and readyAt > now then
			status.Text = `Titan power recharging... {math.ceil(readyAt - now)}s{fades}`
		else
			status.Text = `Titan power ready ({if side == "Humans" then "hunters' side" else "giants' side"}) - {if touch then "tap TITAN" else "press T"} to transform{fades}`
		end
	end)
end

return ShifterController
