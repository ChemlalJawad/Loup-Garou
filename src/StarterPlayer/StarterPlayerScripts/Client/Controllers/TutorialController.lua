--!strict
-- Draws the new-player guide the server tells us we're on: a step card at
-- the top of the screen, a glowing trail from your feet to the goal, and a
-- bouncing marker over the goal. Progress, rewards and step checks all live
-- in TutorialService; this only renders the current step.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.Theme)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local TutorialConfig = require(ReplicatedStorage.Shared.Tutorial.TutorialConfig)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)

local Util = UIKit.Util

local TutorialController = {}

local TRAIL_COLOR = Theme.Color.AccentPrimary
local UPDATE_INTERVAL = 1 / 20

local localPlayer = Players.LocalPlayer
local currentStep = TutorialConfig.DONE

local card: Frame
local titleLabel: TextLabel
local hintLabel: TextLabel
local distanceLabel: TextLabel

local worldFolder: Folder
local targetPart: Part
local targetAttachment: Attachment
local marker: BillboardGui
local beam: Beam? = nil

local function buildCard()
	card = Util.Create("Frame", {
		Name = "TutorialCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.new(0, 380, 0, 82),
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		Visible = false,
		Parent = Shell.GetScreenGui(),
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = card })
	Util.Create("UIStroke", { Color = TRAIL_COLOR, Thickness = 2, Parent = card })

	titleLabel = Util.Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 10),
		Size = UDim2.new(1, -90, 0, 26),
		Font = Theme.Font.SubHeading,
		TextSize = 19,
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	}) :: TextLabel
	hintLabel = Util.Create("TextLabel", {
		Name = "Hint",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 38),
		Size = UDim2.new(1, -32, 0, 36),
		Font = Theme.Font.Body,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	}) :: TextLabel
	distanceLabel = Util.Create("TextLabel", {
		Name = "Distance",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -60, 0, 10),
		Size = UDim2.new(0, 60, 0, 26),
		Font = Theme.Font.SubHeading,
		TextSize = 16,
		TextColor3 = TRAIL_COLOR,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	}) :: TextLabel

	local skip = Util.Create("TextButton", {
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 44, 0, 24),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		Text = "Skip",
		Font = Theme.Font.Body,
		TextSize = 13,
		TextColor3 = Theme.Color.TextSecondary,
		AutoButtonColor = true,
		Parent = card,
	}) :: TextButton
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = skip })
	skip.MouseButton1Click:Connect(function()
		Net.GetEvent(Constants.REMOTE_NAMES.Tutorial.Skip):FireServer()
	end)
end

local function buildWorldGuide()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "TutorialGuide"
	worldFolder.Parent = Workspace

	-- Invisible anchor at the goal: holds the trail's far end and the marker.
	targetPart = Instance.new("Part")
	targetPart.Name = "Goal"
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.CanTouch = false
	targetPart.CastShadow = false
	targetPart.Transparency = 1
	targetPart.Size = Vector3.new(1, 1, 1)
	targetPart.Parent = worldFolder

	targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "TrailEnd"
	targetAttachment.Parent = targetPart

	marker = Instance.new("BillboardGui")
	marker.Name = "GoalMarker"
	marker.Adornee = targetPart
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Size = UDim2.new(0, 60, 0, 60)
	marker.StudsOffset = Vector3.new(0, 8, 0)
	marker.Enabled = false
	marker.Parent = targetPart
	Util.Create("TextLabel", {
		Name = "Arrow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "▼",
		Font = Theme.Font.Heading,
		TextScaled = true,
		TextColor3 = TRAIL_COLOR,
		TextStrokeTransparency = 0.2,
		Parent = marker,
	})
end

-- The trail runs from an attachment at the character's feet to the goal.
-- Rebuilt on respawn, since the old root part (and its attachment) is gone.
local function attachTrail(character: Model)
	if beam then
		beam:Destroy()
		beam = nil
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end
	local feet = Instance.new("Attachment")
	feet.Name = "TutorialTrailStart"
	feet.Position = Vector3.new(0, -2.6, 0)
	feet.Parent = root

	local newBeam = Instance.new("Beam")
	newBeam.Name = "TutorialTrail"
	newBeam.Attachment0 = feet
	newBeam.Attachment1 = targetAttachment
	newBeam.Color = ColorSequence.new(TRAIL_COLOR, Theme.Color.AccentWarning)
	newBeam.Transparency = NumberSequence.new(0.15, 0.5)
	newBeam.Width0 = 1.4
	newBeam.Width1 = 1.4
	newBeam.FaceCamera = true
	newBeam.LightEmission = 1
	newBeam.Segments = 1
	newBeam.Enabled = currentStep ~= TutorialConfig.DONE
	newBeam.Parent = worldFolder
	beam = newBeam
end

local function applyStep(stepIndex: number)
	currentStep = stepIndex
	local step = TutorialConfig.Steps[stepIndex]
	local active = step ~= nil
	card.Visible = active
	marker.Enabled = active
	if beam then
		beam.Enabled = active
	end
	if not step then
		return
	end
	titleLabel.Text = `STEP {stepIndex}/{#TutorialConfig.Steps}  ·  {step.Title}`
	hintLabel.Text = step.Hint
	-- Goal just above the ground so the trail ends at a visible height.
	targetPart.CFrame = CFrame.new(step.Target + Vector3.new(0, 1.5, 0))
end

function TutorialController.Init()
	buildCard()
	buildWorldGuide()

	Net.GetEvent(Constants.REMOTE_NAMES.Tutorial.State).OnClientEvent:Connect(function(stepIndex)
		if type(stepIndex) == "number" then
			applyStep(stepIndex)
		end
	end)

	-- Init must not yield: character wiring happens in its own thread.
	task.spawn(function()
		if localPlayer.Character then
			attachTrail(localPlayer.Character)
		end
	end)
	localPlayer.CharacterAdded:Connect(function(character)
		task.spawn(attachTrail, character)
	end)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		if currentStep == TutorialConfig.DONE then
			return
		end
		accumulated += dt
		if accumulated < UPDATE_INTERVAL then
			return
		end
		accumulated = 0
		-- Bounce the marker and show how far there is left to go.
		marker.StudsOffset = Vector3.new(0, 8 + math.abs(math.sin(os.clock() * 3)) * 2, 0)
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - targetPart.Position).Magnitude
			distanceLabel.Text = `{math.floor(distance)}m`
		end
	end)

	Net.GetEvent(Constants.REMOTE_NAMES.Tutorial.RequestState):FireServer()
end

return TutorialController
