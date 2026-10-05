--!strict
-- The shop's gear, techniques and titans: buying them once with Marks (never
-- real money) and wearing one of each.
--
--   * Gear and techniques are in Config.Catalog, titan forms in
--     Config.TitanForms (the titan shifters' file; an empty tab without it).
--   * Bought items are saved in the profile's "Owned" ({ [id] = true }), the
--     worn ones in "Equip" ({ Gear, Technique, Titan }), and published as the
--     player attributes "Equip_Gear", "Equip_Technique" and "Equip_Titan"
--     (ids, "" for none). Stats.For reads the gear's Mods from there,
--     TechniqueService the technique, the shifters the titan form.
--   * Marks are the same saved balance ProgressService pays into (the
--     profile's Marks and the "Marks" attribute). A purchase is checked and
--     paid in one go, without yielding, so two requests can never both spend
--     the same Marks.
--
--   * The second technique slot ("Technique2", "Equip_Technique2"): only with
--     the SecondTechnique game pass (the "Pass_SecondTechnique" attribute,
--     MonetizationService), never the same technique as the first slot.
--
-- Every request goes through Config.Remotes.Shop and is checked here: data
-- loaded, a known item, not already owned, the hunter's level, the price,
-- and a short cooldown between requests.
--
-- Styles (cosmetics only, no stats; Config.CosmeticItems, defined with the
-- looks): owned and worn here, through Config.Remotes.Style. Saved in the
-- profile's "Cosmetics" ({ Owned, Equip = { [Slot] = id } }) and published
-- as the player attributes "Cos_<Slot>" (an id, "" for the default look),
-- which the looks read. Free items are everyone's; Pass items are owned
-- while the player owns their game pass ("Pass_<PassKey>" attributes);
-- Marks items are bought here; Robux and Season items are granted by
-- MonetizationService / SeasonService (ShopService.GrantStyle).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local HunterGear = require(script.Parent.HunterGear)

local ShopService = {}

export type Category = string -- "Gear" | "Technique" | "Titan"

-- What the shop needs of any item, gear, technique or titan form alike.
type Item = { Id: string, Display: string, Price: number, LevelRequired: number }

local CATEGORIES: { Category } = { "Gear", "Technique", "Titan" }
-- What can be worn: the categories, plus the second technique slot.
local EQUIP_SLOTS: { string } = { "Gear", "Technique", "Technique2", "Titan" }

local remote: RemoteEvent
local styleRemote: RemoteEvent
local nextStyle: { [Player]: number } = {}
local nextAction: { [Player]: number } = {}
local ready: { [Player]: boolean } = {}

-- Config.TitanForms comes from the titan shifters; read defensively.
local function titanForms(): { [string]: any }
	local forms = (Config :: any).TitanForms
	return if type(forms) == "table" then forms else {}
end

local function findItem(category: string, id: string): Item?
	if category == "Titan" then
		local form = titanForms()[id]
		if type(form) == "table" then
			return {
				Id = id,
				Display = if type(form.Display) == "string" then form.Display else id,
				Price = if type(form.Price) == "number" then form.Price else 0,
				LevelRequired = if type(form.LevelRequired) == "number" then form.LevelRequired else 1,
			}
		end
		return nil
	end
	local item = Config.Catalog[id]
	if item and item.Category == category then
		return item
	end
	return nil
end

local function profileOf(player: Player): any
	if not ready[player] then
		return nil
	end
	return DataService.Get(player)
end

-- The saved tables, made if missing (older saves).
local function ownedOf(profile: any): { [string]: boolean }
	if type(profile.Owned) ~= "table" then
		profile.Owned = {}
	end
	return profile.Owned
end

local function equipOf(profile: any): { [string]: string }
	if type(profile.Equip) ~= "table" then
		profile.Equip = {}
	end
	return profile.Equip
end

function ShopService.Level(player: Player): number
	local level = player:GetAttribute("Level")
	return if type(level) == "number" then level else 1
end

-- Free items (price 0) are everyone's.
function ShopService.Owns(player: Player, category: string, id: string): boolean
	local item = findItem(category, id)
	if not item then
		return false
	end
	if item.Price <= 0 then
		return true
	end
	local profile = profileOf(player)
	return profile ~= nil and ownedOf(profile)[id] == true
end

-- The worn item's id in a category ("" for none).
function ShopService.Equipped(player: Player, category: Category): string
	local id = player:GetAttribute(`Equip_{category}`)
	return if type(id) == "string" then id else ""
end

local function result(player: Player, ok: boolean, message: string)
	remote:FireClient(player, "Result", ok, message)
end

local function send(player: Player)
	local profile = profileOf(player)
	if not profile or not player.Parent then
		return
	end
	local equip = equipOf(profile)
	remote:FireClient(player, "State", {
		Owned = table.clone(ownedOf(profile)),
		Equip = { Gear = equip.Gear or "", Technique = equip.Technique or "", Technique2 = equip.Technique2 or "", Titan = equip.Titan or "" },
	})
end

-- The worn gear onto the hunter (rig colours, tanks, swords).
local function applyGear(player: Player)
	local character = player.Character
	if character then
		HunterGear.ApplyGearLook(character)
	end
end

local function setEquip(player: Player, profile: any, category: string, id: string)
	equipOf(profile)[category] = id
	DataService.Touch(player)
	player:SetAttribute(`Equip_{category}`, id)
	if category == "Gear" then
		applyGear(player)
	end
end

-- `price`: a special price (the Wandering Merchant's), else the item's own.
local function buy(player: Player, profile: any, category: string, id: string, price: number?)
	local found = findItem(category, id)
	if not found then
		return
	end
	local item = found
	if price and found.Price > 0 then
		item = table.clone(found)
		item.Price = math.max(math.floor(price), 1)
	end
	local owned = ownedOf(profile)
	if owned[id] or item.Price <= 0 then
		result(player, false, `You already have {item.Display}`)
		return
	end
	local level = ShopService.Level(player)
	if level < item.LevelRequired then
		result(player, false, `{item.Display} unlocks at level {item.LevelRequired}`)
		return
	end
	local marks = if type(profile.Marks) == "number" then profile.Marks else 0
	if marks < item.Price then
		result(player, false, `You need {item.Price - marks} more Marks`)
		return
	end
	-- (No yield between the check and the payment.)
	profile.Marks = marks - item.Price
	owned[id] = true
	DataService.Touch(player)
	player:SetAttribute("Marks", profile.Marks)
	-- A first buy in a category is worn straight away.
	local slot = category :: Category
	if ShopService.Equipped(player, slot) == "" then
		setEquip(player, profile, slot, id)
	end
	result(player, true, `{item.Display} is yours!`)
end

local function hasSecondSlot(player: Player): boolean
	return player:GetAttribute("Pass_SecondTechnique") == true
end

local function equip(player: Player, profile: any, category: string, id: string)
	if category == "Technique2" then
		if id ~= "" and not hasSecondSlot(player) then
			result(player, false, "The second technique slot comes with its game pass")
			return
		end
		if id ~= "" and not ShopService.Owns(player, "Technique", id) then
			return
		end
		if id ~= "" and id == ShopService.Equipped(player, "Technique") then
			setEquip(player, profile, "Technique", "") -- (moved to the second slot)
		end
		setEquip(player, profile, "Technique2", id)
		local item = if id ~= "" then findItem("Technique", id) else nil
		result(player, true, if item then `{item.Display} in slot 2` else "Slot 2 emptied")
		return
	end
	if not table.find(CATEGORIES, category :: Category) then
		return
	end
	if category == "Technique" and id ~= "" and id == ShopService.Equipped(player, "Technique2") then
		setEquip(player, profile, "Technique2", "") -- (moved to the first slot)
	end
	local slot = category :: Category
	if id ~= "" and not ShopService.Owns(player, slot, id) then
		return
	end
	setEquip(player, profile, slot, id)
	local item = if id ~= "" then findItem(slot, id) else nil
	result(player, true, if item then `Equipped {item.Display}` else "Unequipped")
end

local function onRequest(player: Player, action: unknown, a: unknown, b: unknown)
	local now = os.clock()
	if now < (nextAction[player] or 0) then
		return
	end
	nextAction[player] = now + Config.Shop.ActionCooldown
	local profile = profileOf(player)
	if not profile then
		if action ~= "Sync" then
			result(player, false, "Still loading your progress...")
		end
		return
	end
	if action == "Buy" and type(a) == "string" and type(b) == "string" then
		buy(player, profile, a, b)
	elseif action == "Equip" and type(a) == "string" and type(b) == "string" and #b <= 40 then
		equip(player, profile, a, b)
	elseif action ~= "Sync" then
		return
	end
	send(player)
end

-- === Styles (cosmetics) =====================================================

-- Config.CosmeticItems comes with the looks; read defensively.
local function styleItem(id: string): { [string]: any }?
	local items = (Config :: any).CosmeticItems
	local item = if type(items) == "table" then items[id] else nil
	return if type(item) == "table" then item else nil
end

local function cosmeticsOf(profile: any): { Owned: { [string]: boolean }, Equip: { [string]: string } }
	if type(profile.Cosmetics) ~= "table" then
		profile.Cosmetics = { Owned = {}, Equip = {} }
	end
	local c = profile.Cosmetics
	if type(c.Owned) ~= "table" then
		c.Owned = {}
	end
	if type(c.Equip) ~= "table" then
		c.Equip = {}
	end
	return c
end

-- Free items are everyone's, pass items are while the pass is owned.
function ShopService.OwnsStyle(player: Player, id: string): boolean
	local item = styleItem(id)
	if not item then
		return false
	end
	if item.Source == "Free" then
		return true
	end
	if type(item.PassKey) == "string" and player:GetAttribute(`Pass_{item.PassKey}`) == true then
		return true
	end
	local profile = profileOf(player)
	return profile ~= nil and cosmeticsOf(profile).Owned[id] == true
end

local function styleResult(player: Player, ok: boolean, message: string)
	styleRemote:FireClient(player, "Result", ok, message)
end

local function sendStyles(player: Player)
	local profile = profileOf(player)
	if not profile or not player.Parent then
		return
	end
	local owned: { [string]: boolean } = {}
	local items = (Config :: any).CosmeticItems
	if type(items) == "table" then
		for id in items do
			if type(id) == "string" and ShopService.OwnsStyle(player, id) then
				owned[id] = true
			end
		end
	end
	local equip: { [string]: string } = {}
	for _, slot in Config.CosmeticSlots do
		local worn = player:GetAttribute(`Cos_{slot}`)
		equip[slot] = if type(worn) == "string" then worn else ""
	end
	styleRemote:FireClient(player, "State", { Owned = owned, Equip = equip })
end

-- The worn styles onto the "Cos_<Slot>" attributes (a saved choice that
-- isn't owned right now, a pass not checked yet, shows as the default).
local function publishStyles(player: Player)
	local profile = profileOf(player)
	if not profile then
		return
	end
	local saved = cosmeticsOf(profile).Equip
	for _, slot in Config.CosmeticSlots do
		local id = saved[slot]
		local item = if type(id) == "string" and id ~= "" then styleItem(id) else nil
		local ok = item ~= nil and item.Slot == slot and ShopService.OwnsStyle(player, id)
		player:SetAttribute(`Cos_{slot}`, if ok then id else "")
	end
end

-- Buys gear or a technique at a special price (the Wandering Merchant,
-- WorldEventService), with every usual check: data loaded, a known item,
-- not owned yet, the level, the Marks. The hunter gets the usual "Result".
-- True if they own it now.
function ShopService.BuyAt(player: Player, category: string, id: string, price: number): boolean
	local profile = profileOf(player)
	if not profile then
		result(player, false, "Still loading your progress...")
		return false
	end
	if category ~= "Gear" and category ~= "Technique" then
		return false
	end
	buy(player, profile, category, id, price)
	send(player)
	return ownedOf(profile)[id] == true
end

-- Re-publishes everything owned and worn (after a pass or a grant).
function ShopService.Refresh(player: Player)
	publishStyles(player)
	sendStyles(player)
	send(player)
end

-- Gives a style for good (a Robux product, a season reward). False if the
-- profile isn't loaded or the item is unknown. A first item in a slot is
-- worn straight away.
function ShopService.GrantStyle(player: Player, id: string): boolean
	local profile = profileOf(player)
	local item = styleItem(id)
	if not profile or not item then
		return false
	end
	local c = cosmeticsOf(profile)
	c.Owned[id] = true
	if type(item.Slot) == "string" and (c.Equip[item.Slot] or "") == "" then
		c.Equip[item.Slot] = id
	end
	DataService.Touch(player)
	ShopService.Refresh(player)
	return true
end

local function buyStyle(player: Player, profile: any, id: string)
	local item = styleItem(id)
	if not item then
		return
	end
	local display = tostring(item.Display or id)
	if ShopService.OwnsStyle(player, id) then
		styleResult(player, false, `You already have {display}`)
		return
	end
	if item.Source ~= "Marks" or type(item.Price) ~= "number" or item.Price <= 0 then
		return -- (Robux, Season and Pass items aren't sold for Marks)
	end
	local levelRequired = if type(item.LevelRequired) == "number" then item.LevelRequired else 1
	if ShopService.Level(player) < levelRequired then
		styleResult(player, false, `{display} unlocks at level {levelRequired}`)
		return
	end
	local marks = if type(profile.Marks) == "number" then profile.Marks else 0
	if marks < item.Price then
		styleResult(player, false, `You need {item.Price - marks} more Marks`)
		return
	end
	-- (No yield between the check and the payment.)
	profile.Marks = marks - item.Price
	cosmeticsOf(profile).Owned[id] = true
	player:SetAttribute("Marks", profile.Marks)
	DataService.Touch(player)
	local slot = item.Slot
	if type(slot) == "string" and player:GetAttribute(`Cos_{slot}`) == "" then
		cosmeticsOf(profile).Equip[slot] = id
		publishStyles(player)
	end
	styleResult(player, true, `{display} is yours!`)
end

local function equipStyle(player: Player, profile: any, slot: string, id: string)
	if not table.find(Config.CosmeticSlots, slot) then
		return
	end
	local item = if id ~= "" then styleItem(id) else nil
	if id ~= "" and (not item or item.Slot ~= slot or not ShopService.OwnsStyle(player, id)) then
		return
	end
	cosmeticsOf(profile).Equip[slot] = id
	DataService.Touch(player)
	publishStyles(player)
	styleResult(player, true, if item then `Wearing {tostring(item.Display or id)}` else "Back to the corps' issue")
end

local function onStyleRequest(player: Player, action: unknown, a: unknown, b: unknown)
	local now = os.clock()
	if now < (nextStyle[player] or 0) then
		return
	end
	nextStyle[player] = now + Config.Shop.ActionCooldown
	local profile = profileOf(player)
	if not profile then
		if action ~= "Sync" then
			styleResult(player, false, "Still loading your progress...")
		end
		return
	end
	if action == "Buy" and type(a) == "string" and #a <= 60 then
		buyStyle(player, profile, a)
	elseif action == "Equip" and type(a) == "string" and type(b) == "string" and #b <= 60 then
		equipStyle(player, profile, a, b)
	elseif action ~= "Sync" then
		return
	end
	sendStyles(player)
end

-- === Players =================================================================

-- Once the saved profile is in: drop unknown or unowned items, publish
-- what's worn.
local function onLoaded(player: Player)
	if ready[player] or not DataService.Get(player) then
		return
	end
	ready[player] = true
	local profile = profileOf(player)
	local owned = ownedOf(profile)
	for id, value in owned do
		if type(id) ~= "string" or value ~= true then
			owned[id] = nil
		end
	end
	local saved = equipOf(profile)
	local hasForms = next(titanForms()) ~= nil
	for _, slot in EQUIP_SLOTS do
		local id = saved[slot]
		if type(id) ~= "string" then
			id = ""
		end
		local category = if slot == "Technique2" then "Technique" else slot
		-- (Titan forms only checked once they exist in this build.)
		if id ~= "" and (category ~= "Titan" or hasForms) and not ShopService.Owns(player, category, id) then
			id = ""
		end
		if slot == "Technique2" and id == saved.Technique then
			id = ""
		end
		saved[slot] = id
		player:SetAttribute(`Equip_{slot}`, id)
	end
	applyGear(player)
	send(player)
	ShopService.Refresh(player)
end

local function onPlayerAdded(player: Player)
	for _, slot in EQUIP_SLOTS do
		player:SetAttribute(`Equip_{slot}`, "")
	end
	for _, slot in Config.CosmeticSlots do
		player:SetAttribute(`Cos_{slot}`, "")
	end
	player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if player:GetAttribute("DataLoaded") then
			onLoaded(player)
		end
	end)
	if player:GetAttribute("DataLoaded") then
		task.spawn(onLoaded, player)
	end
	-- The swords go on after the uniform: recolour them as they arrive.
	player.CharacterAdded:Connect(function(character)
		character.ChildAdded:Connect(function(child)
			if child.Name == "LeftSword" or child.Name == "RightSword" or child.Name == "HunterGear" then
				task.defer(HunterGear.ApplyGearLook, character)
			end
		end)
	end)
end

function ShopService.Init()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Shop) :: RemoteEvent
	styleRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.Remotes.Style) :: RemoteEvent
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		nextAction[player] = nil
		nextStyle[player] = nil
		ready[player] = nil
	end)
	remote.OnServerEvent:Connect(onRequest)
	styleRemote.OnServerEvent:Connect(onStyleRequest)
end

return ShopService
