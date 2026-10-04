--!strict
-- The hunters' uniform and grapple rig, so everyone looks like a member of
-- the corps:
--
--   * a short brown jacket over a white shirt, white trousers, tall dark
--     boots;
--   * leather straps across the chest and round the thighs, a belt;
--   * a dark green cape with the corps' crossed-blades emblem and a rolled
--     hood;
--   * the grapple rig: the reel box at the small of the back with a hook
--     launcher either side (HookLauncher1 = left, HookLauncher2 = right,
--     each with a "CableOrigin" attachment at its tip), and on each hip a
--     blade box with a gas tank on top.
--   * shop gear (the "Equip_Gear" attribute, Config.Catalog Look) recolours
--     the rig and the swords and resizes the tanks (ApplyGearLook).
--   * cosmetic items (Config.CosmeticItems, the "Cos_Cape", "Cos_Blade" and
--     "Cos_Trail" attributes the shop sets) restyle the cape (colours and a
--     pattern: stripes, star dots, a trim, a two-tone split or a glowing
--     hem), the blades and their slash trail. They win over the gear set's
--     colours and the rank cape ("CapeColor"); WatchCosmetics re-dresses
--     live when they change.
--
-- The avatar itself is re-dressed first through its HumanoidDescription
-- (no asset ids needed): classic shirt and pants off, layered clothing and
-- back / waist / shoulder / front / neck accessories off (hair, hats and
-- the face stay), default body parts at normal scale (no Rthro shapes for
-- the gear to float off), and body colours painted as the uniform (shirt
-- torso, jacket arms, trouser legs). The gear on top is then only the thin
-- pieces: straps, cuffs, collar, belt, boots, the jacket's panels over the
-- torso, the cape and the rig. If the description can't be applied (no
-- Humanoid, an engine error), it falls back to full fabric shells over
-- every body part instead.
--
-- Every piece is massless, non-colliding and invisible to raycasts, so it
-- never gets in the way of the grapple or the slashes. R15 and R6 both
-- work; on R6 the rig is built on the bottom of the torso.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

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

-- Accessories that stay on: they sit on the head, clear of the gear.
local KEEP_ACCESSORIES: { [EnumItem]: boolean } = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

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
	-- Thin leather, buckles and trim cast no shadow (there are a lot of them).
	if math.min(size.X, size.Y, size.Z) < 0.2 then
		p.CastShadow = false
	end
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
local function band(gear: Model, body: BasePart, name: string, y: number, thickness: number, pad: number, color: Color3?)
	local s = body.Size
	local p = gearPart(gear, name, Vector3.new(s.X + pad * 2, thickness, s.Z + pad * 2), color or STRAP, Enum.Material.Leather)
	attach(body, p, CFrame.new(0, y, 0))
end

-- Re-dresses the avatar as the uniform (see the top). Yields. Returns
-- false if it couldn't, so the caller falls back to full shells.
local function applyUniform(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return false
	end
	-- ApplyDescription only works once the character is in the world.
	local waited = 0
	while not character:IsDescendantOf(Workspace) and waited < 5 do
		waited += task.wait(0.1)
	end
	if not character:IsDescendantOf(Workspace) then
		return false
	end
	local ok, err = pcall(function()
		local description = humanoid:GetAppliedDescription()
		description.Shirt = 0
		description.Pants = 0
		description.GraphicTShirt = 0
		local kept = {}
		for _, accessory in description:GetAccessories(true) do
			if not accessory.IsLayered and KEEP_ACCESSORIES[accessory.AccessoryType] then
				table.insert(kept, accessory)
			end
		end
		description:SetAccessories(kept, true)
		description.BackAccessory = ""
		description.WaistAccessory = ""
		description.ShouldersAccessory = ""
		description.FrontAccessory = ""
		description.NeckAccessory = ""
		description.Torso = 0
		description.LeftArm = 0
		description.RightArm = 0
		description.LeftLeg = 0
		description.RightLeg = 0
		description.BodyTypeScale = 0
		description.ProportionScale = 0
		description.HeightScale = 1
		description.WidthScale = 1
		description.DepthScale = 1
		description.HeadScale = 1
		description.TorsoColor = SHIRT
		description.LeftArmColor = JACKET
		description.RightArmColor = JACKET
		description.LeftLegColor = TROUSERS
		description.RightLegColor = TROUSERS
		humanoid:ApplyDescriptionAsync(description)
	end)
	if not ok then
		warn("[HunterGear] uniform not applied, using shells:", err)
		return false
	end
	if not character.Parent then
		return false -- respawned while it was loading
	end
	-- The arms are jacket brown; hands stay bare (the head's skin tone).
	local head = bodyPart(character, "Head")
	if head then
		for _, name in { "LeftHand", "RightHand" } do
			local hand = bodyPart(character, name)
			if hand then
				hand.Color = head.Color
			end
		end
	end
	return true
end

local function jacket(gear: Model, torso: BasePart, full: boolean)
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
	if full then
		local yoke = gearPart(gear, "JacketShoulders", Vector3.new(s.X + pad * 2, pad, s.Z + pad * 2), JACKET, Enum.Material.Fabric)
		attach(torso, yoke, CFrame.new(0, top, 0))
	end
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

-- `rigTop`: the height (in the torso's frame) of the top of the reel box on
-- R6, where the torso is also the hips; the cape stops above it there.
-- The cosmetic item a player wears in `slot` (nil: the default look).
local function cosmetic(character: Model, slot: string): Config.CosmeticItem?
	local player = Players:GetPlayerFromCharacter(character)
	return if player then Config.CosmeticFor(slot, player:GetAttribute(`Cos_{slot}`)) else nil
end

-- The cape's colours: a cosmetic cape ("Cos_Cape") first, else the
-- player's "CapeColor" and "EmblemColor" attributes (ProgressService sets
-- them from the rank / Marks cape), else the corps' green and blue.
local function capeColors(character: Model): (Color3, Color3)
	local item = cosmetic(character, "Cape")
	local look = item and item.Cape
	if look then
		return look.Color, look.Emblem or EMBLEM_BLUE
	end
	local player = Players:GetPlayerFromCharacter(character)
	local color = player and player:GetAttribute("CapeColor")
	local emblem = player and player:GetAttribute("EmblemColor")
	return if typeof(color) == "Color3" then color else CAPE, if typeof(emblem) == "Color3" then emblem else EMBLEM_BLUE
end

-- A cosmetic cape's pattern, laid flat on the outside of the cloth (thin
-- parts welded to it, all named "CapeDeco" so a new cape clears them).
local function decorate(gear: Model, cloth: BasePart, look: Config.CosmeticCape?)
	for _, item in gear:GetChildren() do
		if item.Name == "CapeDeco" then
			item:Destroy()
		end
	end
	if not look or not look.Pattern then
		return
	end
	local w, l = cloth.Size.X, cloth.Size.Y
	local color = look.PatternColor or Color3.new(1, 1, 1)
	local function piece(size: Vector2, x: number, y: number, round: boolean?, material: Enum.Material?)
		local p = if round
			then gearPart(gear, "CapeDeco", Vector3.new(0.02, size.Y, size.X), color, material or Enum.Material.Fabric, Enum.PartType.Cylinder)
			else gearPart(gear, "CapeDeco", Vector3.new(size.X, size.Y, 0.02), color, material or Enum.Material.Fabric)
		attach(cloth, p, CFrame.new(x, y, 0.05) * (if round then CFrame.Angles(0, math.rad(90), 0) else CFrame.identity))
	end
	local pattern = look.Pattern
	if pattern == "Stripes" then
		for _, side in { -1, 1 } do
			piece(Vector2.new(w * 0.09, l), side * w * 0.36, 0)
		end
	elseif pattern == "Stars" then
		-- Dots round the emblem: a row at the bottom, two each side above.
		local dot = math.min(w, l) * 0.1
		for _, at in { Vector2.new(-0.36, 0.36), Vector2.new(0.36, 0.36), Vector2.new(-0.38, 0), Vector2.new(0.38, 0), Vector2.new(-0.25, -0.38), Vector2.new(0, -0.4), Vector2.new(0.25, -0.38) } do
			piece(Vector2.new(dot, dot), at.X * w, at.Y * l, true)
		end
	elseif pattern == "Split" then
		piece(Vector2.new(w, l * 0.3), 0, -l * 0.35)
	elseif pattern == "Trim" or pattern == "Glow" then
		local material = if pattern == "Glow" then Enum.Material.Neon else nil
		local edge = math.min(w, l) * 0.07
		piece(Vector2.new(w, edge), 0, -l / 2 + edge / 2, false, material)
		for _, side in { -1, 1 } do
			piece(Vector2.new(edge, l - edge), side * (w / 2 - edge / 2), edge / 2, false, material)
		end
	end
end

local function cape(gear: Model, torso: BasePart, rigTop: number?, color: Color3, emblemColor: Color3)
	local s = torso.Size
	local top = s.Y / 2 + 0.05
	-- Down to the waist: short enough to leave the reel box in sight.
	local length = if rigTop then math.max(top - rigTop - 0.1, s.Y * 0.4) else s.Y * 0.95
	local width = s.X * 1.12
	local back = s.Z / 2 + PAD * 3.2
	-- Hung from the shoulders, swinging out a touch at the bottom.
	local hang = CFrame.new(0, top, back) * CFrame.Angles(math.rad(if rigTop then -14 else -8), 0, 0)
	local cloth = gearPart(gear, "Cape", Vector3.new(width, length, 0.08), color, Enum.Material.Fabric)
	attach(torso, cloth, hang * CFrame.new(0, -length / 2, 0))
	local character = torso.Parent
	if character and character:IsA("Model") then
		local item = cosmetic(character, "Cape")
		decorate(gear, cloth, item and item.Cape)
	end
	-- The hood, rolled up round the back of the neck.
	local hood = gearPart(gear, "CapeHood", Vector3.new(s.X * 0.95, 0.38, 0.38), color:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Fabric, Enum.PartType.Cylinder)
	attach(torso, hood, CFrame.new(0, top, back - 0.12))
	-- The corps' emblem: a blue shield with two crossed blades.
	local emblemSize = math.min(width * 0.4, length * 0.7)
	local emblemAt = hang * CFrame.new(0, -length * 0.45, 0.05)
	local shield = gearPart(gear, "EmblemShield", Vector3.new(0.04, emblemSize, emblemSize), emblemColor, Enum.Material.Fabric, Enum.PartType.Cylinder)
	attach(torso, shield, emblemAt * CFrame.Angles(0, math.rad(90), 0))
	for i, side in { -1, 1 } do
		local blade = gearPart(gear, `EmblemBlade{i}`, Vector3.new(0.09, emblemSize * 1.25, 0.03), STEEL, Enum.Material.Metal)
		attach(torso, blade, emblemAt * CFrame.new(0, 0, 0.03) * CFrame.Angles(0, 0, side * math.rad(35)))
	end
end

-- The rig, round `frame` (the hips' centre in `hips`' frame) for a hip
-- block of `s`: R15's LowerTorso, or the bottom of an R6 torso.
local function rig(gear: Model, hips: BasePart, frame: CFrame, s: Vector3)
	local back = s.Z / 2
	local function at(offset: CFrame): CFrame
		return frame * offset
	end
	-- The reel box at the small of the back, with its silver drum and a
	-- hook launcher pointing out each side.
	local box = gearPart(gear, "ReelBox", Vector3.new(s.X * 0.62, s.Y * 0.8, 0.45), DARK_STEEL, Enum.Material.Metal)
	attach(hips, box, at(CFrame.new(0, 0.05, back + 0.24)))
	local drum = gearPart(gear, "ReelDrum", Vector3.new(0.12, s.Y * 0.6, s.Y * 0.6), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	attach(hips, drum, at(CFrame.new(0, 0.05, back + 0.48) * CFrame.Angles(0, math.rad(90), 0)))
	for i, side in { -1, 1 } do
		-- HookLauncher1 is the left one, HookLauncher2 the right one; cables
		-- can start at their CableOrigin attachments.
		local launcher = gearPart(gear, `HookLauncher{i}`, Vector3.new(0.4, 0.24, 0.24), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
		attach(hips, launcher, at(CFrame.new(side * (s.X / 2 + 0.05), -0.05, back + 0.12)))
		local origin = Instance.new("Attachment")
		origin.Name = "CableOrigin"
		origin.Position = Vector3.new(side * 0.2, 0, 0)
		origin.Parent = launcher
		-- A gas tank either side of the reel box, pointing back, with its
		-- valve at the back end.
		local tankAt = at(CFrame.new(side * (s.X * 0.31 + 0.14), -0.02, back + 0.55))
		local tank = gearPart(gear, `GasTank{i}`, Vector3.new(1.3, 0.4, 0.4), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
		attach(hips, tank, tankAt * CFrame.Angles(0, math.rad(90), 0))
		local valve = gearPart(gear, `GasValve{i}`, Vector3.new(0.16, 0.24, 0.24), DARK_STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
		attach(hips, valve, tankAt * CFrame.new(0, 0, 0.7) * CFrame.Angles(0, math.rad(90), 0))
	end

	-- Low on each hip, out to the side and behind the hands: a blade box
	-- (the spare blades) pointing back, hung from the belt by a strap. Its
	-- front edge (the grips) stays behind the body, so swinging hands
	-- never go through it.
	local boxLength = 1.6
	for i, side in { -1, 1 } do
		local x = side * (s.X / 2 + 0.5)
		local boxAt = at(CFrame.new(x, -s.Y / 2 - 0.75, 0.5 + 0.18 + boxLength / 2) * CFrame.Angles(math.rad(-8), 0, 0))
		local bladeBox = gearPart(gear, `BladeBox{i}`, Vector3.new(0.3, 0.6, boxLength), DARK_STEEL, Enum.Material.Metal)
		attach(hips, bladeBox, boxAt)
		local trim = gearPart(gear, `BladeBoxTrim{i}`, Vector3.new(0.32, 0.08, boxLength + 0.02), STEEL, Enum.Material.Metal)
		attach(hips, trim, boxAt * CFrame.new(0, 0.26, 0))
		-- The blade grips poke out of the front of the box.
		for g, y in { -0.12, 0.12 } do
			local stub = gearPart(gear, `BladeStub{i}{g}`, Vector3.new(0.12, 0.12, 0.16), STEEL, Enum.Material.Metal)
			attach(hips, stub, boxAt * CFrame.new(0, y, -boxLength / 2 - 0.08))
		end
		local hanger = gearPart(gear, `BoxStrap{i}`, Vector3.new(0.08, 0.95, 0.14), STRAP, Enum.Material.Leather)
		attach(hips, hanger, at(CFrame.new(side * (s.X / 2 + 0.4), -s.Y / 2 - 0.3, 0.75) * CFrame.Angles(0, 0, side * math.rad(-12))))
	end
end

-- Arms and legs. `full`: fabric shells over every limb (the fallback);
-- otherwise the body colours already are the uniform and only the cuffs,
-- the thigh straps and the boots go on.
local function limbs(gear: Model, character: Model, full: boolean)
	for _, prefix in { "Left", "Right" } do
		local upperArm = bodyPart(character, `{prefix}UpperArm`, `{prefix} Arm`)
		local lowerArm = bodyPart(character, `{prefix}LowerArm`)
		local upperLeg = bodyPart(character, `{prefix}UpperLeg`)
		local lowerLeg = bodyPart(character, `{prefix}LowerLeg`)
		local foot = bodyPart(character, `{prefix}Foot`)
		local r6Leg = bodyPart(character, `{prefix} Leg`)
		if full and upperArm then
			shell(gear, upperArm, `{prefix}Sleeve`, JACKET, if lowerArm then 1 else 0.85)
		end
		if full and lowerArm then
			shell(gear, lowerArm, `{prefix}Sleeve2`, JACKET)
		end
		-- A darker turned-back cuff at the wrist.
		local wrist = lowerArm or (if r6Leg then upperArm else nil)
		if wrist then
			local cuffY = -wrist.Size.Y / 2 + (if lowerArm then 0.12 else 0.45) -- (R6: above the hand)
			band(gear, wrist, `{prefix}Cuff`, cuffY, 0.2, PAD * 1.3, JACKET:Lerp(Color3.new(0, 0, 0), 0.2))
		end
		if upperLeg then
			if full then
				shell(gear, upperLeg, `{prefix}Trouser`, TROUSERS)
			end
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
			if full then
				shell(gear, r6Leg, `{prefix}Trouser`, TROUSERS)
			end
			local s = r6Leg.Size
			band(gear, r6Leg, `{prefix}ThighStrap`, s.Y * 0.32, 0.12, PAD * 1.6)
			-- The boot: the bottom half of the leg.
			local height = s.Y * 0.5 + PAD * 1.5
			local boot = gearPart(gear, `{prefix}Boot`, Vector3.new(s.X + PAD * 3, height, s.Z + PAD * 3), BOOTS, Enum.Material.Fabric)
			attach(r6Leg, boot, CFrame.new(0, -s.Y / 2 + height / 2 - PAD * 0.75, 0))
		end
	end
end

-- Dresses a hunter. Yields (the uniform loads). Safe to call again: the
-- old outfit is replaced.
function HunterGear.Dress(character: Model)
	local uniform = applyUniform(character)
	if not character.Parent then
		return
	end
	local old = character:FindFirstChild("HunterGear")
	if old then
		old:Destroy()
	end
	local gear = Instance.new("Model")
	gear.Name = "HunterGear"

	local torso = bodyPart(character, "UpperTorso", "Torso")
	local hips = bodyPart(character, "LowerTorso", "Torso")
	local r6 = hips ~= nil and hips == torso
	-- R6: the rig hangs on the bottom 0.7 studs of the torso.
	local hipSize = if hips and r6 then Vector3.new(hips.Size.X, 0.7, hips.Size.Z) elseif hips then hips.Size else Vector3.one
	local hipFrame = if hips and r6 then CFrame.new(0, -hips.Size.Y / 2 + 0.35, 0) else CFrame.new()
	if torso then
		if not uniform then
			shell(gear, torso, "Shirt", SHIRT)
		end
		jacket(gear, torso, not uniform)
		chestStraps(gear, torso)
		local capeColor, emblemColor = capeColors(character)
		cape(gear, torso, if r6 then -torso.Size.Y / 2 + 0.35 + 0.05 + hipSize.Y * 0.4 else nil, capeColor, emblemColor)
	end
	if hips then
		if not r6 and not uniform then
			shell(gear, hips, "TrouserTop", TROUSERS)
		end
		local belt = if not r6 then hips.Size.Y / 2 - 0.08 else -hips.Size.Y / 2 + 0.1
		band(gear, hips, "Belt", belt, 0.16, PAD * 1.6)
		rig(gear, hips, hipFrame, hipSize)
	end
	limbs(gear, character, not uniform)
	gear.Parent = character
	HunterGear.ApplyGearLook(character)
end

-- === Shop gear (Config.Catalog) ==============================================
-- The equipped gear set (the player's "Equip_Gear" attribute) recolours the
-- rig and the swords and resizes the gas tanks; no gear: the corps' issue.

local TANK_SIZE = Vector3.new(1.3, 0.4, 0.4)
local SWORD_HILT = Color3.fromRGB(52, 54, 62)
local SWORD_COLLAR = Color3.fromRGB(176, 160, 116)
local SWORD_EDGE = Color3.fromRGB(240, 250, 255)
local SWORD_TRAIL = Color3.fromRGB(200, 235, 255)
local RIG_PARTS = { ReelBox = true, BladeBox1 = true, BladeBox2 = true, GasValve1 = true, GasValve2 = true }
local STEEL_PARTS = { ReelDrum = true, HookLauncher1 = true, HookLauncher2 = true, GasTank1 = true, GasTank2 = true, BladeBoxTrim1 = true, BladeBoxTrim2 = true }

local BLADE_SHARP = Color3.fromRGB(215, 225, 235)
local BLADE_DULL = Color3.fromRGB(120, 115, 110)
local DEFAULT_TRAIL_FADE = NumberSequence.new(0.2, 1)
local FULL_WIDTH = NumberSequence.new(1)

-- Trail colour sequences, built once per item.
local trailColors: { [string]: ColorSequence } = {}
local function sequenceOf(id: string, colors: { Color3 }): ColorSequence
	local cached = trailColors[id]
	if cached then
		return cached
	end
	local sequence
	if #colors < 2 then
		sequence = ColorSequence.new(colors[1] or SWORD_TRAIL)
	else
		local points = {}
		for i, color in colors do
			table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color))
		end
		sequence = ColorSequence.new(points)
	end
	trailColors[id] = sequence
	return sequence
end

local function gearLook(character: Model): Config.GearLook
	local player = Players:GetPlayerFromCharacter(character)
	local id = player and player:GetAttribute("Equip_Gear")
	local item = if type(id) == "string" then Config.Catalog[id] else nil
	return (item and item.Category == "Gear" and item.Look) or {}
end

-- Safe to call any time (the swords may not be on yet: call again after).
-- The swords: a cosmetic blade ("Cos_Blade") wins over the gear set's
-- Hilt/Edge; the trail is the cosmetic trail ("Cos_Trail"), else the
-- blade's edge colour (cosmetic, then gear), else the corps' pale blue.
-- Dull swords (the "Dull" attribute HunterService sets) stay grey steel.
function HunterGear.ApplyGearLook(character: Model)
	local look = gearLook(character)
	local bladeItem = cosmetic(character, "Blade")
	local blade = bladeItem and bladeItem.Blade
	local trailItem = cosmetic(character, "Trail")
	local trailLook = trailItem and trailItem.Trail
	local gear = character:FindFirstChild("HunterGear")
	if gear then
		for _, item in gear:GetChildren() do
			if item:IsA("BasePart") then
				if RIG_PARTS[item.Name] then
					item.Color = look.Rig or DARK_STEEL
				elseif STEEL_PARTS[item.Name] then
					item.Color = look.Steel or STEEL
				end
				if item.Name == "GasTank1" or item.Name == "GasTank2" then
					item.Size = TANK_SIZE * (look.TankScale or 1)
				end
			end
		end
	end
	for _, name in { "LeftSword", "RightSword" } do
		local sword = character:FindFirstChild(name)
		if sword then
			for _, item in sword:GetChildren() do
				if item:IsA("BasePart") then
					if item.Name == "Hilt" then
						item.Color = (blade and blade.Hilt) or look.Hilt or SWORD_HILT
					elseif item.Name == "Collar" then
						item.Color = (blade and blade.Hilt) or look.Hilt or SWORD_COLLAR
					elseif item.Name == "Edge" then
						item.Color = (blade and blade.Edge) or look.Edge or SWORD_EDGE
					elseif item.Name == "Blade" or item.Name == "BladeTip" then
						local dull = sword:GetAttribute("Dull") == true
						item.Color = if dull then BLADE_DULL elseif blade then blade.Color else BLADE_SHARP
						item.Material = if not dull and blade and blade.Material then blade.Material else Enum.Material.Metal
						item.Reflectance = if dull then 0 elseif blade and blade.Reflectance then blade.Reflectance else 0.35
						-- (Hidden inside a titan: stays hidden.)
						if item.Transparency < 1 then
							item.Transparency = if not dull and blade and blade.Transparency then blade.Transparency else 0
						end
					end
				end
			end
			local bladePart = sword:FindFirstChild("Blade")
			local trail = bladePart and bladePart:FindFirstChild("BladeTrail")
			if trail and trail:IsA("Trail") then
				if trailItem and trailLook then
					trail.Color = sequenceOf(trailItem.Id, trailLook.Colors)
					trail.Lifetime = trailLook.Lifetime or 0.18
					trail.LightEmission = trailLook.LightEmission or 1
					trail.WidthScale = if trailLook.Width then NumberSequence.new(trailLook.Width, 0.3) else FULL_WIDTH
					trail.Transparency = if trailLook.Transparency then NumberSequence.new(trailLook.Transparency, 1) else DEFAULT_TRAIL_FADE
				else
					trail.Color = if bladeItem and blade then sequenceOf(bladeItem.Id, { blade.Edge }) else ColorSequence.new(look.Edge or SWORD_TRAIL)
					trail.Lifetime = 0.18
					trail.LightEmission = 1
					trail.WidthScale = FULL_WIDTH
					trail.Transparency = DEFAULT_TRAIL_FADE
				end
			end
		end
	end
end

-- Re-colours a dressed hunter's cape and emblem from the player's
-- attributes (after they pick another cape) and redoes a cosmetic cape's
-- pattern, without re-dressing.
function HunterGear.RecolorCape(character: Model)
	local gear = character:FindFirstChild("HunterGear")
	if not gear or not gear:IsA("Model") then
		return
	end
	local color, emblem = capeColors(character)
	local cloth = gear:FindFirstChild("Cape")
	if cloth and cloth:IsA("BasePart") then
		local item = cosmetic(character, "Cape")
		decorate(gear, cloth, item and item.Cape)
	end
	for _, item in gear:GetChildren() do
		if item:IsA("BasePart") then
			if item.Name == "Cape" then
				item.Color = color
			elseif item.Name == "CapeHood" then
				item.Color = color:Lerp(Color3.new(0, 0, 0), 0.12)
			elseif item.Name == "EmblemShield" then
				item.Color = emblem
			end
		end
	end
end

-- Re-dresses live when the shop changes a worn cosmetic (the cape, the
-- blades or their trail). Call once per player.
function HunterGear.WatchCosmetics(player: Player)
	player:GetAttributeChangedSignal("Cos_Cape"):Connect(function()
		local character = player.Character
		if character then
			HunterGear.RecolorCape(character)
		end
	end)
	for _, attribute in { "Cos_Blade", "Cos_Trail" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			local character = player.Character
			if character then
				HunterGear.ApplyGearLook(character)
			end
		end)
	end
end

return HunterGear
