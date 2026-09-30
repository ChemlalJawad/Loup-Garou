--!strict
-- The hunter's HUD: crosshair (green when a hook would land), gas bar,
-- blade pips, the wave banner, big feedback toasts, a "Caught!" screen and
-- a controls card for new players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local Hud = {}

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

local function corner(parent: Instance, radius: number?)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

local gui: ScreenGui
local crosshair: Frame
local gasFill: Frame
local bladesLabel: TextLabel
local waveLabel: TextLabel
local toastLabel: TextLabel
local caughtFrame: Frame
local toastToken = 0

function Hud.Toast(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	toastLabel.TextTransparency = 0
	toastLabel.TextStrokeTransparency = 0.3
	toastLabel.Size = UDim2.new(0, 520, 0, 64)
	TweenService:Create(toastLabel, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Size = UDim2.new(0, 560, 0, 70) }):Play()
	task.delay(1.4, function()
		if token == toastToken then
			TweenService:Create(toastLabel, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local function build()
	gui = new("ScreenGui", {
		Name = "HunterHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = player:WaitForChild("PlayerGui"),
	})

	crosshair = new("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	corner(crosshair, 6)
	new("UIStroke", { Color = Color3.fromRGB(20, 20, 30), Thickness = 1.5, Parent = crosshair })

	-- Gas bar + blades, bottom centre.
	local panel = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0, 360, 0, 58),
		BackgroundColor3 = Color3.fromRGB(25, 28, 40),
		BackgroundTransparency = 0.25,
		Parent = gui,
	})
	corner(panel, 12)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 4),
		Size = UDim2.new(0, 60, 0, 22),
		Text = "GAS",
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(180, 220, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	local gasBack = new("Frame", {
		Position = UDim2.new(0, 12, 0, 28),
		Size = UDim2.new(1, -24, 0, 16),
		BackgroundColor3 = Color3.fromRGB(50, 55, 70),
		Parent = panel,
	})
	corner(gasBack, 8)
	gasFill = new("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(110, 210, 255),
		Parent = gasBack,
	})
	corner(gasFill, 8)
	bladesLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 4),
		Size = UDim2.new(0, 220, 0, 22),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(230, 235, 245),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})

	waveLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.new(0, 420, 0, 40),
		BackgroundColor3 = Color3.fromRGB(25, 28, 40),
		BackgroundTransparency = 0.25,
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 225, 140),
		Parent = gui,
	})
	corner(waveLabel, 12)

	toastLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.32, 0),
		Size = UDim2.new(0, 520, 0, 64),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = gui,
	})

	caughtFrame = new("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(30, 20, 40),
		BackgroundTransparency = 0.35,
		Visible = false,
		Parent = gui,
	})
	new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 600, 0, 120),
		BackgroundTransparency = 1,
		Text = "CAUGHT!\nStay high - giants can't reach the rooftops.",
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 210, 120),
		Parent = caughtFrame,
	})

	-- Controls card (hidden on touch, where the buttons speak for themselves).
	if not UserInputService.TouchEnabled then
		local help = new("TextLabel", {
			Position = UDim2.new(0, 16, 1, -176),
			Size = UDim2.new(0, 380, 0, 152),
			BackgroundColor3 = Color3.fromRGB(25, 28, 40),
			BackgroundTransparency = 0.3,
			Text = "  HOLD Q / E - left / right hook, then swing\n  HOLD SPACE - reel in (hooked) / gas (in the air)\n  SHIFT - gas dash\n  CLICK or F - slash with both blades (spins in the air)\n  Aim for the GLOWING NECK!\n  Crates with blue beams - resupply",
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(235, 240, 250),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = gui,
		})
		corner(help, 10)
		task.delay(45, function()
			TweenService:Create(help, TweenInfo.new(1), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		end)
	end
end

function Hud.Init(grapple: any)
	build()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local function remote(name: string): RemoteEvent
		return remotes:WaitForChild(name) :: RemoteEvent
	end

	remote(Config.Remotes.State).OnClientEvent:Connect(function(state)
		if type(state) == "table" then
			bladesLabel.Text = `BLADES {state.Blades}/{state.MaxBlades}`
			bladesLabel.TextColor3 = if state.Blades > 0 then Color3.fromRGB(230, 235, 245) else Color3.fromRGB(255, 120, 110)
		end
	end)
	bladesLabel.Text = `BLADES {Config.Blades.Max}/{Config.Blades.Max}`

	remote(Config.Remotes.SlashResult).OnClientEvent:Connect(function(result, info)
		if result == "Hit" then
			if info == "Clean" then
				Hud.Toast("CLEAN CUT!", Color3.fromRGB(140, 230, 255))
			else
				Hud.Toast("Hit! Go faster for a clean cut", Color3.fromRGB(230, 230, 230))
			end
		elseif result == "Defeated" then
			Hud.Toast("GIANT DOWN!", Color3.fromRGB(255, 220, 90))
		elseif result == "Dull" then
			Hud.Toast("Blades dull - find a supply crate!", Color3.fromRGB(255, 140, 120))
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

	remote(Config.Remotes.Wave).OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then
			return
		end
		if info.Phase == "Intermission" then
			waveLabel.Text = `WAVE {info.Wave} IN {info.Countdown}...`
		else
			waveLabel.Text = `WAVE {info.Wave} - {info.Alive} GIANT{if info.Alive == 1 then "" else "S"} LEFT`
		end
	end)

	-- Crosshair + gas bar, every frame.
	RunService.RenderStepped:Connect(function()
		local location = UserInputService:GetMouseLocation()
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.TouchEnabled then
			local size = workspace.CurrentCamera.ViewportSize
			location = Vector2.new(size.X / 2, size.Y / 2)
		end
		crosshair.Position = UDim2.new(0, location.X, 0, location.Y)
		local inRange = grapple.AimTarget(0) ~= nil
		crosshair.BackgroundColor3 = if inRange then Color3.fromRGB(120, 255, 150) else Color3.fromRGB(255, 255, 255)
		local ratio = math.clamp(grapple.Gas() / Config.Grapple.GasMax, 0, 1)
		gasFill.Size = UDim2.new(ratio, 0, 1, 0)
		gasFill.BackgroundColor3 = if ratio > 0.25 then Color3.fromRGB(110, 210, 255) else Color3.fromRGB(255, 150, 110)
	end)
end

return Hud
