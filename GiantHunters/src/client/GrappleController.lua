--!strict
-- The grapple rig, modelled on the anime's gear:
--
--   Hold Q / E (L1 / R1, or the on-screen buttons): fire the left / right
--     hook. It FLIES to what you're aiming at and bites; the cable then
--     stays taut (it auto-winds any slack), so gravity swings you around
--     the anchor like a pendulum. Let go to release and keep your momentum.
--   Hold Space (A, or "Gas"): hooked - reel the cables in hard; unhooked,
--     in the air - a gas burst along the camera. On the ground Space jumps.
--   Tap Ctrl or C (B, or "Dash"): a quick gas dash in the direction you
--     steer. (Shift is left alone for shift-lock.)
--   WASD in the air: steer.
--   Click / F (X, or "Slash"): swing both blades - a full spin in the air.
--     Aim for the glowing lump on a giant's neck; faster = cleaner cut.
--   G (Y, or "Flare"): fire a green signal flare.
--
-- Aiming: the mouse, or the centre of the screen with shift-lock, on a
-- touch screen, or when you last used a gamepad.
--
-- Hooks fire even with an empty tank (only reeling, boosting and dashing
-- use gas), and a hooked hunter's tank trickles back a little. Reeling onto
-- a giant stops just off its skin, and you cling on as it moves.
--
-- Grabbed by a giant: every key, click, tap or button wriggles (mash to get
-- free); the server counts them. Swatted: you go flying and your hooks let
-- go.
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

local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Parent.Effects)
local TouchButtons = require(script.Parent.TouchButtons)

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
	TargetNormal: Vector3?, -- the surface's normal there, in TargetPart's space
	OnGiant: boolean, -- bit a giant: reeling stops just off its skin
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
	Left = { Name = "Left", Side = -1, Held = false, State = "Idle", OnGiant = false, Length = 0 },
	Right = { Name = "Right", Side = 1, Held = false, State = "Idle", OnGiant = false, Length = 0 },
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
local lastWriggle = 0
local reelingSince: number? = nil -- for the tutorial: how long you've been reeling in
local titanJumpOff = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true -- hooks never bite the river

local function remote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

local GAMEPADS = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}

-- Where on screen you're aiming (the crosshair): the mouse on desktop; the
-- screen centre with shift-lock, on a touch screen, or on a gamepad.
function GrappleController.AimPoint(): Vector2
	local last = UserInputService:GetLastInputType()
	local centre = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		or last == Enum.UserInputType.Touch
		or GAMEPADS[last] == true
		or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
	if centre then
		local size = camera.ViewportSize
		return Vector2.new(size.X / 2, size.Y / 2)
	end
	return UserInputService:GetMouseLocation()
end

local function aimRay(): Ray
	local location = GrappleController.AimPoint()
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

-- Where a cable leaves a hunter: the tip of the hook launcher on their gear
-- (HunterGear; it's rebuilt after the avatar is re-dressed, so look it up
-- each time), or `fallback` (an attachment at the hip) until it's there.
local function cableOrigin(character: Model?, side: number, fallback: Attachment): Attachment
	local gear = character and character:FindFirstChild("HunterGear")
	local launcher = gear and gear:FindFirstChild(if side < 0 then "HookLauncher1" else "HookLauncher2")
	local origin = launcher and launcher:FindFirstChild("CableOrigin")
	return if origin and origin:IsA("Attachment") then origin else fallback
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
	hook.TargetPart, hook.TargetLocal, hook.TargetNormal = nil, nil, nil
	hook.OnGiant = false
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

-- As a titan the hooks, gas and blades are put away.
local function isTitan(): boolean
	return character ~= nil and (character :: Model):GetAttribute("Shifted") == true
end

-- Part of a giant (or a titan)?
local function isGiantPart(part: Instance): boolean
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if CollectionService:HasTag(model, Config.Tags.Giant) then
			return true
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

local function fire(hook: Hook)
	-- (No gas needed to fire: an empty tank must never leave you stranded.)
	if not root or not humanoid or humanoid.Health <= 0 or held or not hook.Hip or isTitan() then
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
	hook.TargetNormal = targetPart.CFrame:VectorToObjectSpace(hit.Normal)
	hook.OnGiant = isGiantPart(targetPart)
	-- The flying hook head: an attachment on the terrain we slide each frame.
	local origin = cableOrigin(player.Character, hook.Side, hook.Hip)
	local tip = Instance.new("Attachment")
	tip.Name = "HookTip"
	tip.Parent = Workspace.Terrain
	tip.WorldPosition = origin.WorldPosition
	hook.Tip = tip
	hook.Beam = makeBeam(origin, tip)
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
	-- Titans don't jump (the server zeroes the jump too; the state is ours).
	local titan = isTitan()
	if titan ~= titanJumpOff then
		titanJumpOff = titan
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not titan)
	end
	if humanoid.Health <= 0 or held or titan then
		if titan then
			humanoid.AutoRotate = true
		end
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
	if reeling then
		reelingSince = reelingSince or os.clock()
	else
		reelingSince = nil
	end

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
			local anchorPoint = anchor.WorldPosition
			local part = anchor.Parent :: BasePart
			if hook.OnGiant and hook.TargetNormal then
				-- Reel to just off a giant's skin, never through it.
				anchorPoint += part.CFrame:VectorToWorldSpace(hook.TargetNormal) * settings.GiantStandOff
			end
			local toAnchor = anchorPoint - position
			local distance = toAnchor.Magnitude
			if distance < settings.ReleaseDistance then
				if hook.OnGiant then
					-- Arrived: cling on and ride along with it.
					velocity = part.AssemblyLinearVelocity
					hook.Length = settings.ReleaseDistance
					continue
				end
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
	if hooked and not reeling then
		-- A trickle while you hang on a cable.
		gas = math.min(settings.GasMax, gas + settings.GasRegenPerSecondSwinging * dt)
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
	held = false -- a fresh body is never in a giant's hand
	titanJumpOff = false
	character = newCharacter
	root = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	gas = settings.GasMax
	refreshFilter()
	if humanoid then
		-- Hunters flip and tumble through the air all the time: never let
		-- the humanoid decide that's a fall and go floppy.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end
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
	local origin = cableOrigin(other.Character, if side == "Left" then -1 else 1, hip)
	remoteCables[other][side] = { Beam = makeBeam(origin, anchor), Anchor = anchor, Hip = hip }
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

-- Seconds you've been reeling in without a break (0 if you aren't).
function GrappleController.ReelTime(): number
	return if reelingSince then os.clock() - reelingSince else 0
end

-- Held: any key, click, tap or gamepad button is a wriggle. The server
-- counts them (and caps the rate); the wriggle bar shows its count.
local function struggle()
	local now = os.clock()
	if struggleRemote and now - lastWriggle >= 1 / Config.Hunters.StruggleRate then
		lastWriggle = now
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
	-- A hunter who falls, is caught or respawns drops their cables.
	local function watchCables(other: Player)
		other.CharacterRemoving:Connect(function()
			clearRemoteCable(other, "Left")
			clearRemoteCable(other, "Right")
		end)
	end
	for _, other in Players:GetPlayers() do
		watchCables(other)
	end
	Players.PlayerAdded:Connect(watchCables)

	UserInputService.InputBegan:Connect(function(input, _processed)
		if not held then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.Touch or GAMEPADS[kind] then
			struggle()
		end
	end)

	-- (On touch screens our own buttons, from TouchButtons, replace the
	-- default ones: they're laid out so nothing overlaps.)
	local function pressHook(name: string, down: boolean)
		local hook = hooks[name]
		if held then
			return
		end
		if down then
			hook.Held = true
			fire(hook)
		else
			hook.Held = false
			release(hook)
		end
	end
	local function hookAction(name: string): (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
		return function(_action, state, _input)
			if state == Enum.UserInputState.Begin then
				pressHook(name, true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				pressHook(name, false)
			end
			return Enum.ContextActionResult.Sink
		end
	end
	ContextActionService:BindAction("HookLeft", hookAction("Left"), false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("HookRight", hookAction("Right"), false, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)

	ContextActionService:BindActionAtPriority("Gas", function(_action, state, input)
		if held then
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
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	-- Dash: Ctrl or C (Shift stays free for shift-lock).
	ContextActionService:BindAction("Dash", function(_action, state, _input)
		if state == Enum.UserInputState.Begin and not held then
			dash()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB)

	ContextActionService:BindAction("Slash", function(_action, state, _input)
		if state == Enum.UserInputState.Begin and not held then
			slash()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)

	local function flare()
		if not held then
			remote(Config.Remotes.Flare):FireServer()
		end
	end
	ContextActionService:BindAction("Flare", function(_action, state, _input)
		if state == Enum.UserInputState.Begin then
			flare()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonY)

	if TouchButtons.Enabled() then
		TouchButtons.Init()
		TouchButtons.Add("HookLeft", "HookLeft", "L HOOK", function()
			pressHook("Left", true)
		end, function()
			pressHook("Left", false)
		end)
		TouchButtons.Add("HookRight", "HookRight", "R HOOK", function()
			pressHook("Right", true)
		end, function()
			pressHook("Right", false)
		end)
		TouchButtons.Add("Gas", "Gas", "GAS", function()
			if not held then
				gasHeld = true
			end
		end, function()
			gasHeld = false
		end)
		TouchButtons.Add("Dash", "Dash", "DASH", function()
			if not held then
				dash()
			end
		end)
		TouchButtons.Add("Slash", "Slash", "SLASH", function()
			if not held then
				slash()
			end
		end)
		TouchButtons.Add("Flare", "Flare", "FLARE", flare)
		-- As a titan the gear is put away (ShifterController shows its own).
		RunService.Heartbeat:Connect(function()
			local gear = not isTitan()
			for _, name in { "HookLeft", "HookRight", "Gas", "Dash", "Slash", "Flare" } do
				TouchButtons.Show(name, gear)
			end
		end)
	end

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
				gasHeld = false
				releaseAll()
			elseif state == "Free" then
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

	-- Zoomed all the way in, the camera fades the whole character out; keep
	-- the two swords in view (after the camera has had its say each frame).
	RunService:BindToRenderStep("GH_SwordsInView", Enum.RenderPriority.Camera.Value + 1, function()
		local character = player.Character
		if not character then
			return
		end
		for _, name in { "LeftSword", "RightSword" } do
			local sword = character:FindFirstChild(name)
			if sword then
				for _, d in sword:GetDescendants() do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = 0
					end
				end
			end
		end
	end)
end

return GrappleController
