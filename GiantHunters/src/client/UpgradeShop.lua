--!strict
-- The upgrade shop, daily challenges and looks (its own ScreenGui), and the
-- end-of-round summary.
--
-- Opened from the "UPGRADES" button (left edge, sized for thumbs) or at an
-- upgrade board (the headquarters, the spawn post: key R). Nine tabs:
--   * Upgrades: each track's level, what the next one gives, and its price
--     in Marks;
--   * Gear, Techniques, Titans: cards for Config.Catalog and
--     Config.TitanForms, with what each changes (+12% speed, -10% gas...),
--     its price and level, why it's locked, and buy / equip buttons;
--   * Challenges: today's three, with progress bars and the time left;
--   * Look: cape colours and titles, with how to unlock the locked ones;
--   * Robux: game passes and products (Config.Monetization; prices from
--     GetProductInfo, anything with an id of 0 hidden);
--   * Style: the styles (Config.CosmeticItems) by slot, with a colour
--     swatch and wear / buy (Marks or Robux) buttons;
--   * Season: the season track (Config.Season), free and premium rows,
--     progress and claim buttons.
-- The server decides everything (ProgressService, ShopService,
-- MonetizationService, SeasonService); this only shows their snapshots and
-- sends requests. A Robux prompt only opens from a button press here.
-- Also: the Server XP Boost timer under the shop button, and the fireworks
-- someone bought (a client effect, default particles).

local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)

local UpgradeShop = {}

local player = Players.LocalPlayer

local INK = Color3.fromRGB(22, 24, 32)
local PANEL = Color3.fromRGB(34, 37, 48)
local ROW = Color3.fromRGB(44, 48, 62)
local BRASS = Color3.fromRGB(214, 186, 120)
local TEXT = Color3.fromRGB(236, 238, 245)
local MUTED = Color3.fromRGB(156, 162, 178)
local GOOD = Color3.fromRGB(110, 220, 130)
local BAD = Color3.fromRGB(240, 120, 105)
local LOCKED = Color3.fromRGB(70, 72, 82)

local DESIGN = Vector2.new(700, 460) -- the window's size before scaling

local remote: RemoteEvent
local shopRemote: RemoteEvent
local gui: ScreenGui
local window: Frame
local marksLabel: TextLabel
local openButton: TextButton
local pages: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}
local footer: TextLabel
local toastLabel: TextLabel
local summary: Frame
local summaryLines: TextLabel
local summaryTitle: TextLabel
local scales: { UIScale } = {}

local current = "Upgrades"
local snapshot: any = nil
local shopState: any = nil -- ShopService's { Owned, Equip }
local styleState: any = nil -- ShopService's styles { Owned, Equip }
local seasonState: any = nil -- SeasonService's snapshot
local monetRemote: RemoteEvent
local styleRemote: RemoteEvent
local seasonRemote: RemoteEvent
local boostLabel: TextLabel
local prices: { [string]: string } = {} -- "Pass:<id>" / "Product:<id>" -> "R$ 99"
local render: () -> ()
local toastToken = 0

local TABS = { "Upgrades", "Gear", "Techniques", "Titans", "Challenges", "Look", "Robux", "Style", "Season" }

-- The live balance (the shop's purchases change it between snapshots).
local function currentMarks(): number
	local marks = player:GetAttribute("Marks")
	if type(marks) == "number" then
		return marks
	end
	return (snapshot and snapshot.Marks) or 0
end

local function currentLevel(): number
	local level = player:GetAttribute("Level")
	return if type(level) == "number" then level else 1
end
local summaryToken = 0

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

local function corner(parent: Instance, radius: number?)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or TEXT
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return new("TextLabel", props)
end

local function button(props: { [string]: any }, onClick: () -> ()): TextButton
	props.BackgroundColor3 = props.BackgroundColor3 or BRASS
	props.Font = props.Font or Enum.Font.GothamBlack
	props.TextColor3 = props.TextColor3 or INK
	props.AutoButtonColor = true
	local b: TextButton = new("TextButton", props)
	corner(b, 6)
	b.Activated:Connect(onClick)
	return b
end

-- === Scaling =================================================================
-- Laid out at a fixed design size; a UIScale fits it to any screen.

local function screenScale(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	local viewport = camera.ViewportSize
	return math.clamp(math.min(viewport.X / (DESIGN.X + 60), viewport.Y / (DESIGN.Y + 40)), 0.45, 1.25)
end

local function scaled(element: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Scale = screenScale()
	scale.Parent = element
	table.insert(scales, scale)
end

local function rescale()
	local s = screenScale()
	for _, scale in scales do
		scale.Scale = s
	end
end

-- === Toasts ==================================================================

local function toast(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or TEXT
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.3
	toastLabel.Visible = true
	task.delay(2.6, function()
		if token == toastToken then
			local fade = TweenInfo.new(0.5)
			TweenService:Create(toastLabel, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
	end)
end

-- === Pages ===================================================================

local function clear(page: ScrollingFrame)
	for _, child in page:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function row(page: ScrollingFrame, height: number, order: number): Frame
	local frame: Frame = new("Frame", { Size = UDim2.new(1, -8, 0, height), BackgroundColor3 = ROW, LayoutOrder = order, Parent = page })
	corner(frame, 8)
	return frame
end

local function bar(parent: Instance, position: UDim2, size: UDim2, ratio: number, color: Color3)
	local back = new("Frame", { Position = position, Size = size, BackgroundColor3 = INK, Parent = parent })
	corner(back, 4)
	local fill = new("Frame", { Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1), BackgroundColor3 = color, Parent = back })
	corner(fill, 4)
end

local function renderUpgrades(page: ScrollingFrame)
	local marks = currentMarks()
	for i, name in Config.Upgrades.Order do
		local track = Config.Upgrades.Tracks[name]
		local level = (snapshot.Upgrades and snapshot.Upgrades[name]) or 0
		local max = Upgrades.MaxLevel(name)
		local cost = Upgrades.Cost(name, level)
		local frame = row(page, 66, i)
		label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -150, 0, 22), Text = track.Display, TextSize = 18, Font = Enum.Font.GothamBlack, Parent = frame })
		label({ Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -150, 0, 16), Text = track.Info, TextSize = 12, TextColor3 = MUTED, Font = Enum.Font.GothamMedium, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
		-- Level pips.
		for p = 1, max do
			local pip = new("Frame", { Position = UDim2.fromOffset(12 + (p - 1) * 22, 50), Size = UDim2.fromOffset(18, 8), BackgroundColor3 = if p <= level then BRASS else LOCKED, Parent = frame })
			corner(pip, 3)
		end
		local now = Upgrades.Describe(name, Upgrades.Value(name, level))
		local nextText = if cost then `{now}  >  {Upgrades.Describe(name, Upgrades.Value(name, level + 1))}` else `{now}  (max)`
		label({ Position = UDim2.fromOffset(16 + max * 22, 46), Size = UDim2.new(1, -170 - max * 22, 0, 16), Text = nextText, TextSize = 12, TextColor3 = GOOD, Parent = frame })
		local affordable = cost ~= nil and marks >= cost
		button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(120, 44),
			Text = if cost then `BUY  {cost}` else "MAX",
			TextSize = 16,
			BackgroundColor3 = if affordable then BRASS elseif cost then LOCKED else GOOD,
			TextColor3 = if affordable or not cost then INK else MUTED,
			Parent = frame,
		}, function()
			if cost then
				remote:FireServer("Buy", name)
			end
		end)
	end
end

local function renderChallenges(page: ScrollingFrame)
	for i, c in snapshot.Challenges or {} do
		local frame = row(page, 70, i)
		local done = c.Done == true
		label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -150, 0, 22), Text = c.Text, TextSize = 17, Font = Enum.Font.GothamBlack, TextColor3 = if done then GOOD else TEXT, Parent = frame })
		bar(frame, UDim2.fromOffset(12, 40), UDim2.new(1, -170, 0, 12), (c.Progress or 0) / math.max(c.Goal or 1, 1), if done then GOOD else BRASS)
		label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 54), Size = UDim2.fromOffset(80, 14), Text = `{c.Progress or 0} / {c.Goal or 1}`, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Parent = frame })
		-- (A Challenge Reroll, when it's set up: swap this one for another.)
		local rerollId = Config.Monetization.Products.ChallengeReroll
		local swap = not done and rerollId ~= 0
		if swap then
			button({
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -12, 1, -6),
				Size = UDim2.fromOffset(130, 24),
				Text = `SWAP  {"R$"}`,
				TextSize = 11,
				BackgroundColor3 = ROW,
				TextColor3 = MUTED,
				Parent = frame,
			}, function()
				monetRemote:FireServer("Buy", "ChallengeReroll", c.Id)
			end)
		end
		label({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, if swap then 0.3 else 0.5, 0),
			Size = UDim2.fromOffset(130, 30),
			Text = if done then "DONE!" else `+{c.Reward} Marks`,
			TextSize = 17,
			Font = Enum.Font.GothamBlack,
			TextColor3 = if done then GOOD else BRASS,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		})
	end
	local left = math.max(snapshot.ResetIn or 0, 0)
	footer.Text = `New challenges in {left // 3600}h {(left % 3600) // 60}m  -  done so far: {(snapshot.Stats and snapshot.Stats.ChallengesDone) or 0}`
end

-- "Reach Veteran", "Take down 150 giants (40/150)".
local function hint(unlock: Config.Unlock?): string
	if not unlock then
		return ""
	end
	if unlock.Pass then
		return "Comes with a game pass (ROBUX tab)"
	end
	if unlock.Rank then
		return `Reach {unlock.Rank}`
	end
	local at = unlock.At or 0
	local have = (snapshot.Stats and unlock.Stat and snapshot.Stats[unlock.Stat]) or 0
	local what = ({
		Giants = `Take down {at} giants`,
		CleanCuts = `Make {at} clean cuts`,
		Rescues = `Rescue {at} friends`,
		ChallengesDone = `Finish {at} daily challenges`,
		BestRound = `Clear round {at}`,
	} :: { [string]: string })[unlock.Stat or ""] or `{at}`
	if unlock.Stat == "Pathfinder" then
		return "Discover every place on the map (M)"
	end
	return `{what} ({math.min(have, at)}/{at})`
end

local function renderLook(page: ScrollingFrame)
	label({ Size = UDim2.new(1, -8, 0, 24), Text = "CAPES", TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = BRASS, LayoutOrder = 1, Parent = page })
	local grid = new("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Parent = page })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(142, 64), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, cape in Config.Cosmetics.Capes do
		local open = snapshot.Capes and snapshot.Capes[cape.Id] == true
		local chosen = snapshot.Cape == cape.Id
		local swatch = button({
			Text = "",
			BackgroundColor3 = if open then cape.Color else LOCKED,
			LayoutOrder = i,
			Parent = grid,
		}, function()
			if open then
				remote:FireServer("Cape", cape.Id)
			else
				toast(hint(cape.Unlock), MUTED)
			end
		end)
		if chosen then
			new("UIStroke", { Color = BRASS, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = swatch })
		end
		local emblem = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = if open then cape.Emblem else MUTED, Parent = swatch })
		corner(emblem, 9)
		label({ Position = UDim2.fromOffset(4, 28), Size = UDim2.new(1, -8, 0, 16), Text = cape.Display, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, Parent = swatch })
		label({ Position = UDim2.fromOffset(4, 44), Size = UDim2.new(1, -8, 0, 14), Text = if chosen then "WEARING" elseif open then "" else "LOCKED", TextSize = 10, TextColor3 = if chosen then BRASS else MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, Parent = swatch })
	end
	label({ Size = UDim2.new(1, -8, 0, 24), Text = "TITLES", TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = BRASS, LayoutOrder = 3, Parent = page })
	local options: { { Id: string, Display: string, Unlock: Config.Unlock? } } = { { Id = "", Display = "No title (just your rank)" } }
	for _, title in Config.Cosmetics.Titles do
		table.insert(options, title)
	end
	for i, title in options do
		local open = title.Id == "" or (snapshot.Titles and snapshot.Titles[title.Id] == true)
		local chosen = (snapshot.Title or "") == title.Id
		local frame = row(page, 40, 3 + i)
		label({ Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, 0, 1, 0), Text = title.Display, TextSize = 15, TextColor3 = if open then TEXT else MUTED, Parent = frame })
		label({ Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, -110, 1, 0), Text = if open then "" else hint(title.Unlock), TextSize = 11, TextColor3 = MUTED, Font = Enum.Font.GothamMedium, TextWrapped = true, Parent = frame })
		button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(92, 30),
			Text = if chosen then "SHOWN" elseif open then "SHOW" else "LOCKED",
			TextSize = 13,
			BackgroundColor3 = if chosen then GOOD elseif open then BRASS else LOCKED,
			TextColor3 = if open then INK else MUTED,
			Parent = frame,
		}, function()
			if open and not chosen then
				remote:FireServer("Title", title.Id)
			end
		end)
	end
end

-- === Gear, techniques, titans ================================================

type Card = {
	Id: string,
	Category: string, -- "Gear" | "Technique" | "Titan"
	Display: string,
	Description: string,
	Price: number,
	LevelRequired: number,
	Order: number,
	Lines: { { Text: string, Good: boolean } }, -- what it changes
}

local function percent(mult: number, what: string): { Text: string, Good: boolean }
	local delta = math.floor((mult - 1) * 100 + 0.5)
	return { Text = `{if delta >= 0 then "+" else "-"}{math.abs(delta)}% {what}`, Good = delta >= 0 }
end

local function gearLines(mods: Config.GearMods?): { { Text: string, Good: boolean } }
	local lines = {}
	if not mods then
		return lines
	end
	if mods.SpeedMult then
		table.insert(lines, percent(mods.SpeedMult, "speed"))
	end
	if mods.GasMult then
		table.insert(lines, percent(mods.GasMult, "gas"))
	end
	if mods.GasRegenMult then
		table.insert(lines, percent(mods.GasRegenMult, "gas refill"))
	end
	if mods.ReelMult then
		table.insert(lines, percent(mods.ReelMult, "reel"))
	end
	if mods.DamageMult then
		table.insert(lines, percent(mods.DamageMult, "damage"))
	end
	if mods.HookRangeAdd then
		table.insert(lines, { Text = `{if mods.HookRangeAdd >= 0 then "+" else "-"}{math.abs(mods.HookRangeAdd)} hook range`, Good = mods.HookRangeAdd >= 0 })
	end
	if mods.BladeAdd then
		local n = math.abs(mods.BladeAdd)
		table.insert(lines, { Text = `{if mods.BladeAdd >= 0 then "+" else "-"}{n} blade{if n == 1 then "" else "s"}`, Good = mods.BladeAdd >= 0 })
	end
	return lines
end

local function techniqueLines(spec: Config.TechniqueSpec?): { { Text: string, Good: boolean } }
	local lines = {}
	if not spec then
		return lines
	end
	table.insert(lines, { Text = `cooldown {spec.Cooldown} s`, Good = true })
	if spec.Range then
		table.insert(lines, { Text = `range {spec.Range} studs`, Good = true })
	elseif spec.Radius then
		table.insert(lines, { Text = `{spec.Radius} studs round you`, Good = true })
	elseif spec.Distance then
		table.insert(lines, { Text = `{spec.Distance}-stud dash`, Good = true })
	end
	if spec.BladeCost then
		table.insert(lines, { Text = `uses {spec.BladeCost} blade`, Good = false })
	end
	return lines
end

local function cardsFor(category: string): { Card }
	local cards: { Card } = {}
	if category == "Titan" then
		local forms = (Config :: any).TitanForms
		if type(forms) == "table" then
			for id, form in forms do
				if type(id) == "string" and type(form) == "table" then
					table.insert(cards, {
						Id = id,
						Category = "Titan",
						Display = tostring(form.Display or id),
						Description = tostring(form.Description or ""),
						Price = tonumber(form.Price) or 0,
						LevelRequired = tonumber(form.LevelRequired) or 1,
						Order = tonumber(form.Order) or 99,
						Lines = {},
					})
				end
			end
		end
	else
		for id, item in Config.Catalog do
			if item.Category == category then
				table.insert(cards, {
					Id = id,
					Category = category,
					Display = item.Display,
					Description = item.Description,
					Price = item.Price,
					LevelRequired = item.LevelRequired,
					Order = item.Order,
					Lines = if category == "Gear" then gearLines(item.Mods) else techniqueLines(item.Technique),
				})
			end
		end
	end
	table.sort(cards, function(a, b)
		return if a.Order ~= b.Order then a.Order < b.Order else a.Id < b.Id
	end)
	return cards
end

local function renderCatalog(page: ScrollingFrame, category: string)
	local cards = cardsFor(category)
	if #cards == 0 then
		label({ Size = UDim2.new(1, -8, 0, 40), Text = if category == "Titan" then "Titan forms are coming soon!" else "Nothing here yet.", TextSize = 16, TextColor3 = MUTED, Parent = page })
		return
	end
	local marks = currentMarks()
	local level = currentLevel()
	local owned = (shopState and shopState.Owned) or {}
	local equipped = (shopState and shopState.Equip and shopState.Equip[category]) or ""
	for i, card in cards do
		local has = card.Price <= 0 or owned[card.Id] == true
		local wearing = equipped == card.Id
		local levelOk = level >= card.LevelRequired
		local frame = row(page, 92, i)
		if wearing then
			new("UIStroke", { Color = GOOD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame })
		end
		label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -160, 0, 22), Text = card.Display, TextSize = 18, Font = Enum.Font.GothamBlack, TextColor3 = if has or levelOk then TEXT else MUTED, Parent = frame })
		label({ Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -160, 0, 30), Text = card.Description, TextSize = 12, TextColor3 = MUTED, Font = Enum.Font.GothamMedium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = frame })
		-- What it changes, green for better and red for worse.
		local parts = {}
		for _, line in card.Lines do
			local hex = if line.Good then "#6EDC82" else "#F07869"
			table.insert(parts, `<font color="{hex}">{line.Text}</font>`)
		end
		label({ Position = UDim2.fromOffset(12, 64), Size = UDim2.new(1, -160, 0, 18), Text = table.concat(parts, "   "), RichText = true, TextSize = 13, Parent = frame })
		label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(130, 18), Text = if has then "OWNED" else `Level {card.LevelRequired}`, TextSize = 12, TextColor3 = if has or levelOk then BRASS else BAD, TextXAlignment = Enum.TextXAlignment.Right, Parent = frame })
		local text, color, textColor
		if wearing then
			text, color, textColor = "EQUIPPED", GOOD, INK
		elseif has then
			text, color, textColor = "EQUIP", BRASS, INK
		elseif not levelOk then
			text, color, textColor = `LEVEL {card.LevelRequired}`, LOCKED, MUTED
		else
			text, color, textColor = `BUY  {card.Price}`, if marks >= card.Price then BRASS else LOCKED, if marks >= card.Price then INK else MUTED
		end
		button({
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -10),
			Size = UDim2.fromOffset(130, 44),
			Text = text,
			TextSize = 15,
			BackgroundColor3 = color,
			TextColor3 = textColor,
			Parent = frame,
		}, function()
			if wearing then
				shopRemote:FireServer("Equip", card.Category, "") -- tap again to take it off
			elseif has then
				shopRemote:FireServer("Equip", card.Category, card.Id)
			elseif not levelOk then
				toast(`Reach level {card.LevelRequired} to unlock {card.Display}`, MUTED)
			elseif marks < card.Price then
				toast(`You need {card.Price - marks} more Marks`, MUTED)
			else
				shopRemote:FireServer("Buy", card.Category, card.Id)
			end
		end)
	end
	if category == "Technique" then
		footer.Text = "Use your technique with V, R2 on a gamepad, or the SKILL button."
	elseif category == "Titan" then
		footer.Text = "Your titan form is the shape you take when you transform."
	else
		footer.Text = "One set of gear at a time: tap EQUIPPED to go back to the corps' issue."
	end
end

-- === Robux, styles and the season ============================================
-- Prices come from MarketplaceService:GetProductInfo (cached); anything with
-- an id of 0 in Config.Monetization is hidden. A purchase prompt only ever
-- opens from a button press here (the server checks and opens it).

local MON = Config.Monetization

local function passId(key: string): number
	return MON.GamePasses[key] or 0
end

local function productId(key: string): number
	local id = (MON.Products :: any)[key]
	return if type(id) == "number" then id else 0
end

local function ownsPass(key: string): boolean
	return player:GetAttribute(`Pass_{key}`) == true
end

-- "R$ 99" (fetched once, then cached; "R$ ..." while it loads).
local function priceText(kind: string, id: number): string
	local key = `{kind}:{id}`
	local cached = prices[key]
	if cached then
		return cached
	end
	prices[key] = "R$ ..."
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
		end)
		local price = if ok and type(info) == "table" then (info :: any).PriceInRobux else nil
		prices[key] = if type(price) == "number" then `R$ {price}` else "R$ ?"
		render()
	end)
	return prices[key]
end

local function cosmeticItems(): { [string]: any }
	local items = (Config :: any).CosmeticItems
	return if type(items) == "table" then items else {}
end

-- A style's product id (0: not for sale for Robux).
local function styleProduct(id: string, item: any): number
	if item.Source ~= "Robux" then
		return 0
	end
	local key = if type(item.ProductKey) == "string" then item.ProductKey else id
	return MON.Products.Cosmetics[key] or 0
end

-- The swatch colour of a style's Preview (whatever colour it carries).
local function previewColor(item: any): Color3
	local preview = item.Preview
	if typeof(preview) == "Color3" then
		return preview
	end
	if type(preview) == "table" then
		for _, key in { "Color", "color", "Primary", "Colour" } do
			local value = preview[key]
			if typeof(value) == "Color3" then
				return value
			elseif typeof(value) == "ColorSequence" then
				return value.Keypoints[1].Value
			end
		end
		for _, value in preview do
			if typeof(value) == "Color3" then
				return value
			end
		end
	end
	return LOCKED
end

local function cardDisplay(key: string): string
	for _, card in MON.Cards do
		if card.Key == key then
			return card.Display
		end
	end
	return key
end

local function renderRobux(page: ScrollingFrame)
	local shown = 0
	for i, card in MON.Cards do
		local isPass = card.Kind == "Pass"
		local id = if isPass then passId(card.Key) else productId(card.Key)
		if id ~= 0 then
			shown += 1
			local owned = isPass and ownsPass(card.Key)
			local frame = row(page, 66, i)
			if owned then
				new("UIStroke", { Color = GOOD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame })
			end
			label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -160, 0, 22), Text = card.Display, TextSize = 18, Font = Enum.Font.GothamBlack, Parent = frame })
			label({ Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -160, 0, 30), Text = card.Description, TextSize = 12, TextColor3 = MUTED, Font = Enum.Font.GothamMedium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = frame })
			button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(130, 44),
				Text = if owned then "OWNED" else priceText(card.Kind, id),
				TextSize = 16,
				BackgroundColor3 = if owned then ROW else GOOD,
				TextColor3 = if owned then GOOD else INK,
				Parent = frame,
			}, function()
				if not owned then
					monetRemote:FireServer("Buy", card.Key)
				end
			end)
		end
	end
	if shown == 0 then
		label({ Size = UDim2.new(1, -8, 0, 40), Text = "Nothing for sale yet. Earn Marks by playing!", TextSize = 16, TextColor3 = MUTED, Parent = page })
	end
	footer.Text = "Robux items never make you stronger: gear and upgrades still unlock by level."
end

local function renderStyle(page: ScrollingFrame)
	local items = cosmeticItems()
	if next(items) == nil then
		label({ Size = UDim2.new(1, -8, 0, 40), Text = "Styles are coming soon!", TextSize = 16, TextColor3 = MUTED, Parent = page })
		return
	end
	local owned = (styleState and styleState.Owned) or {}
	local worn = (styleState and styleState.Equip) or {}
	local marks = currentMarks()
	local order = 0
	for _, slot in Config.CosmeticSlots do
		local list = {}
		for id, item in items do
			if type(id) == "string" and type(item) == "table" and item.Slot == slot then
				table.insert(list, { Id = id, Item = item })
			end
		end
		if #list > 0 then
			table.sort(list, function(a, b)
				return tostring(a.Item.Display or a.Id) < tostring(b.Item.Display or b.Id)
			end)
			order += 1
			label({ Size = UDim2.new(1, -8, 0, 24), Text = string.upper(if slot == "TitanSkin" then "Titan look" else slot), TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = BRASS, LayoutOrder = order, Parent = page })
			order += 1
			local grid = new("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, Parent = page })
			new("UIGridLayout", { CellSize = UDim2.fromOffset(160, 104), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
			-- The default look first, then the styles.
			table.insert(list, 1, { Id = "", Item = { Display = "Corps issue", Source = "Free" } })
			for i, entry in list do
				local id, item = entry.Id, entry.Item
				local has = id == "" or owned[id] == true
				local wearing = (worn[slot] or "") == id
				local cell = new("Frame", { BackgroundColor3 = ROW, LayoutOrder = i, Parent = grid })
				corner(cell, 8)
				if wearing then
					new("UIStroke", { Color = GOOD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = cell })
				end
				local swatch = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = if id == "" then PANEL else previewColor(item), Parent = cell })
				corner(swatch, 17)
				label({ Position = UDim2.fromOffset(48, 6), Size = UDim2.new(1, -54, 0, 18), Text = tostring(item.Display or id), TextSize = 13, Font = Enum.Font.GothamBlack, TextTruncate = Enum.TextTruncate.AtEnd, Parent = cell })
				label({ Position = UDim2.fromOffset(48, 24), Size = UDim2.new(1, -54, 0, 26), Text = tostring(item.Description or ""), TextSize = 10, TextColor3 = MUTED, Font = Enum.Font.GothamMedium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = cell })
				local text, color, onClick = "", LOCKED, function() end
				if wearing then
					text, color = "WEARING", GOOD
				elseif has then
					text, color = "WEAR", BRASS
					onClick = function()
						styleRemote:FireServer("Equip", slot, id)
					end
				elseif item.Source == "Marks" and type(item.Price) == "number" then
					text, color = `BUY  {item.Price}`, if marks >= item.Price then BRASS else LOCKED
					onClick = function()
						if marks < item.Price then
							toast(`You need {item.Price - marks} more Marks`, MUTED)
						else
							styleRemote:FireServer("Buy", id)
						end
					end
				elseif item.Source == "Robux" and styleProduct(id, item) ~= 0 then
					text, color = priceText("Product", styleProduct(id, item)), GOOD
					onClick = function()
						monetRemote:FireServer("BuyCosmetic", id)
					end
				elseif type(item.PassKey) == "string" and passId(item.PassKey) ~= 0 then
					text, color = cardDisplay(item.PassKey), GOOD
					onClick = function()
						monetRemote:FireServer("Buy", item.PassKey)
					end
				elseif item.Source == "Season" then
					local seasonTier: number? = if type(item.SeasonTier) == "number" then item.SeasonTier else nil
					for t, spec in Config.Season.Tiers do
						if (spec.Free and spec.Free.Cosmetic == id) or (spec.Premium and spec.Premium.Cosmetic == id) then
							seasonTier = t
						end
					end
					text = if seasonTier then `SEASON  TIER {seasonTier}` else "SEASON"
					onClick = function()
						toast("Earn it on the season track (SEASON tab)", MUTED)
					end
				else
					text = "LOCKED"
				end
				button({
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -8),
					Size = UDim2.new(1, -16, 0, 34),
					Text = text,
					TextSize = 13,
					BackgroundColor3 = color,
					TextColor3 = if color == LOCKED then MUTED else INK,
					Parent = cell,
				}, onClick)
			end
		end
	end
	footer.Text = "Styles only change how you look. Tap WEAR, or the corps issue to go back."
end

local function rewardText(reward: Config.SeasonReward?): string
	if not reward then
		return ""
	end
	if reward.Cosmetic then
		local item = cosmeticItems()[reward.Cosmetic]
		return if type(item) == "table" then tostring(item.Display or reward.Cosmetic) else "New style"
	end
	return `+{reward.Marks or 0} Marks`
end

local function renderSeason(page: ScrollingFrame)
	local season = seasonState
	if type(season) ~= "table" then
		label({ Size = UDim2.new(1, -8, 0, 40), Text = "Loading the season...", TextSize = 16, TextColor3 = MUTED, Parent = page })
		return
	end
	local S = Config.Season
	local xp = season.XP or 0
	local tier = season.Tier or 0
	local nextTier = S.Tiers[tier + 1]
	local prevXP = if tier > 0 then S.Tiers[tier].XP else 0
	local head = row(page, if season.Premium or passId("SeasonPremium") == 0 then 70 else 112, 0)
	label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 24), Text = `{string.upper(S.Name)}  -  tier {tier} / {#S.Tiers}`, TextSize = 18, Font = Enum.Font.GothamBlack, TextColor3 = BRASS, Parent = head })
	bar(head, UDim2.fromOffset(12, 36), UDim2.new(1, -24, 0, 12), if nextTier then (xp - prevXP) / math.max(nextTier.XP - prevXP, 1) else 1, BRASS)
	local ends = if type(season.EndsIn) == "number" then `  -  ends in {season.EndsIn // 86400}d {(season.EndsIn % 86400) // 3600}h` else ""
	label({ Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -24, 0, 16), Text = (if nextTier then `{xp} / {nextTier.XP} season XP` else `{xp} season XP: every tier reached!`) .. ends, TextSize = 12, TextColor3 = MUTED, Parent = head })
	if not season.Premium and passId("SeasonPremium") ~= 0 then
		button({ Position = UDim2.fromOffset(12, 72), Size = UDim2.new(1, -24, 0, 32), Text = `UNLOCK PREMIUM TRACK  {priceText("Pass", passId("SeasonPremium"))}`, TextSize = 14, BackgroundColor3 = GOOD, Parent = head }, function()
			monetRemote:FireServer("Buy", "SeasonPremium")
		end)
	end
	local claimedFree = season.ClaimedFree or {}
	local claimedPremium = season.ClaimedPremium or {}
	for i, spec in S.Tiers do
		local reached = xp >= spec.XP
		local frame = row(page, 52, i)
		label({ Position = UDim2.fromOffset(10, 4), Size = UDim2.fromOffset(60, 26), Text = `{i}`, TextSize = 22, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = if reached then BRASS else MUTED, Parent = frame })
		label({ Position = UDim2.fromOffset(10, 30), Size = UDim2.fromOffset(60, 14), Text = `{spec.XP} XP`, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = MUTED, Parent = frame })
		for column, track in { "Free", "Premium" } do
			local reward = if track == "Free" then spec.Free else spec.Premium
			local x = if column == 1 then 0 else 0.5
			local box = new("Frame", { Position = UDim2.new(x, if column == 1 then 76 else 4, 0, 6), Size = UDim2.new(0.5, if column == 1 then -82 else -10, 1, -12), BackgroundColor3 = if track == "Premium" then Color3.fromRGB(58, 50, 40) else INK, Parent = frame })
			corner(box, 6)
			if reward then
				local claimed = (if track == "Free" then claimedFree else claimedPremium)[tostring(i)] == true
				local canClaim = reached and not claimed and (track == "Free" or season.Premium == true)
				label({ Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -92, 1, 0), Text = (if track == "Premium" then "* " else "") .. rewardText(reward), TextSize = 12, TextWrapped = true, TextColor3 = if track == "Premium" then BRASS else TEXT, Parent = box })
				button({
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -4, 0.5, 0),
					Size = UDim2.fromOffset(80, 30),
					Text = if claimed then "CLAIMED" elseif canClaim then "CLAIM" elseif track == "Premium" and not season.Premium then "PREMIUM" else "LOCKED",
					TextSize = 12,
					BackgroundColor3 = if claimed then ROW elseif canClaim then GOOD else LOCKED,
					TextColor3 = if claimed then GOOD elseif canClaim then INK else MUTED,
					Parent = box,
				}, function()
					if canClaim then
						seasonRemote:FireServer("Claim", track, i)
					end
				end)
			end
		end
	end
	footer.Text = `Season XP: {math.floor(S.XPShare * 100)}% of all the XP you earn. Free rewards for everyone!`
end

-- === Fireworks and the XP boost timer ========================================

local FIREWORK_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 200, 80),
	Color3.fromRGB(110, 220, 130),
	Color3.fromRGB(100, 180, 255),
	Color3.fromRGB(210, 130, 255),
	Color3.fromRGB(255, 255, 255),
}

-- One rocket: a bright spark rises, then bursts into coloured sparks.
local function rocket(top: Vector3, rng: Random)
	local folder = Workspace:FindFirstChild("Fireworks") or new("Folder", { Name = "Fireworks", Parent = Workspace })
	local color = FIREWORK_COLORS[rng:NextInteger(1, #FIREWORK_COLORS)]
	local burstAt = top + Vector3.new(rng:NextNumber(-18, 18), rng:NextNumber(-8, 12), rng:NextNumber(-18, 18))
	local spark: Part = new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = color,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.8,
		Position = burstAt - Vector3.new(0, 45, 0),
		Parent = folder,
	})
	local rise = TweenService:Create(spark, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = burstAt })
	rise:Play()
	rise.Completed:Connect(function()
		spark.Transparency = 1
		local emitter: ParticleEmitter = new("ParticleEmitter", {
			Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1.2, 1.8),
			Speed = NumberRange.new(30, 45),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 2.5,
			Acceleration = Vector3.new(0, -12, 0),
			Rate = 0,
			Parent = spark,
		})
		emitter:Emit(90)
		local light: PointLight = new("PointLight", { Color = color, Range = 40, Brightness = 4, Parent = spark })
		TweenService:Create(light, TweenInfo.new(1), { Brightness = 0 }):Play()
		Debris:AddItem(spark, 2.5)
	end)
end

local function showFireworks(position: unknown, name: unknown)
	if typeof(position) ~= "Vector3" then
		return
	end
	local top = position :: Vector3
	if top ~= top or top.Magnitude > 1e5 then
		return
	end
	local rng = Random.new()
	for i = 1, MON.Fireworks.Bursts do
		task.delay((i - 1) * 0.35 + rng:NextNumber(0, 0.15), rocket, top, rng)
	end
	if type(name) == "string" and name == player.DisplayName then
		toast("Fireworks for everyone! Thank you!", BRASS)
	end
end

local function updateBoost()
	local until_ = Workspace:GetAttribute("XPBoostUntil")
	local left = if type(until_) == "number" then until_ - Workspace:GetServerTimeNow() else 0
	boostLabel.Visible = left > 0
	if left > 0 then
		boostLabel.Text = string.format("x%d XP  %d:%02d", MON.XPBoost.Multiplier, left // 60, math.floor(left % 60))
	end
end

local CATALOG_TABS: { [string]: string } = { Gear = "Gear", Techniques = "Technique", Titans = "Titan" }

function render()
	local marks = currentMarks()
	marksLabel.Text = `{marks} Marks`
	openButton.Text = `UPGRADES\n{marks} Marks`
	for name, tab in tabButtons do
		tab.BackgroundColor3 = if name == current then BRASS else ROW
		tab.TextColor3 = if name == current then INK else TEXT
	end
	for name, page in pages do
		page.Visible = name == current
	end
	footer.Text = "Earn Marks by scoring, clean takedowns, rescues and saving the district."
	if not window.Visible then
		return
	end
	local page = pages[current]
	clear(page)
	if not snapshot then
		label({ Size = UDim2.new(1, -8, 0, 40), Text = "Loading your progress...", TextSize = 16, TextColor3 = MUTED, Parent = page })
		return
	end
	if CATALOG_TABS[current] then
		renderCatalog(page, CATALOG_TABS[current])
	elseif current == "Upgrades" then
		renderUpgrades(page)
	elseif current == "Challenges" then
		renderChallenges(page)
	elseif current == "Robux" then
		renderRobux(page)
	elseif current == "Style" then
		renderStyle(page)
	elseif current == "Season" then
		renderSeason(page)
	else
		renderLook(page)
	end
end

local function setOpen(open: boolean)
	window.Visible = open
	if open and not snapshot then
		remote:FireServer("Sync")
	end
	if open and not shopState then
		shopRemote:FireServer("Sync")
	end
	if open and not styleState then
		styleRemote:FireServer("Sync")
	end
	if open and not seasonState then
		seasonRemote:FireServer("Sync")
	end
	render()
end

-- === Round summary ===========================================================

local function showSummary(data: any)
	if type(data) ~= "table" then
		return
	end
	summaryToken += 1
	local token = summaryToken
	summaryTitle.Text = if data.Won then `DISTRICT SAVED - ROUND {data.Round or "?"}` else `DISTRICT FALLEN - ROUND {data.Round or "?"}`
	summaryTitle.TextColor3 = if data.Won then BRASS else BAD
	local lines = {
		`Takedowns: {data.Takedowns or 0}`,
		`Clean cuts: {data.CleanCuts or 0}`,
		`Best cut speed: {data.BestSpeed or 0} studs/s`,
		`Points: {data.Points or 0}`,
		`Marks earned: +{data.Marks or 0}` .. (if data.TotalMarks then `  (you have {data.TotalMarks})` else ""),
	}
	summaryLines.Text = table.concat(lines, "\n")
	summary.Visible = true
	task.delay(12, function()
		if token == summaryToken then
			summary.Visible = false
		end
	end)
end

-- === Build ===================================================================

local function build()
	gui = new("ScreenGui", { Name = "UpgradeShop", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6, Parent = player:WaitForChild("PlayerGui") })

	-- The button: left edge, above the thumbstick on phones.
	openButton = button({
		Name = "OpenShop",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.42, 0),
		Size = UDim2.fromOffset(112, 52),
		Text = "UPGRADES",
		TextSize = 14,
		BackgroundColor3 = PANEL,
		TextColor3 = BRASS,
		BackgroundTransparency = 0.15,
		Parent = gui,
	}, function()
		setOpen(not window.Visible)
	end)
	new("UIStroke", { Color = BRASS, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = openButton })
	scaled(openButton)
	-- The Server XP Boost timer, just under the button (only while it runs).
	boostLabel = label({
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 12, 0.42, 34),
		Size = UDim2.fromOffset(112, 24),
		Text = "",
		TextSize = 13,
		Font = Enum.Font.GothamBlack,
		TextColor3 = INK,
		BackgroundColor3 = GOOD,
		BackgroundTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = gui,
	})
	corner(boostLabel, 6)
	scaled(boostLabel)

	window = new("Frame", {
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = gui,
	})
	corner(window, 12)
	new("UIStroke", { Color = BRASS, Thickness = 2, Parent = window })
	scaled(window)
	label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(300, 30), Text = "HUNTERS' QUARTERMASTER", TextSize = 20, Font = Enum.Font.GothamBlack, TextColor3 = BRASS, Parent = window })
	marksLabel = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -64, 0, 10), Size = UDim2.fromOffset(220, 30), Text = "0 Marks", TextSize = 20, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Right, Parent = window })
	-- (Modal: frees the mouse from shift-lock while the shop is open.)
	button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(44, 36), Text = "X", TextSize = 18, BackgroundColor3 = ROW, TextColor3 = TEXT, Modal = true, Parent = window }, function()
		setOpen(false)
	end)

	local tabWidth = (DESIGN.X - 32 - (#TABS - 1) * 4) / #TABS
	for i, name in TABS do
		tabButtons[name] = button({ Position = UDim2.fromOffset(16 + (i - 1) * (tabWidth + 4), 50), Size = UDim2.fromOffset(tabWidth, 36), Text = string.upper(name), TextScaled = true, Parent = window }, function()
			current = name
			render()
		end)
		new("UITextSizeConstraint", { MaxTextSize = 12, Parent = tabButtons[name] })
		new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), Parent = tabButtons[name] })
		local page: ScrollingFrame = new("ScrollingFrame", {
			Name = name,
			Position = UDim2.fromOffset(16, 96),
			Size = UDim2.new(1, -24, 1, -134),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = BRASS,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
			Parent = window,
		})
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
		pages[name] = page
	end
	footer = label({ Position = UDim2.new(0, 16, 1, -32), Size = UDim2.new(1, -32, 0, 24), Text = "", TextSize = 12, TextColor3 = MUTED, Font = Enum.Font.GothamMedium, Parent = window })

	toastLabel = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(460, 36),
		Text = "",
		TextSize = 17,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = INK,
		BackgroundTransparency = 1,
		TextTransparency = 1,
		ZIndex = 5,
		Parent = gui,
	})
	corner(toastLabel, 8)
	scaled(toastLabel)

	summary = new("Frame", {
		Name = "RoundSummary",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.fromOffset(380, 210),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.08,
		Visible = false,
		Parent = gui,
	})
	corner(summary, 12)
	new("UIStroke", { Color = BRASS, Thickness = 2, Parent = summary })
	scaled(summary)
	summaryTitle = label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -70, 0, 28), Text = "", TextSize = 18, Font = Enum.Font.GothamBlack, Parent = summary })
	summaryLines = label({ Position = UDim2.fromOffset(16, 46), Size = UDim2.new(1, -32, 1, -56), Text = "", TextSize = 16, TextYAlignment = Enum.TextYAlignment.Top, LineHeight = 1.2, Parent = summary })
	button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(40, 32), Text = "X", TextSize = 16, BackgroundColor3 = ROW, TextColor3 = TEXT, Parent = summary }, function()
		summary.Visible = false
	end)

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
end

function UpgradeShop.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remote = remotes:WaitForChild(Config.Remotes.Progress) :: RemoteEvent
	shopRemote = remotes:WaitForChild(Config.Remotes.Shop) :: RemoteEvent
	local summaryRemote = remotes:WaitForChild(Config.Remotes.RoundSummary) :: RemoteEvent
	monetRemote = remotes:WaitForChild(Config.Remotes.Monetization) :: RemoteEvent
	styleRemote = remotes:WaitForChild(Config.Remotes.Style) :: RemoteEvent
	seasonRemote = remotes:WaitForChild(Config.Remotes.Season) :: RemoteEvent

	-- (The grapple reads its upgraded numbers from Stats itself.)
	player.AttributeChanged:Connect(function(name)
		if (name == "Marks" or name == "Level" or string.sub(name, 1, 5) == "Pass_") and openButton then
			render()
		end
	end)

	build()
	render()

	remote.OnClientEvent:Connect(function(kind: unknown, a: unknown, b: unknown)
		if kind == "State" then
			snapshot = a
			render()
		elseif kind == "Open" then
			setOpen(true)
		elseif kind == "Result" then
			toast(tostring(b), if a == true then GOOD else BAD)
		elseif kind == "Challenge" then
			toast(`Challenge complete: {tostring(a)}  +{tostring(b)} Marks`, BRASS)
		end
	end)
	shopRemote.OnClientEvent:Connect(function(kind: unknown, a: unknown, b: unknown)
		if kind == "State" then
			shopState = a
			render()
		elseif kind == "Result" then
			toast(tostring(b), if a == true then GOOD else BAD)
		end
	end)
	summaryRemote.OnClientEvent:Connect(showSummary)
	styleRemote.OnClientEvent:Connect(function(kind: unknown, a: unknown, b: unknown)
		if kind == "State" then
			styleState = a
			render()
		elseif kind == "Result" then
			toast(tostring(b), if a == true then GOOD else BAD)
		end
	end)
	seasonRemote.OnClientEvent:Connect(function(kind: unknown, a: unknown, b: unknown)
		if kind == "State" then
			seasonState = a
			if current == "Season" then
				render()
			end
		elseif kind == "Result" then
			toast(tostring(b), if a == true then GOOD else BAD)
		end
	end)
	monetRemote.OnClientEvent:Connect(function(kind: unknown, a: unknown, b: unknown)
		if kind == "Fireworks" then
			showFireworks(a, b)
		elseif kind == "Result" then
			toast(tostring(b), if a == true then GOOD else BAD)
		elseif kind == "State" then
			render()
		end
	end)
	task.spawn(function()
		while true do
			updateBoost()
			task.wait(1)
		end
	end)
	remote:FireServer("Sync")
	shopRemote:FireServer("Sync")
	styleRemote:FireServer("Sync")
	seasonRemote:FireServer("Sync")
end

return UpgradeShop
