--!strict
-- Techniques: the one active ability a hunter wears (the player's
-- "Equip_Technique" attribute, bought in the shop; Config.Catalog), used
-- with V, R2 or the "SKILL" button. With the SecondTechnique game pass
-- ("Pass_SecondTechnique", MonetizationService) a second one
-- ("Equip_Technique2") on B, L2 or a second SKILL button, with its own
-- cooldown.
--
-- The client only asks (Config.Remotes.Technique, with where it aims); the
-- server checks everything: a known technique the hunter owns and wears,
-- alive, not in a giant's hand, not a titan, its cooldown, and then each
-- technique's own rules (range, targets, blades). It answers "Go" (the
-- client then moves the hunter: the dashes, the gas) or "Denied".
--
--   * Gale Burst: a gas-free hop (client impulse; the server keeps the
--     cooldown and puffs the wind).
--   * Second Wind: half a tank of gas back (on the client's tank).
--   * Smoke Pellet: a smoke cloud; giants close by are dazed.
--   * Anchor Pull: a cable to a Small or Medium giant's ankle: it trips.
--   * Whirlwind Cut: a spinning dash; the server follows the hunter for its
--     length and cuts the napes they pass (one blade).
--   * Flare Lance: a glowing lance the server flies itself; passing close
--     enough to a nape, it lands one full cut (cracking armour first).
-- Cuts go through GiantService.TryHit like any slash (from a stand-in
-- point for the anchor and the lance), so armour, guards, points, Marks and
-- challenges all work as usual. Effects are server parts (everyone sees
-- them) made of default particles and neon, no asset ids.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GiantService = require(script.Parent.GiantService)
local HunterService = require(script.Parent.HunterService)
local Motion = require(script.Parent.Motion)
local ShopService = require(script.Parent.ShopService)

local TechniqueService = {}

type Hunter = { NextUse: number, NextUse2: number, Busy: boolean }

local hunters: { [Player]: Hunter } = {}
local remote: RemoteEvent
local slashRemote: RemoteEvent
local effects: Folder

-- === Helpers =================================================================

-- Alive, not in a giant's hand, not a titan.
local function readyRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	if GiantService.IsHeld(player) or (character :: Model):GetAttribute("Shifted") then
		return nil
	end
	return root
end

local function finite(v: Vector3): boolean
	return v == v and v.Magnitude < 1e6
end

-- Giants still standing.
local function liveGiants(): { Model }
	local list = {}
	for _, model in CollectionService:GetTagged(Config.Tags.Giant) do
		if model:IsA("Model") and model.Parent then
			local health = model:GetAttribute("NapeHealth")
			if type(health) == "number" and health > 0 then
				table.insert(list, model)
			end
		end
	end
	return list
end

local function partOf(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name)
	return if found and found:IsA("BasePart") then found else nil
end

-- A point to cut from that isn't a hunter (TryHit only reads its position).
local function probeAt(position: Vector3): Part
	local probe = Instance.new("Part")
	probe.Anchored = true
	probe.Position = position
	return probe
end

-- A cut a technique made: the same effects and tallies as a slash.
local function reportCut(player: Player, outcome: string, info: any)
	if outcome == "NoTarget" then
		return
	end
	slashRemote:FireClient(player, outcome, info)
	HunterService.Slashed:Fire(player, outcome, info)
end

-- A burst of default particles at a point.
local function puff(position: Vector3, color: Color3, count: number, size: number, speed: number, lifetime: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.15
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 2
	emitter.Rate = 0
	emitter.Parent = anchor
	anchor.Parent = effects
	emitter:Emit(count)
	Debris:AddItem(anchor, lifetime + 0.5)
end

-- Particles that follow a hunter for a moment (wind round a spin).
local function trailOn(root: BasePart, color: Color3, duration: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "TechniqueWind"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.4
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 3) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.3, 0.5)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(180, 20)
	emitter.RotSpeed = NumberRange.new(-360, 360)
	emitter.Rate = 120
	emitter.Parent = root
	task.delay(duration, function()
		emitter.Enabled = false
	end)
	Debris:AddItem(emitter, duration + 0.6)
end

-- A glowing cable for a moment (the anchor's line).
local function flashCable(from: BasePart, to: BasePart, duration: number)
	local a0 = Instance.new("Attachment")
	a0.Parent = from
	local a1 = Instance.new("Attachment")
	a1.Parent = to
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.3
	beam.Width1 = 0.3
	beam.FaceCamera = true
	beam.LightEmission = 0.6
	beam.Color = ColorSequence.new(Color3.fromRGB(230, 220, 190))
	beam.Parent = a0
	for _, item in { a0, a1 } do
		Debris:AddItem(item, duration)
	end
end

-- === The techniques ==========================================================
-- Each checks its own rules, returns false and a reason to refuse, or does
-- its work (yielding parts in a new thread) and returns true.

type Handler = (player: Player, root: BasePart, spec: Config.TechniqueSpec, aim: Vector3?) -> (boolean, string?)

local function galeBurst(_player: Player, root: BasePart, _spec: Config.TechniqueSpec, _aim: Vector3?): (boolean, string?)
	puff(root.Position - Vector3.new(0, 2, 0), Color3.fromRGB(225, 245, 255), 30, 3, 30, 0.7)
	return true, nil
end

local function secondWind(_player: Player, root: BasePart, _spec: Config.TechniqueSpec, _aim: Vector3?): (boolean, string?)
	puff(root.Position, Color3.fromRGB(245, 245, 245), 24, 2.2, 12, 1)
	return true, nil
end

local function smokePellet(player: Player, root: BasePart, spec: Config.TechniqueSpec, _aim: Vector3?): (boolean, string?)
	local radius = spec.Radius or 35
	local centre = root.Position
	local count = 0
	for _, model in liveGiants() do
		if (model:GetPivot().Position - centre).Magnitude <= radius then
			count += 1
		end
	end
	GiantService.DazeAround(centre, radius)
	puff(centre, Color3.fromRGB(200, 205, 215), 70, 14, 22, 3)
	remote:FireClient(player, "Hits", "SmokePellet", count)
	return true, nil
end

local function anchorPull(player: Player, root: BasePart, spec: Config.TechniqueSpec, aim: Vector3?): (boolean, string?)
	local range = spec.Range or 60
	local kinds = spec.Kinds or {}
	local best: BasePart? = nil
	local bestScore = math.huge
	for _, model in liveGiants() do
		local kind = model:GetAttribute("Kind")
		if type(kind) == "string" and table.find(kinds, kind) and not model:GetAttribute("Kneeling") then
			for _, name in { "LeftFoot", "RightFoot" } do
				local foot = partOf(model, name)
				local d = foot and (foot.Position - root.Position).Magnitude
				if foot and d and d <= range then
					-- Nearest the aim (within Radius of it), else nearest the hunter.
					local score = d
					if aim then
						score = (foot.Position - aim).Magnitude
						if score > (spec.Radius or 30) then
							score = math.huge
						end
					end
					if score < bestScore then
						best, bestScore = foot, score
					end
				end
			end
		end
	end
	if not best then
		return false, "No small or medium giant in reach"
	end
	-- Cut from just under the ankle: only the trip can land from there.
	local probe = probeAt(best.Position - Vector3.new(0, 1, 0))
	local outcome, info = GiantService.TryHit(player, probe, 0)
	probe:Destroy()
	if outcome == "NoTarget" then
		return false, "The anchor slipped"
	end
	flashCable(root, best, 0.5)
	puff(best.Position, Color3.fromRGB(210, 190, 150), 20, 3, 14, 1)
	reportCut(player, outcome, info)
	return true, nil
end

local function whirlwindCut(player: Player, root: BasePart, spec: Config.TechniqueSpec, _aim: Vector3?): (boolean, string?)
	-- One blade, through HunterService (when it offers UseBlade).
	local useBlade = (HunterService :: any).UseBlade
	if type(useBlade) == "function" then
		for _ = 1, spec.BladeCost or 1 do
			if not useBlade(player) then
				return false, "Your blades are dull: resupply first"
			end
		end
	end
	local duration = spec.Duration or 0.7
	local maxHits = spec.MaxHits or 2
	trailOn(root, Color3.fromRGB(220, 240, 255), duration)
	task.spawn(function()
		local cut: { [Model]: boolean } = {}
		local hits = 0
		local started = os.clock()
		while os.clock() - started < duration + 0.15 and hits < maxHits do
			task.wait(0.06)
			local here = readyRoot(player)
			if not here then
				break
			end
			for _, model in liveGiants() do
				local nape = partOf(model, "Nape")
				if not cut[model] and nape and (nape.Position - here.Position).Magnitude <= Config.Blades.SlashRange + nape.Size.X / 2 + Config.Cuts.PosedNapeSlack then
					cut[model] = true
					local speed = math.max(Motion.CutSpeed(player), Config.Blades.CleanCutSpeed)
					local outcome, info = GiantService.TryHit(player, here, speed)
					if outcome ~= "NoTarget" then
						hits += 1
						reportCut(player, outcome, info)
					end
					break
				end
			end
		end
		remote:FireClient(player, "Hits", "WhirlwindCut", hits)
	end)
	return true, nil
end

-- Distance from `point` to the segment a-b.
local function segmentDistance(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local length = ab.Magnitude
	if length < 1e-4 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(ab) / (length * length), 0, 1)
	return (point - (a + ab * t)).Magnitude
end

local function flareLance(player: Player, root: BasePart, spec: Config.TechniqueSpec, aim: Vector3?): (boolean, string?)
	local from = root.Position + Vector3.new(0, 1.5, 0)
	if not aim or (aim - from).Magnitude < 1 then
		return false, "Aim first"
	end
	local direction = (aim - from).Unit
	local range = spec.Range or 120
	local speed = spec.Speed or 180
	local radius = spec.Radius or 6
	local start = from + direction * 2

	local lance = Instance.new("Part")
	lance.Name = "FlareLance"
	lance.Anchored = true
	lance.CanCollide = false
	lance.CanQuery = false
	lance.CanTouch = false
	lance.Material = Enum.Material.Neon
	lance.Color = Color3.fromRGB(255, 200, 110)
	lance.Size = Vector3.new(0.35, 0.35, 4.5)
	lance.CFrame = CFrame.lookAt(start, start + direction)
	local light = Instance.new("PointLight")
	light.Color = lance.Color
	light.Range = 14
	light.Brightness = 2
	light.Parent = lance
	local back = Instance.new("Attachment")
	back.Position = Vector3.new(0, 0, 2.2)
	back.Parent = lance
	local front = Instance.new("Attachment")
	front.Position = Vector3.new(0, 0, -2.2)
	front.Parent = lance
	local trail = Instance.new("Trail")
	trail.Attachment0 = back
	trail.Attachment1 = front
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 160))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = lance
	lance.Parent = effects

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { effects }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore

	task.spawn(function()
		local travelled = 0
		local here = start
		while travelled < range do
			local dt = task.wait()
			local step = math.min(speed * dt, range - travelled)
			local nextPoint = here + direction * step
			-- A nape close enough to the lance's path: one full cut.
			for _, model in liveGiants() do
				local nape = partOf(model, "Nape")
				if nape and segmentDistance(nape.Position, here, nextPoint) <= radius + nape.Size.X / 2 then
					-- Cut from just behind the nape (never "in front of the face").
					local probe = probeAt(nape.Position - model:GetPivot().LookVector * 1.5)
					local outcome, info = GiantService.TryHit(player, probe, Config.Blades.CleanCutSpeed)
					probe:Destroy()
					reportCut(player, outcome, info)
					puff(nape.Position, Color3.fromRGB(255, 220, 150), 40, 3, 30, 0.8)
					remote:FireClient(player, "Hits", "FlareLance", if outcome == "NoTarget" then 0 else 1)
					lance:Destroy()
					return
				end
			end
			-- Anything solid stops it.
			local hit = Workspace:Raycast(here, nextPoint - here, params)
			if hit then
				puff(hit.Position, Color3.fromRGB(255, 210, 140), 16, 1.5, 18, 0.6)
				break
			end
			here = nextPoint
			travelled += step
			lance.CFrame = CFrame.lookAt(here, here + direction)
		end
		remote:FireClient(player, "Hits", "FlareLance", 0)
		lance:Destroy()
	end)
	return true, nil
end

local HANDLERS: { [string]: Handler } = {
	GaleBurst = galeBurst,
	SecondWind = secondWind,
	SmokePellet = smokePellet,
	AnchorPull = anchorPull,
	WhirlwindCut = whirlwindCut,
	FlareLance = flareLance,
}

-- === Requests ================================================================

local function onRequest(player: Player, aim: unknown, slot: unknown)
	local hunter = hunters[player]
	if not hunter or hunter.Busy then
		return
	end
	local second = slot == 2
	if second and player:GetAttribute("Pass_SecondTechnique") ~= true then
		return
	end
	local id = ShopService.Equipped(player, if second then "Technique2" else "Technique")
	if second and id == ShopService.Equipped(player, "Technique") then
		return -- (never one technique on two cooldowns)
	end
	local item = Config.Catalog[id]
	local spec = item and item.Technique
	local handler = HANDLERS[id]
	if not item or not spec or not handler or not ShopService.Owns(player, "Technique", id) then
		return
	end
	local now = os.clock()
	local nextUse = if second then hunter.NextUse2 else hunter.NextUse
	if now < nextUse - Config.Shop.TechniqueSlack then
		remote:FireClient(player, "Denied", id, "Not ready yet", nextUse - now)
		return
	end
	local root = readyRoot(player)
	if not root then
		remote:FireClient(player, "Denied", id, "Can't do that now", 0)
		return
	end
	local point: Vector3? = if typeof(aim) == "Vector3" and finite(aim :: Vector3) then aim :: Vector3 else nil
	hunter.Busy = true
	local ok, reason = handler(player, root, spec, point)
	hunter.Busy = false
	if ok then
		if second then
			hunter.NextUse2 = os.clock() + spec.Cooldown
		else
			hunter.NextUse = os.clock() + spec.Cooldown
		end
		remote:FireClient(player, "Go", id, spec.Cooldown)
	else
		remote:FireClient(player, "Denied", id, reason or "Can't do that now", 0)
	end
end

function TechniqueService.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remote = remotes:WaitForChild(Config.Remotes.Technique) :: RemoteEvent
	slashRemote = remotes:WaitForChild(Config.Remotes.SlashResult) :: RemoteEvent
	effects = Instance.new("Folder")
	effects.Name = "TechniqueEffects"
	effects.Parent = Workspace

	local function add(player: Player)
		hunters[player] = { NextUse = 0, NextUse2 = 0, Busy = false }
	end
	for _, player in Players:GetPlayers() do
		add(player)
	end
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(function(player)
		hunters[player] = nil
	end)
	-- A new technique starts ready (no swapping round a cooldown, though:
	-- changing technique keeps the clock running).
	remote.OnServerEvent:Connect(onRequest)
end

return TechniqueService
