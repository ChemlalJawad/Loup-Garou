--!strict
-- The big map (M, the d-pad's right, or the MAP button on touch screens)
-- and the Lost Journal (its JOURNAL tab).
--
-- MAP: a top-down, stylised drawing of the whole land, north up: the hills
-- and the land, the regions and roads (sent by the server from its
-- Layout), the river and its pools, the town with its ring roads and
-- avenues, the Great Wall and the gate, the castle hill. On top: the named
-- places (gold with their name once discovered, a grey "?" until then),
-- you (an arrow that turns with you), the other hunters, giants within
-- Config.Discovery.GiantRange of you (like a long radar: fair), supply
-- crates nearby, and the world event that's on (a pulsing star).
-- Everything is placed by scale, so it fits any screen; the markers move
-- five times a second, and only while the map is open.
--
-- JOURNAL: the Lost Journal pages found so far, to read; the rest are
-- blank until found. The server decides everything (DiscoveryService,
-- JournalService, WorldEventService); this only shows it. It also hides
-- the journal books this hunter has already picked up.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local TouchButtons = require(script.Parent.TouchButtons)

local MapScreen = {}

local player = Players.LocalPlayer
local W = Config.World
local D = Config.Discovery
local EXTENT = W.EdgeRadius -- studs from the centre to the map's edge

local INK = Color3.fromRGB(22, 24, 32)
local PANEL = Color3.fromRGB(34, 37, 48)
local ROW = Color3.fromRGB(44, 48, 62)
local BRASS = Color3.fromRGB(214, 186, 120)
local TEXT = Color3.fromRGB(236, 238, 245)
local MUTED = Color3.fromRGB(156, 162, 178)
local GOLD = Color3.fromRGB(255, 210, 90)

type State = {
	Pois: { { Id: string, Name: string, Kind: string, X: number, Z: number } },
	Found: { [string]: boolean },
	Journals: { [string]: boolean },
	JournalCount: number,
	Map: { Roads: { { number } }, Regions: { { Name: string, Angle: number, Spread: number, Inner: number, Outer: number } } }?,
}

local state: State? = nil
local event: { [string]: any }? = nil
local open = false
local tab = "Map"

local gui: ScreenGui
local panel: Frame
local canvas: Frame -- the square map
local staticLayer: Frame
local poiLayer: Frame
local liveLayer: Frame
local journalPage: ScrollingFrame
local header: TextLabel
local tabButtons: { [string]: TextButton } = {}
local drawnMap: any = nil -- the Map table last drawn

local function new(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

local function corner(parent: Instance, radius: UDim?)
	new("UICorner", { CornerRadius = radius or UDim.new(0, 8), Parent = parent })
end

-- World (x, z) -> the canvas (0..1 each way; north, -Z, is up).
local function toMap(x: number, z: number): (number, number)
	return 0.5 + x / (2 * EXTENT), 0.5 + z / (2 * EXTENT)
end

local function disc(parent: Instance, x: number, z: number, radius: number, color: Color3, transparency: number?, z_: number?): Frame
	local u, v = toMap(x, z)
	local size = radius / EXTENT
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(u, v),
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = z_ or 1,
		Parent = parent,
	})
	corner(f, UDim.new(1, 0))
	return f
end

local function ring(parent: Instance, radius: number, color: Color3, thickness: number, z_: number?): Frame
	local f = disc(parent, 0, 0, radius, color, 1, z_)
	new("UIStroke", { Color = color, Thickness = thickness, Parent = f })
	return f
end

-- A straight line between two world points (thickness in pixels).
local function line(parent: Instance, x1: number, z1: number, x2: number, z2: number, color: Color3, thickness: number, z_: number?)
	local u1, v1 = toMap(x1, z1)
	local u2, v2 = toMap(x2, z2)
	local du, dv = u2 - u1, v2 - v1
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((u1 + u2) / 2, (v1 + v2) / 2),
		Size = UDim2.new(math.sqrt(du * du + dv * dv), thickness * 0.6, 0, thickness),
		Rotation = math.deg(math.atan2(dv, du)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z_ or 2,
		Parent = parent,
	})
end

local function mapLabel(parent: Instance, x: number, z: number, text: string, color: Color3, size: number, z_: number?, offsetY: number?): TextLabel
	local u, v = toMap(x, z)
	return new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(u, 0, v, offsetY or 0),
		Size = UDim2.fromOffset(160, size + 4),
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = color,
		TextStrokeTransparency = 0.35,
		TextStrokeColor3 = INK,
		Font = Enum.Font.GothamBold,
		ZIndex = z_ or 6,
		Parent = parent,
	})
end

-- === The static drawing ======================================================

local function regionColor(name: string): Color3
	local lower = string.lower(name)
	if string.find(lower, "forest") then
		return Color3.fromRGB(46, 92, 52)
	elseif string.find(lower, "farm") then
		return Color3.fromRGB(176, 156, 86)
	elseif string.find(lower, "train") then
		return Color3.fromRGB(150, 122, 84)
	end
	return Color3.fromRGB(120, 140, 100)
end

local function drawStatic()
	staticLayer:ClearAllChildren()
	local map = state and state.Map
	drawnMap = map
	-- The hills, then the land.
	disc(staticLayer, 0, 0, W.EdgeRadius, Color3.fromRGB(70, 86, 62), 0, 1)
	disc(staticLayer, 0, 0, W.LandRadius - 60, Color3.fromRGB(104, 138, 82), 0, 1)
	-- Regions (a soft blob at the middle of each sector, and its name).
	if map then
		for _, region in map.Regions do
			local mid = (region.Inner + region.Outer) / 2
			local p = Geo.Polar(region.Angle, mid)
			local radius = math.min((region.Outer - region.Inner) / 2, mid * region.Spread) * 1.1
			disc(staticLayer, p.X, p.Z, radius, regionColor(region.Name), 0.35, 1)
			mapLabel(staticLayer, p.X, p.Z, string.upper(region.Name), Color3.fromRGB(230, 236, 214), 11, 3)
		end
	end
	-- The castle hill.
	local castle = Geo.CastleCentre()
	disc(staticLayer, castle.X, castle.Z, W.Castle.HillRadius, Color3.fromRGB(128, 120, 96), 0, 2)
	-- Roads outside the wall.
	local road = Color3.fromRGB(196, 170, 120)
	if map then
		for _, points in map.Roads do
			for i = 1, #points - 3, 2 do
				line(staticLayer, points[i], points[i + 1], points[i + 2], points[i + 3], road, 3, 2)
			end
		end
	end
	-- The river and its pools.
	local water = Color3.fromRGB(70, 140, 200)
	local reach = W.River.Reach
	local step = 50
	local x = -reach
	while x < reach do
		local x2 = math.min(x + step, reach)
		line(staticLayer, x, Geo.RiverZ(x), x2, Geo.RiverZ(x2), water, 5, 3)
		x = x2
	end
	for _, side in { -1, 1 } do
		disc(staticLayer, side * reach, Geo.RiverZ(side * reach), W.River.PoolRadius, water, 0, 3)
	end
	-- The town inside the wall: paving, ring roads, avenues, the plaza.
	disc(staticLayer, 0, 0, W.WallRadius, Color3.fromRGB(150, 140, 126), 0, 4)
	for _, radius in W.RingRoads do
		ring(staticLayer, radius, Color3.fromRGB(196, 186, 166), 2, 5)
	end
	for _, degrees in W.AvenueAngles do
		local a = Geo.Polar(math.rad(degrees), W.PlazaRadius)
		local b = Geo.Polar(math.rad(degrees), W.PerimeterRoad)
		line(staticLayer, a.X, a.Z, b.X, b.Z, Color3.fromRGB(196, 186, 166), 2, 5)
	end
	disc(staticLayer, 0, 0, W.PlazaRadius, Color3.fromRGB(206, 196, 176), 0, 5)
	-- The river through town, again on top of the paving.
	x = -W.WallRadius
	while x < W.WallRadius do
		local x2 = x + 40
		line(staticLayer, x, Geo.RiverZ(x), x2, Geo.RiverZ(x2), water, 4, 6)
		x = x2
	end
	-- The Great Wall and the south gate.
	ring(staticLayer, W.WallRadius + W.WallThickness / 2, Color3.fromRGB(60, 58, 56), 4, 7)
	local gate = Geo.Polar(W.GateAngle, W.WallRadius + W.WallThickness / 2)
	disc(staticLayer, gate.X, gate.Z, 22, Color3.fromRGB(255, 220, 90), 0, 8)
	mapLabel(staticLayer, gate.X, gate.Z, "GATE", Color3.fromRGB(255, 230, 140), 10, 8, 12)
	-- North.
	mapLabel(staticLayer, 0, -W.EdgeRadius + 70, "N", TEXT, 16, 8)
end

-- === Places ==================================================================

local function drawPois()
	poiLayer:ClearAllChildren()
	local s = state
	if not s then
		return
	end
	for _, poi in s.Pois do
		local found = s.Found[poi.Id] == true
		disc(poiLayer, poi.X, poi.Z, 16, if found then GOLD else Color3.fromRGB(150, 150, 150), 0, 9)
		if found then
			mapLabel(poiLayer, poi.X, poi.Z, poi.Name, GOLD, 12, 10, -13)
		else
			mapLabel(poiLayer, poi.X, poi.Z, "?", Color3.fromRGB(220, 220, 220), 14, 10, -13)
		end
	end
end

-- === Live markers (pooled) ===================================================

type Pool = { Items: { GuiObject }, Used: number, Make: () -> GuiObject }

local function pool(make: () -> GuiObject): Pool
	return { Items = {}, Used = 0, Make = make }
end

local function take(p: Pool): GuiObject
	p.Used += 1
	local item = p.Items[p.Used]
	if not item then
		item = p.Make()
		p.Items[p.Used] = item
	end
	item.Visible = true
	return item
end

local function finish(p: Pool)
	for i = p.Used + 1, #p.Items do
		p.Items[i].Visible = false
	end
	p.Used = 0
end

local function dot(color: Color3, size: number, round: boolean, z_: number): () -> GuiObject
	return function()
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z_,
			Parent = liveLayer,
		})
		if round then
			corner(f, UDim.new(1, 0))
		end
		new("UIStroke", { Color = INK, Thickness = 1, Parent = f })
		return f
	end
end

local hunters: Pool
local giants: Pool
local goldens: Pool
local crates: Pool
local events: Pool
local me: TextLabel
local eventLabel: TextLabel
local cratePositions: { Vector3 } = {}
local nextCrates = 0

local function place(item: GuiObject, p: Vector3)
	local u, v = toMap(p.X, p.Z)
	item.Position = UDim2.fromScale(u, v)
end

local function rootOf(model: Instance?): BasePart?
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Root"))
	return if root and root:IsA("BasePart") then root else nil
end

local function updateLive()
	local myRoot = rootOf(player.Character)
	local here = if myRoot then myRoot.Position else nil
	-- You.
	if myRoot then
		me.Visible = true
		place(me, myRoot.Position)
		local look = myRoot.CFrame.LookVector
		me.Rotation = math.deg(math.atan2(look.X, -look.Z))
	else
		me.Visible = false
	end
	-- Other hunters.
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local root = rootOf(other.Character)
			if root then
				place(take(hunters), root.Position)
			end
		end
	end
	finish(hunters)
	-- Giants near you (the Golden Giant shows from anywhere, as an event).
	for _, giant in CollectionService:GetTagged(Config.Tags.Giant) do
		local root = rootOf(giant)
		if root and giant:GetAttribute("Defeated") ~= true then
			local golden = giant:GetAttribute("Golden") == true
			if golden then
				place(take(goldens), root.Position)
			elseif here and Geo.Flat(root.Position - here).Magnitude <= D.GiantRange then
				place(take(giants), root.Position)
			end
		end
	end
	finish(giants)
	finish(goldens)
	-- Supply crates (the ones streamed in near you), refreshed now and then.
	local now = os.clock()
	if now >= nextCrates then
		nextCrates = now + 2
		cratePositions = {}
		for _, crate in CollectionService:GetTagged(Config.Tags.Supply) do
			if crate:IsA("BasePart") then
				table.insert(cratePositions, crate.Position)
			end
		end
	end
	for _, p in cratePositions do
		place(take(crates), p)
	end
	finish(crates)
	-- The world event.
	local e = event
	if e and type(e.Positions) == "table" then
		local pulse = 1 + 0.25 * math.sin(now * 6)
		for i, p in e.Positions :: { Vector3 } do
			if typeof(p) == "Vector3" then
				local star = take(events) :: TextLabel
				place(star, p)
				local lit = type(e.Lit) == "table" and e.Lit[i] == true
				star.TextColor3 = if lit then Color3.fromRGB(255, 150, 60) else GOLD
				star.Size = UDim2.fromOffset(26 * pulse, 26 * pulse)
			end
		end
		local left = if type(e.EndsAt) == "number" then math.max(math.floor(e.EndsAt - Workspace:GetServerTimeNow()), 0) else nil
		eventLabel.Text = `★ {string.upper(tostring(e.Name))}: {tostring(e.Text)}` .. (if left then `  ({left // 60}:{string.format("%02d", left % 60)})` else "")
		eventLabel.Visible = true
	else
		eventLabel.Visible = false
	end
	finish(events)
end

-- === The journal =============================================================

local function renderJournal()
	for _, child in journalPage:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local s = state
	local found = 0
	for i, page in Config.Journals.Pages do
		local have = s ~= nil and s.Journals[page.Id] == true
		if have then
			found += 1
		end
		local card = new("Frame", {
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = if have then ROW else PANEL,
			LayoutOrder = i,
			Parent = journalPage,
		})
		corner(card)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = card })
		new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = if have then `{i}. {page.Title}` else `{i}. ???`,
			TextColor3 = if have then BRASS else MUTED,
			TextSize = 16,
			Font = Enum.Font.GothamBlack,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
			Parent = card,
		})
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = if have then page.Text else "Not found yet. Lost pages glow on rooftops, tree platforms and old towers near the named places.",
			TextColor3 = if have then TEXT else MUTED,
			TextSize = 14,
			Font = if have then Enum.Font.Gotham else Enum.Font.GothamMedium,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
			Parent = card,
		})
	end
	return found
end

-- === Header, tabs, opening ===================================================

local function refreshHeader()
	local s = state
	local places, foundPlaces, pages = 0, 0, 0
	if s then
		places = #s.Pois
		for _, poi in s.Pois do
			if s.Found[poi.Id] then
				foundPlaces += 1
			end
		end
		for _, page in Config.Journals.Pages do
			if s.Journals[page.Id] then
				pages += 1
			end
		end
	end
	header.Text = `PLACES {foundPlaces}/{places}    JOURNAL {pages}/{#Config.Journals.Pages}`
end

local function showTab(name: string)
	tab = name
	canvas.Visible = name == "Map"
	if name ~= "Map" then
		eventLabel.Visible = false
	end
	journalPage.Visible = name == "Journal"
	for key, button in tabButtons do
		button.BackgroundColor3 = if key == name then BRASS else ROW
		button.TextColor3 = if key == name then INK else TEXT
	end
	if name == "Journal" then
		renderJournal()
	end
end

local function layout()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local view = camera.ViewportSize
	local width = math.min(view.X - 24, 900)
	local height = math.min(view.Y - 24, 900)
	panel.Size = UDim2.fromOffset(width, height)
	-- The square map fits under the header (44) and over the event line (28).
	local side = math.max(math.min(width - 16, height - 44 - 36), 100)
	canvas.Size = UDim2.fromOffset(side, side)
end

local function setOpen(on: boolean)
	open = on
	gui.Enabled = on
	if on then
		layout()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local explore = remotes and remotes:FindFirstChild(Config.Remotes.Explore)
		if explore and explore:IsA("RemoteEvent") then
			explore:FireServer("Sync")
		end
		showTab(tab)
		updateLive()
	end
end

function MapScreen.Toggle()
	setOpen(not open)
end

-- Hides the journal books this hunter has already found (on this screen
-- only; the server never counts them twice anyway).
local function hideFound(book: Instance)
	local id = book:GetAttribute("JournalId")
	local s = state
	if type(id) ~= "string" or not s or not s.Journals[id] then
		return
	end
	for _, d in book:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("ProximityPrompt") or d:IsA("ParticleEmitter") or d:IsA("PointLight") or d:IsA("BillboardGui") then
			(d :: any).Enabled = false
		end
	end
end

local function hideAllFound()
	local folder = Workspace:FindFirstChild("LostJournals")
	if folder then
		for _, book in folder:GetChildren() do
			hideFound(book)
		end
	end
end

function MapScreen.Init()
	gui = new("ScreenGui", {
		Name = "MapScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 8,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Parent = gui })
	panel = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = INK, BackgroundTransparency = 0.05, Parent = gui })
	corner(panel, UDim.new(0, 14))
	new("UIStroke", { Color = BRASS, Thickness = 2, Parent = panel })

	-- Header: tabs, counts, close.
	local bar = new("Frame", { Size = UDim2.new(1, -16, 0, 36), Position = UDim2.fromOffset(8, 6), BackgroundTransparency = 1, Parent = panel })
	for i, name in { "Map", "Journal" } do
		local button = new("TextButton", {
			Size = UDim2.fromOffset(92, 32),
			Position = UDim2.fromOffset((i - 1) * 100, 2),
			BackgroundColor3 = ROW,
			Text = string.upper(name),
			TextSize = 15,
			Font = Enum.Font.GothamBlack,
			TextColor3 = TEXT,
			AutoButtonColor = true,
			Parent = bar,
		})
		corner(button)
		button.Activated:Connect(function()
			showTab(name)
		end)
		tabButtons[name] = button
	end
	header = new("TextLabel", {
		Size = UDim2.new(1, -250, 1, 0),
		Position = UDim2.fromOffset(204, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 14,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Enum.Font.GothamBold,
		TextColor3 = BRASS,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bar,
	})
	local close = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Color3.fromRGB(150, 60, 60),
		Text = "X",
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = TEXT,
		Parent = bar,
	})
	corner(close)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	-- The map.
	local body = new("Frame", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1, Parent = panel })
	canvas = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), BackgroundTransparency = 1, ClipsDescendants = true, Parent = body })
	staticLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = canvas })
	poiLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9, Parent = canvas })
	liveLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 11, Parent = canvas })
	eventLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -16, 0, 28),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1,
		Text = "",
		TextSize = 13,
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = GOLD,
		Visible = false,
		Parent = body,
	})
	corner(eventLabel)
	-- The legend, top left of the map.
	new("TextLabel", {
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.fromOffset(150, 64),
		BackgroundTransparency = 1,
		Text = "▲ you   ● hunters\n■ giants near you\n● supplies   ★ event",
		RichText = false,
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = TEXT,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 20,
		Parent = canvas,
	})

	hunters = pool(dot(Color3.fromRGB(90, 160, 255), 9, true, 13))
	giants = pool(dot(Color3.fromRGB(230, 70, 60), 10, false, 12))
	goldens = pool(dot(GOLD, 14, false, 12))
	crates = pool(dot(Color3.fromRGB(110, 220, 255), 6, true, 11))
	events = pool(function(): GuiObject
		return new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(26, 26),
			BackgroundTransparency = 1,
			Text = "★",
			TextScaled = true,
			TextColor3 = GOLD,
			TextStrokeTransparency = 0.2,
			Font = Enum.Font.GothamBlack,
			ZIndex = 14,
			Parent = liveLayer,
		})
	end)
	me = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		Text = "▲",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0,
		Font = Enum.Font.GothamBlack,
		ZIndex = 15,
		Parent = liveLayer,
	})

	-- The journal tab.
	journalPage = new("ScrollingFrame", {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, -8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = body,
	})
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = journalPage })

	drawStatic()
	showTab("Map")
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if open then
				layout()
			end
		end)
	end

	-- What the server says.
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local explore = remotes:WaitForChild(Config.Remotes.Explore) :: RemoteEvent
	explore.OnClientEvent:Connect(function(kind: unknown, data: unknown)
		if kind ~= "State" or type(data) ~= "table" then
			return
		end
		state = data :: any
		local s = state :: State
		if s.Map ~= drawnMap then
			drawStatic()
		end
		drawPois()
		refreshHeader()
		hideAllFound()
		if open and tab == "Journal" then
			renderJournal()
		end
	end)
	local eventRemote = remotes:WaitForChild(Config.Remotes.WorldEvent) :: RemoteEvent
	eventRemote.OnClientEvent:Connect(function(kind: unknown, info: unknown)
		if kind == "Event" then
			event = if type(info) == "table" then info :: any else nil
		end
	end)
	explore:FireServer("Sync")
	eventRemote:FireServer("Sync")

	-- Books streaming in.
	task.spawn(function()
		local folder = Workspace:WaitForChild("LostJournals", 60)
		if folder then
			folder.ChildAdded:Connect(function(book)
				task.defer(hideFound, book)
			end)
			hideAllFound()
		end
	end)

	-- Opening: M, the d-pad's right, the MAP button.
	ContextActionService:BindAction("GH_Map", function(_action, inputState, _input)
		if inputState == Enum.UserInputState.Begin then
			MapScreen.Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, D.MapKey, D.MapGamepad)
	if TouchButtons.Enabled() then
		TouchButtons.Init()
		TouchButtons.Add("Map", "Map", "MAP", MapScreen.Toggle)
	end

	-- Markers move while it's open.
	task.spawn(function()
		while true do
			task.wait(D.MapRefresh)
			if open and tab == "Map" then
				updateLive()
			end
		end
	end)
end

return MapScreen
