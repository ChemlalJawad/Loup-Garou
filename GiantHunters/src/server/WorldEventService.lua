--!strict
-- World events: something happening out in the land now and then, one at a
-- time, with a global cooldown (Config.WorldEvents.Cooldown) and never
-- while someone on the server is still doing the tutorial. Announced in the
-- feed, and shown on the big map (Config.Remotes.WorldEvent: ("Event",
-- info) to everyone, nil when it's over).
--
--   * Supply Drop: a crate floats down on a balloon somewhere outside the
--     wall. Once it lands it's a supply crate (gas and blades, key R), and
--     the first hunter to reach it - and everyone else who gets there in
--     the next few seconds - shares some Marks.
--   * Wandering Merchant: a cart parks on a road for a few minutes, selling
--     one random gear set or technique at a discount (bought through
--     ShopService.BuyAt: level, Marks and ownership are all checked there).
--   * Golden Giant (only during a wave): a shining giant joins the wave;
--     when it goes down, everyone who landed a cut on it gets Marks.
--   * Signal Beacons: three beacons across the land; light them all
--     (touch them) before time runs out for a reward for the whole server.
--
-- Everything is checked on the server from where the hunters really are.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local Motion = require(script.Parent.Motion)
local GiantService = require(script.Parent.GiantService)
local WaveService = require(script.Parent.WaveService)
local HunterService = require(script.Parent.HunterService)
local LevelService = require(script.Parent.LevelService)
local ProgressService = require(script.Parent.ProgressService)
local ShopService = require(script.Parent.ShopService)
local Broadcast = require(script.Parent.Broadcast)

local WorldEventService = {}

-- What the clients get: Kind, Name, Text, Positions, EndsAt (server time),
-- Lit (beacons).
export type Info = {
	Kind: string,
	Name: string,
	Text: string,
	Positions: { Vector3 },
	EndsAt: number?,
	Lit: { boolean }?,
}

local E = Config.WorldEvents
local W = Config.World

local remote: RemoteEvent
local folder: Folder
local current: Info? = nil
local rng = Random.new()
local waveOn = false

local function publish(info: Info?)
	current = info
	Workspace:SetAttribute("WorldEvent", if info then info.Kind else "")
	remote:FireAllClients("Event", info)
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- (Same rule as the weather: not while anyone is learning the ropes.)
local function tutorialRunning(): boolean
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("TutorialDone") ~= true then
			return true
		end
	end
	return false
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and Motion.Trusted(player) and player:GetAttribute("DataLoaded") == true then
		return root
	end
	return nil
end

local function reward(player: Player, marks: number, xp: number, why: string)
	ProgressService.GrantMarks(player, marks)
	LevelService.Add(player, xp, why)
end

-- "to the south-east" of the town centre.
local function direction(p: Vector3): string
	local names = { "south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west" }
	local index = math.round(Geo.AngleOf(p) / (math.pi / 4)) % 8
	return names[index + 1]
end

-- === Building bits ===========================================================

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function label(parent: BasePart, text: string, color: Color3, height: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 700
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.Parent = parent
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Text = text
	text_.TextScaled = true
	text_.TextColor3 = color
	text_.TextStrokeTransparency = 0.3
	text_.Font = Enum.Font.GothamBlack
	text_.Parent = gui
	return text_
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

-- The ground (or a roof) at (x, z).
local function groundAt(x: number, z: number): RaycastResult?
	return Workspace:Raycast(Vector3.new(x, 700, z), Vector3.new(0, -900, 0), rayParams)
end

-- A clear, dry spot on the open land outside the wall, between `inner` and
-- `outer` studs from the centre, near `angle` (random if nil).
local function outsideSpot(inner: number, outer: number, angle: number?): Vector3?
	for _ = 1, 24 do
		local a = (angle or rng:NextNumber(0, math.pi * 2)) + (if angle then rng:NextNumber(-0.35, 0.35) else 0)
		local p = Geo.Polar(a, rng:NextNumber(inner, outer))
		if not Geo.InRiver(p.X, p.Z, 30) and not Geo.InCastleHill(p, 20) then
			local hit = groundAt(p.X, p.Z)
			if hit and hit.Material ~= Enum.Material.Water and hit.Normal.Y > 0.75 and hit.Position.Y < 60 then
				return hit.Position
			end
		end
	end
	return nil
end

-- Hunters within `reach` of `p` (flat, and not too far above or below).
local function huntersNear(p: Vector3, reach: number, rise: number): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local d = root.Position - p
			if Vector3.new(d.X, 0, d.Z).Magnitude <= reach and math.abs(d.Y) <= rise then
				table.insert(out, player)
			end
		end
	end
	return out
end

-- === Supply Drop =============================================================

local function supplyDrop()
	local S = E.SupplyDrop
	local spot = outsideSpot(W.WallRadius + W.WallThickness + 80, W.LandRadius - 220)
	if not spot then
		return
	end
	local landed = spot :: Vector3
	local model = Instance.new("Model")
	model.Name = "SupplyDrop"
	local crate = part(model, {
		Name = "Crate",
		Size = Vector3.new(6, 5, 6),
		CFrame = CFrame.new(landed + Vector3.new(0, S.StartHeight, 0)),
		Color = Color3.fromRGB(120, 86, 52),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})
	local band = part(model, { Name = "Band", Size = Vector3.new(6.2, 0.8, 6.2), CFrame = crate.CFrame, Color = Color3.fromRGB(110, 210, 255), Material = Enum.Material.Neon, Anchored = false })
	local rope = part(model, { Name = "Rope", Size = Vector3.new(0.3, 14, 0.3), CFrame = crate.CFrame * CFrame.new(0, 9.5, 0), Color = Color3.fromRGB(220, 210, 180), Anchored = false })
	local balloon = part(model, { Name = "Balloon", Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12), CFrame = crate.CFrame * CFrame.new(0, 21, 0), Color = Color3.fromRGB(230, 70, 70), Anchored = false })
	for _, piece in { band, rope, balloon } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = crate
		weld.Part1 = piece
		weld.Parent = piece
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(140, 220, 255)
	light.Range = 18
	light.Parent = crate
	local sign = label(crate, "SUPPLY DROP", Color3.fromRGB(140, 220, 255), 10)
	model.PrimaryPart = crate
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = folder

	local where = direction(landed)
	local info: Info = {
		Kind = "SupplyDrop",
		Name = "Supply Drop",
		Text = `A supply crate is floating down to the {where}!`,
		Positions = { landed },
		EndsAt = now() + S.FallTime + S.WaitLanded,
	}
	publish(info)
	Broadcast.Feed(`SUPPLY DROP: a crate is floating down to the {where} - be the first there!`, "Gold")

	local tween = TweenService:Create(crate, TweenInfo.new(S.FallTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = CFrame.new(landed + Vector3.new(0, 2.5, 0)) })
	tween:Play()
	task.wait(S.FallTime)
	rope:Destroy()
	balloon:Destroy()
	sign.Text = "SUPPLIES!"
	CollectionService:AddTag(crate, Config.Tags.Supply) -- (a resupply prompt, from HunterService)

	-- Waiting for the first hunter...
	local deadline = os.clock() + S.WaitLanded
	local winners: { [Player]: boolean } = {}
	local windowEnds: number? = nil
	while os.clock() < (windowEnds or deadline) do
		for _, player in huntersNear(crate.Position, S.Reach, 20) do
			if not winners[player] then
				winners[player] = true
				reward(player, S.Marks, S.XP, "SupplyDrop")
				if not windowEnds then
					windowEnds = os.clock() + S.Window
					Broadcast.Feed(`{player.DisplayName} reached the supply drop first! {S.Window} seconds for everyone else to share it`, "Gold")
					info.EndsAt = now() + S.Window
					publish(info)
				end
				Broadcast.Announce("SUPPLY DROP!", `+{S.Marks} Marks - grab gas & blades at the crate`, "Gold", player)
			end
		end
		task.wait(0.25)
	end
	publish(nil)
	if not windowEnds then
		Broadcast.Feed("Nobody reached the supply drop in time...", "Info")
	end
	task.delay(S.LingerAfter, function()
		model:Destroy()
	end)
end

-- === Wandering Merchant ======================================================

local function roadSpot(): Vector3?
	local ok, layout = pcall(function(): any
		return require(script.Parent.World.Layout)
	end)
	local candidates: { Vector3 } = {}
	if ok and type(layout) == "table" and type(layout.Roads) == "table" then
		for _, road in layout.Roads do
			if type(road) == "table" then
				for i = 1, #road - 1 do
					local a, b = road[i], road[i + 1]
					if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
						table.insert(candidates, a:Lerp(b, rng:NextNumber(0.25, 0.75)))
					end
				end
			end
		end
	end
	table.insert(candidates, Vector3.new(0, 0, W.WallRadius + 140)) -- (the road south from the gate)
	for _ = 1, 8 do
		local p = candidates[rng:NextInteger(1, #candidates)]
		local hit = groundAt(p.X + 6, p.Z)
		if hit and hit.Material ~= Enum.Material.Water and not Geo.InRiver(p.X, p.Z, 20) then
			return hit.Position
		end
	end
	return nil
end

local function pickOffer(): Config.CatalogItem?
	local items: { Config.CatalogItem } = {}
	for _, item in Config.Catalog do
		if item.Price > 0 and (item.Category == "Gear" or item.Category == "Technique") then
			table.insert(items, item)
		end
	end
	table.sort(items, function(a, b)
		return a.Id < b.Id
	end)
	return if #items > 0 then items[rng:NextInteger(1, #items)] else nil
end

local function merchant()
	local M = E.Merchant
	local spot = roadSpot()
	local item = pickOffer()
	if not spot or not item then
		return
	end
	local offer = item :: Config.CatalogItem
	local price = math.max(math.floor(offer.Price * (1 - M.Discount)), 1)
	local model = Instance.new("Model")
	model.Name = "MerchantCart"
	local here = CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local wood, cloth = Color3.fromRGB(122, 84, 52), Color3.fromRGB(200, 70, 60)
	local bed = part(model, { Name = "Bed", Size = Vector3.new(9, 1.2, 5.5), CFrame = here * CFrame.new(0, 3, 0), Color = wood, Material = Enum.Material.WoodPlanks, CanCollide = true })
	for _, x in { -3.2, 3.2 } do
		for _, z in { -2.9, 2.9 } do
			part(model, { Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3.6, 3.6), CFrame = here * CFrame.new(x, 1.8, z) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(70, 50, 34), Material = Enum.Material.Wood })
		end
	end
	for _, x in { -4, 4 } do
		for _, z in { -2.4, 2.4 } do
			part(model, { Name = "Post", Size = Vector3.new(0.4, 5, 0.4), CFrame = here * CFrame.new(x, 6, z), Color = wood })
		end
	end
	-- A striped canopy.
	for i = 0, 4 do
		part(model, { Name = "Canopy", Size = Vector3.new(1.8, 0.3, 6.2), CFrame = here * CFrame.new(-3.6 + i * 1.8, 8.6, 0), Color = if i % 2 == 0 then cloth else Color3.fromRGB(245, 232, 200), Material = Enum.Material.Fabric })
	end
	part(model, { Name = "Goods", Size = Vector3.new(2.4, 1.6, 2), CFrame = here * CFrame.new(-2, 4.4, 0), Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.WoodPlanks })
	part(model, { Name = "Goods", Size = Vector3.new(1.6, 1.2, 1.6), CFrame = here * CFrame.new(1.5, 4.2, 0.8), Color = Color3.fromRGB(70, 110, 170), Material = Enum.Material.Fabric })
	local lantern = part(model, { Name = "Lantern", Size = Vector3.new(0.8, 1, 0.8), CFrame = here * CFrame.new(4, 7.6, 2.4), Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 16
	light.Parent = lantern
	label(bed, `MERCHANT: {offer.Display}  {price} Marks`, Color3.fromRGB(255, 220, 140), 9)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = `Buy {offer.Display}`
	prompt.ObjectText = `{price} Marks (was {offer.Price})`
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = M.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Config.Prompts.Key
	prompt.GamepadKeyCode = Config.Prompts.Gamepad
	prompt.Parent = bed
	local busy: { [Player]: boolean } = {}
	prompt.Triggered:Connect(function(player: Player)
		if busy[player] then
			return
		end
		busy[player] = true
		local hadIt = ShopService.Owns(player, offer.Category, offer.Id)
		if ShopService.BuyAt(player, offer.Category, offer.Id, price) and not hadIt then
			Broadcast.Announce("A BARGAIN!", `{offer.Display} for {price} Marks - wear it from the shop`, "Gold", player)
		end
		task.delay(1, function()
			busy[player] = nil
		end)
	end)
	model.PrimaryPart = bed
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = folder

	local where = direction(spot)
	publish({
		Kind = "Merchant",
		Name = "Wandering Merchant",
		Text = `{offer.Display} for {price} Marks (was {offer.Price}), on the road to the {where}`,
		Positions = { spot },
		EndsAt = now() + M.Duration,
	})
	Broadcast.Feed(`A WANDERING MERCHANT is on the road to the {where}: {offer.Display} for {price} Marks!`, "Gold")
	task.wait(M.Duration)
	publish(nil)
	Broadcast.Feed("The wandering merchant has rattled off down the road.", "Info")
	model:Destroy()
end

-- === Golden Giant ============================================================

local function gild(model: Model)
	local G = E.GoldenGiant
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Material ~= Enum.Material.Neon then
			d.Color = d.Color:Lerp(G.Color, 0.8)
			d.Material = Enum.Material.Foil
			d.Reflectance = 0.15
		end
	end
	local root = model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Color = G.Color
		light.Range = 40
		light.Brightness = 2
		light.Parent = root
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 236, 160))
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Lifetime = NumberRange.new(1, 1.8)
		sparkle.Speed = NumberRange.new(2, 6)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = 14
		sparkle.Parent = root
	end
	model:SetAttribute("Golden", true)
end

local function goldenGiant()
	local G = E.GoldenGiant
	local model = GiantService.SpawnGiant(G.Kind)
	gild(model)
	local hitters: { [Player]: boolean } = {}
	local connection = HunterService.Slashed.Event:Connect(function(player: Player, outcome: string, info: any)
		if outcome == "NoTarget" or outcome == "Training" or type(info) ~= "table" or typeof(info.Position) ~= "Vector3" or not model.Parent then
			return
		end
		local frame, size = model:GetBoundingBox()
		local rel = frame:PointToObjectSpace(info.Position)
		if math.abs(rel.X) <= size.X / 2 + 4 and math.abs(rel.Y) <= size.Y / 2 + 4 and math.abs(rel.Z) <= size.Z / 2 + 4 then
			hitters[player] = true
		end
	end)
	local function where(): Vector3
		local root = model:FindFirstChild("Root")
		return if root and root:IsA("BasePart") then root.Position else model:GetPivot().Position
	end
	local info: Info = { Kind = "GoldenGiant", Name = "Golden Giant", Text = "A shining giant joined the wave! Everyone who cuts it shares the prize.", Positions = { where() } }
	publish(info)
	Broadcast.Announce("A GOLDEN GIANT!", "Everyone who lands a cut on it shares the prize when it goes down", "Gold")
	Broadcast.Feed("A GOLDEN GIANT has joined the wave!", "Gold")
	local started = os.clock()
	while model.Parent and model:GetAttribute("Defeated") ~= true and os.clock() - started < 600 do
		task.wait(2)
		info.Positions = { where() }
		publish(info)
	end
	connection:Disconnect()
	publish(nil)
	if model:GetAttribute("Defeated") == true then
		local names = {}
		for player in hitters do
			if player.Parent then
				reward(player, G.Marks, G.XP, "GoldenGiant")
				Broadcast.Announce("GOLDEN GIANT DOWN!", `+{G.Marks} Marks for your part`, "Gold", player)
				table.insert(names, player.DisplayName)
			end
		end
		Broadcast.Feed(if #names > 0 then `The Golden Giant is down! Shared by {table.concat(names, ", ")}` else "The Golden Giant is down!", "Gold")
	else
		Broadcast.Feed("The Golden Giant slipped away...", "Info")
	end
end

-- === Signal Beacons ==========================================================

type Beacon = { Model: Model, Bowl: BasePart, Base: Vector3, Lit: boolean, By: Player? }

local function buildBeacon(spot: Vector3): Beacon
	local model = Instance.new("Model")
	model.Name = "SignalBeacon"
	local stone = Color3.fromRGB(130, 126, 118)
	part(model, { Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 9, 9), CFrame = CFrame.new(spot + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = stone, Material = Enum.Material.Slate, CanCollide = true })
	part(model, { Name = "Post", Size = Vector3.new(2.4, 16, 2.4), CFrame = CFrame.new(spot + Vector3.new(0, 11, 0)), Color = Color3.fromRGB(96, 70, 48), Material = Enum.Material.Wood, CanCollide = true })
	local bowl = part(model, { Name = "Bowl", Size = Vector3.new(6, 1.6, 6), CFrame = CFrame.new(spot + Vector3.new(0, 19.6, 0)), Color = Color3.fromRGB(60, 56, 54), Material = Enum.Material.Metal, CanCollide = true })
	label(bowl, "BEACON", Color3.fromRGB(255, 190, 110), 6)
	model.PrimaryPart = bowl
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = folder
	return { Model = model, Bowl = bowl, Base = spot, Lit = false, By = nil }
end

local function light(beacon: Beacon)
	beacon.Lit = true
	beacon.Bowl.Color = Color3.fromRGB(255, 150, 60)
	beacon.Bowl.Material = Enum.Material.Neon
	local fire = Instance.new("Fire")
	fire.Size = 9
	fire.Heat = 12
	fire.Parent = beacon.Bowl
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 170, 80)
	glow.Range = 40
	glow.Brightness = 2
	glow.Parent = beacon.Bowl
	local gui = beacon.Bowl:FindFirstChildOfClass("BillboardGui")
	local text = gui and gui:FindFirstChildOfClass("TextLabel")
	if text then
		text.Text = "LIT!"
	end
end

local function beacons()
	local B = E.Beacons
	local list: { Beacon } = {}
	local start = rng:NextNumber(0, math.pi * 2)
	for i = 1, B.Count do
		local spot = outsideSpot(B.Radius[1], B.Radius[2], start + (i - 1) * math.pi * 2 / B.Count)
		if spot then
			table.insert(list, buildBeacon(spot))
		end
	end
	if #list == 0 then
		return
	end
	local started = os.clock()
	local function infoNow(): Info
		local positions, lit = {}, {}
		for _, beacon in list do
			table.insert(positions, beacon.Base)
			table.insert(lit, beacon.Lit)
		end
		return {
			Kind = "Beacons",
			Name = "Signal Beacons",
			Text = `Light all {#list} beacons before time runs out - touch each one!`,
			Positions = positions,
			Lit = lit,
			EndsAt = now() + B.Duration - (os.clock() - started),
		}
	end
	publish(infoNow())
	Broadcast.Announce("SIGNAL BEACONS!", `Light all {#list} beacons across the land in {B.Duration // 60} minutes - the whole server shares the reward`, "Gold")
	Broadcast.Feed(`SIGNAL BEACONS: light all {#list} before time runs out!`, "Gold")
	local litCount = 0
	local lighters: { [Player]: number } = {}
	while os.clock() - started < B.Duration and litCount < #list do
		for _, beacon in list do
			if not beacon.Lit then
				local who = huntersNear(beacon.Base, B.Reach, 26)[1]
				if who then
					light(beacon)
					litCount += 1
					lighters[who] = (lighters[who] or 0) + 1
					Broadcast.Feed(`{who.DisplayName} lit a beacon! ({litCount}/{#list})`, "Good")
					publish(infoNow())
				end
			end
		end
		task.wait(0.25)
	end
	publish(nil)
	if litCount >= #list then
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("DataLoaded") == true then
				local extra = (lighters[player] or 0) * B.LighterMarks
				reward(player, B.Marks + extra, B.XP, "Beacons")
				Broadcast.Announce("ALL BEACONS LIT!", `+{B.Marks + extra} Marks for everyone's teamwork`, "Gold", player)
			end
		end
		Broadcast.Feed("Every signal beacon is burning bright - well done, hunters!", "Gold")
	else
		Broadcast.Feed(`The beacons went out ({litCount}/{#list} lit). Next time!`, "Info")
	end
	task.delay(if litCount >= #list then 30 else 5, function()
		for _, beacon in list do
			beacon.Model:Destroy()
		end
	end)
end

-- === The loop ================================================================

local RUNNERS: { [string]: () -> () } = {
	SupplyDrop = supplyDrop,
	Merchant = merchant,
	GoldenGiant = goldenGiant,
	Beacons = beacons,
}

local function pick(): string?
	local total = 0
	local options: { { Kind: string, Weight: number } } = {}
	for kind, weight in E.Weights :: { [string]: number } do
		local allowed = RUNNERS[kind] ~= nil
		if kind == "GoldenGiant" then
			allowed = waveOn and GiantService.AliveCount() > 0 and GiantService.AliveCount() < Config.Waves.MaxAlive
		end
		if allowed and weight > 0 then
			total += weight
			table.insert(options, { Kind = kind, Weight = weight })
		end
	end
	table.sort(options, function(a, b)
		return a.Kind < b.Kind
	end)
	local roll = rng:NextNumber(0, total)
	for _, option in options do
		roll -= option.Weight
		if roll <= 0 then
			return option.Kind
		end
	end
	return nil
end

-- What's on now (nil: nothing).
function WorldEventService.Current(): Info?
	return current
end

function WorldEventService.Init()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.WorldEvent) :: RemoteEvent
	folder = Instance.new("Folder")
	folder.Name = "WorldEvents"
	folder.Parent = Workspace
	rayParams.FilterDescendantsInstances = { folder }
	Workspace:SetAttribute("WorldEvent", "")

	WaveService.WaveStarted.Event:Connect(function()
		waveOn = true
	end)
	for _, event in { WaveService.RoundStarted, WaveService.RoundEnded, WaveService.DistrictFallen } do
		event.Event:Connect(function()
			waveOn = false
		end)
	end

	local nextSync: { [Player]: number } = {}
	remote.OnServerEvent:Connect(function(player: Player, action: unknown)
		local t = os.clock()
		if action == "Sync" and t >= (nextSync[player] or 0) then
			nextSync[player] = t + 1
			remote:FireClient(player, "Event", current)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		nextSync[player] = nil
	end)

	task.spawn(function()
		task.wait(E.FirstDelay)
		while true do
			if #Players:GetPlayers() == 0 or tutorialRunning() then
				task.wait(15)
				continue
			end
			local kind = pick()
			local run = kind and RUNNERS[kind]
			if run then
				local ok, err = pcall(run :: any)
				if not ok then
					warn(`[WorldEventService] {kind} failed: {err}`)
					publish(nil)
				end
			end
			task.wait(rng:NextNumber(E.Cooldown[1], E.Cooldown[2]))
		end
	end)
end

return WorldEventService
