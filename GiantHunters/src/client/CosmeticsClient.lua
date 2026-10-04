--!strict
-- Cosmetic items on this client (Config.CosmeticItems; the shop sets the
-- "Cos_<Slot>" player attributes, this only reads them):
--   * gas jet and cable colours (GrappleController asks GasStyle and
--     CableStyle; the sequences are built once per item, never per frame);
--   * defeat effects: when a hunter with one on takes a giant down, a burst
--     of confetti, stars, hearts, bubbles or mist where the nape was - your
--     own from your SlashResult (Juice calls DefeatBurst), everyone else's
--     from the server's CosmeticFx event (skipped when far away).
-- Bursts are pooled (Config.CosmeticFx.Rigs emitter rigs, a few heart
-- shapes) and halved on phones and low graphics (SkyController.LowEnd).
-- Default ParticleEmitter texture only: no asset ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local SkyController = require(script.Parent.SkyController)

local CosmeticsClient = {}

local Fx = Config.CosmeticFx

-- The item `player` wears in `slot` (nil: the default look).
function CosmeticsClient.Item(player: Player, slot: string): Config.CosmeticItem?
	return Config.CosmeticFor(slot, player:GetAttribute(`Cos_{slot}`))
end

-- === Gas and cables ==========================================================

local DEFAULT_PUFF = ColorSequence.new(Color3.fromRGB(240, 242, 248))
local DEFAULT_CORE = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 225, 255))
local DEFAULT_CABLE = ColorSequence.new(Color3.fromRGB(200, 205, 215))

type GasStyle = { Puff: ColorSequence, Core: ColorSequence, Glow: number }
type CableStyle = { Color: ColorSequence, Glow: number, Width: number }
local DEFAULT_GAS: GasStyle = { Puff = DEFAULT_PUFF, Core = DEFAULT_CORE, Glow = 0 }
local DEFAULT_CABLE_STYLE: CableStyle = { Color = DEFAULT_CABLE, Glow = 0, Width = 1 }
local gasStyles: { [string]: GasStyle } = {}
local cableStyles: { [string]: CableStyle } = {}

-- The gas jets' colours for `player`: puff, core, and extra light emission.
function CosmeticsClient.GasStyle(player: Player): GasStyle
	local item = CosmeticsClient.Item(player, "Gas")
	local gas = item and item.Gas
	if not item or not gas then
		return DEFAULT_GAS
	end
	local style = gasStyles[item.Id]
	if not style then
		style = {
			Puff = ColorSequence.new(gas.Color, gas.Color2 or gas.Color),
			Core = ColorSequence.new(Color3.new(1, 1, 1):Lerp(gas.Core, 0.5), gas.Core),
			Glow = gas.LightEmission or 0,
		}
		gasStyles[item.Id] = style
	end
	return style
end

-- `player`'s cable: colour, extra light emission, x width.
function CosmeticsClient.CableStyle(player: Player): CableStyle
	local item = CosmeticsClient.Item(player, "Cable")
	local cable = item and item.Cable
	if not item or not cable then
		return DEFAULT_CABLE_STYLE
	end
	local style = cableStyles[item.Id]
	if not style then
		style = {
			Color = ColorSequence.new(cable.Color, cable.Color2 or cable.Color),
			Glow = cable.LightEmission or 0,
			Width = cable.Width or 1,
		}
		cableStyles[item.Id] = style
	end
	return style
end

-- === Defeat effects ==========================================================

-- How each shape moves (all built once, here).
type Shape = {
	Size: NumberSequence,
	Transparency: NumberSequence,
	Lifetime: NumberRange,
	Speed: NumberRange,
	Acceleration: Vector3,
	Drag: number,
	LightEmission: number,
	RotSpeed: NumberRange,
	Squash: NumberSequence,
}
local NO_SQUASH = NumberSequence.new(0)
local SHAPES: { [string]: Shape } = {
	Confetti = {
		Size = NumberSequence.new(0.35),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.2, 1.9),
		Speed = NumberRange.new(22, 40),
		Acceleration = Vector3.new(0, -22, 0),
		Drag = 2.5,
		LightEmission = 0.15,
		RotSpeed = NumberRange.new(-300, 300),
		Squash = NumberSequence.new(-0.6), -- flat little slips of paper
	},
	Stars = {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.2, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0, 0.3),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(14, 30),
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 3,
		LightEmission = 1,
		RotSpeed = NumberRange.new(-180, 180),
		Squash = NO_SQUASH,
	},
	Hearts = {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.6) }),
		Transparency = NumberSequence.new(0.1, 1),
		Lifetime = NumberRange.new(0.9, 1.5),
		Speed = NumberRange.new(8, 18),
		Acceleration = Vector3.new(0, 6, 0),
		Drag = 2,
		LightEmission = 0.6,
		RotSpeed = NumberRange.new(-60, 60),
		Squash = NO_SQUASH,
	},
	Bubbles = {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.85, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.8, 2.8),
		Speed = NumberRange.new(4, 10),
		Acceleration = Vector3.new(0, 7, 0),
		Drag = 1.2,
		LightEmission = 0.35,
		RotSpeed = NumberRange.new(0, 0),
		Squash = NO_SQUASH,
	},
	Mist = {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 7) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.5, 2.6),
		Speed = NumberRange.new(6, 14),
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 2,
		LightEmission = 0.25,
		RotSpeed = NumberRange.new(-90, 90),
		Squash = NO_SQUASH,
	},
}

local MAX_COLORS = 4 -- one emitter per colour (a particle keeps its emitter's colour)
type Rig = { Spot: Attachment, Emitters: { ParticleEmitter }, Shape: string? }
local rigs: { Rig } = {}
local nextRig = 1
local colorCache: { [Color3]: ColorSequence } = {}
local lowEnd = false
local fxFolder: Folder? = nil

local function makeRig(): Rig
	local spot = Instance.new("Attachment")
	spot.Name = "DefeatFx"
	spot.Parent = Workspace.Terrain
	local emitters = {}
	for i = 1, MAX_COLORS do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = `Fx{i}`
		emitter.Rate = 0
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Parent = spot
		emitters[i] = emitter
	end
	return { Spot = spot, Emitters = emitters, Shape = nil }
end

local function sequenceOf(color: Color3): ColorSequence
	local cached = colorCache[color]
	if not cached then
		cached = ColorSequence.new(color)
		colorCache[color] = cached
	end
	return cached
end

-- Hearts: a few pooled heart shapes (two balls and a turned square) that
-- float up, spin and fade, on top of the pink sparkles.
type Heart = { Root: Part, Parts: { Part }, Busy: boolean }
local hearts: { Heart } = {}
local HEART_SIZE = 1.4

local function heartPart(name: string, size: Vector3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	return p
end

local function makeHeart(): Heart
	local folder = fxFolder :: Folder
	local root = heartPart("Heart", Vector3.one * 0.1)
	root.Anchored = true
	local parts = {}
	local s = HEART_SIZE
	for i, side in { -1, 1 } do
		local lobe = heartPart(`Lobe{i}`, Vector3.one * s * 0.62, Enum.PartType.Ball)
		lobe.CFrame = root.CFrame * CFrame.new(side * s * 0.22, s * 0.12, 0)
		table.insert(parts, lobe)
	end
	local point = heartPart("Point", Vector3.new(s * 0.55, s * 0.55, s * 0.4))
	point.CFrame = root.CFrame * CFrame.new(0, -s * 0.16, 0) * CFrame.Angles(0, 0, math.rad(45))
	table.insert(parts, point)
	for _, p in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Massless = true
		p.Parent = root
	end
	root.Parent = folder
	return { Root = root, Parts = parts, Busy = false }
end

local function floatHearts(position: Vector3, colors: { Color3 })
	local cap = if lowEnd then Fx.HeartsLowEnd else Fx.Hearts
	local camera = Workspace.CurrentCamera
	local shown = 0
	for i = 1, cap do
		if shown >= math.ceil(cap / 2) then
			break
		end
		local heart = hearts[i]
		if not heart then
			heart = makeHeart()
			hearts[i] = heart
		end
		if not heart.Busy then
			heart.Busy = true
			shown += 1
			local color = colors[(shown - 1) % #colors + 1]
			local start = position + Vector3.new(math.random() * 6 - 3, math.random() * 2, math.random() * 6 - 3)
			local facing = CFrame.lookAt(start, Vector3.new(camera.CFrame.Position.X, start.Y, camera.CFrame.Position.Z))
			heart.Root.CFrame = facing
			for _, p in heart.Parts do
				p.Color = color
				p.Transparency = 0
				TweenService:Create(p, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			end
			local rise = TweenService:Create(heart.Root, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				CFrame = facing * CFrame.new(math.random() * 2 - 1, 6 + math.random() * 3, 0) * CFrame.Angles(0, math.rad(math.random(-40, 40)), 0),
			})
			rise.Completed:Connect(function()
				heart.Busy = false
			end)
			rise:Play()
		end
	end
end

-- A defeat effect (a Config.CosmeticItems "Defeat" id) at `position`.
function CosmeticsClient.DefeatBurst(id: string, position: Vector3)
	local item = Config.CosmeticFor("Defeat", id)
	local defeat = item and item.Defeat
	if not defeat then
		return
	end
	local shape = SHAPES[defeat.Shape] or SHAPES.Confetti
	local rig = rigs[nextRig]
	if not rig then
		rig = makeRig()
		rigs[nextRig] = rig
	end
	nextRig = nextRig % Fx.Rigs + 1
	rig.Spot.WorldPosition = position
	if rig.Shape ~= defeat.Shape then
		rig.Shape = defeat.Shape
		for _, emitter in rig.Emitters do
			emitter.Size = shape.Size
			emitter.Transparency = shape.Transparency
			emitter.Lifetime = shape.Lifetime
			emitter.Speed = shape.Speed
			emitter.Acceleration = shape.Acceleration
			emitter.Drag = shape.Drag
			emitter.LightEmission = shape.LightEmission
			emitter.RotSpeed = shape.RotSpeed
			emitter.Squash = shape.Squash
		end
	end
	local colors = defeat.Colors
	local count = math.max(#colors, 1)
	local total = if lowEnd then math.ceil(defeat.Count / 2) else defeat.Count
	for i = 1, math.min(count, MAX_COLORS) do
		local emitter = rig.Emitters[i]
		emitter.Color = sequenceOf(colors[i] or Color3.new(1, 1, 1))
		emitter:Emit(math.ceil(total / count))
	end
	if defeat.Shape == "Hearts" and fxFolder then
		floatHearts(position, colors)
	end
end

function CosmeticsClient.Init()
	lowEnd = SkyController.LowEnd()
	local folder = Instance.new("Folder")
	folder.Name = "CosmeticFx"
	folder.Parent = Workspace
	fxFolder = folder
	local localPlayer = Players.LocalPlayer
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Fx.Remote) :: RemoteEvent
	remote.OnClientEvent:Connect(function(hunter: Player, id: unknown, position: unknown)
		if hunter == localPlayer or type(id) ~= "string" or typeof(position) ~= "Vector3" then
			return
		end
		local camera = Workspace.CurrentCamera
		if (camera.CFrame.Position - position).Magnitude <= Fx.Range then
			CosmeticsClient.DefeatBurst(id, position)
		end
	end)
end

return CosmeticsClient
