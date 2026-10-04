--!strict
-- Upgrade levels to effective values (pure helpers, shared by server and
-- client). The tracks and their numbers are in Config.Upgrades.
--
-- The server owns each hunter's levels and publishes them as player
-- attributes, "Up_<Track>" = level (e.g. "Up_GasTank" = 2). Anything that
-- needs an upgraded value reads it through here:
--
--   Upgrades.For(player, "HookRange")     -- studs, with the player's level
--   Upgrades.Value("GasTank", 3)          -- a value at a given level
--   Upgrades.GrappleSettings(player)      -- Config.Grapple with upgrades only
--
-- The final numbers (upgrades + level + gear) come from Stats.lua.

local Config = require(script.Parent.Config)

local Upgrades = {}

local PREFIX = "Up_"

-- The rig's numbers before any upgrade.
local BASE_GRAPPLE = table.clone(Config.Grapple)

function Upgrades.Attribute(name: string): string
	return PREFIX .. name
end

-- The track an attribute name belongs to ("Up_GasTank" -> "GasTank"), or nil.
function Upgrades.TrackOf(attribute: string): string?
	if string.sub(attribute, 1, #PREFIX) == PREFIX then
		local name = string.sub(attribute, #PREFIX + 1)
		if Config.Upgrades.Tracks[name] then
			return name
		end
	end
	return nil
end

function Upgrades.MaxLevel(name: string): number
	local track = Config.Upgrades.Tracks[name]
	return if track then #track.Costs else 0
end

-- Marks to buy the level after `level`, or nil at the top (or for an
-- unknown track).
function Upgrades.Cost(name: string, level: number): number?
	local track = Config.Upgrades.Tracks[name]
	return track and track.Costs[level + 1]
end

-- The effective value of a track at `level` (clamped to the track).
function Upgrades.Value(name: string, level: number?): number
	local track = Config.Upgrades.Tracks[name]
	if not track then
		return 0
	end
	local index = math.clamp(math.floor(level or 0), 0, #track.Values - 1) + 1
	return track.Values[index]
end

-- A player's level on a track, from their attribute (0 if unset or bad).
function Upgrades.Level(player: Player, name: string): number
	local level = player:GetAttribute(PREFIX .. name)
	if type(level) ~= "number" or level ~= level then
		return 0
	end
	return math.clamp(math.floor(level), 0, Upgrades.MaxLevel(name))
end

function Upgrades.For(player: Player, name: string): number
	return Upgrades.Value(name, Upgrades.Level(player, name))
end

-- How the shop shows a value ("160", "+20%", "190 studs").
function Upgrades.Describe(name: string, value: number): string
	local track = Config.Upgrades.Tracks[name]
	local format = track and track.Format or "Number"
	if format == "Percent" then
		-- Multipliers (around 1) show the gain; chances (under 1) show as is.
		local first = track and track.Values[1] or 0
		local percent = if first >= 1 then (value - 1) * 100 else value * 100
		return `+{math.floor(percent + 0.5)}%`
	elseif format == "Studs" then
		return `{math.floor(value + 0.5)} studs`
	end
	return tostring(math.floor(value + 0.5))
end

-- Config.Grapple as this player's rig has it.
function Upgrades.GrappleSettings(player: Player): typeof(Config.Grapple)
	local settings = table.clone(BASE_GRAPPLE)
	local regen = Upgrades.For(player, "GasRegen")
	local reel = Upgrades.For(player, "ReelStrength")
	settings.GasMax = Upgrades.For(player, "GasTank")
	settings.GasRegenPerSecondGrounded = BASE_GRAPPLE.GasRegenPerSecondGrounded * regen
	settings.GasRegenPerSecondSwinging = BASE_GRAPPLE.GasRegenPerSecondSwinging * regen
	settings.ReelSpeed = BASE_GRAPPLE.ReelSpeed * reel
	settings.ReelAcceleration = BASE_GRAPPLE.ReelAcceleration * reel
	settings.Range = Upgrades.For(player, "HookRange")
	return settings
end

-- Kept for older callers, and does nothing now: the grapple and the HUD read
-- the live, complete numbers (upgrades, level, gear) from Stats.lua, and
-- Config.Grapple stays the base rig.
function Upgrades.ApplyToGrapple(_player: Player) end

return Upgrades
