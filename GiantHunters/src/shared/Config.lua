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
	DashImpulse = 60, -- side/forward dash (tap Ctrl or C; Shift stays shift-lock)
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
	EscapeHop = 70, -- upward kick when you wriggle out of a giant's hand
	GasRegenPerSecondSwinging = 1.5, -- a trickle while hooked, so nobody is ever stranded
	GiantStandOff = 2, -- reeling onto a giant stops this far off its skin
}

-- === Blades & slashing (server-validated) ===================================
Config.Blades = {
	Max = 8, -- sharp blades per resupply; one is used per hit
	SlashCooldown = 0.4,
	SlashRange = 12, -- studs from your root to what you cut
	CleanCutSpeed = 35, -- studs/s: at or above this speed a hit does full damage
	FallSpeedWeight = 0.3, -- just dropping counts this much toward a clean cut's speed
	SlashCooldownSlack = 0.3, -- the server lets a slash arrive this early (network jitter)
}

-- The three classic cuts. Only the nape takes a giant down; the other two
-- set it up (and save friends).
Config.Cuts = {
	TripTime = 4.5, -- an ankle cut drops the giant to its knees this long
	DazeTime = 4, -- a cut across the eyes (or a cannonball) dazes it this long
	EyesFrontDot = 0.25, -- you have to be in front of a face to reach the eyes
	-- Diminishing returns: each trip or daze on the same giant within
	-- RepeatWindow seconds lasts RepeatFactor as long (never under MinStun),
	-- and only the first one scores.
	RepeatWindow = 12,
	RepeatFactor = 0.6,
	MinStun = 1.2,
	-- The animated nape can sit a little off the server's rest pose while a
	-- giant lunges, holds or kneels: this much extra reach then.
	PosedNapeSlack = 3,
}

-- === Hunters: score, combo, ranks ============================================
Config.Hunters = {
	ComboWindow = 8, -- seconds after a takedown in which the next one chains
	MaxCombo = 5, -- points multiplier cap
	SpeedKill = 70, -- studs/s: a takedown this fast earns a bonus point
	TripPoints = 1,
	DazePoints = 1,
	RescuePoints = 3,
	CannonPoints = 1,
	FlareCooldown = 6,
	StruggleRate = 12, -- max wriggles a second the server counts
}

-- Ranks for this server session, by points.
Config.Ranks = {
	{ Name = "Recruit", Points = 0 },
	{ Name = "Scout", Points = 10 },
	{ Name = "Hunter", Points = 25 },
	{ Name = "Veteran", Points = 50 },
	{ Name = "Captain", Points = 90 },
	{ Name = "Commander", Points = 150 },
}

function Config.RankFor(points: number): string
	local name = Config.Ranks[1].Name
	for _, rank in Config.Ranks do
		if points >= rank.Points then
			name = rank.Name
		end
	end
	return name
end

-- === Giants ==================================================================
export type GiantLook = {
	Body: string?, -- force a body type (see GiantFactory)
	Hair: string?, -- force a hair style
	Shorts: Color3?,
	Crazy: boolean?, -- odd eyes: the "abnormal" look
	Armor: boolean?, -- rock plates, one of them over the nape
	Face: string?, -- force an expression: "Grin", "Sleepy" or "Gape"
	Beard: boolean?, -- force a beard (true) or none (false)
}

export type GiantKind = {
	Name: string,
	Display: string,
	Height: number,
	WalkSpeed: number,
	NapeHealth: number,
	GrabReach: number,
	Points: number,
	Armor: number?, -- hits that crack the rock plate over the nape first
	Abnormal: boolean?, -- sprints, zig-zags and leaps; picks its own targets
	Powers: boolean?, -- throws boulders at rooftop hunters and roars them away
	Look: GiantLook?,
}

Config.GiantKinds = {
	Small = { Name = "Small", Display = "Small Giant", Height = 18, WalkSpeed = 12, NapeHealth = 1, GrabReach = 11, Points = 1 },
	Medium = { Name = "Medium", Display = "Giant", Height = 30, WalkSpeed = 10, NapeHealth = 2, GrabReach = 16, Points = 2 },
	Colossal = { Name = "Colossal", Display = "Colossal Giant", Height = 46, WalkSpeed = 8, NapeHealth = 3, GrabReach = 22, Points = 4 },
	Runner = {
		Name = "Runner",
		Display = "Runner",
		Height = 24,
		WalkSpeed = 24,
		NapeHealth = 1,
		GrabReach = 13,
		Points = 3,
		Abnormal = true,
		Look = { Body = "Lanky", Hair = "Spiky", Shorts = Color3.fromRGB(240, 160, 40), Crazy = true, Face = "Gape", Beard = false },
	},
	Armored = {
		Name = "Armored",
		Display = "Armored Giant",
		Height = 40,
		WalkSpeed = 8,
		NapeHealth = 2,
		GrabReach = 19,
		Points = 8,
		Armor = 3,
		Look = { Body = "Stocky", Hair = "Bald", Shorts = Color3.fromRGB(70, 70, 80), Armor = true },
	},
	-- Shows up now and then from wave 3: throws boulders at hunters who think
	-- they're safe on the rooftops, and roars anyone close away.
	Beast = {
		Name = "Beast",
		Display = "Beast Giant",
		Height = 52,
		WalkSpeed = 8,
		NapeHealth = 4,
		GrabReach = 24,
		Points = 12,
		Powers = true,
		Look = { Body = "Gangly", Hair = "Mop", Shorts = Color3.fromRGB(60, 46, 40), Beard = true, Face = "Gape" },
	},
	-- A player who took the titan power, transformed (see ShifterService).
	Shifter = {
		Name = "Shifter",
		Display = "Titan Shifter",
		Height = 34,
		WalkSpeed = 0,
		NapeHealth = 3,
		GrabReach = 0,
		Points = 8,
		Look = { Body = "Stocky", Hair = "Mop", Shorts = Color3.fromRGB(70, 60, 55) },
	},
	-- Event only: peeks over the wall and kicks the gate in. Can't be hurt.
	Wallbreaker = {
		Name = "Wallbreaker",
		Display = "Wallbreaker",
		Height = 175, -- head and shoulders above the 110-stud wall
		WalkSpeed = 0,
		NapeHealth = 1,
		GrabReach = 0,
		Points = 0,
		Look = { Body = "Lanky", Hair = "Bald", Shorts = Color3.fromRGB(110, 60, 50), Face = "Grin", Beard = false },
	},
} :: { [string]: GiantKind }

-- The Beast Giant's powers.
Config.Beast = {
	ThrowEvery = { 5, 8 }, -- seconds between boulders
	ThrowRange = 340,
	ThrowFlight = 1.3, -- seconds in the air: room to dodge
	ImpactRadius = 12,
	RoarEvery = 14,
	RoarRadius = 60,
	Chance = 0.5, -- per wave, from wave 3 (never more than one at a time)
}

Config.Giants = {
	ThinkInterval = 0.25, -- seconds between AI decisions
	SightRange = 460,
	GrabWindup = 0.8, -- seconds of arm-raise warning before a grab lands
	GrabCooldown = 3,
	HoldTime = 3.5, -- seconds a grabbed hunter has to wriggle free (or be rescued)
	StruggleToEscape = 9, -- wriggles needed to get free
	SwatWindup = 0.5, -- seconds of wind-up before a swat lands
	SwatCooldown = 3.5,
	SwatForce = 105,
	SwatReach = 0.5, -- x height, around the head; never reaches behind the giant
	BehindDot = -0.2, -- "behind" = further back than this from the giant's facing
	DefeatFadeTime = 2.5,
	RunnerLeap = { 3, 6 }, -- seconds between a runner's leaps
}

-- === Rounds & waves ===========================================================
-- A round: the Wallbreaker kicks the gate in, then waves pour through the
-- breach; the last wave brings an Armored Giant. Clear it and the district is
-- saved, the gate is rebuilt, and the next round is a little harder.
Config.Waves = {
	FirstDelay = 20,
	Intermission = 12,
	BetweenRounds = 18,
	WavesPerRound = 5,
	MaxAlive = 16, -- never more giants than this on the field (the rest queue up)
	BeastFromWave = 3,
	-- A wave can't drag on forever: after TimeLimit seconds every giant
	-- storms into town, and stragglers further than StragglerRadius from the
	-- centre steam away.
	TimeLimit = 150,
	StragglerRadius = 620,
	HurrySpeed = 1.4,
	RoamChance = 0.2, -- giants that first roam the wilds (the forests, the training grounds, the castle)
}

-- More hunters, more giants: the roster scales with the player count.
function Config.WaveScale(players: number): number
	return math.clamp(0.5 + 0.25 * players, 0.6, 2)
end

function Config.WaveRoster(round: number, wave: number, scale: number?): { string }
	local roster = {}
	local base = 2 + wave * 2 + (round - 1) * 2
	local count = math.min(math.max(math.round(base * (scale or 1)), 1), Config.Waves.MaxAlive)
	for i = 1, count do
		local kind = "Small"
		if wave >= 2 and i % 3 == 0 then
			kind = "Medium"
		end
		if wave >= 3 and i % 5 == 0 then
			kind = "Runner"
		end
		if wave >= 4 and i % 7 == 0 then
			kind = "Colossal"
		end
		table.insert(roster, kind)
	end
	if wave >= Config.Waves.WavesPerRound then
		for _ = 1, 1 + (round - 1) // 2 do
			table.insert(roster, "Armored")
		end
	end
	return roster
end

-- === World ===================================================================
-- A round walled district: the Great Wall rings the town, the south gate
-- faces the wilds (and the giants), hunters start on top of the north wall.
-- Angles are radians measured from +Z (south) toward +X (east).
Config.World = {
	WallRadius = 300, -- inner face of the Great Wall
	WallThickness = 16,
	WallHeight = 110,
	WallSegments = 48,
	GateAngle = 0, -- the south gate
	GateWidth = 36,
	GateHeight = 56,
	LandRadius = 1300, -- the land outside the wall reaches this far; hills beyond
	PlazaRadius = 56,
	RingRoads = { 120, 200 }, -- radii of the two ring roads
	RoadWidth = 16,
	PerimeterRoad = 272, -- the street running round inside the wall starts here
	AvenueAngles = { 0, 60, 120, 180, 240, 300 }, -- degrees
	AvenueWidth = 22,
	-- Reach: how far east and west (|x|) the river runs before it ends in a
	-- round pool, well short of the hills.
	River = { Z = -150, Width = 26, Wave = 18, WaveLength = 80, WaterY = -2, Reach = 1130, PoolRadius = 38 },
	-- The edge of the world: the land is a round disc this wide (hills
	-- included), and an invisible wall that hooks pass through keeps
	-- everyone inside the hill ring.
	EdgeRadius = 1450,
	BoundaryRadius = 1290,
	BoundaryHeight = 420,
	GiantSpawnRadius = 680, -- giants appear this far out, south of the wall
	-- The old castle (west), on its hill: shared so the giants can keep off it.
	Castle = { Angle = math.rad(282), Radius = 900, HillRadius = 120, Top = 50 },
}

Config.Remotes = {
	Slash = "GH_Slash", -- client -> server ()
	SlashResult = "GH_SlashResult", -- server -> client (result, info, position?)
	State = "GH_State", -- server -> client ({ Blades, MaxBlades, Combo, Points, Rank })
	Resupplied = "GH_Resupplied", -- server -> client ()
	Caught = "GH_Caught", -- server -> client (giantName)
	Wave = "GH_Wave", -- server -> all ({ Round, Wave, Waves, Alive, Phase, Countdown })
	Hook = "GH_Hook", -- client -> server (side, part?, localPosition?); server -> others (player, side, part?, localPosition?)
	Held = "GH_Held", -- server -> client ("Grabbed", { Time, Needed }) | ("Free", reason)
	Struggle = "GH_Struggle", -- client -> server ()
	Knocked = "GH_Knocked", -- server -> client (push: Vector3)
	Flare = "GH_Flare", -- client -> server ()
	Feed = "GH_Feed", -- server -> all (text, tone)
	Announce = "GH_Announce", -- server -> all (title, subtitle, tone)
	Shake = "GH_Shake", -- server -> all (origin: Vector3, strength: number)
	Shift = "GH_Shift", -- client -> server ("Choose", side) | ("Decline") | ("Transform") | ("Punch") | ("Roar")
	Tutorial = "GH_Tutorial", -- client -> server ("Done")
}
-- (Held also sends ("Wriggle", { Count, Needed }): the server's own count of
-- a held hunter's wriggles, which drives the wriggle bar. Wave also carries
-- District, DistrictMax and TimeLeft.)

Config.Tags = {
	Giant = "Giant",
	Supply = "SupplyStation",
	Cannon = "WallCannon",
	Spin = "Spin", -- client spins these (windmill sails)
	NightLight = "NightLight", -- lanterns and torches: lit at night (client)
	LitWindow = "LitWindow", -- windows that glow warm at night (client)
	PowerOrb = "PowerOrb",
	DummyNape = "DummyNape", -- training dummies' targets
	MapBoundary = "MapBoundary", -- the invisible wall round the edge of the land
}

-- === Day and night ===========================================================
-- A full 24 hours every DayMinutes real minutes. The server only moves the
-- clock; each client paints the sky, the light and the lamps from it.
Config.DayNight = {
	DayMinutes = 16,
	StartTime = 9,
	NightStart = 20, -- lamps and torches on, giants' eyes glow, giants faster
	NightEnd = 5,
	NightSpeed = 1.2, -- giants walk this much faster in the dark
}

-- === Titan shifters ============================================================
-- Now and then a glowing crystal appears in town. Whoever takes it chooses a
-- side and can turn into a titan for a while: on the hunters' side your
-- punches crush giants; on the giants' side they knock hunters out (and the
-- hunters can cut your nape). Never more than Max shifters at once.
Config.Shifters = {
	Max = 2,
	OrbEvery = 75, -- seconds between crystals while there's room for a shifter
	Duration = 60, -- seconds as a titan
	Cooldown = 40, -- before you can transform again
	WalkSpeed = 30,
	PunchCooldown = 0.9,
	PunchReach = 0.5, -- x height, in front of the titan
	RoarCooldown = 12,
	RoarRadius = 70,
	KnockoutPoints = 0, -- a rogue titan knocking out a hunter (no farming players)
	KnockoutImmunity = 10, -- seconds a knocked-out hunter can't be knocked out again
	PowerLasts = 240, -- seconds before an unused (or used) titan power fades
}

-- === Gameplay systems ===========================================================
-- (Grouped here: the district's health, anti-cheat tolerances, saving, the
-- map edge, and the action prompts.)

-- The district's health: drains while giants are inside the wall, and when
-- hunters are grabbed or caught. At zero the district falls and it's back to
-- round 1. Full again at the start of every round.
Config.District = {
	Health = 100,
	DrainPerGiant = 0.25, -- per second, per giant inside the wall (x its height / 30)
	MaxDrain = 3, -- per second, however many are inside
	GrabDamage = 1,
	CaughtDamage = 4,
	FallenPause = 8, -- seconds of "DISTRICT FALLEN" before the reset
}

-- The server watches every hunter's position itself (it never trusts the
-- client's velocity): speeds for clean cuts come from this, and a hunter who
-- moves faster than the rig allows can't cut anything for a moment.
Config.AntiCheat = {
	SpeedTolerance = 1.4, -- x Config.Grapple.MaxSpeed
	TeleportSlack = 25, -- studs of extra movement allowed per check (lag, a titan's hip)
	SuspectTime = 2, -- seconds of no cuts after a too-fast move
	HookRelayRate = 10, -- cable updates a second relayed to other players
}

-- Saved between sessions (DataStoreService; works without it in Studio).
Config.Data = {
	Store = "GiantHunters_v1",
	AutosaveEvery = 60,
	Retries = 4,
}

-- The edge of the world: past this (or below FloorY) you're put back on the
-- wall.
Config.Bounds = {
	Margin = 10, -- studs inside Config.World.LandRadius
	FloorY = -60,
}

-- Action prompts (resupply, cannons, the titan crystal): keys nothing else
-- uses (E is the right hook, X a gamepad slash).
Config.Prompts = {
	Key = Enum.KeyCode.R,
	Gamepad = Enum.KeyCode.DPadDown,
}

-- Sounds: built-in Roblox client sound files (rbxasset://...), shipped with
-- every Roblox client - nothing uploaded, no asset ids. Swap any of them for
-- your own uploaded sound ("rbxassetid://<id>") whenever you like.
Config.Sounds = {
	Slash = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.6, Pitch = 1 },
	Hook = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.35, Pitch = 1.6 },
	Resupply = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.7, Pitch = 1 },
	Step = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Pitch = 0.35 },
	Boom = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Pitch = 0.22 },
	Wind = { Id = "rbxasset://sounds/action_falling.mp3", Volume = 0.5, Pitch = 1 },
	Splash = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.6, Pitch = 1 },
}

return Config
