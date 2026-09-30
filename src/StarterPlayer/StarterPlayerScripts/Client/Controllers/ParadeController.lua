--!strict
-- Client renderer for the Brainrot Parade.
--
-- The server only tells us *what* spawned and *when* (ParadeService); each
-- walker's position is ParadeConfig.PositionAt(walker, serverTime), computed
-- here every frame. So the whole carpet animates smoothly with zero
-- per-frame network traffic, and every player sees the same Brainrot in the
-- same place because they share workspace:GetServerTimeNow().
--
-- Models are local (built with BrainrotModels.BuildStatic), buying goes
-- through a local ProximityPrompt that just sends the walker's uid; the
-- server validates everything.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.Theme)
local EggConfig = require(ReplicatedStorage.Shared.Eggs.EggConfig)
local BrainrotModels = require(ReplicatedStorage.Shared.Brainrots.BrainrotModels)
local Mutations = require(ReplicatedStorage.Shared.Brainrots.Mutations)
local ParadeConfig = require(ReplicatedStorage.Shared.Parade.ParadeConfig)
local FX = require(ReplicatedStorage.Shared.Effects.FX)

local ParadeController = {}

type Walker = ParadeConfig.Walker

type Rendered = {
	Walker: Walker,
	Model: Model,
	BuildPivot: CFrame, -- model pivot in build space, so PivotTo(T * BuildPivot) puts its feet at T
	Phase: number, -- per-walker waddle offset so they don't bob in lockstep
}

local localPlayer = Players.LocalPlayer
local rendered: { [string]: Rendered } = {}
local folder: Folder? = nil

local startPoint, endPoint = ParadeConfig.CarpetEndpoints()
local walkDirection = (endPoint - startPoint).Unit
local carpetMidpoint = (startPoint + endPoint) / 2

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "ParadeWalkers"
	newFolder.Parent = Workspace
	folder = newFolder
	return newFolder
end

local function buildLabel(model: Model, walker: Walker)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local mutation = Mutations.Get(walker.Mutation)
	local rarityColor = Theme.RarityColor(walker.Rarity)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ParadeLabel"
	billboard.Adornee = primary
	billboard.Size = UDim2.fromOffset(210, 78)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	-- Limit clutter (and cost): labels only render for players near the
	-- carpet, which is also the only place they're useful.
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Parent = primary

	local function line(text: string, color: Color3, order: number, textSize: number)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 24)
		label.Position = UDim2.fromOffset(0, (order - 1) * 25)
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.25
		label.TextStrokeColor3 = Color3.fromRGB(10, 10, 16)
		label.Font = Theme.Font.Heading
		label.TextSize = textSize
		label.Parent = billboard
	end

	line(Mutations.DecorateName(EggConfig.DisplayName(walker.Id), walker.Mutation), Theme.Color.TextPrimary, 1, 18)
	local tierText = string.upper(walker.Rarity)
	if mutation then
		tierText = `{string.upper(mutation.DisplayName)} x{mutation.IncomeMultiplier} - {tierText}`
	end
	line(tierText, if mutation then mutation.Color else rarityColor, 2, 15)
	line(`{ParadeConfig.FormatCoins(walker.Price)} Coins`, Theme.Color.AccentWarning, 3, 17)
end

local function buildPrompt(model: Model, walker: Walker)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = `Buy ({ParadeConfig.FormatCoins(walker.Price)})`
	prompt.ObjectText = Mutations.DecorateName(EggConfig.DisplayName(walker.Id), walker.Mutation)
	-- Instant: young players tap, they don't hold. The server still guards
	-- against double purchases.
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = ParadeConfig.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = primary
	prompt.Triggered:Connect(function()
		Net.GetEvent(Constants.REMOTE_NAMES.Parade.Buy):FireServer(walker.Uid)
	end)
end

local function placeModel(entry: Rendered, serverTime: number)
	local position = ParadeConfig.PositionAt(entry.Walker, serverTime)
	-- Waddle: a quick bob plus a side-to-side lean, the "walking plush" look
	-- the genre's characters have, for the price of two sines.
	local t = serverTime * 6 + entry.Phase
	local bob = math.abs(math.sin(t)) * 0.35
	local lean = math.sin(t) * 0.09
	local target = CFrame.lookAt(position, position + walkDirection) * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, lean)
	entry.Model:PivotTo(target * entry.BuildPivot)
end

local function removeRendered(uid: string, sold: boolean, buyerName: string?)
	local entry = rendered[uid]
	if not entry then
		return
	end
	rendered[uid] = nil

	local primary = entry.Model.PrimaryPart
	if primary then
		local position = primary.Position
		if sold then
			FX.RarityBurst(position, entry.Walker.Rarity)
			FX.FloatingText(position + Vector3.new(0, 4, 0), `SOLD to {buyerName or "someone"}!`, Theme.Color.AccentWarning)
		else
			FX.Burst(position, Theme.RarityColor(entry.Walker.Rarity), 10)
		end
	end
	entry.Model:Destroy()
end

local function addWalker(walker: Walker)
	if rendered[walker.Uid] then
		return
	end
	if ParadeConfig.ProgressAt(walker, workspace:GetServerTimeNow()) >= 1 then
		return
	end

	local ok, modelOrError = pcall(BrainrotModels.BuildStatic, walker.Id, walker.Rarity)
	if not ok or typeof(modelOrError) ~= "Instance" then
		warn(`[ParadeController] could not build "{walker.Id}": {modelOrError}`)
		return
	end
	local model = modelOrError :: Model
	pcall(function()
		model:ScaleTo(ParadeConfig.MODEL_SCALE)
	end)
	Mutations.ApplyVisual(model, walker.Mutation)

	-- ScaleTo scales around the pivot, not the feet, so the model may now
	-- float or sink. Re-seat it so its lowest point is back on Y = 0 before
	-- capturing the build-space pivot.
	local boxCFrame, boxSize = model:GetBoundingBox()
	local bottomY = boxCFrame.Position.Y - boxSize.Y / 2
	model:PivotTo(model:GetPivot() - Vector3.new(0, bottomY, 0))

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- Walkers are scenery players can walk through: the carpet is a
			-- stage, not an obstacle course.
			descendant.CanCollide = false
			descendant.CastShadow = false
		elseif descendant:IsA("ParticleEmitter") then
			-- Rarity particles are decoration; LightingController turns
			-- tagged emitters off on low graphics quality.
			CollectionService:AddTag(descendant, "DecorEmitter")
		end
	end

	-- Captured while the model still sits at its build-space origin.
	local buildPivot = model:GetPivot()

	local entry: Rendered = {
		Walker = walker,
		Model = model,
		BuildPivot = buildPivot,
		Phase = math.random() * math.pi * 2,
	}
	buildLabel(model, walker)
	buildPrompt(model, walker)
	placeModel(entry, workspace:GetServerTimeNow())
	model.Parent = getFolder()
	rendered[walker.Uid] = entry
end

local function onState(list: { Walker })
	local keep: { [string]: boolean } = {}
	for _, walker in list do
		keep[walker.Uid] = true
		addWalker(walker)
	end
	for uid in rendered do
		if not keep[uid] then
			removeRendered(uid, false, nil)
		end
	end
end

local function isNearCarpet(): boolean
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - carpetMidpoint).Magnitude <= ParadeConfig.RENDER_DISTANCE
end

function ParadeController.Init()
	Net.GetEvent(Constants.REMOTE_NAMES.Parade.Spawned).OnClientEvent:Connect(function(walker)
		if type(walker) == "table" then
			addWalker(walker :: Walker)
		end
	end)
	Net.GetEvent(Constants.REMOTE_NAMES.Parade.Sold).OnClientEvent:Connect(function(uid, buyerName)
		if type(uid) == "string" then
			removeRendered(uid, true, if type(buyerName) == "string" then buyerName else nil)
		end
	end)
	Net.GetEvent(Constants.REMOTE_NAMES.Parade.State).OnClientEvent:Connect(function(list)
		if type(list) == "table" then
			onState(list :: { Walker })
		end
	end)
	Net.GetEvent(Constants.REMOTE_NAMES.Parade.RequestState):FireServer()

	-- One loop animates every walker. Far from the carpet it only checks for
	-- walkers that have reached the exit (twice a second) and skips the
	-- per-walker PivotTo work entirely.
	local sinceFarCheck = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = workspace:GetServerTimeNow()
		local near = isNearCarpet()
		if not near then
			sinceFarCheck += dt
			if sinceFarCheck < 0.5 then
				return
			end
			sinceFarCheck = 0
		end

		for uid, entry in rendered do
			if ParadeConfig.ProgressAt(entry.Walker, now) >= 1 then
				removeRendered(uid, false, nil)
			elseif near then
				placeModel(entry, now)
			end
		end
	end)
end

return ParadeController
