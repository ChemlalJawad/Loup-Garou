--!strict
-- The hunters' uniform and grapple rig, built from parts over the player's
-- own avatar so everyone looks like a member of the corps:
--
--   * a short brown jacket over a white shirt, white trousers, tall dark
--     boots;
--   * leather straps across the chest and round the thighs, a belt;
--   * a dark green cape with the corps' crossed-blades emblem and a rolled
--     hood;
--   * the grapple rig: the reel box at the small of the back with a hook
--     launcher either side, and on each hip a blade box with a gas tank on
--     top.
--
-- Every piece is massless, non-colliding and invisible to raycasts, so it
-- never gets in the way of the grapple or the slashes. R15 avatars get the
-- full outfit; R6 ones get the same on their bigger body parts.

local HunterGear = {}

local JACKET = Color3.fromRGB(124, 86, 54)
local SHIRT = Color3.fromRGB(236, 232, 222)
local TROUSERS = Color3.fromRGB(226, 220, 204)
local BOOTS = Color3.fromRGB(52, 40, 34)
local STRAP = Color3.fromRGB(70, 48, 34)
local BUCKLE = Color3.fromRGB(190, 176, 130)
local CAPE = Color3.fromRGB(46, 84, 58)
local STEEL = Color3.fromRGB(176, 182, 190)
local DARK_STEEL = Color3.fromRGB(64, 66, 72)
local EMBLEM_BLUE = Color3.fromRGB(70, 110, 190)

local PAD = 0.08 -- how far a shell stands proud of the body part

local function gearPart(gear: Model, name: string, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = gear
	return p
end

-- Welds `p` to `body` at `offset` in the body part's frame.
local function attach(body: BasePart, p: BasePart, offset: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = body
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.CFrame = body.CFrame * offset
end

local function bodyPart(character: Model, ...: string): BasePart?
	for _, name in { ... } do
		local found = character:FindFirstChild(name)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

-- A box just bigger than a body part (or the top `share` of it).
local function shell(gear: Model, body: BasePart, name: string, color: Color3, share: number?, pad: number?)
	local s = body.Size
	local fraction = share or 1
	local extra = pad or PAD
	local height = s.Y * fraction + extra
	local p = gearPart(gear, name, Vector3.new(s.X + extra * 2, height, s.Z + extra * 2), color, Enum.Material.Fabric)
	attach(body, p, CFrame.new(0, s.Y / 2 - height / 2 + extra / 2, 0))
end

-- A band all the way round a body part, at `y` studs from its centre.
local function band(gear: Model, body: BasePart, name: string, y: number, thickness: number, pad: number)
	local s = body.Size
	local p = gearPart(gear, name, Vector3.new(s.X + pad * 2, thickness, s.Z + pad * 2), STRAP, Enum.Material.Leather)
	attach(body, p, CFrame.new(0, y, 0))
end

local function jacket(gear: Model, torso: BasePart)
	local s = torso.Size
	local pad = PAD * 2.2
	local height = s.Y * 0.72 -- cropped short, above the belt
	local top = s.Y / 2 + pad / 2
	local y = top - height / 2
	-- Back panel and the two open front panels (the shirt shows between).
	local back = gearPart(gear, "JacketBack", Vector3.new(s.X + pad * 2, height, pad), JACKET, Enum.Material.Fabric)
	attach(torso, back, CFrame.new(0, y, s.Z / 2 + pad / 2))
	for i, side in { -1, 1 } do
		local panelWidth = s.X * 0.3
		local front = gearPart(gear, `JacketFront{i}`, Vector3.new(panelWidth, height, pad), JACKET, Enum.Material.Fabric)
		attach(torso, front, CFrame.new(side * (s.X / 2 + pad - panelWidth / 2), y, -s.Z / 2 - pad / 2))
		local flank = gearPart(gear, `JacketSide{i}`, Vector3.new(pad, height, s.Z + pad * 2), JACKET, Enum.Material.Fabric)
		attach(torso, flank, CFrame.new(side * (s.X / 2 + pad / 2), y, 0))
		-- A turned-down collar either side of the neck.
		local collar = gearPart(gear, `Collar{i}`, Vector3.new(s.X * 0.22, 0.14, s.Z * 0.5), JACKET:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric)
		attach(torso, collar, CFrame.new(side * s.X * 0.22, top + 0.02, -s.Z * 0.12) * CFrame.Angles(0, 0, side * math.rad(12)))
	end
	local yoke = gearPart(gear, "JacketShoulders", Vector3.new(s.X + pad * 2, pad, s.Z + pad * 2), JACKET, Enum.Material.Fabric)
	attach(torso, yoke, CFrame.new(0, top, 0))
end

local function chestStraps(gear: Model, torso: BasePart)
	local s = torso.Size
	local front = -s.Z / 2 - PAD * 1.4
	-- Two straps crossing over the shirt, a strap under the chest, a buckle.
	for i, side in { -1, 1 } do
		local strap = gearPart(gear, `ChestStrap{i}`, Vector3.new(0.16, s.Y * 1.05, 0.06), STRAP, Enum.Material.Leather)
		attach(torso, strap, CFrame.new(0, 0.05, front) * CFrame.Angles(0, 0, side * math.rad(28)))
	end
	local under = gearPart(gear, "ChestBand", Vector3.new(s.X * 0.5, 0.14, 0.06), STRAP, Enum.Material.Leather)
	attach(torso, under, CFrame.new(0, -s.Y * 0.12, front - 0.01))
	local buckle = gearPart(gear, "ChestBuckle", Vector3.new(0.2, 0.2, 0.05), BUCKLE, Enum.Material.Metal)
	attach(torso, buckle, CFrame.new(0, 0.05, front - 0.04))
	-- Over the shoulders, down the back.
	for i, side in { -1, 1 } do
		local brace = gearPart(gear, `BackStrap{i}`, Vector3.new(0.16, s.Y * 1.05, 0.06), STRAP, Enum.Material.Leather)
		attach(torso, brace, CFrame.new(side * s.X * 0.22, 0, s.Z / 2 + PAD * 2.4))
	end
end

local function cape(gear: Model, torso: BasePart)
	local s = torso.Size
	-- Down to the waist: short enough to leave the reel box in sight.
	local length = s.Y * 0.95
	local width = s.X * 1.12
	local back = s.Z / 2 + PAD * 3.2
	local top = s.Y / 2 + 0.05
	-- Hung from the shoulders, swinging out a touch at the bottom.
	local hang = CFrame.new(0, top, back) * CFrame.Angles(math.rad(-8), 0, 0)
	local cloth = gearPart(gear, "Cape", Vector3.new(width, length, 0.08), CAPE, Enum.Material.Fabric)
	attach(torso, cloth, hang * CFrame.new(0, -length / 2, 0))
	-- The hood, rolled up round the back of the neck.
	local hood = gearPart(gear, "CapeHood", Vector3.new(s.X * 0.95, 0.38, 0.38), CAPE:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Fabric, Enum.PartType.Cylinder)
	attach(torso, hood, CFrame.new(0, top, back - 0.12))
	-- The corps' emblem: a blue shield with two crossed blades.
	local emblemAt = hang * CFrame.new(0, -length * 0.42, 0.05)
	local shield = gearPart(gear, "EmblemShield", Vector3.new(0.04, width * 0.4, width * 0.4), EMBLEM_BLUE, Enum.Material.Fabric, Enum.PartType.Cylinder)
	attach(torso, shield, emblemAt * CFrame.Angles(0, math.rad(90), 0))
	for i, side in { -1, 1 } do
		local blade = gearPart(gear, `EmblemBlade{i}`, Vector3.new(0.09, width * 0.5, 0.03), STEEL, Enum.Material.Metal)
		attach(torso, blade, emblemAt * CFrame.new(0, 0, 0.03) * CFrame.Angles(0, 0, side * math.rad(35)))
	end
end

local function rig(gear: Model, hips: BasePart)
	local s = hips.Size
	local back = s.Z / 2
	-- The reel box at the small of the back, with its silver drum and a
	-- hook launcher pointing out each side.
	local box = gearPart(gear, "ReelBox", Vector3.new(s.X * 0.62, s.Y * 0.8, 0.45), DARK_STEEL, Enum.Material.Metal)
	attach(hips, box, CFrame.new(0, 0.05, back + 0.24))
	local drum = gearPart(gear, "ReelDrum", Vector3.new(0.12, s.Y * 0.6, s.Y * 0.6), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	attach(hips, drum, CFrame.new(0, 0.05, back + 0.48) * CFrame.Angles(0, math.rad(90), 0))
	for i, side in { -1, 1 } do
		local launcher = gearPart(gear, `HookLauncher{i}`, Vector3.new(0.4, 0.24, 0.24), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
		attach(hips, launcher, CFrame.new(side * (s.X / 2 + 0.05), -0.05, back + 0.12))
		-- A gas tank either side of the reel box, pointing back, with its
		-- valve at the back end.
		local tankAt = CFrame.new(side * (s.X * 0.31 + 0.14), -0.02, back + 0.55)
		local tank = gearPart(gear, `GasTank{i}`, Vector3.new(1.3, 0.4, 0.4), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
		attach(hips, tank, tankAt * CFrame.Angles(0, math.rad(90), 0))
		local valve = gearPart(gear, `GasValve{i}`, Vector3.new(0.16, 0.24, 0.24), DARK_STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
		attach(hips, valve, tankAt * CFrame.new(0, 0, 0.7) * CFrame.Angles(0, math.rad(90), 0))
	end

	-- Low on each hip, below the hands: a blade box (the spare blades)
	-- pointing back, hung from the belt by a strap.
	for i, side in { -1, 1 } do
		local x = side * (s.X / 2 + 0.3)
		local at = CFrame.new(x, -s.Y / 2 - 0.85, 0.7) * CFrame.Angles(math.rad(-10), 0, 0)
		local bladeBox = gearPart(gear, `BladeBox{i}`, Vector3.new(0.3, 0.6, 1.9), DARK_STEEL, Enum.Material.Metal)
		attach(hips, bladeBox, at)
		local trim = gearPart(gear, `BladeBoxTrim{i}`, Vector3.new(0.32, 0.08, 1.92), STEEL, Enum.Material.Metal)
		attach(hips, trim, at * CFrame.new(0, 0.26, 0))
		-- The blade grips poke out of the front of the box.
		for g, y in { -0.12, 0.12 } do
			local stub = gearPart(gear, `BladeStub{i}{g}`, Vector3.new(0.12, 0.12, 0.2), STEEL, Enum.Material.Metal)
			attach(hips, stub, at * CFrame.new(0, y, -1.02))
		end
		local hanger = gearPart(gear, `BoxStrap{i}`, Vector3.new(0.08, 0.9, 0.14), STRAP, Enum.Material.Leather)
		attach(hips, hanger, CFrame.new(side * (s.X / 2 + 0.2), -s.Y / 2 - 0.3, 0.45))
	end
end

local function limbs(gear: Model, character: Model)
	for _, prefix in { "Left", "Right" } do
		local upperArm = bodyPart(character, `{prefix}UpperArm`, `{prefix} Arm`)
		local lowerArm = bodyPart(character, `{prefix}LowerArm`)
		local upperLeg = bodyPart(character, `{prefix}UpperLeg`)
		local lowerLeg = bodyPart(character, `{prefix}LowerLeg`)
		local foot = bodyPart(character, `{prefix}Foot`)
		local r6Leg = bodyPart(character, `{prefix} Leg`)
		if upperArm then
			shell(gear, upperArm, `{prefix}Sleeve`, JACKET, if lowerArm then 1 else 0.85)
		end
		if lowerArm then
			shell(gear, lowerArm, `{prefix}Cuff`, JACKET)
		end
		if upperLeg then
			shell(gear, upperLeg, `{prefix}Trouser`, TROUSERS)
			-- The harness straps round each thigh.
			band(gear, upperLeg, `{prefix}ThighStrap1`, upperLeg.Size.Y * 0.18, 0.12, PAD * 1.6)
			band(gear, upperLeg, `{prefix}ThighStrap2`, -upperLeg.Size.Y * 0.22, 0.12, PAD * 1.6)
		end
		if lowerLeg then
			shell(gear, lowerLeg, `{prefix}Boot`, BOOTS)
		end
		if foot then
			shell(gear, foot, `{prefix}BootFoot`, BOOTS)
		end
		if r6Leg then
			shell(gear, r6Leg, `{prefix}Trouser`, TROUSERS)
			shell(gear, r6Leg, `{prefix}Boot`, BOOTS, 0.5, PAD * 1.5)
			local s = r6Leg.Size
			band(gear, r6Leg, `{prefix}ThighStrap`, s.Y * 0.32, 0.12, PAD * 1.6)
			-- The R6 boot shell is the top half; slide it down to the bottom.
			local boot = gear:FindFirstChild(`{prefix}Boot`)
			local weld = boot and boot:FindFirstChildOfClass("Weld")
			if weld then
				weld.C0 = CFrame.new(0, -s.Y / 4, 0)
			end
		end
	end
end

-- Dresses a hunter. Safe to call again: the old outfit is replaced.
function HunterGear.Dress(character: Model)
	local old = character:FindFirstChild("HunterGear")
	if old then
		old:Destroy()
	end
	local gear = Instance.new("Model")
	gear.Name = "HunterGear"

	local torso = bodyPart(character, "UpperTorso", "Torso")
	local hips = bodyPart(character, "LowerTorso", "Torso")
	if torso then
		shell(gear, torso, "Shirt", SHIRT)
		jacket(gear, torso)
		chestStraps(gear, torso)
		cape(gear, torso)
	end
	if hips then
		if hips ~= torso then
			shell(gear, hips, "TrouserTop", TROUSERS)
		end
		local belt = if hips ~= torso then hips.Size.Y / 2 - 0.08 else -hips.Size.Y / 2 + 0.1
		band(gear, hips, "Belt", belt, 0.16, PAD * 1.6)
		rig(gear, hips)
	end
	limbs(gear, character)
	gear.Parent = character
end

return HunterGear
