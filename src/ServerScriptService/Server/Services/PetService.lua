--!strict
-- Spawns and drives the visible, following Brainrot companion for every
-- player: the equipped entry from DataService made real in Workspace.
--
-- Reconciliation happens on profile load/change and on character respawn, so
-- the companion always matches `DataService.GetEquipped(player)` without a
-- server-wide per-frame loop - movement is delegated entirely to
-- AlignPosition/AlignOrientation constraints, which replicate smoothly and
-- keep working even if this server's Heartbeat is busy elsewhere.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local BrainrotModels = require(ReplicatedStorage.Shared.Brainrots.BrainrotModels)
local DataService = require(ServerScriptService.Server.Services.DataService)

local PetService = {}

-- Tuning: how the companion trails the player. Offset is in the HRP's local
-- space (behind and to the side); the bob is a slow vertical sine nudged onto
-- the AlignPosition target attachment by a per-companion Heartbeat connection
-- (created/destroyed with the companion) rather than a global per-frame loop.
local FOLLOW_OFFSET = Vector3.new(3, 1.5, 3.5) -- +X right, +Y up, +Z behind
local POSITION_RESPONSIVENESS = 6 -- lower = more lag ("alive" feel)
local POSITION_MAX_FORCE = 15000
local ORIENTATION_RESPONSIVENESS = 4
local ORIENTATION_MAX_FORCE = 15000
local BOB_AMPLITUDE = 0.35
local BOB_PERIOD = 2.6

type Companion = {
	Model: Model,
	Attachment: Attachment,
	AlignPosition: AlignPosition,
	AlignOrientation: AlignOrientation,
	TargetAttachment: Attachment, -- a tiny anchored-less attachment we move by hand each bob step
	BobConnection: RBXScriptConnection?,
}

local companions: { [Player]: Companion } = {}
-- CharacterAdded connections, tracked per player so PlayerRemoving can
-- disconnect them even for a player who left before ever equipping anything.
local characterConnections: { [Player]: RBXScriptConnection } = {}
local petsFolder: Folder? = nil

local function getPetsFolder(): Folder
	if petsFolder and petsFolder.Parent then
		return petsFolder
	end
	local existing = Workspace:FindFirstChild("Pets")
	if existing and existing:IsA("Folder") then
		petsFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Pets"
	folder.Parent = Workspace
	petsFolder = folder
	return folder
end

local function fireEquippedChanged(player: Player, ownedId: string?, rarity: string?)
	Net.GetEvent(Constants.REMOTE_NAMES.Pets.EquippedChanged):FireClient(player, ownedId, rarity)
end

-- Tears down a player's companion model + all its connections/constraints.
-- Safe to call repeatedly (e.g. despawn-before-respawn) - every step is
-- guarded so a half-built companion never leaks a connection.
local function despawnCompanion(player: Player)
	local companion = companions[player]
	if not companion then
		return
	end
	companions[player] = nil

	if companion.BobConnection then
		companion.BobConnection:Disconnect()
	end
	if companion.Model.Parent then
		companion.Model:Destroy()
	end
end

-- Builds a fresh companion model for `ownedId`/`rarity`, welds on the
-- follow rig (AlignPosition/AlignOrientation driven off the player's HRP),
-- and parents it into Workspace.Pets. Returns nil (and warns) if the model
-- can't be built - callers must not let a bad/unknown id break spawn.
local function spawnCompanion(player: Player, character: Model, ownedId: string, rarity: string)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return
	end

	local ok, modelOrError = pcall(BrainrotModels.Build, ownedId, rarity)
	if not ok or typeof(modelOrError) ~= "Instance" then
		warn(`[PetService] failed to build companion "{ownedId}" for {player.Name}: {tostring(modelOrError)}`)
		return
	end
	local model = modelOrError :: Model
	local primary = model.PrimaryPart
	if not primary then
		warn(`[PetService] companion "{ownedId}" has no PrimaryPart, skipping spawn for {player.Name}`)
		model:Destroy()
		return
	end

	model.Name = `Companion_{player.UserId}`
	model:PivotTo(humanoidRootPart.CFrame * CFrame.new(FOLLOW_OFFSET))
	model.Parent = getPetsFolder()

	-- Follow rig: a fixed attachment on the companion, a "hand-driven" target
	-- attachment parented to the player's HRP that we nudge every bob tick,
	-- and AlignPosition/AlignOrientation bridging the two. RigidityEnabled is
	-- left off and Responsiveness tuned low so the companion visibly lags -
	-- that lag is what reads as "alive" rather than a rigidly bolted-on prop.
	local companionAttachment = Instance.new("Attachment")
	companionAttachment.Name = "CompanionAttachment"
	companionAttachment.Parent = primary

	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = `CompanionTarget_{player.UserId}`
	targetAttachment.Position = FOLLOW_OFFSET
	targetAttachment.Parent = humanoidRootPart

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment
	alignPosition.Attachment0 = companionAttachment
	alignPosition.Attachment1 = targetAttachment
	alignPosition.RigidityEnabled = false
	alignPosition.Responsiveness = POSITION_RESPONSIVENESS
	alignPosition.MaxForce = POSITION_MAX_FORCE
	alignPosition.Parent = primary

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	alignOrientation.Attachment0 = companionAttachment
	alignOrientation.Attachment1 = targetAttachment
	alignOrientation.RigidityEnabled = false
	alignOrientation.Responsiveness = ORIENTATION_RESPONSIVENESS
	alignOrientation.MaxTorque = ORIENTATION_MAX_FORCE
	alignOrientation.Parent = primary

	-- Smooth client-side motion + no server-authority contention: the owning
	-- player simulates their own companion.
	pcall(function()
		primary:SetNetworkOwner(player)
	end)

	local companion: Companion = {
		Model = model,
		Attachment = companionAttachment,
		AlignPosition = alignPosition,
		AlignOrientation = alignOrientation,
		TargetAttachment = targetAttachment,
		BobConnection = nil,
	}

	-- Gentle hover bob: nudges the target attachment's local Y in a slow sine
	-- wave. This is a per-companion RenderStepped-equivalent, but since it's
	-- driven from a Heartbeat connection that's created and destroyed with the
	-- companion (not a global per-frame scan over all players), the cost stays
	-- proportional to "how many companions currently exist," same as any other
	-- part of this system.
	local startTime = os.clock()
	companion.BobConnection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startTime
		local bob = math.sin((elapsed / BOB_PERIOD) * math.pi * 2) * BOB_AMPLITUDE
		targetAttachment.Position = FOLLOW_OFFSET + Vector3.new(0, bob, 0)
	end)

	companions[player] = companion
end

-- Reconciles the visible companion with DataService.GetEquipped(player):
-- despawns if nothing is equipped or the id/rarity no longer matches,
-- (re)spawns if it does and nothing correct is currently alive.
local function reconcile(player: Player)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end

	local equipped = DataService.GetEquipped(player)
	local companion = companions[player]

	if not equipped then
		if companion then
			despawnCompanion(player)
			fireEquippedChanged(player, nil, nil)
		end
		return
	end

	local alreadyCorrect = companion ~= nil
		and companion.Model:GetAttribute("BrainrotId") == equipped.Id
		and companion.Model:GetAttribute("BrainrotUid") == equipped.Uid

	if alreadyCorrect then
		return
	end

	despawnCompanion(player)
	spawnCompanion(player, character, equipped.Id, equipped.Rarity)

	local respawned = companions[player]
	if respawned then
		respawned.Model:SetAttribute("BrainrotId", equipped.Id)
		respawned.Model:SetAttribute("BrainrotUid", equipped.Uid)
		respawned.Model:SetAttribute("Rarity", equipped.Rarity)
	end

	fireEquippedChanged(player, equipped.Id, equipped.Rarity)
end

local function onCharacterAdded(player: Player, character: Model)
	-- Wait for the HumanoidRootPart so spawnCompanion has something to attach
	-- to; bounded so a malformed character can't hang this forever.
	character:WaitForChild("HumanoidRootPart", 10)
	reconcile(player)
end

local function onPlayerAdded(player: Player)
	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character :: Model)
	end
end

local function onPlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end
	despawnCompanion(player)
end

function PetService.Init()
	DataService.ProfileLoaded.Event:Connect(function(player: Player)
		reconcile(player)
	end)
	DataService.ProfileChanged.Event:Connect(function(player: Player)
		reconcile(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return PetService
