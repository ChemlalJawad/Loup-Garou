--!strict
-- Townsfolk: little blocky villagers who stroll the streets by day, made
-- and moved on this client only (seven anchored parts each, no Humanoid).
--
--   * They step out of house doors near the camera and wander a graph of
--     the streets (the plaza loop, the ring roads, the avenues and the
--     street inside the wall), keeping to the right.
--   * When a wave is on (the Wave remote's Phase is "Breach" or "Fight"),
--     or a giant comes close, they hurry to the nearest door and vanish
--     inside; they come back out once the district is quiet again.
--   * Fewer at night and in the rain; never more than Config.Ambient's cap,
--     and only within VillagerRange of the camera.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local SkyController = require(script.Parent.SkyController)
local Weather = require(script.Parent.Weather)

local Townsfolk = {}

local A = Config.Ambient
local W = Config.World

-- === The street graph =========================================================
-- Nodes where the avenues meet the plaza loop, the ring roads and the
-- street inside the wall; edges along the avenues (radial) and round the
-- rings (arcs). The church sits across the north avenue's first stretch,
-- the gate square takes the south end of the wall street, and every
-- stretch over the river has a bridge.

type Edge = { Radial: boolean, Angle0: number, Angle1: number, Radius0: number, Radius1: number, From: number, To: number, Length: number }
local RINGS = { 22, W.RingRoads[1], W.RingRoads[2], W.PerimeterRoad + 12 }
local edges: { Edge } = {}
local links: { [number]: { number } } = {} -- node -> edge indices

local function nodeId(avenue: number, ring: number): number
	return ring * 10 + avenue
end

local function addEdge(edge: Edge)
	table.insert(edges, edge)
	for _, node in { edge.From, edge.To } do
		links[node] = links[node] or {}
		table.insert(links[node], #edges)
	end
end

local function buildGraph()
	local angles = W.AvenueAngles
	for i, degrees in angles do
		local angle = math.rad(degrees)
		for ring = 1, #RINGS - 1 do
			-- (the river runs out under the wall beside the 120 and 240 avenues'
			-- last stretch, past the end of their bridges)
			local outer = ring == #RINGS - 1
			local blocked = (degrees == 180 and ring == 1) or (outer and (degrees == W.GateAngle or degrees == 120 or degrees == 240))
			if not blocked then
				addEdge({
					Radial = true,
					Angle0 = angle,
					Angle1 = angle,
					Radius0 = RINGS[ring],
					Radius1 = RINGS[ring + 1],
					From = nodeId(i, ring),
					To = nodeId(i, ring + 1),
					Length = RINGS[ring + 1] - RINGS[ring],
				})
			end
		end
		local nextIndex = i % #angles + 1
		local nextAngle = angle + math.rad((angles[nextIndex] - degrees) % 360)
		for ring, radius in RINGS do
			local touchesGate = ring == #RINGS and (degrees == W.GateAngle or angles[nextIndex] == W.GateAngle)
			if not touchesGate then
				addEdge({
					Radial = false,
					Angle0 = angle,
					Angle1 = nextAngle,
					Radius0 = radius,
					Radius1 = radius,
					From = nodeId(i, ring),
					To = nodeId(nextIndex, ring),
					Length = radius * (nextAngle - angle),
				})
			end
		end
	end
end

-- The point `t` (0..1) along an edge, and the way along it.
local function along(edge: Edge, t: number): (Vector3, Vector3)
	local angle = edge.Angle0 + (edge.Angle1 - edge.Angle0) * t
	local radius = edge.Radius0 + (edge.Radius1 - edge.Radius0) * t
	local p = Geo.Polar(angle, radius)
	local forward = if edge.Radial
		then Vector3.new(math.sin(angle), 0, math.cos(angle)) * (if edge.Radius1 > edge.Radius0 then 1 else -1)
		else Vector3.new(math.cos(angle), 0, -math.sin(angle))
	return p, forward
end

-- The closest point on any edge to `p`: (edge index, t, distance).
local function nearestOnGraph(p: Vector3): (number, number, number)
	local bestEdge, bestT, best = 1, 0, math.huge
	local angle, radius = Geo.AngleOf(p), Geo.RadiusOf(p)
	for index, edge in edges do
		local t: number
		if edge.Radial then
			t = math.clamp((radius - edge.Radius0) / (edge.Radius1 - edge.Radius0), 0, 1)
		else
			local span = edge.Angle1 - edge.Angle0
			local turned = (angle - edge.Angle0) % (2 * math.pi)
			if turned <= span then
				t = turned / span
			else
				t = if turned - span < 2 * math.pi - turned then 1 else 0 -- past whichever end is nearer
			end
		end
		local distance = (Geo.Flat((along(edge, t))) - Geo.Flat(p)).Magnitude
		if distance < best then
			bestEdge, bestT, best = index, t, distance
		end
	end
	return bestEdge, bestT, best
end

-- === Villagers ================================================================

local SKIN = { Color3.fromRGB(240, 204, 172), Color3.fromRGB(214, 170, 134), Color3.fromRGB(170, 120, 86), Color3.fromRGB(120, 82, 58) }
local SHIRTS = { Color3.fromRGB(200, 70, 60), Color3.fromRGB(70, 110, 170), Color3.fromRGB(230, 190, 90), Color3.fromRGB(90, 140, 90), Color3.fromRGB(150, 90, 150), Color3.fromRGB(236, 230, 214) }
local TROUSERS = { Color3.fromRGB(70, 60, 50), Color3.fromRGB(60, 70, 96), Color3.fromRGB(110, 90, 70), Color3.fromRGB(150, 60, 70) }
local HAIR = { Color3.fromRGB(60, 40, 30), Color3.fromRGB(150, 100, 50), Color3.fromRGB(230, 200, 120), Color3.fromRGB(30, 30, 35), Color3.fromRGB(180, 180, 176) }
local STRAW = Color3.fromRGB(214, 186, 120)

type Villager = {
	Model: Model,
	Parts: { BasePart }, -- legs, body, head, hat, arms
	Offsets: { CFrame }, -- each part from the feet, standing
	Mode: string, -- "Out" (leaving a door), "Walk", "Hide", "Gone"
	Edge: number,
	T: number,
	Forward: boolean, -- walking from the edge's From to its To
	Target: Vector3?, -- walking straight here (Out / Hide)
	Speed: number,
	Lane: number,
	Position: Vector3, -- feet, smoothed
	Facing: Vector3,
	Y: number,
	NextGround: number,
	Phase: number,
	Fade: number, -- 0 solid .. 1 gone
	Running: boolean,
	HideUntil: number, -- with no door near: give up and duck out of sight
}

local folder: Folder
local villagers: { Villager } = {}
local doors: { CFrame } = {} -- just outside each streamed-in door, facing the street
local danger = false
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

local function makeVillager(): Villager
	local model = Instance.new("Model")
	model.Name = "Villager"
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?, material: Enum.Material?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		if shape then
			p.Shape = shape
		end
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		table.insert(parts, p)
		table.insert(offsets, offset)
	end
	local skin, shirt, trousers = pick(SKIN), pick(SHIRTS), pick(TROUSERS)
	local dress = math.random() < 0.4
	local small = if math.random() < 0.2 then 0.75 else 1 -- some are children
	local s = small
	add("LeftLeg", Vector3.new(0.8, 2.2, 0.8) * s, CFrame.new(-0.45 * s, 1.1 * s, 0), trousers)
	add("RightLeg", Vector3.new(0.8, 2.2, 0.8) * s, CFrame.new(0.45 * s, 1.1 * s, 0), trousers)
	add("Body", Vector3.new(2, if dress then 3 else 2.2, 1.1) * s, CFrame.new(0, (if dress then 2.9 else 3.3) * s, 0), shirt, nil, Enum.Material.Fabric)
	add("Head", Vector3.one * 1.4 * s, CFrame.new(0, 5.1 * s, 0), skin, Enum.PartType.Ball)
	if math.random() < 0.45 then
		add("Hat", Vector3.new(0.35, 2.2, 2.2) * s, CFrame.new(0, 5.7 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), STRAW, Enum.PartType.Cylinder, Enum.Material.Fabric)
	else
		add("Hair", Vector3.new(1.5, 0.7, 1.5) * s, CFrame.new(0, 5.65 * s, 0.1 * s), pick(HAIR))
	end
	add("LeftArm", Vector3.new(0.55, 2, 0.55) * s, CFrame.new(-1.3 * s, 3.4 * s, 0), shirt, nil, Enum.Material.Fabric)
	add("RightArm", Vector3.new(0.55, 2, 0.55) * s, CFrame.new(1.3 * s, 3.4 * s, 0), shirt, nil, Enum.Material.Fabric)
	model.Parent = folder
	return {
		Model = model,
		Parts = parts,
		Offsets = offsets,
		Mode = "Walk",
		Edge = 1,
		T = 0,
		Forward = true,
		Target = nil,
		Speed = (A.VillagerSpeed[1] + math.random() * (A.VillagerSpeed[2] - A.VillagerSpeed[1])) * (if small < 1 then 1.15 else 1),
		Lane = 2 + math.random() * 3,
		Position = Vector3.zero,
		Facing = Vector3.new(0, 0, -1),
		Y = 0,
		NextGround = 0,
		Phase = math.random() * 6,
		Fade = 1,
		Running = false,
		HideUntil = 0,
	}
end

local function setFade(v: Villager, fade: number)
	v.Fade = fade
	for _, p in v.Parts do
		p.Transparency = fade
	end
end

-- Doors (row houses' "Door" parts) currently streamed in near the camera.
local function refreshDoors(centre: Vector3)
	doors = {}
	local map = Workspace:FindFirstChild("GiantHuntersMap")
	local town = map and map:FindFirstChild("Town")
	if not town then
		return
	end
	for _, house in town:GetChildren() do
		local door = house:FindFirstChild("Door")
		if door and door:IsA("BasePart") and (door.Position - centre).Magnitude < A.VillagerRange then
			local out = door.CFrame.LookVector
			local at = door.Position + Vector3.new(out.X, 0, out.Z).Unit * 2.5 - Vector3.new(0, door.Size.Y / 2, 0)
			table.insert(doors, CFrame.lookAt(at, at + Vector3.new(out.X, 0, out.Z)))
		end
	end
end

local function nearestDoor(p: Vector3, within: number): CFrame?
	local best: CFrame? = nil
	local bestDistance = within
	for _, door in doors do
		local d = (door.Position - p).Magnitude
		if d < bestDistance then
			best, bestDistance = door, d
		end
	end
	return best
end

-- A new villager stepping out of a door near the camera (one that opens
-- onto a street of the graph).
local function spawnVillager(camera: Vector3): boolean
	if #doors == 0 then
		return false
	end
	for _ = 1, 6 do
		local door = doors[math.random(1, #doors)]
		local d = (door.Position - camera).Magnitude
		if d > 30 and d < A.VillagerRange - 20 then
			local edge, t, distance = nearestOnGraph(door.Position)
			if distance < 14 then
				local v = makeVillager()
				v.Edge, v.T, v.Forward = edge, t, math.random() < 0.5
				v.Mode = "Out"
				v.Target = Geo.Flat((along(edges[edge], t)))
				v.Position = Geo.Flat(door.Position)
				v.Y = door.Position.Y
				v.Facing = door.LookVector
				setFade(v, 1)
				table.insert(villagers, v)
				return true
			end
		end
	end
	return false
end

local function remove(index: number)
	villagers[index].Model:Destroy()
	table.remove(villagers, index)
end

-- Off to the nearest door (or out of sight if there's none).
local function hide(v: Villager, now: number)
	if v.Mode == "Hide" or v.Mode == "Gone" then
		return
	end
	local door = nearestDoor(v.Position, 60)
	v.Mode = "Hide"
	v.Target = if door then Geo.Flat(door.Position) else nil
	v.HideUntil = now + 2 + math.random() * 2
	v.Running = true
end

-- Next edge at the node a villager just reached (not straight back, unless
-- it's a dead end).
local function nextEdge(v: Villager)
	local edge = edges[v.Edge]
	local node = if v.Forward then edge.To else edge.From
	local options: { number } = {}
	for _, index in links[node] or ({} :: { number }) do
		if index ~= v.Edge then
			table.insert(options, index)
		end
	end
	local chosen = if #options > 0 then options[math.random(1, #options)] else v.Edge
	local new = edges[chosen]
	v.Edge = chosen
	v.Forward = new.From == node
	v.T = if v.Forward then 0 else 1
end

local function step(v: Villager, dt: number, now: number, giants: { Vector3 })
	-- Giants close by: run for it.
	if v.Mode ~= "Hide" and v.Mode ~= "Gone" then
		for _, g in giants do
			if (g - v.Position).Magnitude < 70 then
				hide(v, now)
				break
			end
		end
	end
	local speed = v.Speed * (if v.Running then 2.4 elseif Weather.Raining() then 1.4 else 1)
	local goal: Vector3
	if v.Mode == "Walk" then
		local edge = edges[v.Edge]
		v.T += (if v.Forward then 1 else -1) * speed * dt / edge.Length
		if v.T > 1 or v.T < 0 then
			v.T = math.clamp(v.T, 0, 1)
			nextEdge(v)
			edge = edges[v.Edge]
		end
		local p, forward = along(edge, v.T)
		if not v.Forward then
			forward = -forward
		end
		-- Keep to the right of the street.
		goal = p + Vector3.new(-forward.Z, 0, forward.X) * v.Lane
	else
		local target = v.Target
		if target then
			local offset = target - v.Position
			if offset.Magnitude < 1 then
				if v.Mode == "Out" then
					v.Mode = "Walk"
					v.Target = nil
				else
					v.Mode = "Gone" -- in through the door
				end
			end
			goal = v.Position + (if offset.Magnitude > 0.01 then offset.Unit * math.min(speed * dt, offset.Magnitude) else Vector3.zero)
		else
			-- Nowhere to hide nearby: hurry on, then duck out of sight.
			goal = v.Position + v.Facing * speed * dt
			if now >= v.HideUntil then
				v.Mode = "Gone"
			end
		end
	end
	local move = Geo.Flat(goal - v.Position)
	if v.Mode == "Walk" then
		-- (smoothed, so turning a corner or changing lane isn't a jump)
		v.Position = v.Position:Lerp(Geo.Flat(goal), math.min(dt * 6, 1))
	else
		v.Position = Geo.Flat(goal)
	end
	if move.Magnitude > 0.02 then
		v.Facing = v.Facing:Lerp(move.Unit, math.min(dt * 8, 1)).Unit
	end
	v.Phase += dt * speed * 1.5
	-- Fading in out of a door, out through one.
	local fadeGoal = if v.Mode == "Gone" then 1 else 0
	if v.Fade ~= fadeGoal then
		setFade(v, if fadeGoal > v.Fade then math.min(v.Fade + dt * 2.5, 1) else math.max(v.Fade - dt * 2.5, 0))
	end
	-- Stand on whatever's underneath (street, bridge), checked now and then.
	if now >= v.NextGround then
		v.NextGround = now + 0.35 + math.random() * 0.2
		local result = Workspace:Raycast(v.Position + Vector3.new(0, v.Y + 5, 0), Vector3.new(0, -14, 0), rayParams)
		if result then
			v.Y = result.Position.Y
		end
	end
end

local function pose(v: Villager): { CFrame }
	local swing = math.sin(v.Phase) * (if v.Running then 0.9 else 0.5)
	local bob = math.abs(math.cos(v.Phase)) * (if v.Running then 0.25 else 0.12)
	local base = CFrame.lookAt(v.Position, v.Position + v.Facing) + Vector3.new(0, v.Y + bob, 0)
	if v.Running then
		base *= CFrame.Angles(-0.2, 0, 0) -- leaning into the run
	end
	local frames: { CFrame } = {}
	for i, offset in v.Offsets do
		local turn = CFrame.new()
		if i == 1 or i == 6 then
			turn = CFrame.Angles(swing, 0, 0)
		elseif i == 2 or i == 7 then
			turn = CFrame.Angles(-swing, 0, 0)
		end
		if i == 1 or i == 2 or i == 6 or i == 7 then
			-- Swing from the hip or the shoulder (the top of the limb).
			local top = v.Parts[i].Size.Y / 2
			frames[i] = base * offset * CFrame.new(0, top, 0) * turn * CFrame.new(0, -top, 0)
		else
			frames[i] = base * offset
		end
	end
	return frames
end

function Townsfolk.Init()
	buildGraph()
	folder = Instance.new("Folder")
	folder.Name = "Townsfolk"
	folder.Parent = Workspace
	rayParams.FilterDescendantsInstances = { folder }

	-- Waves: everyone indoors while the giants are coming.
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local waveRemote = remotes:WaitForChild(Config.Remotes.Wave) :: RemoteEvent
	waveRemote.OnClientEvent:Connect(function(info: any)
		if typeof(info) == "table" then
			danger = info.Phase == "Breach" or info.Phase == "Fight"
		end
	end)

	local lowEnd = SkyController.LowEnd()
	local nextSpawn, nextDoors, nextGiants = 0, 0, 0
	local giants: { Vector3 } = {}
	RunService.Heartbeat:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local here = camera.CFrame.Position
		local now = os.clock()
		if now >= nextDoors then
			nextDoors = now + 4
			refreshDoors(here)
		end
		if now >= nextGiants then
			nextGiants = now + 0.5
			giants = {}
			for _, giant in CollectionService:GetTagged(Config.Tags.Giant) do
				local root = giant:FindFirstChild("Root")
				if root and root:IsA("BasePart") then
					table.insert(giants, Geo.Flat(root.Position))
				end
			end
		end

		-- How many should be out right now.
		local clock = Lighting.ClockTime
		local night = clock >= Config.DayNight.NightStart - 0.5 or clock < Config.DayNight.NightEnd + 0.5
		local cap = if lowEnd then A.VillagersLowEnd else A.Villagers
		if night then
			cap = math.min(cap, A.VillagersNight)
		end
		if Weather.Raining() then
			cap = math.floor(cap / 2)
		end
		local inTown = Geo.RadiusOf(here) < W.WallRadius + A.VillagerRange
		if danger or not inTown then
			cap = 0
		end

		for i = #villagers, 1, -1 do
			local v = villagers[i]
			if danger then
				hide(v, now)
			end
			local far = (Geo.Flat(here) - v.Position).Magnitude > A.VillagerRange + 40
			if far or (v.Mode == "Gone" and v.Fade >= 1) then
				remove(i)
			end
		end
		local alive = 0
		for _, v in villagers do
			if v.Mode ~= "Gone" and v.Mode ~= "Hide" then
				alive += 1
			end
		end
		if alive > cap and #villagers > 0 then
			-- Too many out (night fell, rain came): one heads in.
			for _, v in villagers do
				if v.Mode == "Walk" then
					hide(v, now)
					v.Running = false
					break
				end
			end
		elseif alive < cap and now >= nextSpawn then
			nextSpawn = now + 0.7
			spawnVillager(here)
		end

		local parts: { BasePart } = {}
		local frames: { CFrame } = {}
		for _, v in villagers do
			step(v, dt, now, giants)
			for i, frame in pose(v) do
				table.insert(parts, v.Parts[i])
				table.insert(frames, frame)
			end
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return Townsfolk
