--!strict
-- Builds a giant: a big, goofy-creepy humanoid with a glowing weak spot on
-- the back of its neck (the Nape). Child-friendly by design: cartoon faces,
-- shorts, no gore - defeated giants just puff away into steam.
--
-- Look: soft, rounded shapes only (capsule limbs, a rounded trunk, ball
-- joints), a hunched posture with the head pushed forward, a jutting
-- muzzle, big round eyes that follow you (and blink). Every giant rolls a
-- body type (lanky, stocky, chubby, a short-legged "bighead" or a gangly
-- one), skin, hair style and colour, face, brows, nose and shorts, so a
-- wave never looks like a copy-paste crowd. Signature giants fix their
-- look in Config (GiantLook): the stone Wallbreaker, the ape-like Beast,
-- the Armored one, the titan Shifter, the Sprinter and the Crawler.
--
-- Rig: an invisible Root at hip height carries everything. Waist, hips,
-- knees, shoulders, elbows and the neck are Motor6Ds, so clients animate
-- the lumbering walk, the grab and the head tracking (GiantAnimator)
-- without the server sending any animation. So are the pupils (LeftEye,
-- RightEye) and the eyelids (LeftLid, RightLid). Every part is
-- non-colliding (giants stride through town) but queryable, so hunters can
-- hook onto a giant's body.
--
-- Whatever sits behind the head (hair, helmet, buns, ponytails) stays above
-- the nape, so it is never hidden when you come at it from above or behind.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GiantFactory = {}

local SKIN = {
	Color3.fromRGB(240, 200, 170),
	Color3.fromRGB(226, 178, 142),
	Color3.fromRGB(196, 140, 104),
	Color3.fromRGB(160, 108, 76),
	Color3.fromRGB(118, 80, 58),
	Color3.fromRGB(214, 196, 184), -- pale, a little grey: the eerie ones
	Color3.fromRGB(196, 150, 140),
}
local SHORTS = {
	Color3.fromRGB(90, 110, 160),
	Color3.fromRGB(150, 80, 70),
	Color3.fromRGB(96, 130, 90),
	Color3.fromRGB(120, 100, 80),
	Color3.fromRGB(110, 80, 130),
}
local HAIR = {
	Color3.fromRGB(60, 40, 30),
	Color3.fromRGB(150, 100, 50),
	Color3.fromRGB(230, 200, 120),
	Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(170, 70, 40),
	Color3.fromRGB(128, 56, 30), -- dark ginger
	Color3.fromRGB(176, 176, 172), -- grey
	Color3.fromRGB(236, 234, 226), -- white
}
local LIPS = Color3.fromRGB(70, 25, 30)
local TEETH = Color3.fromRGB(250, 248, 236)
local TONGUE = Color3.fromRGB(226, 110, 120)
local EYE_WHITE = Color3.fromRGB(246, 242, 232)
local PUPIL = Color3.fromRGB(30, 25, 25) -- SkyController sets this back at dawn

-- Body types: multipliers on the base proportions, plus how far forward
-- the giant slouches (radians). Bighead is the classic odd one out: short
-- legs, a huge head and a grin you can see from the top of the wall.
-- Gangly is the creepy one: thin as a rake, a small head, a deep stoop and
-- arms that hang down past its knees. The last three are only for the
-- giants that ask for them (Config.GiantKinds).
type BodyType = { Width: number, LimbLength: number, ArmLength: number, Belly: number, Head: number, Hunch: number, Ribs: boolean }
local BODY_TYPES: { [string]: BodyType } = {
	Lanky = { Width = 0.8, LimbLength = 1.08, ArmLength = 1, Belly = 0.7, Head = 1, Hunch = 0.14, Ribs = true },
	Stocky = { Width = 1.2, LimbLength = 0.92, ArmLength = 1, Belly = 0.9, Head = 0.95, Hunch = 0.08, Ribs = false },
	Chubby = { Width = 1.1, LimbLength = 0.95, ArmLength = 1, Belly = 1.35, Head = 1.05, Hunch = 0.06, Ribs = false },
	Bighead = { Width = 0.95, LimbLength = 0.86, ArmLength = 1, Belly = 0.85, Head = 1.4, Hunch = 0.1, Ribs = false },
	Gangly = { Width = 0.7, LimbLength = 1.15, ArmLength = 1.35, Belly = 0.6, Head = 0.85, Hunch = 0.2, Ribs = true },
	Agile = { Width = 0.75, LimbLength = 1.15, ArmLength = 1, Belly = 0.6, Head = 0.9, Hunch = 0.06, Ribs = false },
	Ape = { Width = 1.08, LimbLength = 0.92, ArmLength = 1.62, Belly = 0.95, Head = 0.9, Hunch = 0.34, Ribs = false },
	Crawler = { Width = 1, LimbLength = 0.9, ArmLength = 1, Belly = 0.95, Head = 1.3, Hunch = 0, Ribs = false },
}
local BODY_TYPE_NAMES = { "Lanky", "Stocky", "Chubby", "Bighead", "Gangly" }
local HAIR_STYLES = { "Bald", "Cap", "Mop", "Spiky", "Bowl", "Mohawk", "Bun", "Curly" }
-- Expressions: the classic wide grin, a dopey half-asleep stare, a gaping
-- mouth with a top and a bottom row of teeth, a lopsided smirk, a round
-- "oh" of surprise, and buck teeth. ("Stern" is the shifters' own.)
local FACES = { "Grin", "Grin", "Sleepy", "Gape", "Smirk", "Oh", "Bunny" }
local BROWS = { "Worried", "Worried", "Angry", "Raised", "Flat" }
local NOSES = { "Ball", "Ball", "Button", "Long", "Wide" }

-- Cylinders run along their local X; this turns one upright.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

export type Rig = {
	Model: Model,
	Root: BasePart,
	Torso: BasePart,
	Head: BasePart,
	Nape: BasePart,
	Feet: { BasePart },
	ArmorPlate: BasePart?, -- rock over the nape (armored giants)
	GuardHand: BasePart?, -- the crystal hand over the nape (hidden until "Guarding")
	TorsoHeight: number,
	TorsoDepth: number,
	TorsoWidth: number,
	ShinLength: number, -- how far the root drops when it kneels
	HeadSize: number,
}

local ROCK = Color3.fromRGB(128, 124, 116)
local CRACK = Color3.fromRGB(255, 140, 60)
local CRYSTAL = Color3.fromRGB(170, 225, 255)

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
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

-- A Motor6D pivoting at `joint` (a world CFrame). Both offsets come from
-- where the parts already are, so part shapes and turns don't matter and
-- the animator's angles mean the same thing on every joint (joint frames
-- are level with the body: X = swing forward/back). `rest` is baked into
-- C0: the pose the joint holds on the server and with no animation.
local function motor(name: string, part0: BasePart, part1: BasePart, joint: CFrame, rest: CFrame?)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(joint) * (rest or CFrame.new())
	m.C1 = part1.CFrame:ToObjectSpace(joint)
	m.Parent = part0
end

-- Where to build a part so that, once the motor at `joint` takes its
-- `rest`, it lands at `final`.
local function unbend(joint: CFrame, rest: CFrame, final: CFrame): CFrame
	return joint * rest:Inverse() * joint:Inverse() * final
end

-- A capsule limb segment hanging below `cframe`'s top end: an upright
-- cylinder with a ball of the same width on its joint end (skipped with
-- knob = false where a shoulder cap or the shorts hide it). Chained
-- segments read as round, fleshy limbs rather than a stack of bricks.
local function segment(model: Model, name: string, width: number, length: number, cframe: CFrame, color: Color3, material: Enum.Material?, knob: boolean?): Part
	local main = part(model, name, Vector3.new(length, width, width), cframe * UPRIGHT, color, Enum.PartType.Cylinder, material)
	if knob ~= false then
		weld(main, part(model, `{name}Joint`, Vector3.one * width, cframe * CFrame.new(0, length / 2, 0), color, Enum.PartType.Ball, material))
	end
	return main
end

-- A soft upright block: three upright cylinders side by side (no flat face
-- to catch the light like the side of a crate) and, with roundTop, a roll
-- along the top (its ends sit under the shoulder caps). Everything is
-- welded to the returned middle cylinder.
local function softBlock(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, roundTop: boolean): Part
	local width, height, depth = size.X, size.Y, size.Z
	local r = depth / 2
	local bodyHeight = if roundTop then height - r else height
	local bodyCentre = cframe * CFrame.new(0, if roundTop then -r / 2 else 0, 0)
	local core = part(model, name, Vector3.new(bodyHeight, depth, depth), bodyCentre * UPRIGHT, color, Enum.PartType.Cylinder, material)
	for i, side in { -1, 1 } do
		weld(core, part(model, `{name}Side{i}`, Vector3.new(bodyHeight, depth, depth), bodyCentre * CFrame.new(side * (width / 2 - r), 0, 0) * UPRIGHT, color, Enum.PartType.Cylinder, material))
	end
	if roundTop then
		weld(core, part(model, `{name}Top`, Vector3.new(width - depth, depth, depth), cframe * CFrame.new(0, height / 2 - r, 0), color, Enum.PartType.Cylinder, material))
	end
	return core
end

-- A point on a ball's surface, in the ball's frame: `turn` radians round to
-- the giant's right, `up` studs above the centre, `out` studs proud of it.
local function onBall(radius: number, turn: number, up: number, out: number): Vector3
	local ring = math.sqrt(math.max(radius * radius - up * up, 0)) + out
	return Vector3.new(ring * math.sin(turn), up, -ring * math.cos(turn))
end

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- The abnormal variants: which oddities this giant gets. A Look can force
-- each one on or off; otherwise Runner-style abnormals roll each one, and a
-- plain giant (no fixed Look) now and then gets a single one. Signature
-- giants, crawlers and the Sprinter (her guard hand) keep their look.
local function rollOddities(kind: Config.GiantKind, look: Config.GiantLook, rng: Random): { [string]: boolean }
	local odd: { [string]: boolean } = {}
	local names = Config.GiantOddities.Names
	local rolls = (kind.Abnormal == true and not look.Guard) or (kind.Look == nil)
	if rolls and kind.Abnormal then
		for _, name in names do
			odd[name] = rng:NextNumber() < Config.GiantOddities.AbnormalChance
		end
	elseif rolls and rng:NextNumber() < Config.GiantOddities.NormalChance then
		odd[pick(rng, names)] = true
	end
	local forced: { [string]: boolean? } = { Tilt = look.Tilt, LongNeck = look.LongNeck, Tongue = look.Tongue, OddArms = look.OddArms }
	for name, value in forced do
		if value ~= nil then
			odd[name] = value
		end
	end
	return odd
end

function GiantFactory.Build(kindName: string, position: Vector3, rng: Random): Rig
	local kind = Config.GiantKinds[kindName]
	assert(kind, `GiantFactory: unknown kind {kindName}`)
	local look: Config.GiantLook = kind.Look or {}
	local bodyName = look.Body or pick(rng, BODY_TYPE_NAMES)
	local body = BODY_TYPES[bodyName]
	local h = kind.Height
	local crawl = look.Pose == "Crawl"
	local ape = look.Pose == "Ape"
	local odd = rollOddities(kind, look, rng)

	local thigh, shin = h * 0.21 * body.LimbLength, h * 0.2 * body.LimbLength
	local legLength = thigh + shin
	local legWidth = h * 0.11 * body.Width
	local pelvisHeight = h * 0.08
	local torsoHeight, torsoWidth, torsoDepth = h * 0.26, h * 0.28 * body.Width, h * 0.15 * body.Width
	local upperArm, foreArm = h * 0.17 * body.LimbLength * body.ArmLength, h * 0.16 * body.LimbLength * body.ArmLength
	local armWidth = h * 0.085 * body.Width
	local neckLength = h * (if odd.LongNeck then 0.1 else 0.05)
	local headSize = h * 0.17 * body.Head

	-- On all fours: kneeling on its shins, the trunk tipped forward almost
	-- flat, its arms the front legs (cut to reach the ground exactly).
	local crawlPitch = 1.4
	local hipY = if crawl then thigh + legWidth * 0.425 + h * 0.01 else legLength
	local waistY = hipY + pelvisHeight
	if crawl then
		local shoulderY = waistY + (torsoHeight - armWidth * 0.5) * math.cos(crawlPitch)
		local reach = shoulderY - armWidth * 1.225 -- hand centre below the wrist + its radius
		upperArm, foreArm = reach * 0.515, reach * 0.485
	end

	local skin = look.Skin or pick(rng, SKIN)
	-- Stone giants are rock all over; furry ones are fur all over, with a
	-- bare, paler face and hands (that reads "ape" from far away).
	local faceMaterial = if look.Stone then Enum.Material.Basalt else nil
	local skinMaterial = if look.Fur then Enum.Material.Fabric else faceMaterial
	local bare = if look.Fur then skin:Lerp(Color3.fromRGB(205, 165, 132), 0.7) else skin
	local darker = skin:Lerp(Color3.new(0, 0, 0), 0.12)
	local shortsColor = look.Shorts or pick(rng, SHORTS)
	local hairColor = look.HairColor or pick(rng, HAIR)

	local model = Instance.new("Model")
	model.Name = `{kindName}Giant`
	local base = CFrame.new(position) -- built facing -Z, feet on `position`

	-- Root at hip height (top of the legs).
	local root = part(model, "Root", Vector3.new(torsoWidth, h * 0.04, torsoDepth), base * CFrame.new(0, hipY, 0), skin)
	root.Transparency = 1
	root.Massless = false
	root.CanQuery = false
	model.PrimaryPart = root

	-- Shorts: a rounded band from just below the hips to the waist.
	local pelvis = softBlock(model, "Pelvis", Vector3.new(torsoWidth * 1.03, pelvisHeight + h * 0.03, torsoDepth * 1.06), base * CFrame.new(0, waistY - (pelvisHeight + h * 0.03) / 2, 0), shortsColor, Enum.Material.Fabric, false)
	weld(root, pelvis)

	-- Trunk: a rounded box on a waist motor (the slouch, the sway of the
	-- walk and the lunge of a grab all happen here), a belly and shoulders.
	-- It reaches down inside the shorts so leaning never opens a gap.
	local torsoCentreY = waistY + torsoHeight / 2
	local tuck = h * 0.04
	local torso = softBlock(model, "Torso", Vector3.new(torsoWidth, torsoHeight + tuck, torsoDepth), base * CFrame.new(0, torsoCentreY - tuck / 2, 0), skin, skinMaterial, true)
	local slouch = if crawl then crawlPitch else body.Hunch
	motor("Waist", root, torso, base * CFrame.new(0, waistY, 0), CFrame.Angles(-slouch, 0, 0))
	if body.Belly >= 0.9 then
		-- On its own motor (no rest pose), so a heavy walk can bounce it.
		local bellyAt = base * CFrame.new(0, waistY + torsoHeight * 0.3, -torsoDepth * 0.28)
		local belly = part(model, "Belly", Vector3.one * torsoWidth * 0.62 * body.Belly, bellyAt, skin, Enum.PartType.Ball, skinMaterial)
		motor("Belly", torso, belly, bellyAt)
	end
	if body.Ribs then
		-- Skinny giants show their ribs: thin rolls across the chest.
		for r = 1, 3 do
			local y = torsoCentreY + torsoHeight * (0.02 + r * 0.1)
			local width = torsoWidth * (0.48 + r * 0.06)
			local rib = part(model, `Rib{r}`, Vector3.new(width, h * 0.016, h * 0.016), base * CFrame.new(0, y, -torsoDepth / 2 + h * 0.004), darker, Enum.PartType.Cylinder)
			rib.CastShadow = false
			weld(torso, rib)
		end
	end
	local shoulderCaps: { BasePart } = {}
	for i, side in { -1, 1 } do
		local cap = part(model, `ShoulderCap{i}`, Vector3.one * armWidth * 1.45, base * CFrame.new(side * (torsoWidth / 2 + armWidth * 0.2), torsoCentreY + torsoHeight / 2 - armWidth * 0.55, 0), skin, Enum.PartType.Ball, skinMaterial)
		weld(torso, cap)
		shoulderCaps[i] = cap
	end

	-- Neck and head. The head juts forward and its motor leans back against
	-- the slouch, so the face stays level and stares straight ahead.
	local neckBaseY = waistY + torsoHeight
	-- A tilted head hangs to one side from the top of the neck, for good
	-- (the whole face goes with it: everything below is built on headCentre).
	local headForward = headSize * 0.12
	local tilt = if odd.Tilt then (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(0.32, 0.45) else 0
	local neckTop = base * CFrame.new(0, neckBaseY + neckLength, -headForward)
	local headCentre = neckTop * CFrame.Angles(0, 0, tilt) * CFrame.new(0, headSize * 0.45, 0)
	local neckFrom = base * Vector3.new(0, neckBaseY - headSize * 0.1, 0)
	local neckTo = headCentre.Position
	local neckWidth = headSize * (if odd.LongNeck then 0.44 else 0.5)
	local neck = part(model, "Neck", Vector3.new((neckTo - neckFrom).Magnitude, neckWidth, neckWidth), CFrame.lookAt((neckFrom + neckTo) / 2, neckTo) * CFrame.Angles(0, math.rad(90), 0), skin, Enum.PartType.Cylinder, skinMaterial)
	weld(torso, neck)
	local head = part(model, "Head", Vector3.one * headSize, headCentre, skin, Enum.PartType.Ball, skinMaterial)
	-- (the joint itself stays level, so the stare and the slouch turn the
	-- head the same way, tilted or not)
	motor("Neck", torso, head, CFrame.new(headCentre.Position), CFrame.Angles(slouch, 0, 0))
	-- Small face details cast no shadow (there are a lot of them).
	local function face(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?, material: Enum.Material?): Part
		local p = part(model, name, size, headCentre * offset, color, shape, material)
		if math.max(size.X, size.Y, size.Z) < headSize * 0.45 then
			p.CastShadow = false
		end
		weld(head, p)
		return p
	end
	local skull = headSize / 2

	-- A jutting muzzle: the jaw and cheeks, carrying the mouth. Stone giants
	-- get a big square-ish jaw under it.
	local muzzleAt = Vector3.new(0, -headSize * 0.2, -headSize * 0.13)
	local muzzleRadius = headSize * 0.4
	face("Muzzle", Vector3.one * muzzleRadius * 2, CFrame.new(muzzleAt), bare, Enum.PartType.Ball, faceMaterial)
	if look.Stone then
		face("Jaw", Vector3.new(headSize * 0.74, headSize * 0.46, headSize * 0.46), CFrame.new(0, -headSize * 0.33, -headSize * 0.16), skin, Enum.PartType.Cylinder, skinMaterial)
	end

	local expression = if odd.Tongue then "Gape" else look.Face or pick(rng, FACES)

	-- Mouths drawn as a line of lips wrapped round the muzzle. `u` runs from
	-- -1 (the giant's right corner) to 1; `curve` lifts each point (in head
	-- sizes) so corners turn up (a grin), down (stern) or to one side (a
	-- smirk). Each lip segment can carry a bar of teeth.
	local function lipLine(centre: number, span: number, pieces: number, curve: (number) -> number, thickness: number, teeth: boolean)
		local function point(u: number): Vector3
			return muzzleAt + onBall(muzzleRadius, centre + u * span, -headSize * 0.02 + curve(u) * headSize, 0)
		end
		for g = 1, pieces do
			local a = point(-1 + (g - 1) * 2 / pieces)
			local b = point(-1 + g * 2 / pieces)
			local along = (b - a).Unit
			local middle = (a + b) / 2
			local outward = Vector3.new(middle.X - muzzleAt.X, 0, middle.Z - muzzleAt.Z).Unit
			local up = (-outward):Cross(along).Unit
			local frame = CFrame.fromMatrix(middle, along, up)
			local length = (b - a).Magnitude * 1.08
			face(`Lip{g}`, Vector3.new(length, headSize * thickness, headSize * 0.05), frame, LIPS)
			if teeth then
				face(`Teeth{g}`, Vector3.new(length * 0.86, headSize * 0.045, headSize * 0.03), frame * CFrame.new(0, headSize * 0.026, -headSize * 0.026), TEETH)
			end
		end
	end
	local function mouthHole(radius: number, drop: number): Vector3
		local at = muzzleAt + onBall(muzzleRadius, 0, -headSize * drop, -radius * 0.55)
		face("Mouth", Vector3.one * radius * 2, CFrame.new(at), LIPS:Lerp(Color3.new(0, 0, 0), 0.4), Enum.PartType.Ball)
		return at
	end
	if expression == "Gape" then
		-- A round, gaping mouth sunk into the muzzle, teeth along the top and
		-- the bottom of it.
		local mouthRadius = headSize * 0.17
		local mouthAt = mouthHole(mouthRadius, 0.04)
		for t, spot in { { -0.4, 0.7 }, { 0, 0.72 }, { 0.4, 0.7 }, { -0.25, -0.7 }, { 0.25, -0.7 } } do
			local turn = spot[1]
			local at = mouthAt + onBall(mouthRadius, turn, spot[2] * mouthRadius, -headSize * 0.01)
			face(`Tooth{t}`, Vector3.new(headSize * 0.06, headSize * 0.06, headSize * 0.04), CFrame.lookAt(at, at + Vector3.new(math.sin(turn), 0, -math.cos(turn))), TEETH)
		end
		if odd.Tongue then
			-- A big pink tongue lolling out over the lower lip and down the chin.
			local from = mouthAt + Vector3.new(0, -mouthRadius * 0.45, 0)
			local to = from + Vector3.new(0, -headSize * 0.2, -headSize * 0.2)
			face("Tongue", Vector3.new(headSize * 0.17, headSize * 0.06, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), TONGUE)
			face("TongueTip", Vector3.new(headSize * 0.06, headSize * 0.17, headSize * 0.17), CFrame.lookAt(to, to + (to - from)) * UPRIGHT, TONGUE, Enum.PartType.Cylinder)
		end
	elseif expression == "Oh" then
		-- A small round "oh" of surprise.
		mouthHole(headSize * 0.09, 0.06)
	elseif expression == "Smirk" then
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		lipLine(side * 0.12, 0.5, 2, function(u: number): number
			return 0.03 * u * u + side * 0.05 * u
		end, 0.08, rng:NextNumber() < 0.5)
	elseif expression == "Stern" then
		-- Closed and determined.
		lipLine(0, 0.42, 2, function(u: number): number
			return -0.025 * u * u
		end, 0.06, false)
	elseif expression == "Bunny" then
		-- A small smile and two big front teeth.
		lipLine(0, 0.45, 2, function(u: number): number
			return 0.04 * u * u
		end, 0.07, false)
		for t, side in { -1, 1 } do
			local at = muzzleAt + onBall(muzzleRadius, side * 0.075, -headSize * 0.085, -headSize * 0.01)
			face(`Tooth{t}`, Vector3.new(headSize * 0.11, headSize * 0.13, headSize * 0.04), CFrame.lookAt(at, at + Vector3.new(math.sin(side * 0.075), 0, -1)), TEETH)
		end
	else
		-- The grin: a wide, toothy smile, corners turned up. Goofy from afar,
		-- a little unsettling up close - on brand. Sleepy giants have a
		-- smaller, dopey one.
		lipLine(0, if expression == "Sleepy" then 0.55 else 0.85, 3, function(u: number): number
			return 0.08 * u * u
		end, 0.1, true)
	end

	-- Big round eyes in shadowed sockets, worried (or angry...) brows, a
	-- nose, ears. The pupils sit on motors so clients can make them follow
	-- the nearest hunter; the lids hide inside the sockets until a blink
	-- pushes them over the eyes.
	local brows = look.Brows or pick(rng, BROWS)
	local glow = look.EyeColor
	local sleepy = expression == "Sleepy"
	local lidShut = Vector3.zero
	for i, side in { -1, 1 } do
		local prefix = if side < 0 then "Left" else "Right"
		local eye = onBall(skull, side * 0.38, headSize * 0.1, -headSize * 0.08)
		local eyeSize = if look.Crazy then (if side < 0 then 0.32 else 0.22) else 0.26
		local gaze = if look.Crazy
			then Vector3.new(side * 0.04, side * 0.035, 0) * headSize
			elseif sleepy then Vector3.new(0, -0.03, 0) * headSize
			else Vector3.zero
		-- (set back far enough that the eye's white stays in front of it)
		local socketAt = eye + Vector3.new(0, headSize * 0.01, headSize * 0.06)
		face(`Socket{i}`, Vector3.one * headSize * (eyeSize + 0.07), CFrame.new(socketAt), skin:Lerp(Color3.new(0, 0, 0), 0.35), Enum.PartType.Ball, skinMaterial)
		face(`Eye{i}`, Vector3.one * headSize * eyeSize, CFrame.new(eye), glow or EYE_WHITE, Enum.PartType.Ball, if glow then Enum.Material.Neon else nil)
		-- Tiny pupils: a vacant stare (they glow at night - see SkyController,
		-- which looks them up by these names).
		local pupilAt = headCentre * CFrame.new(eye + gaze + Vector3.new(0, 0, -headSize * (eyeSize / 2 - 0.015)))
		local pupil = part(model, `Pupil{i}`, Vector3.one * headSize * (if look.Crazy then 0.07 else 0.075), pupilAt, PUPIL, Enum.PartType.Ball)
		pupil.CastShadow = false
		motor(`{prefix}Eye`, head, pupil, pupilAt)
		-- The lid: hidden in the socket (or drooping over the top half of a
		-- sleepy eye); a blink moves it by `lidShut` to cover the eye.
		local lidSize = headSize * (eyeSize + 0.06)
		local lidAt = if sleepy then eye + Vector3.new(0, lidSize * 0.62, -headSize * 0.005) else socketAt
		local lid = part(model, `Lid{i}`, Vector3.one * lidSize, headCentre * CFrame.new(lidAt), darker, Enum.PartType.Ball, skinMaterial)
		lid.CastShadow = false
		motor(`{prefix}Lid`, head, lid, headCentre * CFrame.new(lidAt))
		lidShut = eye - lidAt

		if brows == "Heavy" then
			if i == 1 then
				-- One heavy ridge right across the brow.
				face("Brow1", Vector3.new(headSize * 0.7, headSize * 0.16, headSize * 0.16), CFrame.new(onBall(skull, 0, headSize * 0.25, -headSize * 0.07)), darker, Enum.PartType.Cylinder, skinMaterial)
			end
		else
			local up, roll, thick = 0.27, -0.25, 0.055 -- worried: inner ends up
			if brows == "Angry" then
				up, roll, thick = 0.25, 0.35, 0.065
			elseif brows == "Raised" then
				up, roll, thick = 0.33, -0.08, 0.05
			elseif brows == "Flat" then
				up, roll, thick = 0.27, 0, 0.075
			end
			local brow = onBall(skull, side * 0.38, headSize * up, 0)
			face(`Brow{i}`, Vector3.new(headSize * 0.26, headSize * thick, headSize * 0.07), CFrame.new(brow) * CFrame.Angles(0, -side * 0.38, side * roll), hairColor)
		end
		if look.Ears ~= "None" then
			local big = if look.Ears == "Big" then 1.6 else 1
			face(`Ear{i}`, Vector3.new(headSize * 0.1, headSize * 0.24 * big, headSize * 0.24 * big), CFrame.new(side * (skull + headSize * 0.03 * (big - 1)), -headSize * 0.02, headSize * 0.02), bare:Lerp(Color3.new(0, 0, 0), 0.12), Enum.PartType.Cylinder, faceMaterial)
		end
		if look.Cheeks then
			-- Titan-shifter ridge lines running down from under the eyes.
			local from = onBall(skull, side * 0.42, -headSize * 0.04, 0)
			local to = onBall(skull, side * 0.62, -headSize * 0.24, 0)
			local line = face(`Cheek{i}`, Vector3.new(headSize * 0.035, headSize * 0.035, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), darker:Lerp(Color3.new(0, 0, 0), 0.2))
			line.CastShadow = false
		end
	end
	model:SetAttribute("LidShut", lidShut)
	local nose = look.Nose or pick(rng, NOSES)
	if nose == "Long" then
		-- A long nose poking out, drooping a little (a cylinder along the look).
		local at = onBall(skull, 0, -headSize * 0.06, headSize * 0.08)
		face("Nose", Vector3.new(headSize * 0.3, headSize * 0.13, headSize * 0.13), CFrame.lookAt(at, at + Vector3.new(0, -0.22, -1)) * CFrame.Angles(0, math.rad(90), 0), darker, Enum.PartType.Cylinder, skinMaterial)
	elseif nose == "Wide" then
		face("Nose", Vector3.new(headSize * 0.25, headSize * 0.14, headSize * 0.14), CFrame.new(onBall(skull, 0, -headSize * 0.06, -headSize * 0.01)), darker, Enum.PartType.Cylinder, skinMaterial)
	else
		local size = if nose == "Button" then 0.12 else rng:NextNumber(0.16, 0.26)
		face("Nose", Vector3.one * headSize * size, CFrame.new(onBall(skull, 0, -headSize * 0.04, 0)), darker, Enum.PartType.Ball, skinMaterial)
	end

	-- Hair. Every style keeps clear of the nape: a cap is a ball a little
	-- bigger than the head, set high and back so the face and the back of
	-- the neck both stay clear.
	local style = look.Hair or pick(rng, HAIR_STYLES)
	-- (a tilted head drops one side of the back of the skull: sit higher)
	local lift = math.abs(tilt) * 0.2
	local function cap(size: number)
		-- (a deep slouch tips the nape up behind the head: sit higher then)
		face("Hair", Vector3.one * headSize * size, CFrame.new(0, headSize * (0.2 + body.Hunch * 0.15 + lift), headSize * (0.12 - body.Hunch * 0.15)), hairColor, Enum.PartType.Ball)
	end
	if style == "Cap" then
		cap(1.1)
	elseif style == "Mop" then
		cap(1.1)
		for b, turn in { -0.5, -0.17, 0.17, 0.5 } do
			face(`Bang{b}`, Vector3.one * headSize * 0.28, CFrame.new(onBall(skull, turn, headSize * 0.31, -headSize * 0.04)), hairColor, Enum.PartType.Ball)
		end
	elseif style == "Spiky" then
		for s = 1, 5 do
			local angle = (s - 3) * 0.35
			face(`Spike{s}`, Vector3.new(headSize * 0.18, headSize * 0.4, headSize * 0.18), CFrame.new(math.sin(angle) * headSize * 0.35, headSize * 0.48, headSize * 0.05) * CFrame.Angles(0, 0, -angle), hairColor)
		end
	elseif style == "Bowl" then
		-- A pudding-bowl cut: a cap down to the brows and a straight rim.
		face("Hair", Vector3.one * headSize * 1.08, CFrame.new(0, headSize * (0.17 + lift), headSize * 0.03), hairColor, Enum.PartType.Ball)
		face("BowlRim", Vector3.new(headSize * 0.1, headSize * 1.1, headSize * 1.1), CFrame.new(0, headSize * (0.21 + lift), headSize * 0.02) * UPRIGHT, hairColor, Enum.PartType.Cylinder)
	elseif style == "Mohawk" then
		for s, a in { -0.55, -0.1, 0.35, 0.8 } do
			local at = Vector3.new(0, math.cos(a) * skull, math.sin(a) * skull)
			face(`Mohawk{s}`, Vector3.new(headSize * 0.1, headSize * 0.34, headSize * 0.24), CFrame.new(at) * CFrame.Angles(-a, 0, 0) * CFrame.new(0, headSize * 0.08, 0), hairColor)
		end
	elseif style == "Bun" then
		cap(1.06)
		face("Bun", Vector3.one * headSize * 0.4, CFrame.new(0, headSize * 0.7, headSize * 0.1), hairColor, Enum.PartType.Ball)
	elseif style == "Curly" then
		for c, spot in { { 0, 0.42 }, { -0.7, 0.3 }, { 0.7, 0.3 }, { -1.7, 0.26 }, { 1.7, 0.26 }, { math.pi, 0.3 }, { 0, 0.3 } } do
			local at = onBall(skull, spot[1], headSize * spot[2], -headSize * 0.02)
			face(`Curl{c}`, Vector3.one * headSize * (if c == 1 then 0.5 else 0.36), CFrame.new(if c == 1 then Vector3.new(0, headSize * 0.36, headSize * 0.06) else at), hairColor, Enum.PartType.Ball)
		end
	elseif style == "Ponytail" then
		-- Tied high at the back, sweeping back level with the top of the
		-- head: well above the nape.
		cap(1.06)
		face("Tie", Vector3.one * headSize * 0.24, CFrame.new(0, headSize * 0.37, headSize * 0.56), hairColor:Lerp(Color3.new(0, 0, 0), 0.3), Enum.PartType.Ball)
		local from, to = Vector3.new(0, headSize * 0.36, headSize * 0.5), Vector3.new(0, headSize * 0.16, headSize * 1.18)
		face("Ponytail", Vector3.new((to - from).Magnitude, headSize * 0.28, headSize * 0.28), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), hairColor, Enum.PartType.Cylinder)
		face("PonytailEnd", Vector3.one * headSize * 0.32, CFrame.new(to), hairColor, Enum.PartType.Ball)
	end

	-- Now and then a scruffy beard: a tuft under the chin and sideburns in
	-- front of the ears. It sits well forward, so it never hides the nape.
	local beard = if look.Beard ~= nil then look.Beard else rng:NextNumber() < 0.25
	if beard then
		face("Beard", Vector3.one * headSize * 0.56, CFrame.new(0, -headSize * 0.5, -headSize * 0.24), hairColor, Enum.PartType.Ball)
		for i, side in { -1, 1 } do
			local at = onBall(skull, side * 1.35, -headSize * 0.08, -headSize * 0.03)
			face(`Sideburn{i}`, Vector3.new(headSize * 0.13, headSize * 0.3, headSize * 0.08), CFrame.lookAt(at, at * 2), hairColor)
		end
	end

	-- The weak spot: a glowing lump set into the back of the neck (+Z
	-- side). Narrower than the neck, so it only shows from behind and the
	-- sides.
	local napeY = neckBaseY + neckLength * 0.55
	local napeAxis = neckFrom + (neckTo - neckFrom) * ((napeY - neckFrom.Y) / (neckTo.Y - neckFrom.Y))
	local nape = part(model, "Nape", Vector3.one * headSize * 0.46, CFrame.new(napeAxis + Vector3.new(0, 0, headSize * 0.15)), Color3.fromRGB(255, 120, 60), Enum.PartType.Ball, Enum.Material.Neon)
	nape.Transparency = 0.1
	weld(torso, nape)
	local napeLight = Instance.new("PointLight")
	napeLight.Color = nape.Color
	napeLight.Range = h * 0.4
	napeLight.Brightness = 1.5
	napeLight.Parent = nape

	-- Legs: thigh on a hip motor, shin on a knee motor, then a foot. The
	-- shorts' legs ride on the thighs. A crawler kneels on its shins, feet
	-- flat behind it.
	local feet: { BasePart } = {}
	local shins: { BasePart } = {}
	local forearms: { BasePart } = {}
	local kneeRest = if crawl then CFrame.Angles(-math.pi / 2, 0, 0) else CFrame.new()
	local floor = hipY - legLength -- below the ground for a crawler's (straight, as built) legs
	for _, side in { -1, 1 } do
		local prefix = if side < 0 then "Left" else "Right"
		local x = side * torsoWidth * 0.26
		local thighPart = segment(model, `{prefix}Thigh`, legWidth, thigh, base * CFrame.new(x, hipY - thigh / 2, 0), skin, skinMaterial, false)
		motor(`{prefix}Hip`, root, thighPart, base * CFrame.new(x, hipY, 0))
		weld(thighPart, part(model, `{prefix}ShortsLeg`, Vector3.new(thigh * 0.42, legWidth * 1.22, legWidth * 1.22), base * CFrame.new(x, hipY - thigh * 0.19, 0) * UPRIGHT, shortsColor, Enum.PartType.Cylinder, Enum.Material.Fabric))
		local shinPart = segment(model, `{prefix}Shin`, legWidth * 0.85, shin, base * CFrame.new(x, floor + shin / 2, 0), skin, skinMaterial)
		local knee = base * CFrame.new(x, floor + shin, 0)
		motor(`{prefix}Knee`, thighPart, shinPart, knee, kneeRest)
		local footSize = Vector3.new(legWidth * 0.95, h * 0.045, legWidth * 1.4)
		local footAt = if crawl
			then unbend(knee, kneeRest, knee * CFrame.new(0, -legWidth * 0.425 + h * 0.0225 - h * 0.01, shin + legWidth * 0.3))
			else base * CFrame.new(x, h * 0.0225, -legWidth * 0.25)
		local foot = part(model, `{prefix}Foot`, footSize, footAt, darker, nil, skinMaterial)
		weld(shinPart, foot)
		table.insert(feet, foot)
		table.insert(shins, shinPart)
		if not crawl then
			weld(shinPart, part(model, `{prefix}Toes`, Vector3.one * legWidth * 0.95, base * CFrame.new(x, legWidth * 0.3, -legWidth * 0.8), darker, Enum.PartType.Ball, skinMaterial))
		end
	end

	-- Arms: upper arm on a shoulder motor, forearm on an elbow, then a big
	-- hand (all the better to grab with). A crawler's shoulders turn its
	-- arms straight down to the ground; an ape-like giant's hang forward,
	-- knuckles near the ground.
	local shoulderRest = if crawl then CFrame.Angles(crawlPitch, 0, 0) elseif ape then CFrame.Angles(0.12, 0, 0) else CFrame.new()
	local hands: { BasePart } = {}
	-- Odd arms: one hangs long (past the knee), the other is short and stubby.
	local longSide = if rng:NextNumber() < 0.5 then -1 else 1
	for _, side in { -1, 1 } do
		local prefix = if side < 0 then "Left" else "Right"
		local stretch = if not odd.OddArms then 1 elseif side == longSide then 1.3 else 0.75
		local upperLength, foreLength = upperArm * stretch, foreArm * stretch
		local shoulder = base * CFrame.new(side * (torsoWidth / 2 + armWidth * 0.45), torsoCentreY + torsoHeight / 2 - armWidth * 0.5, 0)
		local upper = segment(model, `{prefix}UpperArm`, armWidth, upperLength, shoulder * CFrame.new(0, -upperLength / 2, 0), skin, skinMaterial, false)
		motor(`{prefix}Shoulder`, torso, upper, shoulder, shoulderRest)
		local fore = segment(model, `{prefix}ForeArm`, armWidth * 0.9, foreLength, shoulder * CFrame.new(0, -upperLength - foreLength / 2, 0), skin, skinMaterial)
		motor(`{prefix}Elbow`, upper, fore, shoulder * CFrame.new(0, -upperLength, 0))
		local hand = part(model, `{prefix}Hand`, Vector3.one * armWidth * 1.35, shoulder * CFrame.new(0, -upperLength - foreLength - armWidth * 0.55, 0), bare, Enum.PartType.Ball, faceMaterial)
		weld(fore, hand)
		table.insert(forearms, fore)
		table.insert(hands, hand)
	end

	-- Fur (the Beast): shaggy tufts on the shoulders, back, chest and
	-- forearms. Below the nape, never over it.
	if look.Fur then
		local function tuft(name: string, size: number, at: CFrame, to: BasePart)
			local p = part(model, name, Vector3.one * size, at, hairColor, Enum.PartType.Ball, Enum.Material.Fabric)
			p.CastShadow = false
			weld(to, p)
		end
		for i, side in { -1, 1 } do
			local capAt = shoulderCaps[i].CFrame
			tuft(`FurShoulder{i}1`, armWidth * 1.2, capAt * CFrame.new(side * armWidth * 0.25, armWidth * 0.35, armWidth * 0.2), torso)
			tuft(`FurShoulder{i}2`, armWidth * 1.05, capAt * CFrame.new(side * -armWidth * 0.35, armWidth * 0.3, armWidth * 0.45), torso)
			tuft(`FurChest{i}`, torsoWidth * 0.32, base * CFrame.new(side * torsoWidth * 0.18, torsoCentreY + torsoHeight * 0.18, -torsoDepth * 0.36), torso)
			local fore = forearms[i]
			tuft(`FurArm{i}1`, armWidth * 1.15, fore.CFrame * CFrame.new(foreArm * 0.3, 0, 0) * CFrame.new(0, 0, armWidth * 0.1), fore)
			tuft(`FurArm{i}2`, armWidth * 1.05, fore.CFrame * CFrame.new(-foreArm * 0.05, 0, 0) * CFrame.new(0, 0, armWidth * 0.15), fore)
		end
		for b, spot in { { 0, 0.1 }, { -0.22, -0.15 }, { 0.22, -0.15 } } do
			tuft(`FurBack{b}`, torsoWidth * 0.36, base * CFrame.new(spot[1] * torsoWidth, torsoCentreY + spot[2] * torsoHeight, torsoDepth * 0.36), torso)
		end
	end

	-- Stone skin (the Wallbreaker): glowing seams cracking across the head
	-- and the shoulders.
	if look.Stone then
		-- A crack: a zig-zag of short glowing chords across a ball's surface
		-- (`centre` and `radius`), through points given as {turn, up} (up in
		-- radii), so it hugs the curve.
		local seams = 0
		local function crack(centre: CFrame, radius: number, points: { { number } }, to: BasePart)
			for k = 1, #points - 1 do
				local a = onBall(radius, points[k][1], radius * points[k][2], 0)
				local b = onBall(radius, points[k + 1][1], radius * points[k + 1][2], 0)
				seams += 1
				local p = part(model, `Seam{seams}`, Vector3.new(headSize * 0.03, headSize * 0.03, (b - a).Magnitude + headSize * 0.02), centre * CFrame.lookAt((a + b) / 2, b), CRACK, nil, Enum.Material.Neon)
				p.CastShadow = false
				weld(to, p)
			end
		end
		crack(headCentre, skull * 1.01, { { -0.1, 0.98 }, { -0.4, 0.8 }, { -0.35, 0.6 }, { -0.7, 0.45 }, { -0.85, 0.2 } }, head)
		crack(headCentre, skull * 1.01, { { 0.3, 0.92 }, { 0.6, 0.75 }, { 0.9, 0.55 }, { 1.1, 0.3 } }, head)
		crack(headCentre, skull * 1.01, { { 2.5, 0.75 }, { 2.85, 0.5 }, { 3.2, 0.6 } }, head) -- well above the nape
		for i, side in { -1, 1 } do
			local radius = armWidth * 0.735
			crack(shoulderCaps[i].CFrame, radius, { { side * 0.8, 0.15 }, { side * 1.3, 0.5 }, { side * 2, 0.75 }, { side * 2.6, 0.5 } }, torso)
		end
	end

	-- Armour: rock plates on the chest (three pieces over a darker backing,
	-- so the seams show), shoulders, shins and forearms, a rocky helmet set
	-- back off the eyes, and a plate over the nape that has to be cracked
	-- first. Its cracks (NapeCrack1-3, hidden) light up on clients as it
	-- takes hits (attribute "Armor", see GiantAnimator).
	local armorPlate: BasePart? = nil
	if look.Armor then
		local function plate(name: string, size: Vector3, cframe: CFrame, to: BasePart, shape: Enum.PartType?, shade: number?)
			local color = ROCK:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.08))
			local p = part(model, name, size, cframe, if shade then color:Lerp(Color3.new(0, 0, 0), shade) else color, shape, Enum.Material.Slate)
			weld(to, p)
			return p
		end
		local chest = base * CFrame.new(0, torsoCentreY, -torsoDepth * 0.4)
		plate("ChestBacking", Vector3.new(torsoWidth * 0.8, torsoHeight * 0.72, torsoDepth * 0.3), chest * CFrame.new(0, torsoHeight * 0.08, torsoDepth * 0.02), torso, nil, 0.45)
		for i, side in { -1, 1 } do
			plate(`ChestPlate{i}`, Vector3.new(torsoWidth * 0.4, torsoHeight * 0.36, torsoDepth * 0.3), chest * CFrame.new(side * torsoWidth * 0.205, torsoHeight * 0.24, -torsoDepth * 0.05) * CFrame.Angles(0.08, side * 0.2, side * -0.06), torso)
		end
		plate("BellyPlate", Vector3.new(torsoWidth * 0.56, torsoHeight * 0.26, torsoDepth * 0.3), chest * CFrame.new(0, -torsoHeight * 0.12, -torsoDepth * 0.04) * CFrame.Angles(-0.12, 0, 0), torso)
		for i, side in { -1, 1 } do
			plate(`ShoulderPlate{i}`, Vector3.one * armWidth * 1.75, base * CFrame.new(side * (torsoWidth / 2 + armWidth * 0.2), torsoCentreY + torsoHeight / 2 - armWidth * 0.4, 0), torso, Enum.PartType.Ball)
		end
		for i, shinPart in shins do
			plate(`ShinPlate{i}`, Vector3.new(shin * 0.7, legWidth * 1.02, legWidth * 1.02), shinPart.CFrame * CFrame.new(-shin * 0.05, 0, 0), shinPart, Enum.PartType.Cylinder)
		end
		for i, fore in forearms do
			plate(`ArmPlate{i}`, Vector3.new(foreArm * 0.7, armWidth * 1, armWidth * 1), fore.CFrame, fore, Enum.PartType.Cylinder)
		end
		plate("Helmet", Vector3.one * headSize * 1.1, headCentre * CFrame.new(0, headSize * 0.21, headSize * 0.13), head, Enum.PartType.Ball)
		plate("HelmetCrest", Vector3.new(headSize * 0.62, headSize * 0.16, headSize * 0.16), headCentre * CFrame.new(0, headSize * 0.66, headSize * 0.1) * CFrame.Angles(0, math.rad(90), 0), head, Enum.PartType.Cylinder, 0.2)
		local napePlate = plate("NapeArmor", Vector3.one * headSize * 0.58, nape.CFrame * CFrame.new(0, 0, headSize * 0.04), torso, Enum.PartType.Ball)
		armorPlate = napePlate
		local plateRadius = headSize * 0.29
		for c, spot in { { 0.2, 0.15, 0.9 }, { -0.35, -0.1, 0.8 }, { 0.5, -0.35, 0.7 } } do
			-- Cracks radiating out from the middle of the plate's back.
			local direction = Vector3.new(spot[1], spot[2], 0).Unit
			local mid = Vector3.new(0, 0, 1) * plateRadius + direction * plateRadius * 0.28
			local crack = part(model, `NapeCrack{c}`, Vector3.new(headSize * 0.035, headSize * 0.035, plateRadius * spot[3]), napePlate.CFrame * CFrame.lookAt(mid, mid + direction), CRACK, nil, Enum.Material.Neon)
			crack.Transparency = 1
			crack.CastShadow = false
			crack.CanQuery = false
			weld(napePlate, crack) -- rides away with the plate when it breaks
		end
	end

	-- The Sprinter's crystal hand: hidden over the nape, shown by clients
	-- while the model's "Guarding" attribute is true (the server decides
	-- when, and refuses nape cuts meanwhile).
	local guardHand: BasePart? = nil
	if look.Guard then
		local guard = part(model, "GuardHand", Vector3.one * headSize * 0.62, nape.CFrame * CFrame.new(0, headSize * 0.06, headSize * 0.16), CRYSTAL, Enum.PartType.Ball, Enum.Material.Glass)
		guard.Transparency = 1
		guard.CanQuery = false
		guard.CastShadow = false
		weld(torso, guard)
		guardHand = guard
	end

	-- Steam rising off the head: signature giants and every giant 46+ tall
	-- (faintly). Default particle texture, no assets.
	if look.Steam or h >= 46 then
		local strong = look.Steam == true
		local steam = Instance.new("ParticleEmitter")
		steam.Name = "Steam"
		steam.Color = ColorSequence.new(Color3.fromRGB(240, 240, 245))
		steam.LightEmission = 0.2
		steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, headSize * 0.25), NumberSequenceKeypoint.new(1, headSize * 0.9) })
		steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, if strong then 0.55 else 0.75), NumberSequenceKeypoint.new(1, 1) })
		steam.Lifetime = NumberRange.new(1.5, 2.6)
		steam.Speed = NumberRange.new(headSize * 0.3, headSize * 0.6)
		steam.SpreadAngle = Vector2.new(30, 30)
		steam.Rate = if strong then 7 else 2.5
		steam.Parent = head
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
	model:SetAttribute("Body", bodyName)
	local oddities: { string } = {}
	for _, name in Config.GiantOddities.Names do
		if odd[name] then
			table.insert(oddities, name)
		end
	end
	if #oddities > 0 then
		model:SetAttribute("Oddities", table.concat(oddities, " "))
	end
	model:SetAttribute("Height", h)
	model:SetAttribute("HeadSize", headSize)
	if look.Pose then
		model:SetAttribute("Pose", look.Pose)
	end
	model:SetAttribute("NapeHealth", kind.NapeHealth)
	model:SetAttribute("MaxNapeHealth", kind.NapeHealth)
	CollectionService:AddTag(model, Config.Tags.Giant)

	return {
		Model = model,
		Root = root,
		Torso = torso,
		Head = head,
		Nape = nape,
		Feet = feet,
		ArmorPlate = armorPlate,
		GuardHand = guardHand,
		TorsoHeight = pelvisHeight + torsoHeight,
		TorsoDepth = torsoDepth,
		TorsoWidth = torsoWidth,
		ShinLength = if crawl then legWidth * 0.3 else shin,
		HeadSize = headSize,
	}
end

return GiantFactory
