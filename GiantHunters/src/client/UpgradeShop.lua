--!strict
-- The upgrade shop, daily challenges and looks (its own ScreenGui), and the
-- end-of-round summary.
--
-- Opened from the "UPGRADES" button (left edge, sized for thumbs) or at an
-- upgrade board (the headquarters, the spawn post: key R). Six tabs:
--   * Upgrades: each track's level, what the next one gives, and its price
--     in Marks;
--   * Gear, Techniques, Titans: cards for Config.Catalog and
--     Config.TitanForms, with what each changes (+12% speed, -10% gas...),
--     its price and level, why it's locked, and buy / equip buttons;
--   * Challenges: today's three, with progress bars and the time left;
--   * Look: cape colours and titles, with how to unlock the locked ones.
-- The server decides everything (ProgressService, ShopService); this only
-- shows their snapshots and sends requests.

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

local DESIGN = Vector2.new(640, 440) -- the window's size before scaling

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
local toastToken = 0

local TABS = { "Upgrades", "Gear", "Techniques", "Titans", "Challenges", "Look" }

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
		label({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
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

local CATALOG_TABS: { [string]: string } = { Gear = "Gear", Techniques = "Technique", Titans = "Titan" }

local function render()
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

	for i, name in TABS do
		tabButtons[name] = button({ Position = UDim2.fromOffset(16 + (i - 1) * 102, 50), Size = UDim2.fromOffset(96, 36), Text = string.upper(name), TextSize = 12, Parent = window }, function()
			current = name
			render()
		end)
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

	-- (The grapple reads its upgraded numbers from Stats itself.)
	player.AttributeChanged:Connect(function(name)
		if (name == "Marks" or name == "Level") and openButton then
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
	remote:FireServer("Sync")
	shopRemote:FireServer("Sync")
end

return UpgradeShop
