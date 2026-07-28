--!strict
-- Self-contained, self-cleaning "juice" library: particle bursts, shockwaves,
-- screen flash/shake, floating text, highlights. Every function here cleans
-- up its own instances when it finishes — leaked emitters/parts are the #1
-- way a juice layer tanks framerate over a long session, so nothing in this
-- file is allowed to leave anything behind.
--
-- Callable from both server and client. Effects that only make sense on the
-- client (screen flash, screen shake) are guarded with RunService:IsClient()
-- so a server call is a safe no-op instead of an error — server-authoritative
-- systems (CTF, eggs, ...) can call FX.Burst/FX.Shockwave/FX.FloatingText for
-- a world event without worrying about which side they're running on.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Theme)

local IS_CLIENT = RunService:IsClient()

local FX = {}

local EFFECTS_FOLDER_NAME = "FXTemp"

-- A shared, anchored, out-of-the-way folder in Workspace to parent temporary
-- effect parts under, so they're easy to find/clear and never orphan loose
-- into Workspace's root.
local effectsFolder: Folder? = nil
local function getEffectsFolder(): Folder
	if effectsFolder and effectsFolder.Parent then
		return effectsFolder
	end
	local existing = Workspace:FindFirstChild(EFFECTS_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		effectsFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = EFFECTS_FOLDER_NAME
	folder.Parent = Workspace
	effectsFolder = folder
	return folder
end

-- === FX.Burst ================================================================
-- A one-shot particle burst at a world position. Self-destroys once the
-- particles have finished their lifetime.
function FX.Burst(position: Vector3, color: Color3, count: number?)
	local amount = count or 24

	local anchor = Instance.new("Part")
	anchor.Name = "FXBurstAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = getEffectsFolder()

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0.7
	emitter.Rate = 0
	emitter.Parent = anchor

	emitter:Emit(amount)

	task.delay(1.1, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

-- === FX.RarityBurst ==========================================================
-- A burst scaled + tinted by Brainrot rarity, so a Secret hatch visibly reads
-- as bigger than a Common one.
local RARITY_BURST_COUNT: { [string]: number } = {
	Common = 14,
	Rare = 22,
	Epic = 32,
	Legendary = 48,
	Secret = 72,
}

function FX.RarityBurst(position: Vector3, rarity: string)
	local color = Theme.RarityColor(rarity)
	local count = RARITY_BURST_COUNT[rarity] or RARITY_BURST_COUNT.Common
	FX.Burst(position, color, count)

	if rarity == "Legendary" or rarity == "Secret" then
		FX.Shockwave(position, color)
	end
end

-- === FX.Shockwave =============================================================
-- An expanding, fading ring (a thin flattened cylinder) at a world position.
function FX.Shockwave(position: Vector3, color: Color3)
	local ring = Instance.new("Part")
	ring.Name = "FXShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = getEffectsFolder()

	local tween = TweenService:Create(
		ring,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 16, 16), Transparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		ring:Destroy()
	end)
end

-- === FX.ScreenFlash (client only) ============================================
-- A brief full-screen color tint. No-ops on the server.
function FX.ScreenFlash(color: Color3, intensity: number?)
	if not IS_CLIENT then
		return
	end

	local player = Players.LocalPlayer
	if not player then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local alpha = math.clamp(intensity or 0.35, 0, 1)

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FXScreenFlash"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 1000
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - alpha
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local tween = TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		screenGui:Destroy()
	end)
end

-- === FX.ScreenShake (client only) ============================================
-- Applies a decaying random CFrame offset to the camera in RenderStepped,
-- then removes itself and restores the camera cleanly. No-ops on the server.
-- Multiple concurrent shakes stack (each owns its own connection + offset)
-- rather than fighting each other or the player's own camera control.
local activeShakeCount = 0

function FX.ScreenShake(intensity: number?, duration: number?)
	if not IS_CLIENT then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local magnitude = intensity or 0.6
	local length = duration or 0.25
	local startTime = os.clock()
	activeShakeCount += 1

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		local remaining = 1 - math.clamp(elapsed / length, 0, 1)
		if remaining <= 0 then
			connection:Disconnect()
			activeShakeCount = math.max(0, activeShakeCount - 1)
			return
		end

		local falloff = remaining * remaining
		local offset = Vector3.new(
			(math.random() * 2 - 1) * magnitude * falloff,
			(math.random() * 2 - 1) * magnitude * falloff,
			0
		)
		camera.CFrame = camera.CFrame * CFrame.new(offset)
	end)
end

-- === FX.FloatingText ==========================================================
-- A 3D world-space floating label (BillboardGui) that rises and fades, then
-- destroys itself. Works on client or server (server-spawned billboards
-- render for everyone, same as any other world BillboardGui).
function FX.FloatingText(position: Vector3, text: string, color: Color3?)
	local anchor = Instance.new("Part")
	anchor.Name = "FXFloatingTextAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = getEffectsFolder()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FXFloatingText"
	billboard.Adornee = anchor
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 1, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = text
	label.TextColor3 = color or Theme.Color.TextPrimary
	label.Font = Theme.Font.Heading
	label.TextSize = 28
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(10, 10, 16)
	label.Parent = billboard

	local duration = 1.1
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, tweenInfo, { StudsOffset = Vector3.new(0, 5, 0) }):Play()
	local fadeTween = TweenService:Create(label, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		anchor:Destroy()
	end)
end

-- === FX.Highlight =============================================================
-- A temporary Highlight instance on `instance`, removed after `duration`
-- seconds. Safe to call repeatedly on the same instance (each call owns its
-- own Highlight, so overlapping calls just layer/replace visually and each
-- cleans up independently).
function FX.Highlight(instance: Instance, color: Color3, duration: number?)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.Parent = instance

	task.delay(duration or 1, function()
		if highlight.Parent then
			highlight:Destroy()
		end
	end)
end

return FX
