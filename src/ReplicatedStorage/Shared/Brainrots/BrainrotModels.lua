--!strict
-- Procedural part-built factory for the 16 canonical Brainrots
-- (docs/BRAINROT_ROSTER.md). No mesh/import pipeline exists in this project,
-- so every character is assembled from primitive Parts/WedgeParts welded
-- into a Model, in code, here.
--
-- Shared module: both PetService (server, authoritative companions) and any
-- client code (ViewportFrame previews, hatchery showcase) may call these
-- factory functions directly.
--
-- === Coordinate convention =================================================
-- Every character is built standing on the XZ plane at local Y = 0 (feet /
-- underside touch the ground), centered on local (0, 0). The character faces
-- -Z (Roblox's own "front" convention). All part CFrames below are therefore
-- absolute *local* CFrames in that space, not offsets from some other part -
-- the whole assembly is moved as a unit later via Model:SetPrimaryPartCFrame
-- (callers, e.g. PetService, use PrimaryPart + AlignPosition/AlignOrientation
-- to place and follow), which preserves every part's relative position.
--
-- === Design shape ===========================================================
-- Rather than 16 fully bespoke rigs, every character is:
--   1. one of a few body ARCHETYPES (Quadruped / Bird / Blob / Aquatic), each
--      a small parametrized builder function below, plus
--   2. a short per-character `Decorate` closure that welds on 2-6 bespoke
--      "extra" parts (tusks, shells, cannons, mandolins, ...) using the same
--      shared `addBlock` / `addWedge` / `addBall` / `addCylinder*` helpers.
-- Rarity glow is layered on top of whichever parts each Decorate closure
-- tags as "accent" parts, so higher rarities read as brighter versions of
-- the same silhouette rather than a separate visual system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Theme)

local BrainrotModels = {}

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Secret"

-- === Low-level build context ================================================
-- Tracks the model under construction so helpers can auto-weld every part
-- after the first (which becomes PrimaryPart) and auto-register "accent"
-- parts that the rarity pass may light up.

type Ctx = {
	Model: Model,
	Anchored: boolean,
	Parts: { BasePart },
	AccentParts: { BasePart },
}

local function newCtx(name: string, anchored: boolean): Ctx
	local model = Instance.new("Model")
	model.Name = name
	return {
		Model = model,
		Anchored = anchored,
		Parts = {},
		AccentParts = {},
	}
end

-- Shared finishing touches + auto-weld-to-primary for every part we add.
local function registerPart(ctx: Ctx, part: BasePart)
	part.CanCollide = false -- a following companion must never body-block a player
	part.CastShadow = true
	part.Anchored = ctx.Anchored
	part.Massless = not ctx.Anchored
	part.Parent = ctx.Model

	table.insert(ctx.Parts, part)

	if not ctx.Model.PrimaryPart then
		ctx.Model.PrimaryPart = part
	elseif not ctx.Anchored then
		-- Anchored (static/showcase) models don't need constraints - nothing
		-- moves. Dynamic models weld every part rigidly to the first (torso).
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = ctx.Model.PrimaryPart
		weld.Part1 = part
		weld.Parent = part
	end
end

local function addBlock(ctx: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	registerPart(ctx, part)
	return part
end

local function addWedge(ctx: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	registerPart(ctx, part)
	return part
end

local function addBall(ctx: Ctx, name: string, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	registerPart(ctx, part)
	return part
end

-- A cylinder lying with its axle along local X (e.g. a wheel, or a horizontal
-- barrel/tusk) - this is a plain Roblox Cylinder's default orientation, no
-- extra rotation needed.
local function addCylinderX(ctx: Ctx, name: string, diameter: number, length: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(length, diameter, diameter)
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	registerPart(ctx, part)
	return part
end

-- A cylinder standing upright (round faces up/down) - used for legs, necks,
-- turbans, stalks. Bakes in the 90-degree fix Roblox cylinders need.
local function addCylinderY(ctx: Ctx, name: string, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	registerPart(ctx, part)
	return part
end

-- Marks a part as an "accent" - the piece of the design that carries the
-- character's AccentColor. Rarity FX (neon upgrade, glow, emitters) is
-- layered onto these parts, so every character's signature detail is also
-- what lights up at higher rarity.
local function accent(ctx: Ctx, part: BasePart): BasePart
	table.insert(ctx.AccentParts, part)
	return part
end

-- === Rarity treatment =======================================================
-- Common/Rare: silhouette + color only, no extra FX.
-- Epic: accent parts go Neon + a soft glow PointLight.
-- Legendary: brighter glow + a particle emitter.
-- Secret: strongest glow + a starfield-style emitter, and an attribute the
-- client can use for cosmetic flourishes (e.g. a slow spin) without any
-- server-side per-frame loop.
local function applyRarity(ctx: Ctx, rarity: Rarity)
	local color = Theme.RarityColor(rarity)
	local primary = ctx.Model.PrimaryPart
	if not primary then
		return
	end

	ctx.Model:SetAttribute("Rarity", rarity)

	if rarity == "Common" or rarity == "Rare" then
		return
	end

	for _, part in ctx.AccentParts do
		part.Material = Enum.Material.Neon
	end

	local light = Instance.new("PointLight")
	light.Name = "RarityGlow"
	light.Color = color
	light.Shadows = false
	light.Parent = primary

	local emitter: ParticleEmitter? = nil
	if rarity == "Epic" then
		light.Brightness = 2
		light.Range = 12
	elseif rarity == "Legendary" then
		light.Brightness = 3
		light.Range = 16
		emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 6
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Speed = NumberRange.new(1, 2)
	elseif rarity == "Secret" then
		light.Brightness = 4
		light.Range = 22
		emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 14
		emitter.Lifetime = NumberRange.new(0.8, 1.8)
		emitter.Speed = NumberRange.new(1.5, 3)
		ctx.Model:SetAttribute("SecretSpin", true)
	end

	if emitter then
		emitter.Name = "RarityEmitter"
		emitter.Color = ColorSequence.new(color)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.LightEmission = 0.7
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = primary
	end
end

-- === Body archetypes ========================================================
-- Each returns a table of named anchor CFrames in the same local space, so a
-- character's Decorate closure can weld extras relative to "where the head
-- is" without recomputing body proportions itself.

type Anchors = { [string]: CFrame }

type QuadrupedOpts = {
	BodyColor: Color3,
	BodyLength: number?,
	BodyWidth: number?,
	BodyHeight: number?,
	LegLength: number?,
	LegThickness: number?,
	HeadSize: Vector3?,
	NeckLength: number?,
	LegCount: number?, -- 3 or 4; 3 skips one hind leg for a quirky tripod look
}

local function buildQuadruped(ctx: Ctx, opts: QuadrupedOpts): Anchors
	local bodyLength = opts.BodyLength or 2.3
	local bodyWidth = opts.BodyWidth or 1.5
	local bodyHeight = opts.BodyHeight or 1.3
	local legLength = opts.LegLength or 1.1
	local legThickness = opts.LegThickness or 0.38
	local headSize = opts.HeadSize or Vector3.new(1.05, 1, 1.05)
	local neckLength = opts.NeckLength or 0.15
	local legCount = opts.LegCount or 4

	local torsoCenterY = legLength + bodyHeight / 2
	local torso = addBlock(
		ctx,
		"Torso",
		Vector3.new(bodyWidth, bodyHeight, bodyLength),
		CFrame.new(0, torsoCenterY, 0),
		opts.BodyColor
	)

	-- Legs at the four corners; dropping the back-right leg gives a 3-legged
	-- variant (used for Tralalero Astrale) without a separate builder.
	local legOffsets = {
		{ x = bodyWidth / 2 - legThickness / 2, z = -bodyLength / 2 + legThickness }, -- front-right
		{ x = -(bodyWidth / 2 - legThickness / 2), z = -bodyLength / 2 + legThickness }, -- front-left
		{ x = bodyWidth / 2 - legThickness / 2, z = bodyLength / 2 - legThickness }, -- back-right
		{ x = -(bodyWidth / 2 - legThickness / 2), z = bodyLength / 2 - legThickness }, -- back-left
	}
	for i = 1, math.min(legCount, 4) do
		local offset = legOffsets[i]
		addCylinderY(
			ctx,
			`Leg{i}`,
			legThickness,
			legLength,
			CFrame.new(offset.x, legLength / 2, offset.z),
			opts.BodyColor
		)
	end

	local neckTopY = torsoCenterY + bodyHeight / 2 + neckLength
	if neckLength > 0.05 then
		addCylinderY(
			ctx,
			"Neck",
			bodyWidth * 0.55,
			neckLength,
			CFrame.new(0, torsoCenterY + bodyHeight / 2 + neckLength / 2, -bodyLength / 2 + headSize.Z * 0.3),
			opts.BodyColor
		)
	end

	local headCF = CFrame.new(0, neckTopY + headSize.Y / 2 - 0.1, -bodyLength / 2 - headSize.Z / 2 + 0.3)
	addBlock(ctx, "Head", headSize, headCF, opts.BodyColor)

	return {
		Torso = torso.CFrame,
		Head = headCF,
		HeadTop = headCF * CFrame.new(0, headSize.Y / 2, 0),
		HeadFront = headCF * CFrame.new(0, 0, -headSize.Z / 2),
		TorsoTop = torso.CFrame * CFrame.new(0, bodyHeight / 2, 0),
		TorsoBack = torso.CFrame * CFrame.new(0, 0, bodyLength / 2),
		TorsoSide = torso.CFrame * CFrame.new(bodyWidth / 2, 0, 0),
	}
end

type BirdOpts = {
	BodyColor: Color3,
	BodyDiameter: number?,
	HeadDiameter: number?,
	LegCount: number?, -- 1 (flamingo) or 2
	LegLength: number?,
}

local function buildBird(ctx: Ctx, opts: BirdOpts): Anchors
	local bodyDiameter = opts.BodyDiameter or 1.7
	local headDiameter = opts.HeadDiameter or 0.85
	local legCount = opts.LegCount or 2
	local legLength = opts.LegLength or 1.0
	local legThickness = 0.16

	local bodyCenterY = legLength + bodyDiameter / 2
	local torso = addBall(ctx, "Torso", bodyDiameter, CFrame.new(0, bodyCenterY, 0), opts.BodyColor)

	if legCount == 1 then
		addCylinderY(ctx, "Leg1", legThickness * 1.3, legLength, CFrame.new(0, legLength / 2, 0.1), opts.BodyColor)
	else
		for i, x in { 0.3, -0.3 } do
			addCylinderY(ctx, `Leg{i}`, legThickness, legLength, CFrame.new(x, legLength / 2, 0.1), opts.BodyColor)
		end
	end

	local headCF = CFrame.new(0, bodyCenterY + bodyDiameter / 2 + headDiameter * 0.3, -bodyDiameter / 2 - headDiameter * 0.15)
	addBall(ctx, "Head", headDiameter, headCF, opts.BodyColor)

	local beakCF = headCF * CFrame.new(0, -headDiameter * 0.1, -headDiameter / 2) * CFrame.Angles(math.rad(-90), 0, 0)
	addWedge(ctx, "Beak", Vector3.new(0.22, 0.35, 0.22), beakCF, Color3.fromRGB(255, 184, 76))

	-- Wings sit as two angled wedges on either flank.
	local wingCFLeft = CFrame.new(bodyDiameter / 2 - 0.1, bodyCenterY, 0.1) * CFrame.Angles(0, 0, math.rad(20))
	local wingCFRight = CFrame.new(-(bodyDiameter / 2 - 0.1), bodyCenterY, 0.1) * CFrame.Angles(0, math.rad(180), math.rad(20))
	local wingSize = Vector3.new(0.9, 0.15, 1.1)

	return {
		Torso = torso.CFrame,
		Head = headCF,
		HeadTop = headCF * CFrame.new(0, headDiameter / 2, 0),
		WingLeft = wingCFLeft,
		WingRight = wingCFRight,
		WingSize = CFrame.new(wingSize), -- smuggled through Anchors just to share the size value
		TorsoBack = torso.CFrame * CFrame.new(0, 0, bodyDiameter / 2),
		TorsoTop = torso.CFrame * CFrame.new(0, bodyDiameter / 2, 0),
	}
end

type BlobOpts = {
	BodyColor: Color3,
	StalkHeight: number?,
	ClusterDiameter: number?,
}

-- A stalk + cluster-of-spheres body for food-shaped characters that don't
-- walk on legs (they hover/bob via PetService's follow offset instead).
local function buildBlob(ctx: Ctx, opts: BlobOpts): Anchors
	local stalkHeight = opts.StalkHeight or 0.8
	local clusterDiameter = opts.ClusterDiameter or 1.6

	local stalk = addCylinderY(
		ctx,
		"Stalk",
		0.55,
		stalkHeight,
		CFrame.new(0, stalkHeight / 2, 0),
		Color3.fromRGB(235, 225, 200)
	)

	local clusterCenterY = stalkHeight + clusterDiameter * 0.35
	addBall(ctx, "ClusterCore", clusterDiameter, CFrame.new(0, clusterCenterY, 0), opts.BodyColor)
	local puffPositions = {
		Vector3.new(0.55, 0.25, 0.2),
		Vector3.new(-0.55, 0.2, -0.2),
		Vector3.new(0, 0.55, -0.4),
		Vector3.new(0.2, 0.4, 0.5),
	}
	for i, offset in puffPositions do
		addBall(
			ctx,
			`ClusterPuff{i}`,
			clusterDiameter * 0.55,
			CFrame.new(offset) + Vector3.new(0, clusterCenterY, 0),
			opts.BodyColor
		)
	end

	return {
		Torso = stalk.CFrame,
		ClusterTop = CFrame.new(0, clusterCenterY + clusterDiameter / 2, 0),
		ClusterCenter = CFrame.new(0, clusterCenterY, 0),
		ClusterFront = CFrame.new(0, clusterCenterY, -clusterDiameter / 2),
	}
end

-- Octopus-style body: a bulbous head over a skirt of curling tentacles. Used
-- only by Polpo Motorino, but built from the same shared primitives.
local function buildAquaticHead(ctx: Ctx, bodyColor: Color3): Anchors
	local headDiameter = 1.7
	local headCenterY = 1.5
	local head = addBall(ctx, "Torso", headDiameter, CFrame.new(0, headCenterY, 0), bodyColor)

	-- Six short curling tentacle segments fanned around the underside.
	for i = 0, 5 do
		local angle = (i / 6) * math.pi * 2
		local x = math.cos(angle) * 0.6
		local z = math.sin(angle) * 0.6
		local baseCF = CFrame.new(x, headCenterY - headDiameter / 2 + 0.2, z)
			* CFrame.Angles(math.rad(20), angle, 0)
		addCylinderY(ctx, `Tentacle{i}Upper`, 0.22, 0.6, baseCF, bodyColor)
		local tipCF = baseCF * CFrame.new(0, -0.5, 0) * CFrame.Angles(math.rad(35), 0, 0)
		addCylinderY(ctx, `Tentacle{i}Tip`, 0.16, 0.45, tipCF, bodyColor)
	end

	return {
		Torso = head.CFrame,
		Top = CFrame.new(0, headCenterY + headDiameter / 2, 0),
		Front = CFrame.new(0, headCenterY, -headDiameter / 2),
		Side = CFrame.new(headDiameter / 2, headCenterY, 0),
	}
end

-- === Per-character definitions ==============================================

type CharacterDef = {
	Id: string,
	Build: (ctx: Ctx) -> (),
}

local ACCENT_NEON = Enum.Material.Neon

local characters: { [string]: CharacterDef } = {}

-- Spaghettoro - wild boar, spaghetti tusks, marinara mohawk.
characters.Spaghettoro = {
	Id = "Spaghettoro",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(120, 84, 63)
		local anchors = buildQuadruped(ctx, {
			BodyColor = bodyColor,
			BodyLength = 2.2,
			BodyWidth = 1.5,
			BodyHeight = 1.2,
			LegLength = 0.9,
			HeadSize = Vector3.new(1.1, 0.95, 1.15),
		})
		-- Spaghetti tusks: two thin curling yellow cylinders under the snout.
		local tuskColor = Color3.fromRGB(240, 220, 140)
		addCylinderX(ctx, "TuskLeft", 0.12, 0.5, anchors.HeadFront * CFrame.new(0.25, -0.25, 0) * CFrame.Angles(0, 0, math.rad(20)), tuskColor)
		addCylinderX(ctx, "TuskRight", 0.12, 0.5, anchors.HeadFront * CFrame.new(-0.25, -0.25, 0) * CFrame.Angles(0, 0, math.rad(-20)), tuskColor)
		-- Marinara mohawk: a red neon ridge along the spine.
		accent(ctx, addBlock(ctx, "Mohawk", Vector3.new(0.2, 0.35, 1.4), anchors.TorsoTop, Color3.fromRGB(200, 60, 40), ACCENT_NEON))
		-- Round pig ears.
		addWedge(ctx, "EarLeft", Vector3.new(0.1, 0.4, 0.35), anchors.HeadTop * CFrame.new(0.4, -0.1, 0.1) * CFrame.Angles(0, 0, math.rad(-30)), bodyColor)
		addWedge(ctx, "EarRight", Vector3.new(0.1, 0.4, 0.35), anchors.HeadTop * CFrame.new(-0.4, -0.1, 0.1) * CFrame.Angles(0, 0, math.rad(30)), bodyColor)
	end,
}

-- Cannolini Volpe - fox wrapped in a crispy cannoli shell.
characters.CannoliniVolpe = {
	Id = "CannoliniVolpe",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(214, 122, 63)
		local anchors = buildQuadruped(ctx, {
			BodyColor = bodyColor,
			BodyLength = 2.0,
			BodyWidth = 1.2,
			BodyHeight = 1.05,
			LegLength = 0.95,
			HeadSize = Vector3.new(0.85, 0.8, 0.9),
		})
		-- Crispy cannoli shell wrapped around the torso.
		accent(ctx, addCylinderX(ctx, "CannoliShell", 1.7, 1.9, anchors.Torso, Color3.fromRGB(235, 205, 150), ACCENT_NEON))
		-- Pointy fox ears.
		addWedge(ctx, "EarLeft", Vector3.new(0.05, 0.5, 0.35), anchors.HeadTop * CFrame.new(0.3, 0, 0), bodyColor)
		addWedge(ctx, "EarRight", Vector3.new(0.05, 0.5, 0.35), anchors.HeadTop * CFrame.new(-0.3, 0, 0), bodyColor)
		-- Bushy tail.
		addWedge(ctx, "Tail", Vector3.new(0.5, 0.5, 1.0), anchors.TorsoBack * CFrame.new(0, 0.2, 0.4) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(245, 240, 235))
	end,
}

-- Polpo Motorino - octopus riding a tiny moped on its tentacles.
characters.PolpoMotorino = {
	Id = "PolpoMotorino",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(210, 90, 150)
		local anchors = buildAquaticHead(ctx, bodyColor)
		-- Tiny moped: body + two wheels underneath, handlebar up front.
		accent(ctx, addBlock(ctx, "MopedBody", Vector3.new(0.5, 0.35, 1.2), anchors.Torso * CFrame.new(0, -0.95, 0), Color3.fromRGB(230, 190, 40), ACCENT_NEON))
		addCylinderX(ctx, "WheelFront", 0.5, 0.22, anchors.Torso * CFrame.new(0, -1.1, -0.5), Color3.fromRGB(30, 30, 34))
		addCylinderX(ctx, "WheelBack", 0.5, 0.22, anchors.Torso * CFrame.new(0, -1.1, 0.5), Color3.fromRGB(30, 30, 34))
		addCylinderX(ctx, "Handlebar", 0.08, 0.6, anchors.Torso * CFrame.new(0, -0.75, -0.55), Color3.fromRGB(60, 60, 66))
	end,
}

-- Pinguino Mandolino - penguin playing a mandolin, trailing music notes.
characters.PinguinoMandolino = {
	Id = "PinguinoMandolino",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(30, 34, 44)
		local anchors = buildBird(ctx, { BodyColor = bodyColor, BodyDiameter = 1.5, LegCount = 2, LegLength = 0.4 })
		-- White belly patch.
		addBall(ctx, "Belly", 1.1, anchors.Torso * CFrame.new(0, -0.1, 0.35), Color3.fromRGB(240, 240, 245))
		-- Mandolin: a flat teardrop body plus a thin neck, held at the side.
		accent(ctx, addBlock(ctx, "Mandolin", Vector3.new(0.1, 0.6, 0.5), anchors.TorsoBack * CFrame.new(0.9, 0, -0.1) * CFrame.Angles(0, 0, math.rad(15)), Color3.fromRGB(180, 120, 60), ACCENT_NEON))
		addCylinderX(ctx, "MandolinNeck", 0.06, 0.5, anchors.TorsoBack * CFrame.new(0.9, 0.35, -0.1) * CFrame.Angles(0, 0, math.rad(90 + 15)), Color3.fromRGB(90, 60, 30))
	end,
}

-- Broccolino Turbanti - broccoli floret in a chef's turban.
characters.BroccolinoTurbanti = {
	Id = "BroccolinoTurbanti",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(60, 140, 70)
		local anchors = buildBlob(ctx, { BodyColor = bodyColor, StalkHeight = 0.9, ClusterDiameter = 1.6 })
		-- Chef's turban: a white cylinder band + a poofy top.
		accent(ctx, addCylinderY(ctx, "TurbanBand", 1.3, 0.35, anchors.ClusterTop, Color3.fromRGB(250, 250, 250), ACCENT_NEON))
		addBall(ctx, "TurbanPoof", 1.0, anchors.ClusterTop * CFrame.new(0, 0.35, 0), Color3.fromRGB(250, 250, 250))
	end,
}

-- Lucertola Focaccina - lizard with a focaccia-bread back shell.
characters.LucertolaFocaccina = {
	Id = "LucertolaFocaccina",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(90, 165, 90)
		local anchors = buildQuadruped(ctx, {
			BodyColor = bodyColor,
			BodyLength = 1.9,
			BodyWidth = 1.0,
			BodyHeight = 0.7,
			LegLength = 0.55,
			LegThickness = 0.24,
			HeadSize = Vector3.new(0.6, 0.55, 0.75),
		})
		-- Focaccia shell: a flattened tan dome on the back with dimples.
		accent(ctx, addBlock(ctx, "FocacciaShell", Vector3.new(1.2, 0.4, 1.6), anchors.TorsoTop * CFrame.new(0, 0.1, 0), Color3.fromRGB(225, 190, 120), ACCENT_NEON))
		for i, offset in { Vector3.new(0.3, 0, 0.4), Vector3.new(-0.3, 0, -0.1), Vector3.new(0.15, 0, -0.4) } do
			addBall(ctx, `Dimple{i}`, 0.14, anchors.TorsoTop * CFrame.new(offset) * CFrame.new(0, 0.3, 0), Color3.fromRGB(180, 130, 70))
		end
		-- Tail.
		addCylinderX(ctx, "Tail", 0.18, 1.0, anchors.TorsoBack * CFrame.new(0, 0, 0.6), bodyColor)
	end,
}

-- Girafferro Espressone - giraffe with an espresso-machine head, steaming horns.
characters.GirafferroEspressone = {
	Id = "GirafferroEspressone",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(225, 190, 110)
		local anchors = buildQuadruped(ctx, {
			BodyColor = bodyColor,
			BodyLength = 2.0,
			BodyWidth = 1.2,
			BodyHeight = 1.1,
			LegLength = 1.5,
			NeckLength = 1.4,
			HeadSize = Vector3.new(0.9, 0.8, 0.9),
		})
		-- Espresso-machine head: chrome block replacing a soft snout, with two
		-- steaming spout "horns".
		accent(ctx, addBlock(ctx, "EspressoHead", Vector3.new(0.95, 0.7, 0.95), anchors.Head, Color3.fromRGB(160, 40, 40), ACCENT_NEON))
		addCylinderY(ctx, "SpoutLeft", 0.1, 0.4, anchors.HeadTop * CFrame.new(0.25, 0, 0), Color3.fromRGB(210, 210, 220))
		addCylinderY(ctx, "SpoutRight", 0.1, 0.4, anchors.HeadTop * CFrame.new(-0.25, 0, 0), Color3.fromRGB(210, 210, 220))
		-- Giraffe spots.
		for i, offset in { Vector3.new(0.3, -0.2, 0.1), Vector3.new(-0.25, 0.25, -0.3), Vector3.new(0.1, -0.3, -0.5) } do
			addBlock(ctx, `Spot{i}`, Vector3.new(0.3, 0.3, 0.05), anchors.TorsoSide * CFrame.new(offset), Color3.fromRGB(160, 110, 50))
		end
	end,
}

-- Rondine Ravioli - swallow with ravioli-pocket wings.
characters.RondineRavioli = {
	Id = "RondineRavioli",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(60, 90, 150)
		local anchors = buildBird(ctx, { BodyColor = bodyColor, BodyDiameter = 1.3, LegCount = 2, LegLength = 0.3 })
		-- Ravioli-pocket wings: a wedge wing with a square pasta-pocket patch.
		local wingSize = Vector3.new(0.85, 0.15, 1.05)
		addWedge(ctx, "WingLeft", wingSize, anchors.WingLeft, bodyColor)
		addWedge(ctx, "WingRight", wingSize, anchors.WingRight, bodyColor)
		accent(ctx, addBlock(ctx, "RavioliLeft", Vector3.new(0.4, 0.08, 0.4), anchors.WingLeft * CFrame.new(0.3, 0.1, 0), Color3.fromRGB(235, 210, 160), ACCENT_NEON))
		accent(ctx, addBlock(ctx, "RavioliRight", Vector3.new(0.4, 0.08, 0.4), anchors.WingRight * CFrame.new(-0.3, 0.1, 0), Color3.fromRGB(235, 210, 160), ACCENT_NEON))
		-- Forked swallow tail.
		addWedge(ctx, "TailLeft", Vector3.new(0.3, 0.1, 0.6), anchors.TorsoBack * CFrame.new(0.15, 0, 0.3) * CFrame.Angles(0, math.rad(10), 0), bodyColor)
		addWedge(ctx, "TailRight", Vector3.new(0.3, 0.1, 0.6), anchors.TorsoBack * CFrame.new(-0.15, 0, 0.3) * CFrame.Angles(0, math.rad(-10), 0), bodyColor)
	end,
}

-- Scoiattolo Cannoncino - squirrel strapped to a mini cannon backpack.
characters.ScoiattoloCannoncino = {
	Id = "ScoiattoloCannoncino",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(160, 110, 70)
		local anchors = buildQuadruped(ctx, {
			BodyColor = bodyColor,
			BodyLength = 1.7,
			BodyWidth = 1.0,
			BodyHeight = 0.9,
			LegLength = 0.7,
			LegThickness = 0.26,
			HeadSize = Vector3.new(0.75, 0.7, 0.75),
		})
		-- Big bushy tail arcing up behind.
		addBall(ctx, "TailBase", 0.5, anchors.TorsoBack * CFrame.new(0, 0.3, 0.3), bodyColor)
		addBall(ctx, "TailTip", 0.4, anchors.TorsoBack * CFrame.new(0, 0.9, 0.5), bodyColor)
		-- Mini cannon backpack, angled up and back.
		accent(ctx, addCylinderX(ctx, "Cannon", 0.35, 0.9, anchors.TorsoTop * CFrame.new(0, 0.35, -0.1) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(60, 60, 66), ACCENT_NEON))
	end,
}

-- Tartaruga Vespaccia - turtle with a Vespa-scooter shell.
characters.TartarugaVespaccia = {
	Id = "TartarugaVespaccia",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(80, 150, 90)
		local anchors = buildQuadruped(ctx, {
			BodyColor = bodyColor,
			BodyLength = 1.8,
			BodyWidth = 1.3,
			BodyHeight = 0.65,
			LegLength = 0.4,
			LegThickness = 0.3,
			HeadSize = Vector3.new(0.55, 0.5, 0.6),
		})
		-- Vespa-shell: a rounded scooter-body shape on the back with a
		-- headlight up front and mirrors.
		accent(ctx, addBlock(ctx, "VespaShell", Vector3.new(1.4, 0.55, 1.9), anchors.TorsoTop * CFrame.new(0, 0.25, 0), Color3.fromRGB(220, 230, 200), ACCENT_NEON))
		addBall(ctx, "Headlight", 0.22, anchors.TorsoTop * CFrame.new(0, 0.25, -0.95), Color3.fromRGB(255, 245, 200))
		addCylinderX(ctx, "MirrorStalkLeft", 0.05, 0.3, anchors.TorsoTop * CFrame.new(0.5, 0.55, -0.8), Color3.fromRGB(60, 60, 66))
		addCylinderX(ctx, "MirrorStalkRight", 0.05, 0.3, anchors.TorsoTop * CFrame.new(-0.5, 0.55, -0.8), Color3.fromRGB(60, 60, 66))
	end,
}

-- Fenicottero Pizzaiolo - flamingo spinning pizza dough on one leg.
characters.FenicotteroPizzaiolo = {
	Id = "FenicotteroPizzaiolo",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(240, 130, 170)
		local anchors = buildBird(ctx, { BodyColor = bodyColor, BodyDiameter = 1.4, LegCount = 1, LegLength = 1.7 })
		local wingSize = Vector3.new(0.75, 0.15, 0.95)
		addWedge(ctx, "WingLeft", wingSize, anchors.WingLeft, bodyColor)
		addWedge(ctx, "WingRight", wingSize, anchors.WingRight, bodyColor)
		-- Chef hat.
		addCylinderY(ctx, "ChefHat", 0.55, 0.5, anchors.HeadTop * CFrame.new(0, 0.25, 0), Color3.fromRGB(250, 250, 250))
		-- Spinning pizza dough disc, held out at wing height.
		accent(ctx, addCylinderY(ctx, "PizzaDough", 1.1, 0.08, anchors.WingLeft * CFrame.new(0.6, -0.3, 0), Color3.fromRGB(235, 205, 140), ACCENT_NEON))
	end,
}

-- Pipistrello Marinaro - bat in a sailor cap, sail-shaped wings.
characters.PipistrelloMarinaro = {
	Id = "PipistrelloMarinaro",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(45, 45, 60)
		local anchors = buildBird(ctx, { BodyColor = bodyColor, BodyDiameter = 1.3, LegCount = 2, LegLength = 0.35 })
		-- Large sail-shaped wings.
		local wingSize = Vector3.new(1.5, 0.1, 1.7)
		accent(ctx, addWedge(ctx, "WingLeft", wingSize, anchors.WingLeft, Color3.fromRGB(60, 90, 150), ACCENT_NEON))
		accent(ctx, addWedge(ctx, "WingRight", wingSize, anchors.WingRight, Color3.fromRGB(60, 90, 150), ACCENT_NEON))
		-- Sailor cap: white cylinder with a blue band.
		addCylinderY(ctx, "SailorCap", 0.7, 0.35, anchors.HeadTop * CFrame.new(0, 0.15, 0), Color3.fromRGB(250, 250, 250))
		addCylinderY(ctx, "SailorBand", 0.72, 0.1, anchors.HeadTop * CFrame.new(0, 0, 0), Color3.fromRGB(50, 80, 150))
	end,
}

-- Cannolo Trombonini - walking cannoli playing a trombone.
characters.CannoloTrombonini = {
	Id = "CannoloTrombonini",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(235, 205, 150)
		local shellRadius = 0.75
		local legLength = 1.0
		local bodyCenterY = legLength + shellRadius
		local shell = addCylinderX(ctx, "Torso", shellRadius * 2, 1.6, CFrame.new(0, bodyCenterY, 0) * CFrame.Angles(0, 0, math.rad(90)), bodyColor)
		-- Two thin legs.
		addCylinderY(ctx, "Leg1", 0.22, legLength, CFrame.new(0.3, legLength / 2, 0), Color3.fromRGB(80, 60, 50))
		addCylinderY(ctx, "Leg2", 0.22, legLength, CFrame.new(-0.3, legLength / 2, 0), Color3.fromRGB(80, 60, 50))
		-- Cream filling peeking from both ends.
		addBall(ctx, "FillingFront", shellRadius * 1.5, CFrame.new(0, bodyCenterY, -0.85), Color3.fromRGB(250, 245, 230))
		addBall(ctx, "FillingBack", shellRadius * 1.5, CFrame.new(0, bodyCenterY, 0.85), Color3.fromRGB(250, 245, 230))
		-- Trombone: slide + bell, held out front.
		accent(ctx, addCylinderX(ctx, "TromboneSlide", 0.12, 1.1, CFrame.new(0, bodyCenterY + 0.1, -1.2), Color3.fromRGB(230, 190, 40), ACCENT_NEON))
		addCylinderX(ctx, "TromboneBell", 0.35, 0.3, CFrame.new(0, bodyCenterY + 0.1, -1.75), Color3.fromRGB(230, 190, 40))

		shell.Name = "Torso"
	end,
}

-- Crocobrivido Vulcanico - volcanic crocodile, lava cracks & bomber jacket.
characters.CrocobrividoVulcanico = {
	Id = "CrocobrividoVulcanico",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(40, 60, 45)
		local anchors = buildQuadruped(ctx, {
			BodyColor = bodyColor,
			BodyLength = 2.8,
			BodyWidth = 1.3,
			BodyHeight = 1.0,
			LegLength = 0.7,
			LegThickness = 0.35,
			HeadSize = Vector3.new(0.9, 0.6, 1.3),
		})
		-- Lava crack accents along the spine and tail.
		accent(ctx, addBlock(ctx, "LavaCrackSpine", Vector3.new(0.15, 0.1, 1.6), anchors.TorsoTop, Color3.fromRGB(255, 110, 30), ACCENT_NEON))
		accent(ctx, addBlock(ctx, "LavaCrackTail", Vector3.new(0.12, 0.1, 0.9), anchors.TorsoBack * CFrame.new(0, 0.1, 0.5), Color3.fromRGB(255, 110, 30), ACCENT_NEON))
		-- Bomber jacket draped over the shoulders/front torso.
		addBlock(ctx, "BomberJacket", Vector3.new(1.4, 0.6, 1.1), anchors.TorsoTop * CFrame.new(0, -0.1, -0.6), Color3.fromRGB(120, 80, 50))
		-- Tail.
		addCylinderX(ctx, "Tail", 0.4, 1.3, anchors.TorsoBack * CFrame.new(0, 0, 0.85), bodyColor)
	end,
}

-- Squalezza Ferroviaria - shark fused with a locomotive front, steam plume.
characters.SqualezzaFerroviaria = {
	Id = "SqualezzaFerroviaria",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(70, 80, 95)
		local anchors = buildQuadruped(ctx, {
			BodyColor = bodyColor,
			BodyLength = 2.9,
			BodyWidth = 1.4,
			BodyHeight = 1.3,
			LegLength = 0.5,
			LegThickness = 0.4,
			LegCount = 4,
			HeadSize = Vector3.new(1.1, 0.9, 1.2),
		})
		-- Locomotive cowcatcher front (a wedge welded to the head/nose).
		accent(ctx, addWedge(ctx, "Cowcatcher", Vector3.new(1.0, 0.6, 0.7), anchors.HeadFront * CFrame.new(0, -0.2, -0.2) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(220, 60, 50), ACCENT_NEON))
		-- Dorsal fin.
		addWedge(ctx, "DorsalFin", Vector3.new(0.15, 0.7, 0.9), anchors.TorsoTop * CFrame.Angles(0, 0, 0), bodyColor)
		-- Small wheels along the underside read as "train wheels" on a shark body.
		for i, z in { -0.7, 0, 0.7 } do
			addCylinderX(ctx, `Wheel{i}`, 0.4, 0.2, anchors.Torso * CFrame.new(0, -0.7, z), Color3.fromRGB(30, 30, 34))
		end
	end,
}

-- Tralalero Astrale - cosmic three-legged shark-sneaker hybrid, starlight.
characters.TralaleroAstrale = {
	Id = "TralaleroAstrale",
	Build = function(ctx)
		local bodyColor = Color3.fromRGB(35, 30, 70)
		local anchors = buildQuadruped(ctx, {
			BodyColor = bodyColor,
			BodyLength = 2.4,
			BodyWidth = 1.3,
			BodyHeight = 1.1,
			LegLength = 0.9,
			LegThickness = 0.4,
			LegCount = 3, -- the "three-legged" part of the design
			HeadSize = Vector3.new(1.0, 0.85, 1.2),
		})
		-- Shark dorsal fin.
		accent(ctx, addWedge(ctx, "DorsalFin", Vector3.new(0.15, 0.8, 1.0), anchors.TorsoTop, Color3.fromRGB(120, 90, 255), ACCENT_NEON))
		-- Sneaker-shaped "feet": a block sole + wedge toe on the remaining legs.
		for i, offset in { Vector3.new(0.56, 0.1, -0.9), Vector3.new(-0.56, 0.1, -0.9), Vector3.new(0.56, 0.1, 0.9) } do
			addBlock(ctx, `SneakerSole{i}`, Vector3.new(0.5, 0.2, 0.8), CFrame.new(offset), Color3.fromRGB(240, 240, 245))
			addWedge(ctx, `SneakerToe{i}`, Vector3.new(0.5, 0.25, 0.3), CFrame.new(offset) * CFrame.new(0, 0.1, -0.5), Color3.fromRGB(240, 240, 245))
		end
		-- Star flecks scattered across the body (small white neon studs).
		for i, offset in { Vector3.new(0.4, 0.3, 0.2), Vector3.new(-0.3, 0.1, -0.3), Vector3.new(0.1, -0.2, 0.4), Vector3.new(-0.2, 0.35, 0.1) } do
			accent(ctx, addBall(ctx, `StarFleck{i}`, 0.1, anchors.TorsoSide * CFrame.new(offset), Color3.fromRGB(255, 255, 255), ACCENT_NEON))
		end
	end,
}

-- === Public API ==============================================================

local function build(brainrotId: string, rarity: Rarity, anchored: boolean): Model
	local def = characters[brainrotId]
	assert(def ~= nil, `BrainrotModels: unknown brainrot id "{brainrotId}"`)

	local ctx = newCtx(brainrotId, anchored)
	def.Build(ctx)
	applyRarity(ctx, rarity)

	assert(ctx.Model.PrimaryPart ~= nil, `BrainrotModels: "{brainrotId}" built with no parts`)
	return ctx.Model
end

-- A dynamic companion: unanchored, welded, collision-free, ready for
-- AlignPosition/AlignOrientation to drive around. Not parented - the caller
-- decides where it lives (PetService parents it under a Pets folder).
function BrainrotModels.Build(brainrotId: string, rarity: Rarity): Model
	return build(brainrotId, rarity, false)
end

-- A static display copy: anchored, no physics/constraints, for hatchery
-- podiums or a UI ViewportFrame. Not parented.
function BrainrotModels.BuildStatic(brainrotId: string, rarity: Rarity): Model
	return build(brainrotId, rarity, true)
end

-- Every buildable id, for callers that want to sanity-check or iterate (e.g.
-- a showcase that spawns one of each).
function BrainrotModels.GetKnownIds(): { string }
	local ids = {}
	for id in characters do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return BrainrotModels
