--!strict
-- The Great Wall: a ring of stone 110 studs high round the whole district,
-- with a walkway, merlons and watchtowers on top, stone bands down its
-- faces, iron grates where the river runs under it, wall cannons by the
-- gate, and the hunters' post (the spawn) on top of the north wall.
--
-- The south gate is the story of every round: the Wallbreaker kicks its
-- doors in (Wall.Breach), giants pour through, and once the district is
-- saved the doors are rebuilt (Wall.Repair).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local Kit = require(script.Parent.Kit)

local Wall = {}

local W = Config.World
local P = Kit.Palette
local R, T, H = W.WallRadius, W.WallThickness, W.WallHeight

local gateModel: Model? = nil
local doors: { Model } = {}
local breached = false

-- A frame on the wall's centre line at `angle`: local Z points outward
-- (away from the town), local X along the wall.
local function frameAt(angle: number, y: number): CFrame
	return CFrame.new(Geo.Polar(angle, R + T / 2, y)) * CFrame.Angles(0, angle, 0)
end

local function segment(parent: Instance, angle: number, length: number)
	local model = Kit.Model("WallSegment", parent)
	local base = frameAt(angle, 0)
	Kit.Part({ Name = "Stone", Size = Vector3.new(length, H, T), CFrame = base * CFrame.new(0, H / 2, 0), Color = P.WallStone, Material = Enum.Material.Slate, Parent = model })
	Kit.Part({ Name = "Plinth", Size = Vector3.new(length, 6, T + 3), CFrame = base * CFrame.new(0, 3, 0), Color = P.WallBand, Material = Enum.Material.Slate, Parent = model })
	for _, y in { 22, 44, 66, 88 } do
		Kit.Detail({ Name = "Band", Size = Vector3.new(length, 2.2, T + 1.6), CFrame = base * CFrame.new(0, y, 0), Color = P.WallBand, Material = Enum.Material.Slate, Parent = model })
	end
	Kit.Part({ Name = "Walk", Size = Vector3.new(length, 0.6, T), CFrame = base * CFrame.new(0, H + 0.3, 0), Color = P.WallTop, Material = Enum.Material.Cobblestone, Parent = model })
	Kit.Part({ Name = "Parapet", Size = Vector3.new(length, 2.2, 1.2), CFrame = base * CFrame.new(0, H + 1.7, -T / 2 + 0.6), Color = P.WallBand, Material = Enum.Material.Slate, Parent = model })
	for _, x in { -length / 3, 0, length / 3 } do
		Kit.Part({ Name = "Merlon", Size = Vector3.new(5, 4.4, 2.4), CFrame = base * CFrame.new(x, H + 2.8, T / 2 - 1.2), Color = P.WallBand, Material = Enum.Material.Slate, Parent = model })
	end
end

local function door(parent: Instance, frame: CFrame, side: number): Model
	local model = Kit.Model("GateDoor", parent)
	local width = W.GateWidth / 2 - 0.2
	local leaf = Kit.Part({
		Name = "Leaf",
		Size = Vector3.new(width, W.GateHeight - 0.4, 2.6),
		CFrame = frame * CFrame.new(side * (width / 2 + 0.1), W.GateHeight / 2, 0),
		Color = Color3.fromRGB(110, 72, 44),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	for _, y in { 0.2, 0.5, 0.8 } do
		local band = Kit.Detail({
			Name = "IronBand",
			Size = Vector3.new(width, 1.6, 3),
			CFrame = frame * CFrame.new(side * (width / 2 + 0.1), W.GateHeight * y, 0),
			Color = P.Iron,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = leaf
		weld.Part1 = band
		weld.Parent = band
	end
	return model
end

local function hangDoors()
	local gate = gateModel
	if not gate then
		return
	end
	local frame = frameAt(W.GateAngle, 0)
	doors = { door(gate, frame, -1), door(gate, frame, 1) }
end

local function gatehouse(parent: Instance)
	local gate = Kit.Model("SouthGate", parent)
	gateModel = gate
	local frame = frameAt(W.GateAngle, 0)
	local depth = T + 12
	local towerWidth = 13
	local height = H + 14
	local gw, gh = W.GateWidth, W.GateHeight
	for _, side in { -1, 1 } do
		local x = side * (gw / 2 + towerWidth / 2)
		Kit.Part({ Name = "GateTower", Size = Vector3.new(towerWidth, height, depth), CFrame = frame * CFrame.new(x, height / 2, 0), Color = P.WallStone, Material = Enum.Material.Slate, Parent = gate })
		for _, z in { -1, 1 } do
			-- Crenellated top of each tower, front and back.
			Kit.Part({ Name = "Merlon", Size = Vector3.new(4, 4.4, 2.4), CFrame = frame * CFrame.new(x - side * 3, height + 2.2, z * (depth / 2 - 1.2)), Color = P.WallBand, Material = Enum.Material.Slate, Parent = gate })
			Kit.Part({ Name = "Merlon", Size = Vector3.new(4, 4.4, 2.4), CFrame = frame * CFrame.new(x + side * 3, height + 2.2, z * (depth / 2 - 1.2)), Color = P.WallBand, Material = Enum.Material.Slate, Parent = gate })
		end
		-- Darker stone jambs framing the opening.
		Kit.Detail({ Name = "Jamb", Size = Vector3.new(2.4, gh + 2, depth + 1), CFrame = frame * CFrame.new(side * (gw / 2 + 1.2), (gh + 2) / 2, 0), Color = P.WallBand, Material = Enum.Material.Slate, Parent = gate })
	end
	Kit.Part({ Name = "Lintel", Size = Vector3.new(gw, height - gh, depth), CFrame = frame * CFrame.new(0, gh + (height - gh) / 2, 0), Color = P.WallStone, Material = Enum.Material.Slate, Parent = gate })
	-- The wall's stone bands carry on across the gatehouse (round the
	-- opening below the lintel).
	for _, y in { 22, 44, 66, 88 } do
		if y > gh then
			Kit.Detail({ Name = "Band", Size = Vector3.new(gw + towerWidth * 2 + 1.6, 2.2, depth + 1.6), CFrame = frame * CFrame.new(0, y, 0), Color = P.WallBand, Material = Enum.Material.Slate, Parent = gate })
		else
			for _, side in { -1, 1 } do
				Kit.Detail({ Name = "Band", Size = Vector3.new(towerWidth + 0.8, 2.2, depth + 1.6), CFrame = frame * CFrame.new(side * (gw / 2 + 2.4 + towerWidth / 2 - 0.4), y, 0), Color = P.WallBand, Material = Enum.Material.Slate, Parent = gate })
			end
		end
	end
	Kit.Detail({ Name = "Keystone", Size = Vector3.new(gw + 4.8, 4, depth + 1), CFrame = frame * CFrame.new(0, gh + 2, 0), Color = P.WallBand, Material = Enum.Material.Slate, Parent = gate })
	Kit.Part({ Name = "Walk", Size = Vector3.new(gw + towerWidth * 2, 0.6, depth), CFrame = frame * CFrame.new(0, height + 0.3, 0), Color = P.WallTop, Material = Enum.Material.Cobblestone, Parent = gate })
	-- Banners: one over the gate on each face.
	for _, z in { -1, 1 } do
		local face = frame * CFrame.new(0, gh + 26, z * (depth / 2 + 0.5))
		-- A wall frame's -Z faces the town; turn the outer one to face the wilds.
		Kit.Banner(gate, if z > 0 then face * CFrame.Angles(0, math.pi, 0) else face, 18, 22)
	end
	hangDoors()
end

local function watchtower(parent: Instance, angle: number)
	local model = Kit.Model("Watchtower", parent)
	local base = frameAt(angle, H + 0.6)
	local size, height = 12, 18
	Kit.Part({ Name = "Body", Size = Vector3.new(size, height, size), CFrame = base * CFrame.new(0, height / 2, 0), Color = P.WallStone, Material = Enum.Material.Slate, Parent = model })
	for _, face in { 0, 90, 180, 270 } do
		Kit.Detail({ Name = "Window", Size = Vector3.new(3, 4.5, 0.4), CFrame = base * CFrame.Angles(0, math.rad(face), 0) * CFrame.new(0, height * 0.62, -size / 2 - 0.1), Color = Color3.fromRGB(40, 36, 34), Material = Enum.Material.SmoothPlastic, Parent = model })
	end
	local roofHeight = 7
	for _, side in { -1, 1 } do
		Kit.Part({
			Class = "WedgePart",
			Name = "Roof",
			Size = Vector3.new(size + 2, roofHeight, size / 2 + 1),
			CFrame = base * CFrame.new(0, height + roofHeight / 2, side * (size / 4 + 0.5)) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			Color = P.Roof[1],
			Material = Enum.Material.Slate,
			Parent = model,
		})
	end
	Kit.Rod(model, "Flagpole", (base * CFrame.new(0, height + roofHeight - 1, 0)).Position, (base * CFrame.new(0, height + roofHeight + 9, 0)).Position, 0.5, P.Iron, Enum.Material.Metal)
	Kit.Detail({ Name = "Flag", Size = Vector3.new(0.2, 3, 5), CFrame = base * CFrame.new(0, height + roofHeight + 7.4, 2.6), Color = P.HunterBlue, Material = Enum.Material.Fabric, Parent = model })
end

local function cannon(parent: Instance, angle: number)
	local model = Kit.Model("WallCannon", parent)
	local base = frameAt(angle, H + 0.6) * CFrame.new(0, 0, -1)
	local carriage = Kit.Part({ Name = "Carriage", Size = Vector3.new(4, 2.4, 6), CFrame = base * CFrame.new(0, 1.2, 0), Color = Color3.fromRGB(96, 70, 48), Material = Enum.Material.Wood, Parent = model })
	model.PrimaryPart = carriage
	for _, side in { -1, 1 } do
		Kit.Detail({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 3.4, 3.4), CFrame = base * CFrame.new(side * 2.4, 1.7, 0.6), Color = Color3.fromRGB(70, 52, 36), Material = Enum.Material.Wood, Parent = model })
	end
	-- Barrel along local +Z (out over the wilds), tipped a little down.
	local barrel = Kit.Part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, 2.2, 2.2),
		CFrame = base * CFrame.new(0, 3.2, 1.5) * CFrame.Angles(math.rad(8), 0, 0) * CFrame.Angles(0, math.rad(-90), 0),
		Color = Color3.fromRGB(52, 54, 60),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Kit.Detail({ Name = "Muzzle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 2.8, 2.8), CFrame = barrel.CFrame * CFrame.new(3.8, 0, 0), Color = Color3.fromRGB(40, 42, 48), Material = Enum.Material.Metal, Parent = model })
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= carriage then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = carriage
			weld.Part1 = part
			weld.Parent = part
		end
	end
	CollectionService:AddTag(model, Config.Tags.Cannon)
end

-- Iron grates where the river runs under the wall, so the slot reads as a
-- culvert.
local function waterGates(parent: Instance)
	local crossings = {}
	local wasInside = Geo.IsInside(Vector3.new(-W.LandRadius, 0, Geo.RiverZ(-W.LandRadius)))
	for x = -W.LandRadius, W.LandRadius, 1 do
		local p = Vector3.new(x, 0, Geo.RiverZ(x))
		local inside = Geo.IsInside(p)
		if inside ~= wasInside then
			table.insert(crossings, p)
			wasInside = inside
		end
	end
	for _, crossing in crossings do
		local angle = Geo.AngleOf(crossing)
		for _, face in { -1, 1 } do
			local frame = CFrame.new(Geo.Polar(angle, R + T / 2 + face * (T / 2 + 0.6), 0)) * CFrame.Angles(0, angle, 0)
			local span = W.River.Width + 8
			for x = -span / 2, span / 2, 2.6 do
				Kit.Detail({ Name = "GrateBar", Size = Vector3.new(0.5, 13, 0.5), CFrame = frame * CFrame.new(x, -5.5, 0), Color = P.Iron, Material = Enum.Material.Metal, Parent = parent })
			end
			Kit.Detail({ Name = "GrateArch", Size = Vector3.new(span + 4, 4, 1.4), CFrame = frame * CFrame.new(0, 2, 0), Color = P.WallBand, Material = Enum.Material.Slate, Parent = parent })
		end
	end
end

-- The hunters' post on top of the north wall: the spawn, two supply crates,
-- banners down the town-side face. Returns the spawn.
local function hunterPost(parent: Instance): SpawnLocation
	local angle = W.GateAngle + math.pi
	local top = frameAt(angle, H + 0.6)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HunterSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 10)
	-- Hunters spawn facing the spawn's front: a wall frame's -Z already
	-- points into town.
	spawn.CFrame = top * CFrame.new(0, 0.5, 0)
	spawn.Color = Color3.fromRGB(120, 200, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 3
	spawn.Parent = parent
	for _, side in { -1, 1 } do
		Kit.SupplyStation(parent, (top * CFrame.new(side * 14, 0, 0)).Position, side < 0)
		local inner = CFrame.new(Geo.Polar(angle + side * 0.05, R - 0.6, H - 4)) * CFrame.Angles(0, angle, 0)
		Kit.Banner(parent, inner, 16, 30)
	end
	return spawn
end

function Wall.Build(parent: Instance): SpawnLocation
	local folder = Instance.new("Folder")
	folder.Name = "GreatWall"
	folder.Parent = parent
	local n = W.WallSegments
	local length = 2 * (R + T) * math.tan(math.pi / n) + 0.6
	for i = 0, n - 1 do
		local angle = W.GateAngle + i / n * math.pi * 2
		if i ~= 0 then
			segment(folder, angle, length)
		end
	end
	gatehouse(folder)
	for _, degrees in { 45, 90, 135, 225, 270, 315 } do
		watchtower(folder, W.GateAngle + math.rad(degrees))
	end
	for _, offset in { -0.34, -0.17, 0.17, 0.34 } do
		cannon(folder, W.GateAngle + offset)
	end
	waterGates(folder)
	return hunterPost(folder)
end

function Wall.IsBreached(): boolean
	return breached
end

-- The doors burst inward as tumbling debris, with rubble and a dust cloud.
function Wall.Breach()
	if breached then
		return
	end
	breached = true
	local frame = frameAt(W.GateAngle, 0)
	local inward = frame.LookVector -- a wall frame's local -Z points into town
	for _, model in doors do
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = true
				part.CanQuery = false
				part.AssemblyLinearVelocity = inward.Unit * 70 + Vector3.new(0, 30, 0)
				part.AssemblyAngularVelocity = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1) * 2
			end
		end
		task.delay(7, function()
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					TweenService:Create(part, TweenInfo.new(1.5), { Transparency = 1 }):Play()
				end
			end
			Debris:AddItem(model, 1.6)
		end)
	end
	doors = {}
	local gate = gateModel
	for _ = 1, 16 do
		local size = math.random(20, 60) / 10
		local rock = Kit.Part({
			Name = "Rubble",
			Size = Vector3.new(size, size * 0.8, size),
			CFrame = frame * CFrame.new(math.random(-16, 16), W.GateHeight - math.random(0, 6), math.random(-4, 4)),
			Color = P.WallBand,
			Material = Enum.Material.Slate,
			Parent = gate or workspace,
		})
		rock.Anchored = false
		rock.CanQuery = false
		rock.AssemblyLinearVelocity = inward.Unit * math.random(20, 60) + Vector3.new(math.random(-15, 15), math.random(5, 25), math.random(-15, 15))
		Debris:AddItem(rock, 9)
	end
	local dust = Instance.new("Part")
	dust.Anchored = true
	dust.CanCollide = false
	dust.CanQuery = false
	dust.Transparency = 1
	dust.Size = Vector3.new(W.GateWidth, W.GateHeight, 6)
	dust.CFrame = frame * CFrame.new(0, W.GateHeight / 2, 0)
	dust.Parent = gate or workspace
	local cloud = Instance.new("ParticleEmitter")
	cloud.Color = ColorSequence.new(Color3.fromRGB(196, 184, 164))
	cloud.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 22) })
	cloud.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	cloud.Lifetime = NumberRange.new(2.5, 4)
	cloud.Speed = NumberRange.new(10, 30)
	cloud.SpreadAngle = Vector2.new(60, 60)
	cloud.Rate = 0
	cloud.Parent = dust
	cloud:Emit(80)
	Debris:AddItem(dust, 6)
end

-- New doors for a new round.
function Wall.Repair()
	if not breached then
		return
	end
	breached = false
	hangDoors()
end

return Wall
