--!strict
-- Builds a giant: a big, goofy-creepy humanoid with a glowing weak spot on
-- the back of its neck (the Nape). Child-friendly by design: cartoon faces,
-- shorts, no gore - defeated giants just puff away into steam.
--
-- Look: soft, rounded shapes only (capsule limbs, a rounded trunk, ball
-- joints), a hunched posture with the head pushed forward, a jutting
-- muzzle with a wide toothy grin, big round eyes. Every giant rolls a body
-- type (lanky, stocky, chubby, or a short-legged "bighead"), skin, hair
-- style and shorts, so a wave never looks like a copy-paste crowd.
--
-- Rig: an invisible Root at hip height carries everything. Waist, hips,
-- knees, shoulders, elbows and the neck are Motor6Ds, so clients animate
-- the lumbering walk, the grab and the head tracking (GiantAnimator)
-- without the server sending any animation. Every part is non-colliding
-- (giants stride through town) but queryable, so hunters can hook onto a
-- giant's body.

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
}
local LIPS = Color3.fromRGB(70, 25, 30)
local TEETH = Color3.fromRGB(250, 248, 236)

-- Body types: multipliers on the base proportions, plus how far forward
-- the giant slouches (radians). Bighead is the classic odd one out: short
-- legs, a huge head and a grin you can see from the top of the wall.
-- Gangly is the creepy one: thin as a rake, a small head, a deep stoop and
-- arms that hang down past its knees.
local BODY_TYPES = {
	Lanky = { Width = 0.8, LimbLength = 1.08, ArmLength = 1, Belly = 0.7, Head = 1, Hunch = 0.14, Ribs = true },
	Stocky = { Width = 1.2, LimbLength = 0.92, ArmLength = 1, Belly = 0.9, Head = 0.95, Hunch = 0.08, Ribs = false },
	Chubby = { Width = 1.1, LimbLength = 0.95, ArmLength = 1, Belly = 1.35, Head = 1.05, Hunch = 0.06, Ribs = false },
	Bighead = { Width = 0.95, LimbLength = 0.86, ArmLength = 1, Belly = 0.85, Head = 1.4, Hunch = 0.1, Ribs = false },
	Gangly = { Width = 0.7, LimbLength = 1.15, ArmLength = 1.35, Belly = 0.6, Head = 0.85, Hunch = 0.2, Ribs = true },
}
local BODY_TYPE_NAMES = { "Lanky", "Stocky", "Chubby", "Bighead", "Gangly" }
local HAIR_STYLES = { "Bald", "Cap", "Mop", "Spiky" }
-- Expressions: the classic wide grin, a dopey half-asleep stare, or a
-- gaping mouth with a top and a bottom row of teeth.
local FACES = { "Grin", "Grin", "Sleepy", "Gape" }

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
	TorsoHeight: number,
	TorsoDepth: number,
	TorsoWidth: number,
	ShinLength: number,
	HeadSize: number,
}

local ROCK = Color3.fromRGB(128, 124, 116)

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

-- A capsule limb segment hanging below `cframe`'s top end: an upright
-- cylinder with a ball of the same width on its joint end. Chained
-- segments read as round, fleshy limbs rather than a stack of bricks.
local function segment(model: Model, name: string, width: number, length: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local main = part(model, name, Vector3.new(length, width, width), cframe * UPRIGHT, color, Enum.PartType.Cylinder, material)
	local knob = part(model, `{name}Joint`, Vector3.one * width, cframe * CFrame.new(0, length / 2, 0), color, Enum.PartType.Ball, material)
	weld(main, knob)
	return main
end

-- A soft upright block: three upright cylinders side by side (no flat face
-- to catch the light like the side of a crate) and, with roundTop, a roll
-- along the top with a ball on each top corner. Everything is welded to
-- the returned middle cylinder.
local function softBlock(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, roundTop: boolean): Part
	local width, height, depth = size.X, size.Y, size.Z
	local r = depth / 2
	local bodyHeight = if roundTop then height - r else height
	local bodyCentre = cframe * CFrame.new(0, if roundTop then -r / 2 else 0, 0)
	local core = part(model, name, Vector3.new(bodyHeight, depth, depth), bodyCentre * UPRIGHT, color, Enum.PartType.Cylinder, material)
	for i, side in { -1, 1 } do
		local x = side * (width / 2 - r)
		weld(core, part(model, `{name}Side{i}`, Vector3.new(bodyHeight, depth, depth), bodyCentre * CFrame.new(x, 0, 0) * UPRIGHT, color, Enum.PartType.Cylinder, material))
		if roundTop then
			weld(core, part(model, `{name}Corner{i}`, Vector3.one * depth, cframe * CFrame.new(x, height / 2 - r, 0), color, Enum.PartType.Ball, material))
		end
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

function GiantFactory.Build(kindName: string, position: Vector3, rng: Random): Rig
	local kind = Config.GiantKinds[kindName]
	assert(kind, `GiantFactory: unknown kind {kindName}`)
	local look: Config.GiantLook = kind.Look or {}
	local bodyName = look.Body or BODY_TYPE_NAMES[rng:NextInteger(1, #BODY_TYPE_NAMES)]
	local body = BODY_TYPES[bodyName]
	local h = kind.Height

	local thigh, shin = h * 0.21 * body.LimbLength, h * 0.2 * body.LimbLength
	local legLength = thigh + shin
	local legWidth = h * 0.11 * body.Width
	local pelvisHeight = h * 0.08
	local torsoHeight, torsoWidth, torsoDepth = h * 0.26, h * 0.28 * body.Width, h * 0.15 * body.Width
	local upperArm, foreArm = h * 0.17 * body.LimbLength * body.ArmLength, h * 0.16 * body.LimbLength * body.ArmLength
	local armWidth = h * 0.085 * body.Width
	local neckLength = h * 0.05
	local headSize = h * 0.17 * body.Head

	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local darker = skin:Lerp(Color3.new(0, 0, 0), 0.12)
	local shortsColor = look.Shorts or SHORTS[rng:NextInteger(1, #SHORTS)]
	local hairColor = HAIR[rng:NextInteger(1, #HAIR)]

	local model = Instance.new("Model")
	model.Name = `{kindName}Giant`
	local base = CFrame.new(position) -- built facing -Z, feet on `position`

	-- Root at hip height (top of the legs).
	local hipY = legLength
	local root = part(model, "Root", Vector3.new(torsoWidth, h * 0.04, torsoDepth), base * CFrame.new(0, hipY, 0), skin)
	root.Transparency = 1
	root.Massless = false
	root.CanQuery = false
	model.PrimaryPart = root

	-- Shorts: a rounded band from just below the hips to the waist.
	local waistY = hipY + pelvisHeight
	local pelvis = softBlock(model, "Pelvis", Vector3.new(torsoWidth * 1.03, pelvisHeight + h * 0.03, torsoDepth * 1.06), base * CFrame.new(0, waistY - (pelvisHeight + h * 0.03) / 2, 0), shortsColor, Enum.Material.Fabric, false)
	weld(root, pelvis)

	-- Trunk: a rounded box on a waist motor (the slouch, the sway of the
	-- walk and the lunge of a grab all happen here), a belly and shoulders.
	-- It reaches down inside the shorts so leaning never opens a gap.
	local torsoCentreY = waistY + torsoHeight / 2
	local tuck = h * 0.04
	local torso = softBlock(model, "Torso", Vector3.new(torsoWidth, torsoHeight + tuck, torsoDepth), base * CFrame.new(0, torsoCentreY - tuck / 2, 0), skin, nil, true)
	motor("Waist", root, torso, base * CFrame.new(0, waistY, 0), CFrame.Angles(-body.Hunch, 0, 0))
	weld(torso, part(model, "Belly", Vector3.one * torsoWidth * 0.62 * body.Belly, base * CFrame.new(0, waistY + torsoHeight * 0.3, -torsoDepth * 0.28), skin, Enum.PartType.Ball))
	if body.Ribs then
		-- Skinny giants show their ribs: thin rolls across the chest.
		for r = 1, 3 do
			local y = torsoCentreY + torsoHeight * (0.02 + r * 0.1)
			local width = torsoWidth * (0.48 + r * 0.06)
			weld(torso, part(model, `Rib{r}`, Vector3.new(width, h * 0.016, h * 0.016), base * CFrame.new(0, y, -torsoDepth / 2 + h * 0.004), darker, Enum.PartType.Cylinder))
		end
	end
	for i, side in { -1, 1 } do
		weld(torso, part(model, `ShoulderCap{i}`, Vector3.one * armWidth * 1.45, base * CFrame.new(side * (torsoWidth / 2 + armWidth * 0.2), torsoCentreY + torsoHeight / 2 - armWidth * 0.55, 0), skin, Enum.PartType.Ball))
	end

	-- Neck and head. The head juts forward and its motor leans back against
	-- the slouch, so the face stays level and stares straight ahead.
	local neckBaseY = waistY + torsoHeight
	local headForward = headSize * 0.12
	local headCentre = base * CFrame.new(0, neckBaseY + neckLength + headSize * 0.45, -headForward)
	local neckFrom = base * Vector3.new(0, neckBaseY - headSize * 0.1, 0)
	local neckTo = headCentre.Position
	local neck = part(model, "Neck", Vector3.new((neckTo - neckFrom).Magnitude, headSize * 0.5, headSize * 0.5), CFrame.lookAt((neckFrom + neckTo) / 2, neckTo) * CFrame.Angles(0, math.rad(90), 0), skin, Enum.PartType.Cylinder)
	weld(torso, neck)
	local head = part(model, "Head", Vector3.one * headSize, headCentre, skin, Enum.PartType.Ball)
	motor("Neck", torso, head, headCentre, CFrame.Angles(body.Hunch, 0, 0))
	local function face(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?)
		weld(head, part(model, name, size, headCentre * offset, color, shape))
	end
	local skull = headSize / 2

	-- A jutting muzzle: the jaw and cheeks, carrying the grin.
	local muzzleAt = Vector3.new(0, -headSize * 0.2, -headSize * 0.13)
	local muzzleRadius = headSize * 0.4
	face("Muzzle", Vector3.one * muzzleRadius * 2, CFrame.new(muzzleAt), skin, Enum.PartType.Ball)

	local expression = look.Face or FACES[rng:NextInteger(1, #FACES)]

	-- The grin: a wide, toothy smile wrapped round the muzzle, corners
	-- turned up. Goofy from afar, a little unsettling up close - on brand.
	-- Sleepy giants have a smaller, dopey one.
	local GRIN_SPAN, GRIN_PIECES = if expression == "Sleepy" then 0.55 else 0.85, 5
	local function grinPoint(turn: number): Vector3
		local lift = headSize * 0.08 * (turn / GRIN_SPAN) ^ 2
		return muzzleAt + onBall(muzzleRadius, turn, -headSize * 0.02 + lift, 0)
	end
	if expression == "Gape" then
		-- A round, gaping mouth sunk into the muzzle, a row of teeth along the
		-- top and the bottom of it.
		local mouthRadius = headSize * 0.17
		local mouthAt = muzzleAt + onBall(muzzleRadius, 0, -headSize * 0.04, -mouthRadius * 0.55)
		face("Mouth", Vector3.one * mouthRadius * 2, CFrame.new(mouthAt), LIPS:Lerp(Color3.new(0, 0, 0), 0.4), Enum.PartType.Ball)
		for row, up in { 0.7, -0.7 } do
			for t, turn in { -0.42, -0.14, 0.14, 0.42 } do
				local at = mouthAt + onBall(mouthRadius, turn, up * mouthRadius, -headSize * 0.01)
				face(`Tooth{row}{t}`, Vector3.new(headSize * 0.055, headSize * 0.06, headSize * 0.04), CFrame.lookAt(at, at + Vector3.new(math.sin(turn), 0, -math.cos(turn))), TEETH)
			end
		end
	end
	for g = 1, if expression == "Gape" then 0 else GRIN_PIECES do
		local a = grinPoint(-GRIN_SPAN + (g - 1) * 2 * GRIN_SPAN / GRIN_PIECES)
		local b = grinPoint(-GRIN_SPAN + g * 2 * GRIN_SPAN / GRIN_PIECES)
		local along = (b - a).Unit
		local middle = (a + b) / 2
		local outward = Vector3.new(middle.X - muzzleAt.X, 0, middle.Z - muzzleAt.Z).Unit
		local up = (-outward):Cross(along).Unit
		local frame = CFrame.fromMatrix(middle, along, up)
		local length = (b - a).Magnitude * 1.06
		face(`Grin{g}`, Vector3.new(length, headSize * 0.1, headSize * 0.05), frame, LIPS)
		for t, x in { -0.24, 0.24 } do
			face(`Tooth{g}{t}`, Vector3.new(length * 0.4, headSize * 0.045, headSize * 0.03), frame * CFrame.new(x * length, headSize * 0.028, -headSize * 0.025), TEETH)
		end
	end

	-- Big round eyes looking straight ahead, worried brows, a round nose,
	-- round ears.
	for i, side in { -1, 1 } do
		local eye = onBall(skull, side * 0.38, headSize * 0.1, -headSize * 0.08)
		local eyeSize = if look.Crazy then (if side < 0 then 0.32 else 0.22) else 0.26
		local gaze = if look.Crazy
			then Vector3.new(side * 0.04, side * 0.035, 0) * headSize
			elseif expression == "Sleepy" then Vector3.new(0, -0.03, 0) * headSize
			else Vector3.zero
		-- A shadowed socket behind each eye: a hollow, staring look.
		face(`Socket{i}`, Vector3.one * headSize * (eyeSize + 0.07), CFrame.new(eye + Vector3.new(0, headSize * 0.01, headSize * 0.03)), skin:Lerp(Color3.new(0, 0, 0), 0.35), Enum.PartType.Ball)
		face(`Eye{i}`, Vector3.one * headSize * eyeSize, CFrame.new(eye), Color3.fromRGB(246, 242, 232), Enum.PartType.Ball)
		-- Tiny pupils: a vacant stare (they glow at night - see SkyController).
		face(`Pupil{i}`, Vector3.one * headSize * (if look.Crazy then 0.07 else 0.075), CFrame.new(eye + gaze + Vector3.new(0, 0, -headSize * (eyeSize / 2 - 0.015))), Color3.fromRGB(30, 25, 25), Enum.PartType.Ball)
		if expression == "Sleepy" then
			-- Heavy eyelids drooping over the top half of each eye.
			face(`Lid{i}`, Vector3.one * headSize * eyeSize * 1.1, CFrame.new(eye + Vector3.new(0, headSize * eyeSize * 0.32, -headSize * 0.005)), darker, Enum.PartType.Ball)
		end
		local brow = onBall(skull, side * 0.38, headSize * 0.27, 0)
		face(`Brow{i}`, Vector3.new(headSize * 0.26, headSize * 0.055, headSize * 0.07), CFrame.new(brow) * CFrame.Angles(0, -side * 0.38, side * -0.25), hairColor)
		face(`Ear{i}`, Vector3.new(headSize * 0.1, headSize * 0.24, headSize * 0.24), CFrame.new(side * skull, -headSize * 0.02, headSize * 0.02), darker, Enum.PartType.Cylinder)
	end
	face("Nose", Vector3.one * headSize * rng:NextNumber(0.16, 0.26), CFrame.new(onBall(skull, 0, -headSize * 0.04, 0)), darker, Enum.PartType.Ball)

	-- Hair.
	local style = look.Hair or HAIR_STYLES[rng:NextInteger(1, #HAIR_STYLES)]
	if style == "Cap" then
		-- Balls are always uniform: a slightly bigger sphere pushed up and back
		-- covers the crown and the back of the head, leaving the face clear.
		face("Hair", Vector3.one * headSize * 1.04, CFrame.new(0, headSize * 0.12, headSize * 0.1), hairColor, Enum.PartType.Ball)
	elseif style == "Mop" then
		face("Hair", Vector3.one * headSize * 1.1, CFrame.new(0, headSize * 0.14, headSize * 0.1), hairColor, Enum.PartType.Ball)
		for b, turn in { -0.5, -0.17, 0.17, 0.5 } do
			face(`Bang{b}`, Vector3.one * headSize * 0.28, CFrame.new(onBall(skull, turn, headSize * 0.31, -headSize * 0.04)), hairColor, Enum.PartType.Ball)
		end
	elseif style == "Spiky" then
		for s = 1, 5 do
			local angle = (s - 3) * 0.35
			face(`Spike{s}`, Vector3.new(headSize * 0.18, headSize * 0.4, headSize * 0.18), CFrame.new(math.sin(angle) * headSize * 0.35, headSize * 0.48, headSize * 0.05) * CFrame.Angles(0, 0, -angle), hairColor)
		end
	end

	-- Now and then a scruffy beard: a tuft under the chin and sideburns. It
	-- sits well forward, so it never hides the nape.
	local beard = if look.Beard ~= nil then look.Beard else rng:NextNumber() < 0.25
	if beard then
		face("Beard", Vector3.one * headSize * 0.56, CFrame.new(0, -headSize * 0.5, -headSize * 0.24), hairColor, Enum.PartType.Ball)
		for i, side in { -1, 1 } do
			face(`Sideburn{i}`, Vector3.one * headSize * 0.22, CFrame.new(onBall(skull, side * 0.95, -headSize * 0.14, -headSize * 0.04)), hairColor, Enum.PartType.Ball)
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
	local glow = Instance.new("PointLight")
	glow.Color = nape.Color
	glow.Range = h * 0.4
	glow.Brightness = 1.5
	glow.Parent = nape

	-- Legs: thigh on a hip motor, shin on a knee motor, then a foot. The
	-- shorts' legs ride on the thighs.
	local feet: { BasePart } = {}
	local shins: { BasePart } = {}
	local forearms: { BasePart } = {}
	for _, side in { -1, 1 } do
		local prefix = if side < 0 then "Left" else "Right"
		local x = side * torsoWidth * 0.26
		local thighPart = segment(model, `{prefix}Thigh`, legWidth, thigh, base * CFrame.new(x, hipY - thigh / 2, 0), skin)
		motor(`{prefix}Hip`, root, thighPart, base * CFrame.new(x, hipY, 0))
		weld(thighPart, part(model, `{prefix}ShortsLeg`, Vector3.new(thigh * 0.42, legWidth * 1.22, legWidth * 1.22), base * CFrame.new(x, hipY - thigh * 0.19, 0) * UPRIGHT, shortsColor, Enum.PartType.Cylinder, Enum.Material.Fabric))
		local shinPart = segment(model, `{prefix}Shin`, legWidth * 0.85, shin, base * CFrame.new(x, shin / 2, 0), skin)
		motor(`{prefix}Knee`, thighPart, shinPart, base * CFrame.new(x, shin, 0))
		local foot = part(model, `{prefix}Foot`, Vector3.new(legWidth * 0.95, h * 0.045, legWidth * 1.4), base * CFrame.new(x, h * 0.0225, -legWidth * 0.25), darker)
		weld(shinPart, foot)
		table.insert(feet, foot)
		table.insert(shins, shinPart)
		weld(shinPart, part(model, `{prefix}Toes`, Vector3.one * legWidth * 0.95, base * CFrame.new(x, legWidth * 0.3, -legWidth * 0.8), darker, Enum.PartType.Ball))
	end

	-- Arms: upper arm on a shoulder motor, forearm on an elbow, then a big
	-- hand (all the better to grab with).
	for _, side in { -1, 1 } do
		local prefix = if side < 0 then "Left" else "Right"
		local shoulder = base * CFrame.new(side * (torsoWidth / 2 + armWidth * 0.45), torsoCentreY + torsoHeight / 2 - armWidth * 0.5, 0)
		local upper = segment(model, `{prefix}UpperArm`, armWidth, upperArm, shoulder * CFrame.new(0, -upperArm / 2, 0), skin)
		motor(`{prefix}Shoulder`, torso, upper, shoulder)
		local fore = segment(model, `{prefix}ForeArm`, armWidth * 0.9, foreArm, shoulder * CFrame.new(0, -upperArm - foreArm / 2, 0), skin)
		motor(`{prefix}Elbow`, upper, fore, shoulder * CFrame.new(0, -upperArm, 0))
		local hand = part(model, `{prefix}Hand`, Vector3.one * armWidth * 1.35, shoulder * CFrame.new(0, -upperArm - foreArm - armWidth * 0.55, 0), skin, Enum.PartType.Ball)
		weld(fore, hand)
		table.insert(forearms, fore)
	end

	-- Armour: rock plates on the chest, shoulders, shins and forearms, a
	-- rocky helmet, and a plate over the nape that has to be cracked first.
	local armorPlate: BasePart? = nil
	if look.Armor then
		local function plate(name: string, size: Vector3, cframe: CFrame, to: BasePart, shape: Enum.PartType?)
			local p = part(model, name, size, cframe, ROCK:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.08)), shape, Enum.Material.Slate)
			weld(to, p)
			return p
		end
		plate("ChestPlate", Vector3.new(torsoWidth * 0.82, torsoHeight * 0.42, torsoDepth * 0.34), base * CFrame.new(0, torsoCentreY + torsoHeight * 0.2, -torsoDepth * 0.4), torso)
		for i, side in { -1, 1 } do
			plate(`ShoulderPlate{i}`, Vector3.one * armWidth * 1.75, base * CFrame.new(side * (torsoWidth / 2 + armWidth * 0.2), torsoCentreY + torsoHeight / 2 - armWidth * 0.4, 0), torso, Enum.PartType.Ball)
		end
		for i, shinPart in shins do
			plate(`ShinPlate{i}`, Vector3.new(shin * 0.7, legWidth * 1.02, legWidth * 1.02), shinPart.CFrame * CFrame.new(-shin * 0.05, 0, 0), shinPart, Enum.PartType.Cylinder)
		end
		for i, fore in forearms do
			plate(`ArmPlate{i}`, Vector3.new(foreArm * 0.7, armWidth * 1, armWidth * 1), fore.CFrame, fore, Enum.PartType.Cylinder)
		end
		plate("Helmet", Vector3.one * headSize * 1.06, headCentre * CFrame.new(0, headSize * 0.1, headSize * 0.08), head, Enum.PartType.Ball)
		armorPlate = plate("NapeArmor", Vector3.one * headSize * 0.58, nape.CFrame * CFrame.new(0, 0, headSize * 0.04), torso, Enum.PartType.Ball)
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
	model:SetAttribute("Height", h)
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
		TorsoHeight = pelvisHeight + torsoHeight,
		TorsoDepth = torsoDepth,
		TorsoWidth = torsoWidth,
		ShinLength = shin,
		HeadSize = headSize,
	}
end

return GiantFactory
