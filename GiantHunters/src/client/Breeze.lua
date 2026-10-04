--!strict
-- The breeze, on this client only: washing on the lines flaps and the
-- market awnings sway (parts tagged Config.Tags.Sway by the map). Only
-- those near the camera move, a dozen times a second; it blows harder in
-- the rain. Each part swings round its top edge from where the map put it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Weather = require(script.Parent.Weather)

local Breeze = {}

local EVERY = 1 / 12

-- Where each part was built (kept by instance, so a part that streams out
-- and back in never drifts).
local base: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local swaying: { [BasePart]: number } = {} -- part -> its own phase

local function add(instance: Instance)
	if instance:IsA("BasePart") then
		if not base[instance] then
			base[instance] = instance.CFrame
		end
		swaying[instance] = math.random() * 6
	end
end

function Breeze.Init()
	local tag = Config.Tags.Sway
	for _, part in CollectionService:GetTagged(tag) do
		add(part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(part)
		if part:IsA("BasePart") then
			swaying[part] = nil
		end
	end)

	local clock, pending = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		pending += dt
		if pending < EVERY then
			return
		end
		pending = 0
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local here = camera.CFrame.Position
		local wind = 1 + Weather.Amount() * (if Weather.Kind() == "Rain" then 0.8 else 0)
		local parts: { BasePart } = {}
		local frames: { CFrame } = {}
		for part, phase in swaying do
			local from = base[part]
			if from and (from.Position - here).Magnitude < Config.Ambient.SwayRange then
				local top = part.Size.Y / 2
				-- Washing flaps; awnings (heavier) only sway a little.
				local cloth = part.Name == "Cloth"
				local swing = if cloth
					then (0.25 + math.sin(clock * 0.9 + phase) * 0.12) * wind + math.sin(clock * 6 + phase) * 0.12 * wind
					else math.sin(clock * 1.6 + phase) * 0.035 * wind
				table.insert(parts, part)
				table.insert(frames, from * CFrame.new(0, top, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -top, 0))
			end
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return Breeze
