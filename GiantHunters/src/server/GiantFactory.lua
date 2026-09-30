--!strict
-- Builds a giant: a big, goofy, part-built humanoid with a glowing weak
-- spot on the back of its neck (the Nape). Child-friendly by design: bright
-- clothes, cartoon faces, and no gore anywhere - defeated giants just puff
-- away into steam (see GiantService).
--
-- Rig: an invisible Root at hip height carries everything. Legs hang from
-- it and arms from the torso on Motor6Ds, so clients can swing them for a
-- walk cycle (GiantAnimator) without the server sending any animation.
-- Every part is non-colliding (giants stride through the town) but
-- queryable, so hunters can hook onto a giant's body.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GiantFactory = {}

local SKIN = {
	Color3.fromRGB(240, 200, 170),
	Color3.fromRGB(214, 160, 120),
	Color3.fromRGB(170, 115, 80),
	Color3.fromRGB(120, 80, 55),
}
local SHIRTS = {
	Color3.fromRGB(90, 130, 200),
	Color3.fromRGB(200, 90, 90),
	Color3.fromRGB(110, 170, 100),
	Color3.fromRGB(220, 170, 70),
	Color3.fromRGB(150, 110, 190),
}
local HAIR = {
	Color3.fromRGB(60, 40, 30),
	Color3.fromRGB(150, 100, 50),
	Color3.fromRGB(230, 200, 120),
	Color3.fromRGB(30, 30, 35),
}

export type Rig = {
	Model: Model,
	Root: BasePart,
	Torso: BasePart,
	Nape: BasePart,
	TorsoHeight: number,
	TorsoDepth: number,
}

local function limb(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = model
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
end

function GiantFactory.Build(kindName: string, position: Vector3, rng: Random): Rig
	local kind = Config.GiantKinds[kindName]
	assert(kind, `GiantFactory: unknown kind {kindName}`)
	local h = kind.Height
	local legLength, legWidth = h * 0.42, h * 0.12
	local torsoHeight, torsoWidth, torsoDepth = h * 0.32, h * 0.3, h * 0.16
	local headSize = h * 0.18
	local armLength, armWidth = h * 0.36, h * 0.09

	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
	local pants = Color3.fromRGB(80, 70, 60):Lerp(shirt, 0.2)

	local model = Instance.new("Model")
	model.Name = `{kindName}Giant`

	-- Everything is laid out facing -Z, at `position` on the ground.
	local base = CFrame.new(position)
	local root = limb(model, "Root", Vector3.new(torsoWidth, h * 0.05, torsoDepth), base * CFrame.new(0, legLength, 0), skin)
	root.Transparency = 1
	root.Massless = false
	root.CanQuery = false
	model.PrimaryPart = root

	local torso = limb(model, "Torso", Vector3.new(torsoWidth, torsoHeight, torsoDepth), base * CFrame.new(0, legLength + torsoHeight / 2, 0), shirt, Enum.Material.Fabric)
	weld(root, torso)
	-- Belly button... no. A belt, for a bit of costume.
	weld(torso, limb(model, "Belt", Vector3.new(torsoWidth + 0.2, h * 0.03, torsoDepth + 0.2), base * CFrame.new(0, legLength + h * 0.02, 0), Color3.fromRGB(90, 60, 40)))

	local headCentre = base * CFrame.new(0, legLength + torsoHeight + headSize / 2, 0)
	local head = limb(model, "Head", Vector3.new(headSize, headSize, headSize * 0.9), headCentre, skin)
	weld(torso, head)
	-- Hair cap, cartoon eyes (whites + pupils) and a big grin, on the front (-Z).
	weld(head, limb(model, "Hair", Vector3.new(headSize * 1.05, headSize * 0.3, headSize * 0.95), headCentre * CFrame.new(0, headSize * 0.4, 0.02 * h), HAIR[rng:NextInteger(1, #HAIR)]))
	for i, x in { -0.22, 0.22 } do
		local eye = limb(model, `Eye{i}`, Vector3.new(headSize * 0.22, headSize * 0.22, headSize * 0.05), headCentre * CFrame.new(x * headSize, headSize * 0.08, -headSize * 0.46), Color3.fromRGB(250, 250, 250))
		weld(head, eye)
		weld(head, limb(model, `Pupil{i}`, Vector3.new(headSize * 0.1, headSize * 0.1, headSize * 0.05), headCentre * CFrame.new(x * headSize, headSize * 0.06, -headSize * 0.49), Color3.fromRGB(30, 25, 25)))
	end
	weld(head, limb(model, "Grin", Vector3.new(headSize * 0.5, headSize * 0.08, headSize * 0.05), headCentre * CFrame.new(0, -headSize * 0.22, -headSize * 0.46), Color3.fromRGB(90, 40, 40)))

	-- The weak spot: a glowing patch on the back of the neck (+Z side).
	local nape = limb(
		model,
		"Nape",
		Vector3.new(headSize * 0.8, headSize * 0.45, h * 0.03),
		base * CFrame.new(0, legLength + torsoHeight + headSize * 0.1, torsoDepth / 2 + h * 0.01),
		Color3.fromRGB(255, 120, 60),
		Enum.Material.Neon
	)
	nape.Transparency = 0.2
	weld(torso, nape)
	local glow = Instance.new("PointLight")
	glow.Color = nape.Color
	glow.Range = h * 0.4
	glow.Brightness = 1.5
	glow.Parent = nape

	-- Legs on hip motors (pivot at the top of each leg).
	for i, side in { -1, 1 } do
		local leg = limb(model, if side < 0 then "LeftLeg" else "RightLeg", Vector3.new(legWidth, legLength, legWidth * 1.1), base * CFrame.new(side * legWidth * 0.6, legLength / 2, 0), pants, Enum.Material.Fabric)
		motor(if side < 0 then "LeftHip" else "RightHip", root, leg, CFrame.new(side * legWidth * 0.6, 0, 0), CFrame.new(0, legLength / 2, 0))
		weld(leg, limb(model, `Foot{i}`, Vector3.new(legWidth * 1.1, h * 0.04, legWidth * 1.6), base * CFrame.new(side * legWidth * 0.6, h * 0.02, -legWidth * 0.3), Color3.fromRGB(70, 50, 40)))
	end
	-- Arms on shoulder motors (pivot at the top of each arm).
	for _, side in { -1, 1 } do
		local shoulder = CFrame.new(side * (torsoWidth / 2 + armWidth / 2), torsoHeight / 2 - armWidth / 2, 0)
		local arm = limb(model, if side < 0 then "LeftArm" else "RightArm", Vector3.new(armWidth, armLength, armWidth), base * CFrame.new(0, legLength + torsoHeight / 2, 0) * shoulder * CFrame.new(0, -armLength / 2 + armWidth / 2, 0), skin)
		motor(if side < 0 then "LeftShoulder" else "RightShoulder", torso, arm, shoulder, CFrame.new(0, armLength / 2 - armWidth / 2, 0))
	end

	-- Kinematic movement: the server steers these; physics does the gliding.
	local attachment = Instance.new("Attachment")
	attachment.Name = "Drive"
	attachment.Parent = root
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "Move"
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.MaxForce = math.huge
	alignPosition.MaxVelocity = kind.WalkSpeed
	alignPosition.Responsiveness = 40
	alignPosition.Position = root.Position
	alignPosition.Parent = root
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "Face"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.Responsiveness = 12
	alignOrientation.CFrame = CFrame.new()
	alignOrientation.Parent = root

	model:SetAttribute("Kind", kindName)
	model:SetAttribute("Height", h)
	model:SetAttribute("NapeHealth", kind.NapeHealth)
	model:SetAttribute("MaxNapeHealth", kind.NapeHealth)
	CollectionService:AddTag(model, Config.Tags.Giant)

	return {
		Model = model,
		Root = root,
		Torso = torso,
		Nape = nape,
		TorsoHeight = torsoHeight,
		TorsoDepth = torsoDepth,
	}
end

return GiantFactory
