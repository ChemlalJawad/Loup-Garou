--!strict
-- Jump pads and trampolines, applied on the client.
--
-- A player's character is physically simulated by their own client, so a
-- launch applied here takes effect on the very next frame; the same launch
-- done on the server would arrive a round trip late and feel mushy (or be
-- overwritten by the client's own simulation). Pads carry no economic value,
-- so there's nothing to cheat - the server doesn't need to validate them.
--
-- Pads are found by CollectionService tag (Constants.TAGS), so any zone can
-- place one and it just works, including ones streamed in later.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local FX = require(ReplicatedStorage.Shared.Effects.FX)

local MovementController = {}

local localPlayer = Players.LocalPlayer

-- Per-pad debounce: a character's several limbs touch a pad within the same
-- few frames; one launch per contact is the intent.
local PAD_COOLDOWN = 0.45
local lastLaunchAt: { [Instance]: number } = {}
local connections: { [Instance]: RBXScriptConnection } = {}

local function localRootFromHit(hit: BasePart): (BasePart?, Humanoid?)
	local character = localPlayer.Character
	if not character or not hit:IsDescendantOf(character) then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

local function ready(pad: Instance): boolean
	local now = os.clock()
	local last = lastLaunchAt[pad]
	if last and now - last < PAD_COOLDOWN then
		return false
	end
	lastLaunchAt[pad] = now
	return true
end

local function launch(root: BasePart, humanoid: Humanoid, velocity: Vector3)
	-- Leave the ground state first, otherwise the Humanoid's grounded
	-- controller can eat the vertical impulse on the same frame.
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	root.AssemblyLinearVelocity = velocity
end

local function onJumpPadTouched(pad: BasePart, hit: BasePart)
	local root, humanoid = localRootFromHit(hit)
	if not root or not humanoid or not ready(pad) then
		return
	end
	local attribute = pad:GetAttribute("LaunchVelocity")
	local velocity = if typeof(attribute) == "Vector3" then attribute else Vector3.new(0, 90, 0)
	launch(root, humanoid :: Humanoid, velocity)
	FX.Burst(pad.Position + Vector3.new(0, 1, 0), Theme.Color.AccentPrimary, 16)
end

local function onBouncyTouched(pad: BasePart, hit: BasePart)
	local root, humanoid = localRootFromHit(hit)
	if not root or not humanoid or not ready(pad) then
		return
	end
	local attribute = pad:GetAttribute("BouncePower")
	local power = if type(attribute) == "number" then attribute else 70
	-- Keep horizontal momentum so hopping between trampolines works; only
	-- the vertical component is replaced.
	local current = root.AssemblyLinearVelocity
	launch(root, humanoid :: Humanoid, Vector3.new(current.X, power, current.Z))
	FX.Burst(pad.Position + Vector3.new(0, 0.5, 0), pad.Color, 10)
end

local function watch(tag: string, handler: (BasePart, BasePart) -> ())
	local function attach(instance: Instance)
		if connections[instance] or not instance:IsA("BasePart") then
			return
		end
		local pad = instance :: BasePart
		connections[pad] = pad.Touched:Connect(function(hit)
			handler(pad, hit)
		end)
	end
	local function detach(instance: Instance)
		local connection = connections[instance]
		if connection then
			connection:Disconnect()
			connections[instance] = nil
		end
		lastLaunchAt[instance] = nil
	end

	for _, instance in CollectionService:GetTagged(tag) do
		attach(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(attach)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(detach)
end

function MovementController.Init()
	watch(Constants.TAGS.JumpPad, onJumpPadTouched)
	watch(Constants.TAGS.Bouncy, onBouncyTouched)
end

return MovementController
