--!strict
-- Every tuning number for Giant Hunters in one place.

local Config = {}

Config.GAME_NAME = "Giant Hunters"

-- === Grapple rig (client-simulated movement) ================================
-- Modelled on the anime's gear: hooks fly out and bite, the cables stay taut
-- (they auto-wind any slack), so letting gravity take you makes you SWING
-- around the anchor. Gas reels you in hard, or boosts you when unhooked.
Config.Grapple = {
	Range = 170, -- studs a hook can reach
	HookSpeed = 480, -- studs/s the hook flies before it bites
	ReelSpeed = 70, -- studs/s the cable shortens while reeling (gas)
	ReelAcceleration = 110, -- extra pull toward the anchor while reeling
	SlackPull = 18, -- gentle pull while just hanging on, keeps swings lively
	BoostAcceleration = 90, -- unhooked gas burst along the camera
	AirControl = 35, -- studs/s^2 of WASD steering in the air
	DashImpulse = 60, -- side/forward dash (tap Shift)
	DashCooldown = 0.6,
	MaxSpeed = 170,
	LaunchImpulse = 40, -- upward kick when you hook from the ground
	HookSideOffset = 7, -- left/right hooks aim this far either side of the crosshair
	ReleaseDistance = 4, -- let go automatically when this close to the anchor
	GasMax = 100,
	GasPerSecondReel = 11, -- per reeling hook
	GasPerSecondBoost = 16,
	GasPerDash = 8,
	GasRegenPerSecondGrounded = 6, -- kind to young players: slow refill on foot
}

-- === Blades & slashing (server-validated) ===================================
Config.Blades = {
	Max = 8, -- sharp blades per resupply; one is used per hit
	SlashCooldown = 0.4,
	SlashRange = 12, -- studs from your root to the weak spot
	CleanCutSpeed = 35, -- studs/s: at or above this speed a hit does full damage
}

-- === Giants ==================================================================
export type GiantKind = {
	Name: string,
	Height: number,
	WalkSpeed: number,
	NapeHealth: number,
	GrabReach: number,
	Points: number,
}

Config.GiantKinds = {
	Small = { Name = "Small", Height = 18, WalkSpeed = 12, NapeHealth = 1, GrabReach = 11, Points = 1 },
	Medium = { Name = "Medium", Height = 30, WalkSpeed = 10, NapeHealth = 2, GrabReach = 16, Points = 2 },
	Colossal = { Name = "Colossal", Height = 46, WalkSpeed = 8, NapeHealth = 3, GrabReach = 22, Points = 4 },
} :: { [string]: GiantKind }

Config.Giants = {
	ThinkInterval = 0.25, -- seconds between AI decisions
	SightRange = 420,
	GrabWindup = 0.8, -- seconds of arm-raise warning before a grab lands
	GrabCooldown = 2.5,
	DefeatFadeTime = 2.5,
}

-- === Waves ===================================================================
Config.Waves = {
	FirstDelay = 20,
	Intermission = 15,
	MaxAlive = 14,
}

-- Giants in wave n: a few small ones early, bigger ones as it goes.
function Config.WaveRoster(wave: number): { string }
	local roster = {}
	local count = math.min(2 + wave * 2, Config.Waves.MaxAlive)
	for i = 1, count do
		local kind = "Small"
		if wave >= 2 and i % 3 == 0 then
			kind = "Medium"
		end
		if wave >= 4 and i % 5 == 0 then
			kind = "Colossal"
		end
		table.insert(roster, kind)
	end
	return roster
end

-- === World ===================================================================
Config.World = {
	HalfSize = 320, -- the walled city is a square this far from the centre
	WallHeight = 80,
	WallThickness = 10,
	StreetSpacing = 48,
}

Config.Remotes = {
	Slash = "GH_Slash", -- client -> server ()
	SlashResult = "GH_SlashResult", -- server -> client (result, info)
	State = "GH_State", -- server -> client ({ Blades })
	Resupplied = "GH_Resupplied", -- server -> client ()
	Caught = "GH_Caught", -- server -> client (giantName)
	Wave = "GH_Wave", -- server -> all ({ Wave, Alive, Phase, Countdown })
	Hook = "GH_Hook", -- client -> server (side, part?, localPosition?); server -> others (player, side, part?, localPosition?)
}

Config.Tags = {
	Giant = "Giant",
	Supply = "SupplyStation",
}

return Config
