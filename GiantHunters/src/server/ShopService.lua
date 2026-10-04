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
-- Every request goes through Config.Remotes.Shop and is checked here: data
-- loaded, a known item, not already owned, the hunter's level, the price,
-- and a short cooldown between requests.

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

local remote: RemoteEvent
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
		Equip = { Gear = equip.Gear or "", Technique = equip.Technique or "", Titan = equip.Titan or "" },
	})
end

-- The worn gear onto the hunter (rig colours, tanks, swords).
local function applyGear(player: Player)
	local character = player.Character
	if character then
		HunterGear.ApplyGearLook(character)
	end
end

local function setEquip(player: Player, profile: any, category: Category, id: string)
	equipOf(profile)[category] = id
	DataService.Touch(player)
	player:SetAttribute(`Equip_{category}`, id)
	if category == "Gear" then
		applyGear(player)
	end
end

local function buy(player: Player, profile: any, category: string, id: string)
	local item = findItem(category, id)
	if not item then
		return
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

local function equip(player: Player, profile: any, category: string, id: string)
	if not table.find(CATEGORIES, category :: Category) then
		return
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
	for _, category in CATEGORIES do
		local id = saved[category]
		if type(id) ~= "string" then
			id = ""
		end
		-- (Titan forms only checked once they exist in this build.)
		if id ~= "" and (category ~= "Titan" or hasForms) and not ShopService.Owns(player, category, id) then
			id = ""
		end
		saved[category] = id
		player:SetAttribute(`Equip_{category}`, id)
	end
	applyGear(player)
	send(player)
end

local function onPlayerAdded(player: Player)
	for _, category in CATEGORIES do
		player:SetAttribute(`Equip_{category}`, "")
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
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		nextAction[player] = nil
		ready[player] = nil
	end)
	remote.OnServerEvent:Connect(onRequest)
end

return ShopService
