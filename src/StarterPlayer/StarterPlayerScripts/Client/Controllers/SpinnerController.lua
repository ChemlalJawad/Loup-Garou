--!strict
-- Spins scenery tagged Constants.TAGS.Spinner (windmill sails, ...) around
-- its pivot on the client: zero network traffic, and only while a player is
-- close enough to see it. Attributes on the tagged Model: SpinAxis ("X",
-- "Y" or "Z", world axis) and SpinSpeed (degrees per second).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local SpinnerController = {}

local VISIBLE_DISTANCE = 450
local AXES = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }

type Spinner = { Model: Model, Base: CFrame, Axis: Vector3, Speed: number }

local spinners: { [Model]: Spinner } = {}

local function add(instance: Instance)
	if not instance:IsA("Model") or spinners[instance] then
		return
	end
	local axisName = instance:GetAttribute("SpinAxis")
	local speed = instance:GetAttribute("SpinSpeed")
	spinners[instance] = {
		Model = instance,
		Base = instance:GetPivot(),
		Axis = AXES[if type(axisName) == "string" then axisName else "Y"] or Vector3.yAxis,
		Speed = math.rad(if type(speed) == "number" then speed else 30),
	}
end

local function remove(instance: Instance)
	if instance:IsA("Model") then
		spinners[instance] = nil
	end
end

function SpinnerController.Init()
	local tag = Constants.TAGS.Spinner
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	-- Also fires on stream-out; a re-streamed model comes back via Added.
	CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)

	local localPlayer = Players.LocalPlayer
	RunService.Heartbeat:Connect(function()
		if next(spinners) == nil then
			return
		end
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local here = if root and root:IsA("BasePart") then root.Position else nil
		local now = workspace:GetServerTimeNow()
		for model, spinner in spinners do
			if model.Parent == nil then
				spinners[model] = nil
			elseif not here or (spinner.Base.Position - here).Magnitude <= VISIBLE_DISTANCE then
				local rotation = CFrame.fromAxisAngle(spinner.Axis, (now * spinner.Speed) % (math.pi * 2))
				-- Rotate in world space around the pivot's position.
				model:PivotTo(CFrame.new(spinner.Base.Position) * rotation * (spinner.Base - spinner.Base.Position))
			end
		end
	end)
end

return SpinnerController
