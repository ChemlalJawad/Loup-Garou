--!strict
-- The worn technique (the "Equip_Technique" attribute; Config.Catalog): V on
-- a keyboard, R2 on a gamepad, the "SKILL" button on a touch screen.
--
-- A press asks the server (TechniqueService) with the point under the
-- crosshair; only on its "Go" does anything happen here: the dashes (Gale
-- Burst, Whirlwind Cut) move the hunter, Second Wind fills the tank, and
-- the cooldown ring starts. A small widget of its own, right of the screen:
-- the technique's name, a ring of dots that fills back up, the seconds left
-- and the key.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local TouchButtons = require(script.Parent.TouchButtons)

local TechniqueController = {}

local player = Players.LocalPlayer

local DOTS = 24
local READY = Color3.fromRGB(214, 186, 120)
local WAITING = Color3.fromRGB(70, 72, 82)
local TEXT = Color3.fromRGB(236, 238, 245)

local remote: RemoteEvent
local grapple: any = nil -- GrappleController (aim, gas)
local widget: Frame
local nameLabel: TextLabel
local timeLabel: TextLabel
local noteLabel: TextLabel
local dots: { Frame } = {}
local cooldownStart = 0
local cooldownEnd = 0
local noteToken = 0

local function equipped(): string
	local id = player:GetAttribute("Equip_Technique")
	return if type(id) == "string" then id else ""
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function shifted(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("Shifted") == true
end

local function note(text: string)
	noteToken += 1
	local token = noteToken
	noteLabel.Text = text
	noteLabel.TextTransparency = 0
	task.delay(1.8, function()
		if token == noteToken then
			TweenService:Create(noteLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

-- === Local effects ===========================================================

-- Where the hunter is heading: the stick / WASD, else the camera.
local function heading(): Vector3
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		return humanoid.MoveDirection.Unit
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
end

local function galeBurst(spec: Config.TechniqueSpec)
	local root = rootPart()
	if root then
		local impulse = spec.Impulse or 85
		root.AssemblyLinearVelocity += heading() * impulse + Vector3.new(0, impulse * 0.35, 0)
	end
end

-- A spinning ring round the hunter while they whirl forward.
local function whirlwind(spec: Config.TechniqueSpec)
	local root = rootPart()
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return
	end
	local forward = camera.CFrame.LookVector
	forward = Vector3.new(forward.X, math.clamp(forward.Y, -0.4, 0.5), forward.Z).Unit
	local speed = spec.Speed or 100
	local duration = spec.Duration or ((spec.Distance or 40) / speed)
	local ring = Instance.new("Part")
	ring.Name = "WhirlwindRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 9, 9)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(210, 235, 255)
	ring.Transparency = 0.55
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = Workspace
	local started = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		local here = rootPart()
		if t >= duration or not here or shifted() then
			ring:Destroy()
			if connection then
				connection:Disconnect()
			end
			return
		end
		here.AssemblyLinearVelocity = forward * speed
		ring.CFrame = CFrame.new(here.Position) * CFrame.Angles(0, t * 40, math.pi / 2)
	end)
end

local function secondWind(spec: Config.TechniqueSpec)
	-- GrappleController owns the tank: AddGas when it offers it.
	if grapple and type(grapple.AddGas) == "function" and type(grapple.GasMax) == "function" then
		grapple.AddGas(grapple.GasMax() * (spec.GasFraction or 0.5))
	end
end

local LOCAL: { [string]: (Config.TechniqueSpec) -> () } = {
	GaleBurst = galeBurst,
	WhirlwindCut = whirlwind,
	SecondWind = secondWind,
}

-- === Input ===================================================================

local function aimPoint(): Vector3?
	if grapple and type(grapple.AimTarget) == "function" then
		local hit = grapple.AimTarget()
		if typeof(hit) == "RaycastResult" then
			return hit.Position
		end
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position + camera.CFrame.LookVector * 200 else nil
end

local function use()
	local id = equipped()
	if id == "" or shifted() then
		return
	end
	local left = cooldownEnd - os.clock()
	if left > 0 then
		note(`Ready in {math.ceil(left)} s`)
		return
	end
	remote:FireServer(aimPoint())
end

-- === The widget ==============================================================

local function shortName(id: string): string
	local item = Config.Catalog[id]
	return if item then string.upper(item.Display) else ""
end

local function refresh()
	local id = equipped()
	local show = id ~= "" and not shifted()
	widget.Visible = show
	TouchButtons.Show("Technique", show)
	nameLabel.Text = shortName(id)
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "TechniqueUI"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 4
	screen.Parent = player:WaitForChild("PlayerGui")

	widget = Instance.new("Frame")
	widget.Name = "Technique"
	widget.AnchorPoint = Vector2.new(1, 0.5)
	widget.Position = UDim2.new(1, -14, 0.6, 0)
	widget.Size = UDim2.fromOffset(84, 108)
	widget.BackgroundTransparency = 1
	widget.Visible = false
	widget.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Parent = widget
	local function rescale()
		local camera = Workspace.CurrentCamera
		if camera then
			scale.Scale = math.clamp(math.min(camera.ViewportSize.X, camera.ViewportSize.Y) / 700, 0.7, 1.2)
		end
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.new(0.5, 0, 0, 0)
	disc.Size = UDim2.fromOffset(72, 72)
	disc.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	disc.BackgroundTransparency = 0.3
	disc.Parent = widget
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = disc
	for i = 1, DOTS do
		local angle = (i - 1) / DOTS * math.pi * 2
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.new(0.5, math.sin(angle) * 31, 0.5, -math.cos(angle) * 31)
		dot.Size = UDim2.fromOffset(6, 6)
		dot.BackgroundColor3 = READY
		dot.BorderSizePixel = 0
		dot.Parent = disc
		local dotRound = Instance.new("UICorner")
		dotRound.CornerRadius = UDim.new(1, 0)
		dotRound.Parent = dot
		dots[i] = dot
	end
	timeLabel = Instance.new("TextLabel")
	timeLabel.BackgroundTransparency = 1
	timeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	timeLabel.Position = UDim2.fromScale(0.5, 0.5)
	timeLabel.Size = UDim2.fromOffset(50, 30)
	timeLabel.Font = Enum.Font.GothamBlack
	timeLabel.TextSize = 20
	timeLabel.TextColor3 = TEXT
	timeLabel.Text = if UserInputService.TouchEnabled then "" else "V"
	timeLabel.Parent = disc

	nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(-20, 76)
	nameLabel.Size = UDim2.new(1, 40, 0, 16)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 11
	nameLabel.TextColor3 = READY
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Parent = widget

	noteLabel = Instance.new("TextLabel")
	noteLabel.BackgroundTransparency = 1
	noteLabel.AnchorPoint = Vector2.new(1, 0)
	noteLabel.Position = UDim2.new(1, 0, 0, 92)
	noteLabel.Size = UDim2.fromOffset(220, 16)
	noteLabel.Font = Enum.Font.GothamBold
	noteLabel.TextSize = 12
	noteLabel.TextColor3 = TEXT
	noteLabel.TextStrokeTransparency = 0.4
	noteLabel.TextXAlignment = Enum.TextXAlignment.Right
	noteLabel.TextTransparency = 1
	noteLabel.Parent = widget
end

local function tick()
	if not widget.Visible then
		return
	end
	local now = os.clock()
	local total = math.max(cooldownEnd - cooldownStart, 0.01)
	local done = math.clamp((now - cooldownStart) / total, 0, 1)
	local lit = math.floor(done * DOTS + 0.5)
	for i, dot in dots do
		dot.BackgroundColor3 = if i <= lit then READY else WAITING
	end
	local left = cooldownEnd - now
	timeLabel.Text = if left > 0 then tostring(math.ceil(left)) elseif UserInputService.TouchEnabled then "" else "V"
end

-- === Init ====================================================================

function TechniqueController.Init(grappleController: any)
	grapple = grappleController
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Technique) :: RemoteEvent
	build()

	ContextActionService:BindAction("Technique", function(_action, state, _input)
		if state == Enum.UserInputState.Begin then
			use()
		end
		return Enum.ContextActionResult.Pass
	end, false, Config.Shop.TechniqueKey, Config.Shop.TechniqueGamepad)
	if TouchButtons.Enabled() then
		TouchButtons.Init()
		TouchButtons.Add("Technique", "Technique", "SKILL", use)
	end

	remote.OnClientEvent:Connect(function(kind: unknown, id: unknown, a: unknown, b: unknown)
		if type(id) ~= "string" then
			return
		end
		local item = Config.Catalog[id]
		local spec = item and item.Technique
		if kind == "Go" and spec then
			cooldownStart = os.clock()
			cooldownEnd = cooldownStart + (if type(a) == "number" then a else spec.Cooldown)
			local effect = LOCAL[id]
			if effect then
				effect(spec)
			end
		elseif kind == "Denied" then
			note(tostring(a))
			if type(b) == "number" and b > 0 then
				cooldownEnd = math.max(cooldownEnd, os.clock() + b)
			end
		elseif kind == "Hits" and type(a) == "number" then
			if id == "SmokePellet" then
				note(if a > 0 then `{a} giant{if a == 1 then "" else "s"} lost in the smoke!` else "Nobody close enough")
			elseif a > 0 then
				note(if a == 1 then "Direct hit!" else `{a} cuts!`)
			elseif id == "FlareLance" then
				note("The lance missed")
			end
		end
	end)

	player:GetAttributeChangedSignal("Equip_Technique"):Connect(refresh)
	player.CharacterAdded:Connect(function(character)
		character:GetAttributeChangedSignal("Shifted"):Connect(refresh)
		refresh()
	end)
	if player.Character then
		player.Character:GetAttributeChangedSignal("Shifted"):Connect(refresh)
	end
	refresh()
	RunService.RenderStepped:Connect(tick)
end

return TechniqueController
