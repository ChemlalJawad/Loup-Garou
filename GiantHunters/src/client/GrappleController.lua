--!strict
-- The grapple rig: two hooks, a gas boost, and the slash.
--
--   Hold Q / E (L1 / R1, or the on-screen buttons): shoot the left / right
--     hook at what you're aiming at, and get pulled toward it. Let go to
--     release. Hook onto buildings, trees, walls - and giants.
--   Space / Shift (ButtonA, or "Gas"): burst of gas along the camera, for
--     steering and speed. Only in the air, so Space still jumps on the ground.
--   Click / F (X, or "Slash"): swing your blades. Aim for the glowing patch
--     on a giant's neck; the faster you're going, the cleaner the cut.
--
-- Movement is simulated here on the client (it owns its character's
-- physics), so it feels instant. Damage is decided by the server.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local GrappleController = {}

type Hook = {
	Side: number, -- -1 left, 1 right
	Hip: Attachment?,
	Anchor: Attachment?,
	Beam: Beam?,
}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local settings = Config.Grapple

local character: Model? = nil
local root: BasePart? = nil
local humanoid: Humanoid? = nil
local hooks: { [string]: Hook } = {
	Left = { Side = -1 },
	Right = { Side = 1 },
}
local gas = settings.GasMax
local boosting = false
local lastSlash = 0
local fxFolder: Folder

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function aimRay(): Ray
	-- Mouse position on desktop; the screen centre with shift-lock or touch.
	local location = UserInputService:GetMouseLocation()
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.TouchEnabled then
		local size = camera.ViewportSize
		location = Vector2.new(size.X / 2, size.Y / 2)
	end
	return camera:ViewportPointToRay(location.X, location.Y)
end

local function refreshFilter()
	local ignore: { Instance } = { fxFolder }
	if character then
		table.insert(ignore, character)
	end
	rayParams.FilterDescendantsInstances = ignore
end

-- Where a hook fired now would land, or nil if nothing is in range.
function GrappleController.AimTarget(sideOffset: number?): RaycastResult?
	if not root then
		return nil
	end
	local ray = aimRay()
	local reach = settings.Range + (camera.CFrame.Position - root.Position).Magnitude
	local first = Workspace:Raycast(ray.Origin, ray.Direction * reach, rayParams)
	if not first then
		return nil
	end
	local target = first.Position
	if sideOffset and sideOffset ~= 0 then
		target += camera.CFrame.RightVector * sideOffset
	end
	-- Re-cast from the hunter so the hook lands on something they can
	-- actually see from where they are.
	local fromRoot = target - root.Position
	if fromRoot.Magnitude > settings.Range then
		return nil
	end
	return Workspace:Raycast(root.Position, fromRoot.Unit * (fromRoot.Magnitude + 4), rayParams) or first
end

local function release(hook: Hook)
	if hook.Beam then
		hook.Beam:Destroy()
		hook.Beam = nil
	end
	if hook.Anchor then
		hook.Anchor:Destroy()
		hook.Anchor = nil
	end
end

local function releaseAll()
	for _, hook in hooks do
		release(hook)
	end
end

local function fire(hook: Hook)
	if not root or not humanoid or humanoid.Health <= 0 or gas <= 0 or not hook.Hip then
		return
	end
	local hit = GrappleController.AimTarget(hook.Side * settings.HookSideOffset)
	if not hit or not hit.Instance:IsA("BasePart") then
		return
	end
	release(hook)
	local anchor = Instance.new("Attachment")
	anchor.Name = "GrappleAnchor"
	anchor.Parent = hit.Instance
	anchor.WorldPosition = hit.Position
	hook.Anchor = anchor

	local beam = Instance.new("Beam")
	beam.Name = "Cable"
	beam.Attachment0 = hook.Hip
	beam.Attachment1 = anchor
	beam.Width0 = 0.18
	beam.Width1 = 0.18
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Color = ColorSequence.new(Color3.fromRGB(200, 205, 215))
	beam.LightEmission = 0.3
	beam.Parent = fxFolder
	hook.Beam = beam

	-- From the ground, a little hop so the pull lifts you instead of
	-- dragging you along the street.
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		root.AssemblyLinearVelocity += Vector3.new(0, settings.LaunchImpulse, 0)
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
end

local function slashFx()
	if not root then
		return
	end
	-- Two quick bright arcs in front of you: the blade swing.
	for _, side in { -1, 1 } do
		local arc = Instance.new("Part")
		arc.Anchored = true
		arc.CanCollide = false
		arc.CanQuery = false
		arc.CanTouch = false
		arc.CastShadow = false
		arc.Material = Enum.Material.Neon
		arc.Color = Color3.fromRGB(220, 240, 255)
		arc.Size = Vector3.new(6, 0.15, 0.6)
		arc.CFrame = root.CFrame * CFrame.new(side * 1.2, 0.5, -2.5) * CFrame.Angles(0, 0, side * 0.6)
		arc.Parent = fxFolder
		TweenService:Create(arc, TweenInfo.new(0.2), { Transparency = 1, Size = Vector3.new(9, 0.05, 0.3) }):Play()
		task.delay(0.25, function()
			arc:Destroy()
		end)
	end
end

local function slash()
	local now = os.clock()
	if now - lastSlash < Config.Blades.SlashCooldown or not humanoid or humanoid.Health <= 0 then
		return
	end
	lastSlash = now
	slashFx()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Slash) :: RemoteEvent
	remote:FireServer()
end

local function isHooked(): boolean
	return hooks.Left.Anchor ~= nil or hooks.Right.Anchor ~= nil
end

local function step(dt: number)
	if not root or not humanoid then
		return
	end
	if humanoid.Health <= 0 then
		releaseAll()
		return
	end
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	local accel = Vector3.zero
	local hookCount = 0
	for _, hook in hooks do
		local anchor = hook.Anchor
		if anchor then
			if not anchor.Parent or not (anchor.Parent :: Instance):IsDescendantOf(Workspace) then
				release(hook) -- whatever it was on is gone (a giant steamed away)
			else
				local toAnchor = anchor.WorldPosition - root.Position
				if toAnchor.Magnitude < settings.ReleaseDistance then
					release(hook)
				else
					accel += toAnchor.Unit * settings.PullAcceleration
					hookCount += 1
				end
			end
		end
	end
	if boosting and gas > 0 and (airborne or hookCount > 0) then
		accel += camera.CFrame.LookVector * settings.BoostAcceleration
		gas -= settings.GasPerSecondBoost * dt
	end
	gas -= settings.GasPerSecondHooked * hookCount * dt
	if gas <= 0 then
		gas = 0
		releaseAll()
	end
	if hookCount == 0 and not airborne then
		gas = math.min(settings.GasMax, gas + settings.GasRegenPerSecondGrounded * dt)
	end

	if accel.Magnitude > 0 then
		local velocity = root.AssemblyLinearVelocity + accel * dt
		if velocity.Magnitude > settings.MaxSpeed then
			velocity = velocity.Unit * settings.MaxSpeed
		end
		root.AssemblyLinearVelocity = velocity
		if hookCount > 0 and not airborne then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
end

local function onCharacter(newCharacter: Model)
	releaseAll()
	character = newCharacter
	root = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	gas = settings.GasMax
	refreshFilter()
	if root then
		for name, hook in hooks do
			local hip = Instance.new("Attachment")
			hip.Name = `{name}Hip`
			hip.Position = Vector3.new(hook.Side * 0.9, -0.6, 0)
			hip.Parent = root
			hook.Hip = hip
		end
	end
end

function GrappleController.Gas(): number
	return gas
end

function GrappleController.IsHooked(): boolean
	return isHooked()
end

function GrappleController.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "GrappleFx"
	fxFolder.Parent = Workspace
	refreshFilter()

	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(c)
		task.spawn(onCharacter, c)
	end)

	local function hookAction(name: string): (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
		return function(_action, state, _input)
			if state == Enum.UserInputState.Begin then
				fire(hooks[name])
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				release(hooks[name])
			end
			return Enum.ContextActionResult.Sink
		end
	end
	ContextActionService:BindAction("HookLeft", hookAction("Left"), true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("HookRight", hookAction("Right"), true, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("HookLeft", "L Hook")
	ContextActionService:SetTitle("HookRight", "R Hook")

	ContextActionService:BindActionAtPriority("Boost", function(_action, state, input)
		if state == Enum.UserInputState.Begin then
			-- On the ground, Space is still a jump.
			if input.KeyCode == Enum.KeyCode.Space and humanoid and humanoid.FloorMaterial ~= Enum.Material.Air and not isHooked() then
				return Enum.ContextActionResult.Pass
			end
			boosting = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			boosting = false
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonA)
	ContextActionService:SetTitle("Boost", "Gas")

	ContextActionService:BindAction("Slash", function(_action, state, _input)
		if state == Enum.UserInputState.Begin then
			slash()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.F, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("Slash", "Slash")

	task.spawn(function()
		local resupplied = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Resupplied) :: RemoteEvent
		resupplied.OnClientEvent:Connect(function()
			gas = settings.GasMax
		end)
	end)

	RunService.Heartbeat:Connect(step)
end

return GrappleController
