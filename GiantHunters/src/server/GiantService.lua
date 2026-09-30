--!strict
-- Giants: spawning, AI, grabbing, weak-spot damage, defeat, and the wave
-- loop.
--
-- AI (4 decisions a second per giant): walk toward the nearest hunter it
-- can reach - someone on the ground or low on a building. A hunter high up
-- is out of reach, which is exactly what the grapple rig is for. In reach,
-- the giant raises its arms (a clear warning), and if the hunter is still
-- there when the wind-up ends, they're caught and respawn at the plaza.
--
-- Damage only ever lands on the Nape, and only via TryHitNape, which the
-- slash handler calls after its own validation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GiantFactory = require(script.Parent.GiantFactory)

local GiantService = {}

type Giant = {
	Rig: GiantFactory.Rig,
	Kind: Config.GiantKind,
	NextGrabAt: number,
	Winding: boolean,
	WanderTarget: Vector3?,
	Defeated: boolean,
}

export type HitResult = "NoTarget" | "Hit" | "Defeated"

local giants: { [Model]: Giant } = {}
local spawnPoints: { Vector3 } = {}
local rng = Random.new()
local folder: Folder
local caughtEvent: RemoteEvent
local waveEvent: RemoteEvent

GiantService.Defeated = Instance.new("BindableEvent") -- (player, kindName, points)

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function chestPoint(giant: Giant): Vector3
	local root = giant.Rig.Root
	return root.Position + Vector3.new(0, giant.Rig.TorsoHeight * 0.6, 0) + root.CFrame.LookVector * giant.Rig.TorsoDepth
end

local function nearestReachable(giant: Giant): (Player?, BasePart?)
	local here = giant.Rig.Root.Position
	local best, bestRoot, bestDistance = nil, nil, Config.Giants.SightRange
	for _, player in Players:GetPlayers() do
		local root = aliveRoot(player)
		-- Hunters perched above the giant's head are safe (and should be!).
		if root and root.Position.Y < giant.Kind.Height * 1.1 then
			local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(here.X, 0, here.Z)).Magnitude
			if d < bestDistance then
				best, bestRoot, bestDistance = player, root, d
			end
		end
	end
	return best, bestRoot
end

local function steer(giant: Giant, toward: Vector3)
	local root = giant.Rig.Root
	local move = root:FindFirstChild("Move") :: AlignPosition?
	local face = root:FindFirstChild("Face") :: AlignOrientation?
	if not move or not face then
		return
	end
	local half = Config.World.HalfSize - 15
	local clamped = Vector3.new(math.clamp(toward.X, -half, half), root.Position.Y, math.clamp(toward.Z, -half, half))
	move.Position = clamped
	local flat = Vector3.new(clamped.X - root.Position.X, 0, clamped.Z - root.Position.Z)
	if flat.Magnitude > 1 then
		face.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	end
end

local function tryGrab(giant: Giant, player: Player, root: BasePart)
	local now = os.clock()
	if giant.Winding or now < giant.NextGrabAt then
		return
	end
	giant.Winding = true
	giant.Rig.Model:SetAttribute("Grabbing", true) -- clients raise its arms: the warning
	task.delay(Config.Giants.GrabWindup, function()
		giant.Winding = false
		giant.NextGrabAt = os.clock() + Config.Giants.GrabCooldown
		if giant.Defeated or not giant.Rig.Model.Parent then
			return
		end
		giant.Rig.Model:SetAttribute("Grabbing", false)
		local stillThere = aliveRoot(player)
		if stillThere == root and (root.Position - chestPoint(giant)).Magnitude <= giant.Kind.GrabReach * 1.15 then
			caughtEvent:FireClient(player, giant.Kind.Name)
			local humanoid = (root.Parent :: Model):FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0 -- respawn at the plaza; no gore, just a "Caught!" screen
			end
		end
	end)
end

local function think(giant: Giant)
	if giant.Defeated then
		return
	end
	local player, root = nearestReachable(giant)
	if player and root then
		steer(giant, root.Position)
		if (root.Position - chestPoint(giant)).Magnitude <= giant.Kind.GrabReach then
			tryGrab(giant, player, root)
		end
	else
		-- Nobody reachable: amble around town.
		local here = giant.Rig.Root.Position
		local target = giant.WanderTarget
		if not target or (Vector3.new(target.X, here.Y, target.Z) - here).Magnitude < 10 then
			local half = Config.World.HalfSize - 40
			target = Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half))
			giant.WanderTarget = target
		end
		steer(giant, target :: Vector3)
	end
end

local function spawnGiant(kindName: string)
	local point = spawnPoints[rng:NextInteger(1, #spawnPoints)] + Vector3.new(rng:NextNumber(-20, 20), 0, rng:NextNumber(-20, 20))
	local rig = GiantFactory.Build(kindName, point, rng)
	-- Face the middle of town (the rig is built facing -Z).
	local facing = Vector3.new(-point.X, 0, -point.Z)
	local pivot = rig.Model:GetPivot().Position
	if facing.Magnitude > 1 then
		rig.Model:PivotTo(CFrame.lookAt(pivot, pivot + facing.Unit))
	end
	rig.Model.Parent = folder
	rig.Root:SetNetworkOwner(nil) -- server-simulated, never handed to a nearby client
	local move = rig.Root:FindFirstChild("Move") :: AlignPosition
	move.Position = rig.Root.Position
	local face = rig.Root:FindFirstChild("Face") :: AlignOrientation
	face.CFrame = rig.Root.CFrame - rig.Root.Position
	giants[rig.Model] = {
		Rig = rig,
		Kind = Config.GiantKinds[kindName],
		NextGrabAt = os.clock() + 3,
		Winding = false,
		WanderTarget = nil,
		Defeated = false,
	}
end

local function defeat(giant: Giant, player: Player)
	giant.Defeated = true
	local model = giant.Rig.Model
	model:SetAttribute("Defeated", true)
	GiantService.Defeated:Fire(player, giant.Kind.Name, giant.Kind.Points)

	-- Stop, anchor, and dissolve into steam: no ragdoll, nothing scary.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanQuery = false
			TweenService:Create(descendant, TweenInfo.new(Config.Giants.DefeatFadeTime), { Transparency = 1 }):Play()
		elseif descendant:IsA("PointLight") then
			descendant.Enabled = false
		end
	end
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Color3.fromRGB(245, 245, 250))
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, giant.Kind.Height * 0.15), NumberSequenceKeypoint.new(1, giant.Kind.Height * 0.4) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(2, 3.5)
	steam.Speed = NumberRange.new(8, 16)
	steam.SpreadAngle = Vector2.new(40, 40)
	steam.Rate = 40
	steam.Parent = giant.Rig.Torso
	task.delay(Config.Giants.DefeatFadeTime, function()
		steam.Enabled = false
	end)
	task.delay(Config.Giants.DefeatFadeTime + 3.5, function()
		model:Destroy()
		giants[model] = nil
	end)
end

-- Called by HunterService after it has validated the slash (cooldown,
-- blades). Finds the closest weak spot within range of the hunter and
-- damages it; a fast pass ("clean cut") does full damage.
function GiantService.TryHitNape(player: Player, root: BasePart): (HitResult, string?)
	local bestGiant: Giant? = nil
	local bestDistance = math.huge
	for _, giant in giants do
		if not giant.Defeated then
			local nape = giant.Rig.Nape
			local reach = Config.Blades.SlashRange + nape.Size.Magnitude / 2
			local d = (nape.Position - root.Position).Magnitude
			if d <= reach and d < bestDistance then
				bestGiant, bestDistance = giant, d
			end
		end
	end
	local giant = bestGiant
	if not giant then
		return "NoTarget", nil
	end
	local speed = root.AssemblyLinearVelocity.Magnitude
	local damage = if speed >= Config.Blades.CleanCutSpeed then 1 else 0.5
	local model = giant.Rig.Model
	local health = (model:GetAttribute("NapeHealth") :: number) - damage
	model:SetAttribute("NapeHealth", math.max(health, 0))
	if health <= 0 then
		defeat(giant, player)
		return "Defeated", giant.Kind.Name
	end
	return "Hit", if damage >= 1 then "Clean" else "Glancing"
end

function GiantService.AliveCount(): number
	local count = 0
	for _, giant in giants do
		if not giant.Defeated then
			count += 1
		end
	end
	return count
end

local function broadcast(wave: number, phase: string, countdown: number)
	waveEvent:FireAllClients({ Wave = wave, Alive = GiantService.AliveCount(), Phase = phase, Countdown = countdown })
end

local function waveLoop()
	local wave = 0
	local countdown = Config.Waves.FirstDelay
	while true do
		for t = countdown, 1, -1 do
			broadcast(wave + 1, "Intermission", t)
			task.wait(1)
		end
		wave += 1
		for _, kindName in Config.WaveRoster(wave) do
			spawnGiant(kindName)
			task.wait(0.4)
		end
		-- Fight until the wave is cleared (or everyone has left).
		while GiantService.AliveCount() > 0 do
			broadcast(wave, "Fight", 0)
			task.wait(1)
			if #Players:GetPlayers() == 0 then
				for model, giant in giants do
					giant.Defeated = true
					model:Destroy()
				end
				table.clear(giants)
				wave = 0
			end
		end
		countdown = Config.Waves.Intermission
	end
end

function GiantService.Init(points: { Vector3 })
	spawnPoints = points
	folder = Instance.new("Folder")
	folder.Name = "Giants"
	folder.Parent = Workspace

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	caughtEvent = remotes:WaitForChild(Config.Remotes.Caught) :: RemoteEvent
	waveEvent = remotes:WaitForChild(Config.Remotes.Wave) :: RemoteEvent

	task.spawn(function()
		while true do
			task.wait(Config.Giants.ThinkInterval)
			for _, giant in giants do
				local ok, err = pcall(think :: any, giant)
				if not ok then
					warn("[GiantService] think failed:", err)
				end
			end
		end
	end)
	task.spawn(waveLoop)
end

return GiantService
