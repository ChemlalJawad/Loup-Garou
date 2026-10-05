--!strict
-- Game feel, all on this client (nothing replicates):
--   * hit-stop: on a hit the camera and your own animations hold still for
--     a few hundredths of a second (physics carries on);
--   * a white flash and a pale vignette on a clean cut, a stronger one on a
--     takedown, and a big steam-and-spark burst on the nape (Effects);
--   * floating score text where the cut landed ("+8  x3"), from the points
--     the server actually gave you;
--   * speed lines streaming out from where you're flying, at high speed;
--   * the camera rolls a little into swings (setting "Camera roll");
--   * the grab tell: when a giant near you raises its arms (or a Beast
--     roars), a growl from it and a red glow on the edge of the screen with
--     a "!" arrow pointing at it;
--   * defeated giants sag to their knees and slump forward while they steam
--     away (the server has already anchored them; this only bends them).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Parent.Effects)
local Settings = require(script.Parent.Settings)
local CosmeticsClient = require(script.Parent.CosmeticsClient)

local Juice = {}

local player = Players.LocalPlayer
local Feel = Config.Feel

local gui: ScreenGui
local flash: Frame
local edges: { [string]: Frame } = {}
local edgeTint = Color3.new(1, 1, 1)
local edgeGlow = 0 -- 0..1, the vignette (it fades)
local dangerArrow: TextLabel
local lines: { Frame } = {}
local floaters: { { Gui: BillboardGui, Text: TextLabel, Spot: Attachment } } = {}
local nextFloater = 1

local stopUntil = 0
local stopCFrame: CFrame? = nil
local pausedTracks: { [AnimationTrack]: number } = {}
local roll = 0

local lastHitAt = 0
local lastHitPosition: Vector3? = nil
local lastPoints: number? = nil
local combo = 1

-- Giants about to grab (or roar) near you, until when.
local dangers: { [Model]: number } = {}

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

local function myRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- === Hit-stop ================================================================

local function resumeTracks()
	for track, speed in pausedTracks do
		if track.IsPlaying then
			track:AdjustSpeed(speed)
		end
	end
	table.clear(pausedTracks)
end

function Juice.HitStop(duration: number)
	local camera = Workspace.CurrentCamera
	if os.clock() >= stopUntil then
		stopCFrame = camera.CFrame
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				pausedTracks[track] = track.Speed
				track:AdjustSpeed(0)
			end
		end
	end
	stopUntil = math.max(stopUntil, os.clock() + duration)
end

-- === Flash and vignette =====================================================

function Juice.Flash(strength: number, tint: Color3?)
	flash.BackgroundColor3 = tint or Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(0.18 + strength * 0.2), { BackgroundTransparency = 1 }):Play()
end

function Juice.Vignette(strength: number, tint: Color3)
	edgeTint = tint
	edgeGlow = math.max(edgeGlow, strength)
end

-- === Level up ===============================================================
-- A warm gold flash and glow, a shower of sparks round you, a bright chime.

function Juice.LevelUp()
	local gold = Color3.fromRGB(255, 215, 90)
	if flash then
		Juice.Flash(0.35, gold)
	end
	Juice.Vignette(0.6, gold)
	local root = myRoot()
	if root then
		Effects.Burst(root.Position + Vector3.new(0, 2, 0), gold, 1.4, 40)
	end
	Effects.Play("Resupply", nil, 0.8, 1.5)
end

-- === Floating text ==========================================================

function Juice.FloatText(position: Vector3, text: string, color: Color3, big: boolean?)
	local slot = floaters[nextFloater]
	if not slot then
		local spot = new("Attachment", { Name = "FloatText", Parent = Workspace.Terrain })
		local billboard = new("BillboardGui", { Name = "FloatText", AlwaysOnTop = true, LightInfluence = 0, Size = UDim2.fromOffset(220, 60), Adornee = spot, Enabled = false, ResetOnSpawn = false, Parent = gui.Parent })
		local label = new("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextStrokeTransparency = 0.2,
			TextStrokeColor3 = Color3.fromRGB(20, 22, 30),
			Parent = billboard,
		})
		slot = { Gui = billboard, Text = label, Spot = spot }
		floaters[nextFloater] = slot
	end
	nextFloater = nextFloater % Feel.FloatingTexts + 1
	local boost = Settings.TextBoost() * (if big then 1.35 else 1)
	slot.Spot.WorldPosition = position
	slot.Gui.Size = UDim2.fromOffset(220 * boost, 60 * boost)
	slot.Gui.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
	slot.Gui.Enabled = true
	slot.Text.Text = text
	slot.Text.TextColor3 = color
	slot.Text.TextTransparency = 0
	slot.Text.TextStrokeTransparency = 0.2
	slot.Text.Rotation = math.random(-8, 8)
	local rise = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(slot.Gui, rise, { StudsOffsetWorldSpace = Vector3.new(0, 7, 0) }):Play()
	TweenService:Create(slot.Text, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	local gui = slot.Gui
	task.delay(1.25, function()
		if slot.Text.TextTransparency >= 1 then
			gui.Enabled = false
		end
	end)
end

-- === Results from the server ================================================

-- (Colours chosen to stay apart for every kind of colour vision.)
local SKY = Color3.fromRGB(86, 180, 233)
local GOLD = Color3.fromRGB(255, 215, 90)
local WHITE = Color3.fromRGB(240, 244, 250)

local function onSlashResult(result: string, info: any)
	info = if type(info) == "table" then info else {}
	local position: Vector3? = if typeof(info.Position) == "Vector3" then info.Position else nil
	if position then
		lastHitAt = os.clock()
		lastHitPosition = position
	end
	local clean = info.Clean == true
	if result == "Defeated" then
		Juice.HitStop(Feel.HitStopDefeat)
		Juice.Flash(0.55, Color3.fromRGB(235, 248, 255))
		Juice.Vignette(1, if clean then SKY else WHITE)
		Effects.Shake(0.7)
		Effects.Play("Cut", nil, 1.2, 1 + (combo - 1) * 0.08)
		if position then
			Effects.NapeBurst(position, if clean then 2.4 else 1.8)
			-- Your defeat effect (confetti, stars...), if you wear one.
			local fx = Players.LocalPlayer:GetAttribute("Cos_Defeat")
			if type(fx) == "string" and fx ~= "" then
				CosmeticsClient.DefeatBurst(fx, position)
			end
		end
	elseif result == "Hit" or result == "Training" then
		Juice.HitStop(Feel.HitStop)
		if clean then
			Juice.Flash(0.3, Color3.fromRGB(225, 245, 255))
			Juice.Vignette(0.7, SKY)
		end
		Effects.Shake(if clean then 0.4 else 0.2)
		Effects.Play("Cut", nil, 1, 1 + (combo - 1) * 0.08)
		if position then
			Effects.NapeBurst(position, if clean then 1.4 else 0.8)
			Juice.FloatText(position, if clean then "CLEAN!" else "HIT", if clean then SKY else WHITE)
		end
	elseif result == "Armor" or result == "ArmorBroken" then
		Juice.HitStop(Feel.HitStop)
		Effects.Shake(0.35)
		if position then
			Effects.NapeBurst(position, if result == "ArmorBroken" then 1.6 else 0.7, Color3.fromRGB(205, 200, 185))
			Juice.FloatText(position, if result == "ArmorBroken" then "CRACKED!" else "CLANG", Color3.fromRGB(215, 210, 195))
		end
	elseif result == "Trip" or result == "Daze" then
		Juice.HitStop(Feel.HitStop * 0.7)
		Effects.Shake(0.25)
		if position then
			Juice.FloatText(position, if result == "Trip" then "TRIPPED" else "DAZED", SKY)
		end
	elseif result == "Guarded" then
		Effects.Shake(0.15)
		if position then
			Juice.FloatText(position, "BLOCKED", Color3.fromRGB(200, 170, 255))
		end
	end
end

local function onState(state: any)
	if type(state) ~= "table" then
		return
	end
	combo = if type(state.Combo) == "number" and (state.ComboLeft or 0) > 0 then math.max(state.Combo, 1) else 1
	local points = state.Points
	if type(points) ~= "number" then
		return
	end
	-- (A big jump with no cut just before it is saved points loading in.)
	local recent = os.clock() - lastHitAt < 3
	if lastPoints and points > lastPoints and (recent or points - lastPoints <= 20) then
		-- Score text where the cut landed (or over your head).
		local root = myRoot()
		local at = if lastHitPosition and recent then lastHitPosition elseif root then root.Position + Vector3.new(0, 4, 0) else nil
		if at then
			local text = `+{points - lastPoints}`
			if combo >= 2 then
				text ..= `  x{combo}`
			end
			Juice.FloatText(at + Vector3.new(0, 3, 0), text, GOLD, true)
		end
	end
	lastPoints = points
end

-- === Grab tells ==============================================================

-- Moves that can knock you about: they get the danger arrow too.
local ATTACKS = { Stomp = true, Swipe = true, Lunge = true, Crouch = true, Shake = true }

local function watchGiant(model: Instance)
	if not model:IsA("Model") then
		return
	end
	model:GetAttributeChangedSignal("Grabbing"):Connect(function()
		if model:GetAttribute("Grabbing") ~= true or model:GetAttribute("Defeated") then
			return
		end
		local root = myRoot()
		local giantRoot = model:FindFirstChild("Root")
		if not root or not giantRoot or not giantRoot:IsA("BasePart") then
			return
		end
		local kind = Config.GiantKinds[(model:GetAttribute("Kind") :: string?) or ""]
		local reach = if kind and kind.Powers then Config.Beast.RoarRadius else (if kind then kind.GrabReach else 16) * Feel.GrabTellReach
		local distance = (giantRoot.Position - root.Position).Magnitude
		local head = model:FindFirstChild("Head")
		if distance < reach + 60 then
			local height = (model:GetAttribute("Height") :: number?) or 20
			Effects.Play("Roar", if head and head:IsA("BasePart") then head else giantRoot, 1, math.sqrt(30 / height))
		end
		if distance < reach then
			dangers[model] = os.clock() + Config.Giants.GrabWindup + 0.4
		end
	end)
	model:GetAttributeChangedSignal("Defeated"):Connect(function()
		if model:GetAttribute("Defeated") == true then
			dangers[model] = nil
			Juice.Collapse(model)
		end
	end)
	-- The newer attacks (GiantService sets "Action"): the same red edge
	-- arrow while one is winding up near you.
	model:GetAttributeChangedSignal("Action"):Connect(function()
		local action = model:GetAttribute("Action")
		local spec = if type(action) == "string" and ATTACKS[action] then Config.GiantActions[action] else nil
		local root = myRoot()
		local giantRoot = model:FindFirstChild("Root")
		if not spec or model:GetAttribute("Defeated") or not root or not giantRoot or not giantRoot:IsA("BasePart") then
			return
		end
		local height = (model:GetAttribute("Height") :: number?) or 20
		if (giantRoot.Position - root.Position).Magnitude < height * 1.6 + 20 then
			dangers[model] = os.clock() + (spec.Impact or spec.Windup) + 0.3
		end
	end)
end

-- === Defeat: down on its knees, then slump forward ===========================

function Juice.Collapse(model: Model)
	local root = model:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		return
	end
	local camera = Workspace.CurrentCamera
	if (camera.CFrame.Position - root.Position).Magnitude > 700 then
		return
	end
	local motors: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	local crawl = model:GetAttribute("Pose") == "Crawl"
	local shin = model:FindFirstChild("LeftShin")
	local drop = if crawl then 0 elseif shin and shin:IsA("BasePart") then shin.Size.X * 0.95 else 0
	local height = (model:GetAttribute("Height") :: number?) or 20
	local startRoot = root.CFrame
	local start: { [string]: CFrame } = {}
	for name, motor in motors do
		start[name] = motor.Transform
	end
	-- Phase 1 (to the knees), phase 2 (slump forward, sinking a little).
	local kneel: { [string]: CFrame } = {
		Waist = CFrame.Angles(if crawl then -0.15 else -0.35, 0, 0.05),
		LeftHip = CFrame.Angles(if crawl then 0 else 0.1, 0, 0),
		RightHip = CFrame.Angles(if crawl then 0 else 0.1, 0, 0),
		LeftKnee = CFrame.Angles(if crawl then 0 else -1.5, 0, 0),
		RightKnee = CFrame.Angles(if crawl then 0 else -1.5, 0, 0),
		LeftShoulder = CFrame.Angles(0.4, 0, -0.15),
		RightShoulder = CFrame.Angles(0.4, 0, 0.15),
		LeftElbow = CFrame.Angles(0.3, 0, 0),
		RightElbow = CFrame.Angles(0.3, 0, 0),
		Neck = CFrame.Angles(0.15, 0, 0),
	}
	local slump: { [string]: CFrame } = table.clone(kneel)
	slump.Waist = CFrame.Angles(if crawl then -0.3 else -0.85, 0, 0.08)
	slump.Neck = CFrame.Angles(0.35, 0.15, 0)
	slump.LeftShoulder = CFrame.Angles(0.15, 0, -0.1)
	slump.RightShoulder = CFrame.Angles(0.15, 0, 0.1)
	local began = os.clock()
	local KNEEL, SLUMP = 0.45, 1.4
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if not model.Parent or not root.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - began
		local a = math.clamp(t / KNEEL, 0, 1)
		a = 1 - (1 - a) * (1 - a) -- ease out: it drops
		local b = math.clamp((t - KNEEL) / (SLUMP - KNEEL), 0, 1)
		b = b * b * (3 - 2 * b)
		for name, motor in motors do
			local from = start[name]
			local mid = kneel[name]
			if from and mid then
				motor.Transform = from:Lerp(mid, a):Lerp(slump[name] or mid, b)
			end
		end
		root.CFrame = startRoot - Vector3.new(0, drop * a + height * 0.04 * b, 0)
		if t > SLUMP + 0.1 then
			connection:Disconnect()
		end
	end)
	task.delay(KNEEL, function()
		if model.Parent and not crawl then
			Effects.Play("Boom", root, math.clamp(height / 46, 0.4, 1), 1.1)
			local here = myRoot()
			if here then
				local distance = (here.Position - root.Position).Magnitude
				local reach = height * Feel.StepReach
				if distance < reach then
					Effects.Shake(0.6 * (height / 46) * (1 - distance / reach))
				end
			end
		end
	end)
end

-- === Build ===================================================================

local function build()
	gui = new("ScreenGui", { Name = "HunterJuice", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = -1, Parent = player:WaitForChild("PlayerGui") })
	-- Speed lines under everything else.
	for i = 1, Feel.SpeedLines do
		lines[i] = new("Frame", { Name = "SpeedLine", AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })
	end
	-- The vignette / danger glow: four edges, each fading in from the side.
	local function edge(name: string, anchor: Vector2, position: UDim2, size: UDim2, rotation: number)
		local frame = new("Frame", { Name = name, AnchorPoint = anchor, Position = position, Size = size, BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Parent = gui })
		new("UIGradient", { Rotation = rotation, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = frame })
		edges[name] = frame
	end
	edge("Left", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.16, 1), 0)
	edge("Right", Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.16, 1), 180)
	edge("Top", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.18), 90)
	edge("Bottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.18), -90)
	dangerArrow = new("TextLabel", {
		Name = "DangerArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		BackgroundTransparency = 1,
		Text = "▲\n!",
		TextScaled = true,
		LineHeight = 0.8,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 80, 50),
		TextStrokeTransparency = 0,
		Visible = false,
		Parent = gui,
	})
	flash = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Parent = gui })
end

function Juice.Init(grapple: any)
	build()
	local camera = Workspace.CurrentCamera

	for _, model in CollectionService:GetTagged(Config.Tags.Giant) do
		watchGiant(model)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Giant):Connect(watchGiant)

	-- Camera roll into swings, then hit-stop (which holds the camera still).
	RunService:BindToRenderStep("GH_Roll", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		local root = myRoot()
		local target = 0
		if Settings.Get("CameraRoll") and root and grapple.IsHooked() then
			local sideways = root.AssemblyLinearVelocity:Dot(camera.CFrame.RightVector) / Config.Grapple.MaxSpeed
			target = -math.clamp(sideways * 1.6, -1, 1) * math.rad(Feel.RollMax)
		end
		roll += (target - roll) * math.min(dt * Feel.RollRate, 1)
		if math.abs(roll) > 0.0005 then
			camera.CFrame *= CFrame.Angles(0, 0, roll)
		end
	end)
	RunService:BindToRenderStep("GH_HitStop", Enum.RenderPriority.Camera.Value + 3, function()
		if os.clock() < stopUntil then
			if stopCFrame then
				camera.CFrame = stopCFrame
			end
		elseif stopCFrame then
			stopCFrame = nil
			resumeTracks()
		end
	end)

	-- Every frame: speed lines, the vignette and the danger glow.
	local lineState: { { Angle: number, Radius: number, Speed: number, Length: number } } = {}
	for i = 1, #lines do
		lineState[i] = { Angle = math.random() * math.pi * 2, Radius = math.random() * 0.5, Speed = 0.8 + math.random() * 0.8, Length = 0.6 + math.random() * 0.8 }
	end
	RunService.RenderStepped:Connect(function(dt: number)
		local viewport = camera.ViewportSize
		local root = myRoot()
		local now = os.clock()

		-- Speed lines stream out from where you're heading.
		local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
		local strength = math.clamp((speed - Feel.SpeedLinesFrom) / (Feel.SpeedLinesFull - Feel.SpeedLinesFrom), 0, 1) * ((Settings.Get("Fov") :: number?) or 1)
		if not Settings.Get("SpeedLines") then
			strength = 0
		end
		local centre = viewport / 2
		if root and strength > 0 then
			local ahead, onScreen = camera:WorldToViewportPoint(camera.CFrame.Position + root.AssemblyLinearVelocity.Unit * 50)
			if onScreen then
				centre = centre:Lerp(Vector2.new(ahead.X, ahead.Y), 0.6)
			end
		end
		local count = math.ceil(#lines * math.min(strength, 1))
		local reach = math.max(viewport.X, viewport.Y) * 0.75
		for i, line in lines do
			local state = lineState[i]
			if i > count then
				if line.Visible then
					line.Visible = false
				end
				continue
			end
			state.Radius += dt * state.Speed * (1 + strength)
			if state.Radius > 1 then
				state.Radius = 0.25 + math.random() * 0.15
				state.Angle = math.random() * math.pi * 2
			end
			local direction = Vector2.new(math.cos(state.Angle), math.sin(state.Angle))
			local at = centre + direction * state.Radius * reach
			line.Visible = true
			line.Position = UDim2.fromOffset(at.X, at.Y)
			line.Size = UDim2.fromOffset(state.Length * 140 * state.Radius + 20, 2)
			line.Rotation = math.deg(state.Angle)
			line.BackgroundTransparency = 1 - math.min(strength, 1) * 0.45 * state.Radius
		end

		-- Danger: the closest giant about to grab you.
		local danger: Vector3? = nil
		local closest = math.huge
		for model, untilTime in dangers do
			local giantRoot = model:FindFirstChild("Root")
			if now > untilTime or not model.Parent or not giantRoot or not giantRoot:IsA("BasePart") then
				dangers[model] = nil
			elseif root and (giantRoot.Position - root.Position).Magnitude < closest then
				closest = (giantRoot.Position - root.Position).Magnitude
				danger = giantRoot.Position
			end
		end
		local weights = { Left = 0, Right = 0, Top = 0, Bottom = 0 }
		if danger then
			local pulse = 0.65 + 0.35 * math.sin(now * 18)
			local v = camera.CFrame:VectorToObjectSpace(danger - camera.CFrame.Position)
			local flat = Vector2.new(v.X, -v.Y)
			if v.Z > 0 and flat.Magnitude < 1 then
				flat = Vector2.new(0, 1) -- right behind you: the bottom edge
			end
			flat = if flat.Magnitude > 0.001 then flat.Unit else Vector2.new(0, 1)
			weights.Right = math.max(flat.X, 0) * pulse
			weights.Left = math.max(-flat.X, 0) * pulse
			weights.Bottom = math.max(flat.Y, 0) * pulse
			weights.Top = math.max(-flat.Y, 0) * pulse
			-- The "!" arrow sits on an oval round the crosshair, pointing at it.
			local spot = viewport / 2 + Vector2.new(flat.X * viewport.X * 0.36, flat.Y * viewport.Y * 0.34)
			dangerArrow.Visible = true
			dangerArrow.Position = UDim2.fromOffset(spot.X, spot.Y)
			dangerArrow.Rotation = math.deg(math.atan2(flat.Y, flat.X)) + 90
			dangerArrow.TextTransparency = 1 - pulse
			local boost = Settings.TextBoost()
			dangerArrow.Size = UDim2.fromOffset(64 * boost, 64 * boost)
		elseif dangerArrow.Visible then
			dangerArrow.Visible = false
		end
		edgeGlow = math.max(edgeGlow - dt * 2.5, 0)
		for name, frame in edges do
			local d = (weights :: any)[name] :: number
			local alpha = math.max(d * 0.75, edgeGlow * 0.6)
			frame.BackgroundColor3 = if d * 0.75 > edgeGlow * 0.6 then Color3.fromRGB(255, 50, 30) else edgeTint
			frame.BackgroundTransparency = 1 - alpha
		end
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local function remote(name: string): RemoteEvent
		return remotes:WaitForChild(name) :: RemoteEvent
	end
	remote(Config.Remotes.SlashResult).OnClientEvent:Connect(onSlashResult)
	remote(Config.Remotes.State).OnClientEvent:Connect(onState)
	remote(Config.Remotes.Held).OnClientEvent:Connect(function(state: string)
		if state == "Grabbed" then
			table.clear(dangers)
			Juice.Flash(0.35, Color3.fromRGB(255, 90, 60))
		end
	end)
end

return Juice
