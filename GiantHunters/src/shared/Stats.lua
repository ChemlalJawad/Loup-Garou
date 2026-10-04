--!strict
-- A hunter's effective numbers, the one place they're combined (server and
-- client alike: everything is read from replicated player attributes).
--
--   final = base (Config.Grapple / Config.Blades)
--         -> the Marks upgrades ("Up_<Track>", Upgrades.lua)
--         -> level bonuses ("Level", Config.Leveling)
--         -> the equipped gear's Mods ("Equip_Gear", Config.Catalog)
--
--   Stats.For(player)          -- StatsTable (cached until an input changes)
--   Stats.Grapple(player)      -- Config.Grapple with all of that applied
--   Stats.Changed(player, fn)  -- fn() whenever Level, an Up_* or Equip_Gear changes
--   Stats.XPNext(level)        -- XP to go from `level` to the next (0 at the top)
--   Stats.LevelBonus(level)    -- { Speed, Gas, Damage } multipliers from the level alone

local Players = game:GetService("Players")

local Config = require(script.Parent.Config)
local Upgrades = require(script.Parent.Upgrades)

local Stats = {}

export type StatsTable = {
	Level: number,
	SpeedMult: number, -- level x gear (applied to the speeds below)
	MaxSpeed: number, -- studs/s cap (the server's speed check uses this)
	SwingPull: number, -- Config.Grapple.SlackPull
	BoostForce: number, -- Config.Grapple.BoostAcceleration
	DashImpulse: number,
	ReelSpeed: number,
	ReelForce: number, -- Config.Grapple.ReelAcceleration
	GasMax: number,
	GasRegen: number, -- per second on foot
	GasRegenSwinging: number, -- per second on a cable
	HookRange: number,
	BladeMax: number,
	DamageMult: number, -- x nape damage
}

export type Mods = {
	SpeedMult: number?,
	GasMult: number?,
	GasRegenMult: number?,
	ReelMult: number?,
	DamageMult: number?,
	HookRangeAdd: number?,
	BladeAdd: number?,
}

local L = Config.Leveling
local BASE = table.clone(Config.Grapple) -- (never changes, whatever writes to Config.Grapple)

local cache: { [Player]: StatsTable } = {}
local watched: { [Player]: RBXScriptConnection } = {}

local function relevant(attribute: string): boolean
	return attribute == "Level" or attribute == "Equip_Gear" or Upgrades.TrackOf(attribute) ~= nil
end

-- Clears the cache whenever an input changes (once per player).
local function watch(player: Player)
	if watched[player] then
		return
	end
	watched[player] = player.AttributeChanged:Connect(function(attribute)
		if relevant(attribute) then
			cache[player] = nil
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	cache[player] = nil
	local connection = watched[player]
	if connection then
		connection:Disconnect()
		watched[player] = nil
	end
end)

local function number(value: unknown, default: number): number
	if type(value) == "number" and value == value and math.abs(value) < math.huge then
		return value
	end
	return default
end

function Stats.Level(player: Player): number
	return math.clamp(math.floor(number(player:GetAttribute("Level"), 1)), 1, L.MaxLevel)
end

function Stats.XPNext(level: number): number
	if level >= L.MaxLevel then
		return 0
	end
	return math.floor(L.XPBase + L.XPPerLevel * math.max(level, 1) ^ L.XPExponent + 0.5)
end

function Stats.LevelBonus(level: number): { Speed: number, Gas: number, Damage: number }
	local above = math.clamp(math.floor(level), 1, L.MaxLevel) - 1
	return {
		Speed = 1 + above * L.SpeedPerLevel,
		Gas = 1 + above * L.GasPerLevel,
		Damage = 1 + above * L.DamagePerLevel,
	}
end

-- The equipped gear's Mods (Config.Catalog may not exist yet: empty then).
function Stats.GearMods(player: Player): Mods
	local id = player:GetAttribute("Equip_Gear")
	local catalog = (Config :: any).Catalog
	if type(id) ~= "string" or id == "" or type(catalog) ~= "table" then
		return {}
	end
	local item = catalog[id]
	if type(item) ~= "table" or item.Category ~= "Gear" or type(item.Mods) ~= "table" then
		return {}
	end
	return item.Mods :: Mods
end

local function compute(player: Player): StatsTable
	local level = Stats.Level(player)
	local bonus = Stats.LevelBonus(level)
	local mods = Stats.GearMods(player)
	-- Multipliers are kept sensible whatever the catalog says.
	local speed = bonus.Speed * math.clamp(number(mods.SpeedMult, 1), 0.5, 2)
	local gas = bonus.Gas * math.clamp(number(mods.GasMult, 1), 0.5, 3)
	local regen = Upgrades.For(player, "GasRegen") * math.clamp(number(mods.GasRegenMult, 1), 0.5, 3)
	local reel = Upgrades.For(player, "ReelStrength") * math.clamp(number(mods.ReelMult, 1), 0.5, 2)
	return {
		Level = level,
		SpeedMult = speed,
		MaxSpeed = BASE.MaxSpeed * speed,
		SwingPull = BASE.SlackPull * speed,
		BoostForce = BASE.BoostAcceleration * speed,
		DashImpulse = BASE.DashImpulse * speed,
		ReelSpeed = BASE.ReelSpeed * reel,
		ReelForce = BASE.ReelAcceleration * reel,
		GasMax = math.floor(Upgrades.For(player, "GasTank") * gas + 0.5),
		GasRegen = BASE.GasRegenPerSecondGrounded * regen,
		GasRegenSwinging = BASE.GasRegenPerSecondSwinging * regen,
		HookRange = Upgrades.For(player, "HookRange") + math.clamp(number(mods.HookRangeAdd, 0), 0, 100),
		BladeMax = math.max(1, math.floor(Upgrades.For(player, "BladeCount") + math.clamp(number(mods.BladeAdd, 0), -4, 8))),
		DamageMult = bonus.Damage * math.clamp(number(mods.DamageMult, 1), 0.5, 3),
	}
end

function Stats.For(player: Player): StatsTable
	local stats = cache[player]
	if not stats then
		watch(player)
		stats = compute(player)
		if player.Parent then
			cache[player] = stats
		end
	end
	return stats :: StatsTable
end

-- Config.Grapple as this player's rig has it.
function Stats.Grapple(player: Player): typeof(Config.Grapple)
	local s = Stats.For(player)
	local settings = table.clone(BASE)
	settings.MaxSpeed = s.MaxSpeed
	settings.SlackPull = s.SwingPull
	settings.BoostAcceleration = s.BoostForce
	settings.DashImpulse = s.DashImpulse
	settings.ReelSpeed = s.ReelSpeed
	settings.ReelAcceleration = s.ReelForce
	settings.GasMax = s.GasMax
	settings.GasRegenPerSecondGrounded = s.GasRegen
	settings.GasRegenPerSecondSwinging = s.GasRegenSwinging
	settings.Range = s.HookRange
	return settings
end

-- Calls `callback` whenever one of the player's stats may have changed.
function Stats.Changed(player: Player, callback: () -> ()): RBXScriptConnection
	return player.AttributeChanged:Connect(function(attribute)
		if relevant(attribute) then
			cache[player] = nil -- (in case this runs before the cache's own watcher)
			callback()
		end
	end)
end

return Stats
