--!strict
-- Light client polish for the follow companion PetService spawns and drives
-- server-side. This controller never moves the companion itself (that's
-- AlignPosition/AlignOrientation, owned by PetService) - it only decorates
-- the local player's own companion: a floating nameplate with the Brainrot's
-- display name in its rarity color, and a small pop-in flourish whenever the
-- equipped companion changes.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.Theme)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)

local PetController = {}

local WAIT_FOR_COMPANION_SECONDS = 5
local NAMEPLATE_SIZE = UDim2.new(0, 180, 0, 40)
local NAMEPLATE_OFFSET = Vector3.new(0, 1.6, 0)

local player = Players.LocalPlayer

-- Guards against a slow companion-find (spawn race) or a rapid re-equip
-- outrunning the previous attempt: each call to onEquippedChanged gets a
-- token, and only the newest one is allowed to actually attach a nameplate.
local latestToken = 0

local function findCompanionModel(): Model?
	local petsFolder = Workspace:FindFirstChild("Pets")
	if not petsFolder then
		return nil
	end
	local name = `Companion_{player.UserId}`
	local existing = petsFolder:FindFirstChild(name)
	if existing and existing:IsA("Model") then
		return existing
	end
	return nil
end

local function waitForCompanionModel(): Model?
	local model = findCompanionModel()
	if model then
		return model
	end

	local petsFolder = Workspace:FindFirstChild("Pets") or Workspace:WaitForChild("Pets", WAIT_FOR_COMPANION_SECONDS)
	if not petsFolder then
		return nil
	end

	local name = `Companion_{player.UserId}`
	local found = petsFolder:FindFirstChild(name)
	if found and found:IsA("Model") then
		return found
	end

	local deadline = os.clock() + WAIT_FOR_COMPANION_SECONDS
	local result: Model? = nil
	local connection: RBXScriptConnection
	connection = petsFolder.ChildAdded:Connect(function(child)
		if child.Name == name and child:IsA("Model") then
			result = child
		end
	end)
	while not result and os.clock() < deadline do
		task.wait(0.1)
	end
	connection:Disconnect()
	return result
end

local function buildNameplate(model: Model, ownedId: string, rarity: string)
	local primary = model.PrimaryPart
	if not primary then
		return
	end

	local displayName = EggConfig.DisplayNames[ownedId] or ownedId
	local rarityColor = Theme.RarityColor(rarity)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CompanionNameplate"
	billboard.Adornee = primary
	billboard.Size = NAMEPLATE_SIZE
	billboard.StudsOffset = NAMEPLATE_OFFSET
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = primary

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = displayName
	label.TextColor3 = rarityColor
	label.Font = Theme.Font.SubHeading
	label.TextSize = 16
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(10, 10, 16)
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.Parent = billboard

	-- Small pop-in flourish: fade + scale up from a slightly smaller billboard
	-- size, so re-equipping reads as a deliberate moment rather than the
	-- nameplate just appearing.
	billboard.Size = UDim2.new(0, NAMEPLATE_SIZE.X.Offset * 0.6, 0, NAMEPLATE_SIZE.Y.Offset * 0.6)
	TweenService:Create(billboard, TweenInfo.new(Theme.Motion.Slow, Theme.Motion.EasingStyle, Theme.Motion.EasingDirection), {
		Size = NAMEPLATE_SIZE,
	}):Play()
	TweenService:Create(label, TweenInfo.new(Theme.Motion.Normal, Theme.Motion.EasingStyle, Theme.Motion.EasingDirection), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.3,
	}):Play()
end

local function onEquippedChanged(ownedId: string?, rarity: string?)
	latestToken += 1
	local token = latestToken

	if not ownedId or not rarity then
		return
	end

	task.spawn(function()
		local model = waitForCompanionModel()
		if token ~= latestToken then
			-- A newer equip change landed while we were waiting; don't attach a
			-- stale nameplate on top of (or instead of) the current companion.
			return
		end
		if not model then
			return
		end
		buildNameplate(model, ownedId, rarity)
	end)
end

function PetController.Init()
	Net.GetEvent(Constants.REMOTE_NAMES.Pets.EquippedChanged).OnClientEvent:Connect(onEquippedChanged)

	-- Cover the case where a companion was already spawned (e.g. this
	-- controller starting after PetService already reconciled on join).
	local existing = findCompanionModel()
	if existing then
		local ownedId = existing:GetAttribute("BrainrotId")
		local rarity = existing:GetAttribute("Rarity")
		if type(ownedId) == "string" and type(rarity) == "string" then
			buildNameplate(existing, ownedId, rarity)
		end
	end
end

return PetController
