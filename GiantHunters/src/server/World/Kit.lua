--!strict
-- What every world builder shares: anchored parts in one call, the palette,
-- and a few small set pieces (banners, crates, lamps, trees) that turn up
-- all over the district.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Kit = {}

-- Cylinders run along their local X; these turn one upright, or along a
-- lookAt direction.
Kit.UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
Kit.ALONG_LOOK = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis onto a CFrame's look direction

Kit.Palette = {
	WallStone = Color3.fromRGB(186, 178, 160),
	WallBand = Color3.fromRGB(150, 142, 126),
	WallTop = Color3.fromRGB(168, 160, 144),
	Plaster = {
		Color3.fromRGB(238, 228, 208),
		Color3.fromRGB(228, 212, 184),
		Color3.fromRGB(216, 202, 182),
		Color3.fromRGB(242, 236, 222),
		Color3.fromRGB(226, 216, 198),
		Color3.fromRGB(222, 196, 168),
	},
	Stone = {
		Color3.fromRGB(172, 162, 148),
		Color3.fromRGB(158, 150, 138),
		Color3.fromRGB(186, 174, 154),
	},
	Timber = Color3.fromRGB(92, 64, 44),
	Roof = {
		Color3.fromRGB(178, 78, 56),
		Color3.fromRGB(162, 94, 62),
		Color3.fromRGB(124, 66, 50),
		Color3.fromRGB(98, 106, 122),
		Color3.fromRGB(188, 100, 66),
	},
	Glass = Color3.fromRGB(56, 68, 86),
	Door = Color3.fromRGB(86, 56, 38),
	Iron = Color3.fromRGB(60, 62, 68),
	HunterBlue = Color3.fromRGB(38, 70, 132),
	Cream = Color3.fromRGB(236, 226, 192),
	Gold = Color3.fromRGB(230, 190, 90),
	Bark = Color3.fromRGB(104, 76, 54),
	Leaves = {
		Color3.fromRGB(76, 132, 60),
		Color3.fromRGB(92, 146, 64),
		Color3.fromRGB(66, 118, 58),
	},
}

export type Props = { [string]: any }

-- An anchored part from a property table. `Class` picks WedgePart etc.
function Kit.Part(props: Props): BasePart
	local p = Instance.new(props.Class or "Part") :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" and key ~= "Class" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

-- Small decoration: no shadow, no touch events.
function Kit.Detail(props: Props): BasePart
	local p = Kit.Part(props)
	p.CastShadow = false
	p.CanTouch = false
	return p
end

function Kit.Model(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- A cylinder between two points.
function Kit.Rod(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local length = (b - a).Magnitude
	local frame = if math.abs((b - a).Unit.Y) > 0.999
		then CFrame.new((a + b) / 2) * Kit.UPRIGHT
		else CFrame.lookAt((a + b) / 2, b) * Kit.ALONG_LOOK
	return Kit.Part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = frame,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

-- The hunters' banner: blue cloth, cream trim, a shield with two crossed
-- blades. `cframe` is the top centre of the cloth, facing out along -Z.
function Kit.Banner(parent: Instance, cframe: CFrame, width: number, height: number)
	local model = Kit.Model("Banner", parent)
	local P = Kit.Palette
	Kit.Detail({ Name = "Rod", Size = Vector3.new(width + 1.5, 0.6, 0.6), CFrame = cframe, Color = P.Timber, Material = Enum.Material.Wood, Parent = model })
	Kit.Detail({ Name = "Cloth", Size = Vector3.new(width, height, 0.3), CFrame = cframe * CFrame.new(0, -height / 2, 0), Color = P.HunterBlue, Material = Enum.Material.Fabric, Parent = model })
	Kit.Detail({ Name = "Trim", Size = Vector3.new(width, height * 0.06, 0.34), CFrame = cframe * CFrame.new(0, -height + height * 0.03, 0), Color = P.Cream, Material = Enum.Material.Fabric, Parent = model })
	local emblem = cframe * CFrame.new(0, -height * 0.45, -0.25)
	local shield = width * 0.5
	Kit.Detail({ Name = "Shield", Size = Vector3.new(shield, shield, 0.2), CFrame = emblem * CFrame.Angles(0, 0, math.rad(45)), Color = P.Cream, Material = Enum.Material.Fabric, Parent = model })
	for _, tilt in { -35, 35 } do
		Kit.Detail({ Name = "Blade", Size = Vector3.new(width * 0.1, shield * 1.5, 0.22), CFrame = emblem * CFrame.new(0, 0, -0.1) * CFrame.Angles(0, 0, math.rad(tilt)), Color = Color3.fromRGB(200, 210, 222), Material = Enum.Material.Metal, Parent = model })
	end
end

-- A supply station: crate, gas canisters, and a tall blue beam to find it.
-- `beam` false for crates that sit somewhere already easy to spot.
function Kit.SupplyStation(parent: Instance, position: Vector3, beam: boolean?)
	local model = Kit.Model("SupplyStation", parent)
	local crate = Kit.Part({
		Name = "Crate",
		Size = Vector3.new(6, 5, 6),
		Position = position + Vector3.new(0, 2.5, 0),
		Color = Color3.fromRGB(150, 110, 60),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	Kit.Detail({
		Name = "Canisters",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 2.2, 2.2),
		CFrame = CFrame.new(position + Vector3.new(0, 6.1, 0)) * Kit.UPRIGHT,
		Color = Color3.fromRGB(180, 190, 200),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	for _, x in { -1.6, 1.6 } do
		Kit.Detail({
			Name = "BladeBox",
			Size = Vector3.new(1, 2.4, 4.6),
			Position = position + Vector3.new(x + (if x > 0 then 1.9 else -1.9), 1.4, 0),
			Color = Kit.Palette.Iron,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	if beam ~= false then
		local glow = Kit.Detail({
			Name = "Beacon",
			Size = Vector3.new(1, 36, 1),
			Position = position + Vector3.new(0, 24, 0),
			Color = Color3.fromRGB(120, 230, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})
		local light = Instance.new("PointLight")
		light.Color = glow.Color
		light.Range = 18
		light.Parent = glow
	end
	CollectionService:AddTag(crate, Config.Tags.Supply)
	return model
end

-- A street lamp: post, arm, lantern with a warm light.
function Kit.Lamp(parent: Instance, position: Vector3, facing: number)
	local model = Kit.Model("Lamp", parent)
	local post = Kit.Detail({ Name = "Post", Size = Vector3.new(0.7, 11, 0.7), Position = position + Vector3.new(0, 5.5, 0), Color = Kit.Palette.Iron, Material = Enum.Material.Metal, Parent = model })
	post.CastShadow = true
	local top = CFrame.new(position + Vector3.new(0, 11, 0)) * CFrame.Angles(0, facing, 0)
	Kit.Detail({ Name = "Arm", Size = Vector3.new(0.4, 0.4, 2.6), CFrame = top * CFrame.new(0, -0.3, -1.1), Color = Kit.Palette.Iron, Material = Enum.Material.Metal, Parent = model })
	local lantern = Kit.Detail({ Name = "Lantern", Size = Vector3.new(1.2, 1.6, 1.2), CFrame = top * CFrame.new(0, -1.4, -2.2), Color = Color3.fromRGB(255, 214, 140), Material = Enum.Material.Neon, Parent = model })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 130)
	light.Range = 22
	light.Brightness = 1.6
	light.Parent = lantern
	CollectionService:AddTag(lantern, Config.Tags.NightLight) -- lit at night by each client
end

-- A torch: an iron bracket and a burning head (fire and warm light, lit at
-- night by each client). `cframe` is the base of the shaft, upright.
function Kit.Torch(parent: Instance, cframe: CFrame)
	local model = Kit.Model("Torch", parent)
	Kit.Detail({ Name = "Shaft", Size = Vector3.new(0.5, 4, 0.5), CFrame = cframe * CFrame.new(0, 2, 0), Color = Kit.Palette.Iron, Material = Enum.Material.Metal, Parent = model })
	local head = Kit.Detail({ Name = "Head", Size = Vector3.new(1, 1.2, 1), CFrame = cframe * CFrame.new(0, 4.4, 0), Color = Color3.fromRGB(70, 46, 30), Material = Enum.Material.Wood, Parent = model })
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 7
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
	fire.Enabled = false
	fire.Parent = head
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = 24
	light.Brightness = 2
	light.Enabled = false
	light.Parent = head
	CollectionService:AddTag(head, Config.Tags.NightLight)
end

-- A round-crowned broadleaf tree (town squares, gardens, the plains).
function Kit.Tree(parent: Instance, position: Vector3, height: number, rng: Random)
	local model = Kit.Model("Tree", parent)
	local trunk = height * 0.09
	Kit.Part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height * 0.62, trunk, trunk),
		CFrame = CFrame.new(position + Vector3.new(0, height * 0.31, 0)) * Kit.UPRIGHT,
		Color = Kit.Palette.Bark,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	for i = 1, 3 do
		local size = height * rng:NextNumber(0.42, 0.58)
		Kit.Part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			Position = position + Vector3.new(rng:NextNumber(-0.18, 0.18) * height, height * (0.62 + i * 0.09), rng:NextNumber(-0.18, 0.18) * height),
			Color = Kit.Palette.Leaves[rng:NextInteger(1, #Kit.Palette.Leaves)],
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = model,
		})
	end
	return model
end

-- A fir: trunk and three stacked tiers (hills and the edges of the wilds).
function Kit.Fir(parent: Instance, position: Vector3, height: number, rng: Random)
	local model = Kit.Model("Fir", parent)
	Kit.Part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height * 0.5, height * 0.07, height * 0.07),
		CFrame = CFrame.new(position + Vector3.new(0, height * 0.25, 0)) * Kit.UPRIGHT,
		Color = Kit.Palette.Bark,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	local green = Color3.fromRGB(46 + rng:NextInteger(0, 16), 92 + rng:NextInteger(0, 20), 58)
	for tier = 1, 3 do
		local width = height * (0.62 - tier * 0.14)
		Kit.Part({
			Name = "Tier",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height * 0.24, width, width),
			CFrame = CFrame.new(position + Vector3.new(0, height * (0.2 + tier * 0.22), 0)) * Kit.UPRIGHT,
			Color = green,
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = model,
		})
	end
	return model
end

return Kit
