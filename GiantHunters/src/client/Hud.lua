--!strict
-- The hunter's HUD, styled after the gear in the stories:
--   * the crosshair, green when a hook would land, with left/right hook
--     marks either side (yellow flying, green hooked);
--   * the gear panel: two gas tanks, two boxes of blades, your speed, your
--     points and rank;
--   * "SLASH!" / "TRIP" / "DAZE" hints when a cut is in reach;
--   * the round and wave banner, big announcements, a kill feed, a combo
--     counter, feedback toasts;
--   * the radar (Radar.lua);
--   * GRABBED! (mash to wriggle free), SWATTED!, and the Caught screen.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Radar = require(script.Parent.Radar)
local Effects = require(script.Parent.Effects)

local Hud = {}

local player = Players.LocalPlayer

local TONES = {
	Info = Color3.fromRGB(235, 240, 250),
	Good = Color3.fromRGB(140, 235, 160),
	Danger = Color3.fromRGB(255, 120, 100),
	Gold = Color3.fromRGB(255, 215, 110),
}
local INK = Color3.fromRGB(22, 24, 32)
local PANEL = Color3.fromRGB(28, 30, 40)
local BRASS = Color3.fromRGB(190, 170, 120)

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

local function corner(parent: Instance, radius: number?)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBlack
	props.TextColor3 = props.TextColor3 or TONES.Info
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0.5
	return new("TextLabel", props)
end

local gui: ScreenGui
local crosshair: Frame
local hookMarks: { [string]: TextLabel } = {}
local gasFills: { Frame } = {}
local bladeIcons: { Frame } = {}
local speedLabel: TextLabel
local rankLabel: TextLabel
local hintLabel: TextLabel
local waveLabel: TextLabel
local announceTitle: TextLabel
local announceSub: TextLabel
local toastLabel: TextLabel
local comboLabel: TextLabel
local comboBar: Frame
local feedList: Frame
local caughtFrame: Frame
local grabFrame: Frame
local grabBar: Frame
local grabTimer: Frame
local flash: Frame

local toastToken = 0
local announceToken = 0
local comboUntil = 0
local comboWindow = Config.Hunters.ComboWindow
local blades = Config.Blades.Max
local grabbed = false
local grabStarted = 0
local grabTime = Config.Giants.HoldTime
local grabNeeded = Config.Giants.StruggleToEscape
local wriggles = 0
local lastWriggle = 0

function Hud.Toast(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or TONES.Info
	toastLabel.TextTransparency = 0
	toastLabel.TextStrokeTransparency = 0.3
	toastLabel.Size = UDim2.fromOffset(520, 56)
	TweenService:Create(toastLabel, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(580, 64) }):Play()
	task.delay(1.4, function()
		if token == toastToken then
			TweenService:Create(toastLabel, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

function Hud.Announce(title: string, subtitle: string, tone: string)
	announceToken += 1
	local token = announceToken
	local color = (TONES :: any)[tone] or TONES.Info
	announceTitle.Text = title
	announceTitle.TextColor3 = color
	announceSub.Text = subtitle
	for _, l in { announceTitle, announceSub } do
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.35
	end
	announceTitle.Position = UDim2.new(0.5, 0, 0.2, -20)
	TweenService:Create(announceTitle, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0.2, 0) }):Play()
	task.delay(3.2, function()
		if token == announceToken then
			for _, l in { announceTitle, announceSub } do
				TweenService:Create(l, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
	end)
end

function Hud.Feed(text: string, tone: string)
	local line = label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = (TONES :: any)[tone] or TONES.Info,
		TextStrokeTransparency = 0.4,
		LayoutOrder = -math.floor(os.clock() * 100),
		Parent = feedList,
	})
	local lines = {}
	for _, child in feedList:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	if #lines > 6 then
		table.sort(lines, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		lines[1]:Destroy() -- the oldest
	end
	task.delay(7, function()
		if line.Parent then
			TweenService:Create(line, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.9, function()
				line:Destroy()
			end)
		end
	end)
end

local function setBlades(count: number)
	blades = count
	for i, icon in bladeIcons do
		icon.BackgroundColor3 = if i <= count then Color3.fromRGB(215, 230, 245) else Color3.fromRGB(60, 62, 72)
	end
end

local function build()
	gui = new("ScreenGui", { Name = "HunterHud", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })

	-- Crosshair with hook marks.
	crosshair = new("Frame", { Name = "Crosshair", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.15, Parent = gui })
	corner(crosshair, 5)
	new("UIStroke", { Color = INK, Thickness = 1.5, Parent = crosshair })
	for _, name in { "Left", "Right" } do
		local x = if name == "Left" then -22 else 22
		hookMarks[name] = label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, 0),
			Size = UDim2.fromOffset(14, 26),
			Text = if name == "Left" then "[" else "]",
			TextSize = 26,
			Parent = crosshair,
		})
	end
	hintLabel = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 14), Size = UDim2.fromOffset(220, 24), Text = "", TextSize = 20, Parent = crosshair })

	-- The gear panel, bottom centre: tank | blades | speed | blades | tank.
	local panel = new("Frame", { Name = "Gear", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(420, 92), BackgroundColor3 = PANEL, BackgroundTransparency = 0.2, Parent = gui })
	corner(panel, 14)
	new("UIStroke", { Color = BRASS, Thickness = 2, Parent = panel })
	for i, x in { 14, 420 - 14 - 30 } do
		local tank = new("Frame", { Position = UDim2.fromOffset(x, 12), Size = UDim2.fromOffset(30, 68), BackgroundColor3 = Color3.fromRGB(48, 52, 64), Parent = panel })
		corner(tank, 10)
		new("UIStroke", { Color = Color3.fromRGB(150, 160, 175), Thickness = 1.5, Parent = tank })
		local fill = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 215, 255), Parent = tank })
		corner(fill, 10)
		gasFills[i] = fill
		label({ Position = UDim2.fromOffset(0, 26), Size = UDim2.fromOffset(30, 16), Text = "GAS", TextSize = 10, Parent = tank })
	end
	-- Blade boxes: four blades each side of the speed readout.
	for box = 0, 1 do
		for slot = 1, 4 do
			local index = box * 4 + slot
			local x = if box == 0 then 58 + (slot - 1) * 16 else 420 - 58 - 16 * 4 + (slot - 1) * 16 + 4
			local icon = new("Frame", { Position = UDim2.fromOffset(x, 20), Size = UDim2.fromOffset(7, 52), BackgroundColor3 = Color3.fromRGB(215, 230, 245), Rotation = 14, Parent = panel })
			corner(icon, 2)
			bladeIcons[index] = icon
		end
	end
	speedLabel = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(110, 40), Text = "0", TextSize = 38, Parent = panel })
	label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.fromOffset(110, 14), Text = "SPEED", TextSize = 12, TextColor3 = BRASS, Parent = panel })
	rankLabel = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(160, 18), Text = "RECRUIT  -  0 PTS", Font = Enum.Font.GothamBold, TextSize = 13, Parent = panel })

	-- Round / wave banner and announcements.
	waveLabel = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(520, 38), BackgroundTransparency = 0.25, BackgroundColor3 = PANEL, Text = "", TextSize = 20, TextColor3 = TONES.Gold, Parent = gui })
	corner(waveLabel, 12)
	new("UIStroke", { Color = BRASS, Thickness = 1.5, Parent = waveLabel })
	announceTitle = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.2, 0), Size = UDim2.fromOffset(900, 64), Text = "", TextScaled = true, TextTransparency = 1, TextStrokeTransparency = 1, Parent = gui })
	announceSub = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.2, 48), Size = UDim2.fromOffset(900, 28), Text = "", TextSize = 22, Font = Enum.Font.GothamBold, TextTransparency = 1, TextStrokeTransparency = 1, Parent = gui })
	toastLabel = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 0), Size = UDim2.fromOffset(520, 56), Text = "", TextScaled = true, TextTransparency = 1, TextStrokeTransparency = 1, Parent = gui })

	-- Kill feed, top right.
	feedList = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 100), Size = UDim2.fromOffset(440, 170), BackgroundTransparency = 1, Parent = gui })
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = feedList })

	-- Combo, right of centre.
	comboLabel = label({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 150, 0.5, -40), Size = UDim2.fromOffset(220, 48), Text = "", TextSize = 40, TextColor3 = TONES.Gold, TextXAlignment = Enum.TextXAlignment.Left, Parent = gui })
	local comboBack = new("Frame", { Position = UDim2.new(0, 0, 1, 2), Size = UDim2.fromOffset(150, 6), BackgroundColor3 = Color3.fromRGB(60, 60, 70), Parent = comboLabel })
	corner(comboBack, 3)
	comboBar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = TONES.Gold, Parent = comboBack })
	corner(comboBar, 3)

	-- Grabbed: red edges, mash prompt, wriggle and time bars.
	grabFrame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 20, 20), BackgroundTransparency = 0.7, Visible = false, Parent = gui })
	label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(700, 70), Text = "GRABBED!", TextScaled = true, TextColor3 = TONES.Danger, Parent = grabFrame })
	label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 56),
		Size = UDim2.fromOffset(700, 30),
		Text = if UserInputService.TouchEnabled then "TAP FAST to wriggle free!" else "MASH F / SPACE / CLICK to wriggle free!",
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		Parent = grabFrame,
	})
	local grabBack = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 100), Size = UDim2.fromOffset(360, 18), BackgroundColor3 = Color3.fromRGB(40, 30, 30), Parent = grabFrame })
	corner(grabBack, 9)
	grabBar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = TONES.Good, Parent = grabBack })
	corner(grabBar, 9)
	local timerBack = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 124), Size = UDim2.fromOffset(360, 6), BackgroundColor3 = Color3.fromRGB(40, 30, 30), Parent = grabFrame })
	grabTimer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = TONES.Danger, Parent = timerBack })

	caughtFrame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(30, 20, 40), BackgroundTransparency = 0.35, Visible = false, Parent = gui })
	label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(700, 120),
		Text = "CAUGHT!\nStay high, attack from behind, and mash to wriggle free.",
		TextScaled = true,
		TextColor3 = TONES.Gold,
		Parent = caughtFrame,
	})
	flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1, Parent = gui })

	-- Controls card (hidden on touch, where the buttons speak for themselves).
	if not UserInputService.TouchEnabled then
		local help = label({
			Position = UDim2.new(0, 16, 1, -236),
			Size = UDim2.fromOffset(420, 218),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.3,
			Text = "  Purple crystal = TITAN POWER (T to transform)\n  HOLD Q / E - left / right hook, then swing\n  HOLD SPACE - reel in (hooked) / gas (in the air)\n  SHIFT - gas dash      G - signal flare\n  CLICK or F - slash with both blades (spins in the air)\n  NECK = takedown   EYES = daze   ANKLES = trip\n  Attack from BEHIND - giants can't see you there\n  Grabbed? MASH to wriggle free!\n  Blue beams - resupply    Wall cannons - by the gate",
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextStrokeTransparency = 1,
			Parent = gui,
		})
		corner(help, 10)
		task.delay(60, function()
			TweenService:Create(help, TweenInfo.new(1), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		end)
	end
end

local RESULTS = {
	Hit = function(info: any)
		if info.Clean then
			Hud.Toast("CLEAN CUT!", Color3.fromRGB(140, 230, 255))
		else
			Hud.Toast("Hit! Go faster for a clean cut", TONES.Info)
		end
	end,
	Defeated = function(info: any)
		Hud.Toast(`{string.upper(info.Kind or "Giant")} DOWN!`, TONES.Gold)
	end,
	Armor = function(info: any)
		Hud.Toast(`ARMOR CRACKING - {info.Remaining or 1} MORE`, Color3.fromRGB(210, 205, 190))
	end,
	ArmorBroken = function(_info: any)
		Hud.Toast("ARMOR BROKEN! Now the nape!", TONES.Gold)
	end,
	Trip = function(_info: any)
		Hud.Toast("TRIPPED! It's on its knees!", TONES.Good)
	end,
	Daze = function(_info: any)
		Hud.Toast("DAZED! Get behind it!", TONES.Good)
	end,
}

-- The nearest cut in reach, for the hint under the crosshair.
local function cutInReach(here: Vector3): string?
	local reach = Config.Blades.SlashRange
	local found: string? = nil
	for _, giant in CollectionService:GetTagged(Config.Tags.Giant) do
		-- (Titans on the hunters' side can't be cut, and neither can your own.)
		local friendlyTitan = giant:GetAttribute("Shifter") ~= nil and (giant:GetAttribute("Side") ~= "Giants" or giant:GetAttribute("Shifter") == player.UserId)
		if giant:IsA("Model") and not giant:GetAttribute("Defeated") and not giant:GetAttribute("Event") and not friendlyTitan then
			local head = giant:FindFirstChild("Head")
			local root = giant:FindFirstChild("Root")
			local inFront = false
			if head and head:IsA("BasePart") and root and root:IsA("BasePart") then
				local toHere = here - head.Position
				inFront = toHere.Magnitude > 0.01 and toHere.Unit:Dot(root.CFrame.LookVector) > Config.Cuts.EyesFrontDot
				if inFront and toHere.Magnitude <= reach + head.Size.X / 2 then
					found = "DAZE (eyes)"
				end
			end
			local nape = giant:FindFirstChild("Nape")
			if not inFront and nape and nape:IsA("BasePart") and (nape.Position - here).Magnitude <= reach + nape.Size.X / 2 then
				return if (giant:GetAttribute("Armor") :: number? or 0) > 0 then "CRACK THE ARMOR!" else "SLASH THE NAPE!"
			end
			if not found and not giant:GetAttribute("Kneeling") then
				for _, footName in { "LeftFoot", "RightFoot" } do
					local foot = giant:FindFirstChild(footName)
					if foot and foot:IsA("BasePart") and (foot.Position - here).Magnitude <= reach + foot.Size.Z / 2 then
						found = "TRIP (ankle)"
					end
				end
			end
		end
	end
	return found
end

function Hud.Init(grapple: any)
	build()
	Radar.Init(gui)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local function remote(name: string): RemoteEvent
		return remotes:WaitForChild(name) :: RemoteEvent
	end

	setBlades(Config.Blades.Max)
	remote(Config.Remotes.State).OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		setBlades(state.Blades or blades)
		rankLabel.Text = `{string.upper(state.Rank or "Recruit")}  -  {state.Points or 0} PTS`
		if (state.Combo or 0) >= 2 and (state.ComboLeft or 0) > 0 then
			comboUntil = os.clock() + state.ComboLeft
			comboLabel.Text = `x{state.Combo} COMBO`
			comboLabel.Size = UDim2.fromOffset(200, 40)
			TweenService:Create(comboLabel, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(220, 48) }):Play()
		end
	end)

	remote(Config.Remotes.SlashResult).OnClientEvent:Connect(function(result, info)
		info = if type(info) == "table" then info else {}
		local handler = (RESULTS :: any)[result]
		if handler then
			handler(info)
		elseif result == "Dull" then
			Hud.Toast("Blades dull - find a supply crate!", Color3.fromRGB(255, 140, 120))
		end
		if typeof(info.Position) == "Vector3" then
			local color = if result == "Armor" or result == "ArmorBroken" then Color3.fromRGB(200, 195, 180) else Color3.fromRGB(245, 245, 250)
			Effects.Burst(info.Position, color, if result == "Defeated" then 4 else 2.5, if result == "Defeated" then 40 else 18)
		end
		if info.Rescued then
			Hud.Toast(`You cut {info.Rescued} loose!`, TONES.Good)
		end
	end)

	remote(Config.Remotes.Caught).OnClientEvent:Connect(function()
		caughtFrame.Visible = true
		task.delay(Players.RespawnTime + 0.5, function()
			caughtFrame.Visible = false
		end)
	end)

	remote(Config.Remotes.Resupplied).OnClientEvent:Connect(function()
		Hud.Toast("Resupplied!", Color3.fromRGB(140, 230, 255))
	end)

	remote(Config.Remotes.Held).OnClientEvent:Connect(function(state: string, info: any)
		if state == "Grabbed" then
			grabbed = true
			grabStarted = os.clock()
			wriggles = 0
			if type(info) == "table" then
				grabTime = info.Time or grabTime
				grabNeeded = info.Needed or grabNeeded
			end
			grabFrame.Visible = true
			Effects.Shake(0.6)
		else
			grabbed = false
			grabFrame.Visible = false
			if info == "Escaped" then
				Hud.Toast("YOU BROKE FREE!", TONES.Good)
			elseif info == "Rescued" then
				Hud.Toast("RESCUED!", TONES.Good)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, _processed)
		if not grabbed then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.Gamepad1 then
			local now = os.clock()
			if now - lastWriggle >= 1 / Config.Hunters.StruggleRate then
				lastWriggle = now
				wriggles += 1
			end
		end
	end)

	remote(Config.Remotes.Knocked).OnClientEvent:Connect(function()
		Hud.Toast("SWATTED! Attack from behind!", TONES.Danger)
		flash.BackgroundTransparency = 0.4
		TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	end)

	remote(Config.Remotes.Feed).OnClientEvent:Connect(function(text: string, tone: string)
		Hud.Feed(text, tone)
	end)
	remote(Config.Remotes.Announce).OnClientEvent:Connect(function(title: string, subtitle: string, tone: string)
		Hud.Announce(title, subtitle, tone)
	end)

	remote(Config.Remotes.Wave).OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then
			return
		end
		local round = `ROUND {info.Round}`
		if info.Phase == "Intermission" then
			waveLabel.Text = if info.Wave == 0 then `{round}  -  THE GIANTS COME IN {info.Countdown}...` else `{round}  -  WAVE {info.Wave + 1} IN {info.Countdown}...`
		elseif info.Phase == "Breach" then
			waveLabel.Text = `{round}  -  SOMETHING IS AT THE GATE...`
		elseif info.Phase == "Victory" then
			waveLabel.Text = `{round}  -  DISTRICT SAVED!`
		else
			waveLabel.Text = `{round}  -  WAVE {info.Wave}/{info.Waves}  -  {info.Alive} GIANT{if info.Alive == 1 then "" else "S"} LEFT`
		end
	end)

	-- Every frame: crosshair, hook marks, gas, speed, hints, combo, grab bars.
	local hookColors = { Idle = Color3.fromRGB(150, 155, 165), Flying = Color3.fromRGB(255, 220, 90), Attached = Color3.fromRGB(120, 255, 150) }
	local hintTimer = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local location = UserInputService:GetMouseLocation()
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.TouchEnabled then
			local size = Workspace.CurrentCamera.ViewportSize
			location = Vector2.new(size.X / 2, size.Y / 2)
		end
		crosshair.Position = UDim2.fromOffset(location.X, location.Y)
		local inRange = grapple.AimTarget(0) ~= nil
		crosshair.BackgroundColor3 = if inRange then Color3.fromRGB(120, 255, 150) else Color3.fromRGB(255, 255, 255)
		local left, right = grapple.HookStates()
		hookMarks.Left.TextColor3 = (hookColors :: any)[left] or hookColors.Idle
		hookMarks.Right.TextColor3 = (hookColors :: any)[right] or hookColors.Idle

		local ratio = math.clamp(grapple.Gas() / Config.Grapple.GasMax, 0, 1)
		for _, fill in gasFills do
			fill.Size = UDim2.fromScale(1, ratio)
			fill.BackgroundColor3 = if ratio > 0.25 then Color3.fromRGB(120, 215, 255) else Color3.fromRGB(255, 150, 110)
		end
		local speed = grapple.Speed()
		speedLabel.Text = tostring(math.floor(speed))
		speedLabel.TextColor3 = if speed >= Config.Hunters.SpeedKill then TONES.Gold elseif speed >= Config.Blades.CleanCutSpeed then Color3.fromRGB(140, 230, 255) else TONES.Info

		hintTimer += dt
		if hintTimer > 0.1 then
			hintTimer = 0
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local hint = if root and root:IsA("BasePart") and not grabbed then cutInReach(root.Position) else nil
			hintLabel.Text = hint or ""
			hintLabel.TextColor3 = if hint and string.find(hint, "NAPE") then TONES.Danger elseif hint then TONES.Good else TONES.Info
		end

		local comboLeft = comboUntil - os.clock()
		comboLabel.Visible = comboLeft > 0
		comboBar.Size = UDim2.fromScale(math.clamp(comboLeft / comboWindow, 0, 1), 1)

		if grabbed then
			grabBar.Size = UDim2.fromScale(math.clamp(wriggles / grabNeeded, 0, 1), 1)
			grabTimer.Size = UDim2.fromScale(math.clamp(1 - (os.clock() - grabStarted) / grabTime, 0, 1), 1)
		end
	end)
end

return Hud
