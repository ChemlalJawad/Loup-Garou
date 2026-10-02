--!strict
-- The grapple rig, modelled on the anime's gear:
--
--   Hold Q / E (L1 / R1, or the on-screen buttons): fire the left / right
--     hook. It FLIES to what you're aiming at and bites; the cable then
--     stays taut (it auto-winds any slack), so gravity swings you around
--     the anchor like a pendulum. Let go to release and keep your momentum.
--   Hold Space (A, or "Gas"): hooked - reel the cables in hard; unhooked,
--     in the air - a gas burst along the camera. On the ground Space jumps.
--   Tap Shift (B, or "Dash"): a quick gas dash in the direction you steer.
--   WASD in the air: steer.
--   Click / F (X, or "Slash"): swing both blades - a full spin in the air.
--     Aim for the glowing lump on a giant's neck; faster = cleaner cut.
--   G (Y, or "Flare"): fire a green signal flare.
--
-- Grabbed by a giant: every key wriggles (mash to get free). Swatted: you
-- go flying and your hooks let go.
--
-- Gas shows as white jets behind you, and the view widens with speed.
--
-- Movement is simulated here on the client (it owns its character's
-- physics), so it feels instant; the server relays your cables to other
-- players so they see you swing, and decides all damage itself.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Parent.Effects)

local GrappleController = {}

type Hook = {
	Name: string,
	Side: number, -- -1 left, 1 right
	Held: boolean,
	Hip: Attachment?,
	-- Flying: the tip travels to Target; Attached: Anchor holds the cable.
	State: "Idle" | "Flying" | "Attached",
	Tip: Attachment?, -- flying hook head (on the terrain, moved each frame)
	TargetPart: BasePart?,
	TargetLocal: Vector3?, -- target in TargetPart's space (it may move)
	Anchor: Attachment?,
	Length: number,
	Beam: Beam?,
}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local settings = Config.Grapple

local character: Model? = nil
local root: BasePart? = nil
local humanoid: Humanoid? = nil
local hooks: { [string]: Hook } = {
	Left = { Name = "Left", Side = -1, Held = false, State = "Idle", Length = 0 },
	Right = { Name = "Right", Side = 1, Held = false, State = "Idle", Length = 0 },
}
local gas = settings.GasMax
local gasHeld = false
local lastSlash = 0
local lastDash = 0
local spinUntil = 0
local spinStartYaw = 0
local fxFolder: Folder
local hookRemote: RemoteEvent? = nil
local gasPuff: ParticleEmitter? = nil -- white jets behind you while gas flows
local BASE_FOV = 70
local held = false -- in a giant's hand: inputs wriggle instead
local wind: Sound? = nil
local struggleRemote: RemoteEvent? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function remote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

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
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character) -- hooks never bite hunters
		end
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
	local fromRoot = target - root.Position
	if fromRoot.Magnitude > settings.Range then
		return nil
	end
	-- Re-cast from the hunter, so the hook lands on something they can see.
	return Workspace:Raycast(root.Position, fromRoot.Unit * (fromRoot.Magnitude + 4), rayParams) or first
end

local function makeBeam(from: Attachment, to: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Name = "Cable"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Width0 = 0.16
	beam.Width1 = 0.16
	beam.FaceCamera = true
	beam.Segments = 10
	beam.Color = ColorSequence.new(Color3.fromRGB(200, 205, 215))
	beam.LightEmission = 0.25
	beam.Parent = fxFolder
	return beam
end

local function release(hook: Hook, tellServer: boolean?)
	if hook.Beam then
		hook.Beam:Destroy()
	end
	if hook.Anchor then
		hook.Anchor:Destroy()
	end
	if hook.Tip then
		hook.Tip:Destroy()
	end
	local wasActive = hook.State ~= "Idle"
	hook.Beam, hook.Anchor, hook.Tip = nil, nil, nil
	hook.TargetPart, hook.TargetLocal = nil, nil
	hook.State = "Idle"
	if wasActive and tellServer ~= false and hookRemote then
		hookRemote:FireServer(hook.Name, nil, nil)
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
	release(hook, false)
	local targetPart = hit.Instance :: BasePart
	hook.TargetPart = targetPart
	hook.TargetLocal = targetPart.CFrame:PointToObjectSpace(hit.Position)
	-- The flying hook head: an attachment on the terrain we slide each frame.
	local tip = Instance.new("Attachment")
	tip.Name = "HookTip"
	tip.WorldPosition = hook.Hip.WorldPosition
	tip.Parent = Workspace.Terrain
	hook.Tip = tip
	hook.Beam = makeBeam(hook.Hip, tip)
	hook.State = "Flying"
	Effects.Play("Hook", nil, 1, if hook.Side < 0 then 1 else 1.12)
end

local function bite(hook: Hook)
	local part, localPos = hook.TargetPart, hook.TargetLocal
	if not root or not part or not localPos or not part:IsDescendantOf(Workspace) then
		release(hook, false)
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.Name = "GrappleAnchor"
	anchor.Position = localPos
	anchor.Parent = part
	hook.Anchor = anchor
	if hook.Tip then
		hook.Tip:Destroy()
		hook.Tip = nil
	end
	if hook.Beam then
		hook.Beam.Attachment1 = anchor
	end
	hook.Length = (anchor.WorldPosition - root.Position).Magnitude
	hook.State = "Attached"
	if hookRemote then
		hookRemote:FireServer(hook.Name, part, localPos)
	end
	-- From the ground, a hop so the swing lifts you instead of dragging you.
	if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
		root.AssemblyLinearVelocity += Vector3.new(0, settings.LaunchImpulse, 0)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function setBladeTrails(enabled: boolean)
	if not character then
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Trail") and descendant.Name == "BladeTrail" then
			descendant.Enabled = enabled
		end
	end
end

local function slashFx()
	if not root then
		return
	end
	setBladeTrails(true)
	task.delay(0.35, function()
		setBladeTrails(false)
	end)
	-- A bright arc in front of you, for the swing's "shing".
	local arc = Instance.new("Part")
	arc.Anchored = true
	arc.CanCollide = false
	arc.CanQuery = false
	arc.CanTouch = false
	arc.CastShadow = false
	arc.Material = Enum.Material.Neon
	arc.Color = Color3.fromRGB(220, 240, 255)
	arc.Size = Vector3.new(8, 0.12, 0.5)
	arc.CFrame = root.CFrame * CFrame.new(0, 0.4, -3)
	arc.Parent = fxFolder
	TweenService:Create(arc, TweenInfo.new(0.2), { Transparency = 1, Size = Vector3.new(11, 0.04, 0.2) }):Play()
	task.delay(0.25, function()
		arc:Destroy()
	end)
end

local function slash()
	local now = os.clock()
	if now - lastSlash < Config.Blades.SlashCooldown or not humanoid or humanoid.Health <= 0 or not root then
		return
	end
	lastSlash = now
	slashFx()
	Effects.Play("Slash")
	-- In the air, the swing is a full spin: the signature move.
	if humanoid.FloorMaterial == Enum.Material.Air then
		spinUntil = now + 0.32
		local look = root.CFrame.LookVector
		spinStartYaw = math.atan2(-look.X, -look.Z)
	end
	remote(Config.Remotes.Slash):FireServer()
end

local function dash()
	local now = os.clock()
	if now - lastDash < settings.DashCooldown or gas < settings.GasPerDash or not root or not humanoid then
		return
	end
	lastDash = now
	gas -= settings.GasPerDash
	if gasPuff then
		gasPuff:Emit(16)
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = camera.CFrame.LookVector
	end
	root.AssemblyLinearVelocity += direction.Unit * settings.DashImpulse + Vector3.new(0, 8, 0)
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function attachedCount(): number
	local count = 0
	for _, hook in hooks do
		if hook.State == "Attached" then
			count += 1
		end
	end
	return count
end

local function step(dt: number)
	if not root or not humanoid then
		return
	end
	if humanoid.Health <= 0 or held then
		releaseAll()
		if gasPuff then
			gasPuff.Enabled = false
		end
		if wind then
			wind.Volume = 0
		end
		return
	end
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	local position = root.Position
	local velocity = root.AssemblyLinearVelocity
	local reeling = gasHeld and gas > 0 and attachedCount() > 0

	for _, hook in hooks do
		if hook.State == "Flying" and hook.Tip and hook.TargetPart and hook.TargetLocal then
			-- Fly the hook head toward its (possibly moving) target.
			if not hook.TargetPart:IsDescendantOf(Workspace) then
				release(hook, false)
			else
				local target = hook.TargetPart.CFrame:PointToWorldSpace(hook.TargetLocal)
				local toTarget = target - hook.Tip.WorldPosition
				local travel = settings.HookSpeed * dt
				if toTarget.Magnitude <= travel then
					bite(hook)
				else
					hook.Tip.WorldPosition += toTarget.Unit * travel
				end
			end
		elseif hook.State == "Attached" and hook.Anchor then
			local anchor = hook.Anchor
			if not anchor.Parent or not (anchor.Parent :: Instance):IsDescendantOf(Workspace) then
				release(hook) -- whatever it bit is gone (a giant steamed away)
				continue
			end
			local toAnchor = anchor.WorldPosition - position
			local distance = toAnchor.Magnitude
			if distance < settings.ReleaseDistance then
				release(hook)
				continue
			end
			local u = toAnchor / distance
			-- The cable auto-winds: it never gets longer than you are far.
			hook.Length = math.min(hook.Length, distance)
			if reeling then
				hook.Length = math.max(settings.ReleaseDistance, hook.Length - settings.ReelSpeed * dt)
				velocity += u * settings.ReelAcceleration * dt
				gas -= settings.GasPerSecondReel * dt
			else
				velocity += u * settings.SlackPull * dt
			end
			-- Taut cable: cancel any motion that would stretch it, and pull
			-- back if we're past its length. That's the pendulum swing.
			if distance > hook.Length then
				local outward = velocity:Dot(u)
				if outward < 0 then
					velocity -= u * outward
				end
				velocity += u * (distance - hook.Length) * 12 * dt
			end
		end
	end

	local hooked = attachedCount() > 0
	local boosting = false
	if airborne then
		-- WASD steering in the air.
		velocity += humanoid.MoveDirection * settings.AirControl * dt
		-- Unhooked gas burst.
		if gasHeld and not hooked and gas > 0 then
			boosting = true
			velocity += camera.CFrame.LookVector * settings.BoostAcceleration * dt
			gas -= settings.GasPerSecondBoost * dt
		end
	elseif not hooked then
		gas = math.min(settings.GasMax, gas + settings.GasRegenPerSecondGrounded * dt)
	end
	if gas <= 0 then
		gas = 0
	end
	if gasPuff then
		gasPuff.Enabled = reeling or boosting
	end

	if velocity.Magnitude > settings.MaxSpeed then
		velocity = velocity.Unit * settings.MaxSpeed
	end
	-- Speed widens the view a little and the wind picks up: swinging
	-- should feel fast.
	local rush = math.clamp((velocity.Magnitude - 40) / (settings.MaxSpeed - 40), 0, 1)
	camera.FieldOfView += (BASE_FOV + rush * 18 - camera.FieldOfView) * math.min(dt * 4, 1)
	if wind then
		wind.Volume = Config.Sounds.Wind.Volume * rush
	end
	if velocity ~= root.AssemblyLinearVelocity then
		root.AssemblyLinearVelocity = velocity
		if hooked and not airborne and velocity.Y > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end

	-- Body orientation in the air: face where you're flying, lean into it,
	-- or spin through a slash.
	local now = os.clock()
	if airborne then
		humanoid.AutoRotate = false
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		local yaw: number? = nil
		if now < spinUntil then
			yaw = spinStartYaw + (1 - (spinUntil - now) / 0.32) * math.pi * 2
		elseif flat.Magnitude > 12 then
			yaw = math.atan2(-flat.X, -flat.Z)
		end
		if yaw then
			local lean = math.clamp(-velocity.Y / 120, -0.5, 0.5)
			local target = CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(lean, 0, 0)
			local blend = if now < spinUntil then 1 else math.min(dt * 10, 1)
			root.CFrame = root.CFrame:Lerp(target, blend)
		end
	else
		humanoid.AutoRotate = true
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
		local puff = Instance.new("ParticleEmitter")
		puff.Name = "GasPuff"
		puff.Color = ColorSequence.new(Color3.fromRGB(240, 242, 248))
		puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 2.2) })
		puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		puff.Lifetime = NumberRange.new(0.3, 0.55)
		puff.Speed = NumberRange.new(6, 12)
		puff.SpreadAngle = Vector2.new(25, 25)
		puff.EmissionDirection = Enum.NormalId.Back
		puff.Rate = 60
		puff.Enabled = false
		puff.Parent = root
		gasPuff = puff
	end
end

-- Other hunters' cables, relayed by the server, drawn locally.
local remoteCables: { [Player]: { [string]: { Beam: Beam, Anchor: Attachment, Hip: Attachment } } } = {}

local function clearRemoteCable(other: Player, side: string)
	local cables = remoteCables[other]
	local cable = cables and cables[side]
	if cable then
		cable.Beam:Destroy()
		cable.Anchor:Destroy()
		cable.Hip:Destroy()
		cables[side] = nil
	end
end

local function onRemoteHook(other: Player, side: string, part: BasePart?, localPos: Vector3?)
	if other == player or (side ~= "Left" and side ~= "Right") then
		return
	end
	clearRemoteCable(other, side)
	local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
	if not part or not localPos or not otherRoot or not otherRoot:IsA("BasePart") then
		return
	end
	local hip = Instance.new("Attachment")
	hip.Position = Vector3.new(if side == "Left" then -0.9 else 0.9, -0.6, 0)
	hip.Parent = otherRoot
	local anchor = Instance.new("Attachment")
	anchor.Position = localPos
	anchor.Parent = part
	remoteCables[other] = remoteCables[other] or {}
	remoteCables[other][side] = { Beam = makeBeam(hip, anchor), Anchor = anchor, Hip = hip }
end

function GrappleController.Gas(): number
	return gas
end

function GrappleController.IsHooked(): boolean
	return attachedCount() > 0
end

-- "Idle" | "Flying" | "Attached" for the left and right hooks.
function GrappleController.HookStates(): (string, string)
	return hooks.Left.State, hooks.Right.State
end

function GrappleController.Speed(): number
	return if root then root.AssemblyLinearVelocity.Magnitude else 0
end

function GrappleController.IsHeld(): boolean
	return held
end

local function struggle()
	if struggleRemote then
		struggleRemote:FireServer()
	end
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
	-- Keep other hunters out of the hook raycasts as they respawn.
	Players.PlayerAdded:Connect(function(other)
		other.CharacterAdded:Connect(refreshFilter)
	end)
	for _, other in Players:GetPlayers() do
		other.CharacterAdded:Connect(refreshFilter)
	end
	Players.PlayerRemoving:Connect(function(other)
		clearRemoteCable(other, "Left")
		clearRemoteCable(other, "Right")
		remoteCables[other] = nil
	end)

	local function hookAction(name: string): (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
		return function(_action, state, _input)
			local hook = hooks[name]
			if held then
				if state == Enum.UserInputState.Begin then
					struggle()
				end
				return Enum.ContextActionResult.Sink
			end
			if state == Enum.UserInputState.Begin then
				hook.Held = true
				fire(hook)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				hook.Held = false
				release(hook)
			end
			return Enum.ContextActionResult.Sink
		end
	end
	ContextActionService:BindAction("HookLeft", hookAction("Left"), true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("HookRight", hookAction("Right"), true, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("HookLeft", "L Hook")
	ContextActionService:SetTitle("HookRight", "R Hook")

	ContextActionService:BindActionAtPriority("Gas", function(_action, state, input)
		if held then
			if state == Enum.UserInputState.Begin then
				struggle()
			end
			return Enum.ContextActionResult.Sink
		end
		if state == Enum.UserInputState.Begin then
			-- On the ground and unhooked, Space is still a jump.
			if input.KeyCode == Enum.KeyCode.Space and humanoid and humanoid.FloorMaterial ~= Enum.Material.Air and attachedCount() == 0 then
				return Enum.ContextActionResult.Pass
			end
			gasHeld = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			gasHeld = false
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:SetTitle("Gas", "Gas")

	ContextActionService:BindAction("Dash", function(_action, state, _input)
		if state == Enum.UserInputState.Begin then
			if held then
				struggle()
			else
				dash()
			end
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("Dash", "Dash")

	ContextActionService:BindAction("Slash", function(_action, state, _input)
		if state == Enum.UserInputState.Begin then
			if held then
				struggle()
			else
				slash()
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.F, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("Slash", "Slash")

	ContextActionService:BindAction("Flare", function(_action, state, _input)
		if state == Enum.UserInputState.Begin and not held then
			remote(Config.Remotes.Flare):FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle("Flare", "Flare")

	task.spawn(function()
		local hookEvent = remote(Config.Remotes.Hook)
		hookRemote = hookEvent
		hookEvent.OnClientEvent:Connect(onRemoteHook)
		remote(Config.Remotes.Resupplied).OnClientEvent:Connect(function()
			gas = settings.GasMax
			Effects.Play("Resupply")
		end)
		struggleRemote = remote(Config.Remotes.Struggle)
		remote(Config.Remotes.Held).OnClientEvent:Connect(function(state: string, reason: any)
			if state == "Grabbed" then
				held = true
				releaseAll()
			else
				held = false
				-- Wriggled out or cut loose: a hop up and back, out of its reach.
				if (reason == "Escaped" or reason == "Rescued") and root and humanoid then
					root.AssemblyLinearVelocity = -root.CFrame.LookVector * 35 + Vector3.new(0, settings.EscapeHop, 0)
					humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
				end
			end
		end)
		remote(Config.Remotes.Knocked).OnClientEvent:Connect(function(push: Vector3)
			if typeof(push) ~= "Vector3" or not root or not humanoid or held then
				return
			end
			releaseAll()
			root.AssemblyLinearVelocity = push
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			Effects.Shake(1)
		end)
	end)

	local windSound = Instance.new("Sound")
	windSound.Name = "SpeedWind"
	windSound.SoundId = Config.Sounds.Wind.Id
	windSound.PlaybackSpeed = Config.Sounds.Wind.Pitch
	windSound.Looped = true
	windSound.Volume = 0
	windSound.Parent = game:GetService("SoundService")
	windSound:Play()
	wind = windSound

	RunService.Heartbeat:Connect(step)
end

return GrappleController
