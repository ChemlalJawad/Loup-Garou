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
	Face: string?, -- force an expression: "Grin", "Sleepy", "Gape", "Smirk", "Oh", "Bunny" or "Stern"
	Beard: boolean?, -- force a beard (true) or none (false)
	Skin: Color3?, -- fixed colours, so a signature giant always looks the same
	HairColor: Color3?,
	EyeColor: Color3?, -- glowing eyes of this colour
	Steam: boolean?, -- steam rising off it (giants 46+ tall always steam a little)
	Brows: string?, -- "Worried", "Angry", "Raised", "Flat" or "Heavy" (a brow ridge)
	Nose: string?, -- "Ball", "Button", "Long" or "Wide"
	Ears: string?, -- "Round", "Big" or "None"
	Stone: boolean?, -- rocky skin with glowing seams (the Wallbreaker)
	SkinMaterial: Enum.Material?, -- the skin's material (titan skins, Config.CosmeticItems)
	Fur: boolean?, -- tufts of fur on the shoulders, back, chest and forearms
	Cheeks: boolean?, -- ridge lines under the eyes (titan shifters)
	Pose: string?, -- "Crawl" (on all fours) or "Ape" (knuckles near the ground)
	Guard: boolean?, -- a crystal hand that can cover the nape (attribute "Guarding")
	Crystal: boolean?, -- a crown of crystal spikes and crystal shoulder points (titan forms)
	Spines: boolean?, -- short horn-like spines down the upper back, below the nape (titan forms)
	-- Oddities (the abnormal variants). Left nil, they're rolled (see
	-- Config.GiantOddities); set true or false to force one on or off.
	Tilt: boolean?, -- the head hangs permanently to one side
	LongNeck: boolean?, -- a neck twice as long
	Tongue: boolean?, -- tongue lolling out of a gaping mouth (forces Face "Gape")
	OddArms: boolean?, -- one arm much longer than the other
}

-- How often the oddities turn up. Abnormals (Runners) roll each one at
-- AbnormalChance; plain giants (no fixed Look) get a single one, rarely.
-- Signature giants (a fixed Look that isn't abnormal) never roll.
Config.GiantOddities = {
	AbnormalChance = 0.35,
	NormalChance = 0.06,
	Names = { "Tilt", "LongNeck", "Tongue", "OddArms" },
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
		Look = { Body = "Lanky", Hair = "Spiky", Shorts = Color3.fromRGB(240, 160, 40), Crazy = true, Face = "Gape", Beard = false, Brows = "Raised" },
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
		Look = { Body = "Stocky", Hair = "Bald", Shorts = Color3.fromRGB(70, 70, 80), Armor = true, Skin = Color3.fromRGB(214, 168, 136), Brows = "Angry", Face = "Grin", Beard = false },
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
		Look = {
			Body = "Ape",
			Pose = "Ape",
			Hair = "Mop",
			Shorts = Color3.fromRGB(60, 46, 40),
			Beard = true,
			Face = "Gape",
			Skin = Color3.fromRGB(84, 62, 50), -- dark fur all over (Fur)
			HairColor = Color3.fromRGB(62, 45, 36),
			EyeColor = Color3.fromRGB(255, 200, 80),
			Brows = "Angry",
			Ears = "Big",
			Fur = true,
		},
	},
	-- Abnormal and quick on her feet: zig-zags and leaps like a Runner, and can
	-- cover her nape with a crystal hand (attribute "Guarding", see GiantFactory).
	Sprinter = {
		Name = "Sprinter",
		Display = "Sprinter",
		Height = 28,
		WalkSpeed = 22,
		NapeHealth = 2,
		GrabReach = 14,
		Points = 5,
		Abnormal = true,
		Look = { Body = "Agile", Hair = "Ponytail", Face = "Smirk", Brows = "Angry", Nose = "Button", Beard = false, Guard = true, Shorts = Color3.fromRGB(150, 60, 90) },
	},
	-- Slow, on all fours, nape on top: the easy one for new hunters.
	Crawler = {
		Name = "Crawler",
		Display = "Crawler",
		Height = 22,
		WalkSpeed = 9,
		NapeHealth = 1,
		GrabReach = 10,
		Points = 1,
		Look = { Body = "Crawler", Pose = "Crawl", Face = "Grin", Hair = "Spiky", Beard = false }, -- nothing on the back of its head: the nape is right there
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
		Look = {
			Body = "Stocky",
			Hair = "Bun",
			Shorts = Color3.fromRGB(70, 60, 55),
			Face = "Stern",
			Brows = "Angry",
			Beard = false,
			Cheeks = true,
			Steam = true,
			Skin = Color3.fromRGB(226, 178, 142),
			HairColor = Color3.fromRGB(60, 40, 30),
			EyeColor = Color3.fromRGB(120, 230, 150), -- re-tinted by side on clients (attribute "Side")
		},
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
		Look = {
			Body = "Lanky",
			Hair = "Bald",
			Shorts = Color3.fromRGB(110, 60, 50),
			Face = "Grin",
			Beard = false,
			Skin = Color3.fromRGB(126, 104, 98), -- rock, a little red
			Stone = true,
			EyeColor = Color3.fromRGB(255, 170, 60),
			Brows = "Heavy",
			Nose = "Wide",
			Ears = "None",
			Steam = true,
		},
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
	-- The Sprinter's guard: with a hunter within GuardRange x her height
	-- behind her, now and then (GuardChance) the hand rises (GuardWindup s),
	-- covers the nape for GuardTime s, then rests GuardCooldown s.
	GuardRange = 1.2,
	GuardChance = 0.6,
	GuardWindup = 0.5,
	GuardTime = 1.5,
	GuardCooldown = 6,
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
	StragglerRadius = 760, -- beyond the giant spawn ring (World.GiantSpawnRadius)
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
		if wave % 2 == 1 and i == 2 then
			kind = "Crawler" -- one now and then, from the first wave
		end
		if wave >= 3 and i % 8 == 0 then
			kind = "Sprinter"
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
	Shift = "GH_Shift", -- client -> server ("Choose", side) | ("Decline") | ("Transform") | ("Primary") | ("Secondary") | ("Gauge"); server -> client ("Dash", velocity)
	Tutorial = "GH_Tutorial", -- client -> server ("Done")
	-- Progression (ProgressService / UpgradeShop):
	Progress = "GH_Progress", -- client -> server ("Sync") | ("Buy", track) | ("Cape", id) | ("Title", id?); server -> client ("State", snapshot) | ("Result", ok, message) | ("Challenge", text, reward) | ("Open")
	RoundSummary = "GH_RoundSummary", -- server -> client ({ Round, Won, Takedowns, CleanCuts, BestSpeed, Points, Marks })
	XP = "GH_XP", -- server -> client ("XP", amount) | ("LevelUp", level, marks) (Level, XP, XPNext are player attributes)
	-- Shop: gear, techniques, titans (ShopService / TechniqueService):
	Shop = "GH_Shop", -- client -> server ("Sync") | ("Buy", category, id) | ("Equip", category, id); category "Gear" | "Technique" | "Titan"; server -> client ("State", { Owned, Equip }) | ("Result", ok, message)
	Technique = "GH_Technique", -- client -> server (aimPoint: Vector3?, the world point under the crosshair, slot: 2? for the second technique); server -> client ("Go", id, cooldown) | ("Denied", id, reason, wait) | ("Hits", id, count)
	-- Robux shop, styles and the season (MonetizationService / ShopService / SeasonService / UpgradeShop):
	Monetization = "GH_Monetization", -- client -> server ("Sync") | ("Buy", key, arg?) | ("BuyCosmetic", itemId); server -> client ("State", { Passes, Season }) | ("Result", ok, message); server -> all ("Fireworks", position, buyerName)
	Style = "GH_Style", -- client -> server ("Sync") | ("Buy", itemId) (Marks) | ("Equip", slot, itemId); server -> client ("State", { Owned, Equip }) | ("Result", ok, message)
	Season = "GH_Season", -- client -> server ("Sync") | ("Claim", "Free" | "Premium", tier); server -> client ("State", { Id, Name, XP, Tier, ClaimedFree, ClaimedPremium, Premium, EndsIn? }) | ("Result", ok, message)
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
	Sway = "Sway", -- washing and awnings: moved by the breeze on each client
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

-- === Weather =================================================================
-- Now and then a soft rain or a fog bank rolls in for a few minutes (never
-- while someone is still doing the tutorial). The server picks it and sets
-- the Workspace attribute "Weather" ("Clear", "Rain" or "Fog"); each client
-- fades the sky, the rain and the townsfolk into it (Weather.lua, Sky.lua).
Config.Weather = {
	Attribute = "Weather",
	ClearMinutes = { 6, 11 }, -- dry spell between two fronts
	Minutes = { 2, 4 }, -- how long a front lasts
	RainChance = 0.6, -- rain, else fog
	FadeSeconds = 20, -- clients ease in and out over this
	RainRate = 420, -- drops a second round the camera (a third on phones)
}

-- === Ambient life (client only) ==============================================
-- Townsfolk strolling the streets by day (indoors when the giants come),
-- flocks of birds over the roofs, washing and awnings moving in the breeze.
-- All of it is made and moved on each client, near the camera only.
Config.Ambient = {
	Villagers = 30, -- most townsfolk out at once (by day)
	VillagersNight = 8,
	VillagersLowEnd = 14, -- phones and low graphics
	VillagerRange = 250, -- studs from the camera they live within
	VillagerSpeed = { 4, 6.5 }, -- strolling; they run at x2.4 when a wave is on
	Flocks = 3,
	FlocksLowEnd = 2,
	BirdsPerFlock = 6,
	BirdScatter = 130, -- a giant this close sends a flock flying
	SwayRange = 220, -- washing and awnings move only this close
}

-- === Titan shifters ============================================================
-- Now and then a glowing crystal appears in town. Whoever takes it chooses a
-- side and can turn into a titan for a while (their equipped form, see
-- Config.TitanForms): on the hunters' side your punches crush giants; on
-- the giants' side they knock hunters out (and the hunters can cut your
-- nape). Never more than Max shifters at once.
Config.Shifters = {
	Max = 2,
	OrbEvery = 75, -- seconds between crystals while there's room for a shifter
	Duration = 60, -- seconds as a titan
	Cooldown = 40, -- before you can transform again
	-- (Walk speed, size, nape health and the powers come from the form:
	-- Config.TitanForms.)
	PounceSpeed = 95, -- Swiftfang's leap, studs a second forward (plus a hop)
	BoulderFlight = 1.1, -- seconds a thrown boulder is in the air
	PushForce = 100, -- how hard slams, vents and crystals push hunters away
	KnockoutPoints = 0, -- a rogue titan knocking out a hunter (no farming players)
	KnockoutImmunity = 10, -- seconds a knocked-out hunter can't be knocked out again
	PowerLasts = 240, -- seconds before an unused (or used) titan power fades
	-- The Titan Gauge: players who own and equip a titan form (other than
	-- "Default") fill it with takedowns made on foot; full, T transforms
	-- them straight away (hunters' side only, still within Max).
	GaugeMax = 100,
	GaugeTakedown = 20,
	GaugeClean = 10, -- extra for a clean cut
	GaugeDuration = 45, -- seconds as a titan from a full gauge (then it's gone)
}

-- === Titan forms ===============================================================
-- What a shifter turns into. Bought with Marks in the shop ("Titans" tab,
-- ShopService), which sets the player attribute "Equip_Titan" to the form's
-- Id ("" or missing = "Default"). ShifterService reads it when you
-- transform, from a crystal or a full Titan Gauge. Every form has two
-- powers: Primary (click / F) and Secondary (G). `Action` picks what the
-- server does; Reach, Radius, Range, Duration and Boost tune it.
export type TitanPower = {
	Key: string, -- "Primary" | "Secondary"
	Name: string,
	Cooldown: number,
	Description: string,
	Action: string, -- "Punch" | "Pounce" | "Roar" | "Slam" | "Frenzy" | "Boulder" | "Vent" | "CrystalGuard"
	Reach: number?, -- Punch / Pounce: x height, in front of the titan
	Radius: number?, -- studs
	Range: number?, -- Boulder: studs
	Duration: number?, -- seconds
	Boost: number?, -- Frenzy: x walk speed
}
export type TitanForm = {
	Id: string,
	Display: string,
	Description: string,
	Price: number, -- Marks (never real money)
	LevelRequired: number,
	Order: number,
	Height: number,
	WalkSpeed: number,
	NapeHealth: number,
	DamageTaken: number?, -- x nape damage (rock plates soak some of it)
	Look: GiantLook,
	Powers: { TitanPower },
}

Config.TitanForms = {
	Default = {
		Id = "Default",
		Display = "Classic Titan",
		Description = "The titan the crystal gives everyone: steady, strong and loud.",
		Price = 0,
		LevelRequired = 1,
		Order = 1,
		Height = 34,
		WalkSpeed = 30,
		NapeHealth = 3,
		Look = Config.GiantKinds.Shifter.Look :: GiantLook,
		Powers = {
			{ Key = "Primary", Name = "Punch", Cooldown = 0.9, Action = "Punch", Reach = 0.5, Description = "A big punch: giants stagger." },
			{ Key = "Secondary", Name = "Roar", Cooldown = 12, Action = "Roar", Radius = 70, Description = "Dazes every giant close by (or blows hunters away)." },
		},
	},
	Swiftfang = {
		Id = "Swiftfang",
		Display = "Swiftfang",
		Description = "Small, lean and very fast. Pounces on giants from a distance.",
		Price = 250,
		LevelRequired = 3,
		Order = 2,
		Height = 24,
		WalkSpeed = 42,
		NapeHealth = 2,
		Look = {
			Body = "Agile",
			Hair = "Spiky",
			Shorts = Color3.fromRGB(40, 70, 90),
			Face = "Smirk",
			Brows = "Angry",
			Nose = "Button",
			Ears = "Big",
			Beard = false,
			Cheeks = true,
			Steam = true,
			Spines = true,
			Skin = Color3.fromRGB(196, 150, 140),
			HairColor = Color3.fromRGB(236, 234, 226),
			EyeColor = Color3.fromRGB(120, 230, 150),
		},
		Powers = {
			{ Key = "Primary", Name = "Pounce", Cooldown = 1.6, Action = "Pounce", Reach = 0.7, Description = "Leaps forward and lands a punch at the end of it." },
			{ Key = "Secondary", Name = "Frenzy", Cooldown = 15, Action = "Frenzy", Duration = 5, Boost = 1.5, Description = "5 seconds of top speed, and pounces recharge twice as fast." },
		},
	},
	Boulderhurler = {
		Id = "Boulderhurler",
		Display = "Boulderhurler",
		Description = "Long furry arms that pick up rocks and lob them across town.",
		Price = 400,
		LevelRequired = 5,
		Order = 3,
		Height = 38,
		WalkSpeed = 26,
		NapeHealth = 3,
		Look = {
			Body = "Ape",
			Pose = "Ape",
			Hair = "Mop",
			Shorts = Color3.fromRGB(80, 70, 60),
			Face = "Grin",
			Brows = "Heavy",
			Nose = "Wide",
			Beard = false,
			Fur = true,
			Cheeks = true,
			Steam = true,
			Skin = Color3.fromRGB(176, 140, 96), -- sandy fur all over
			HairColor = Color3.fromRGB(150, 112, 70),
			EyeColor = Color3.fromRGB(120, 230, 150),
		},
		Powers = {
			{ Key = "Primary", Name = "Big Swing", Cooldown = 1.1, Action = "Punch", Reach = 0.62, Description = "Long arms: a punch that reaches further." },
			{ Key = "Secondary", Name = "Boulder Toss", Cooldown = 6, Action = "Boulder", Range = 260, Radius = 16, Description = "Lobs a boulder at the nearest enemy ahead: giants are knocked silly, hunters knocked back." },
		},
	},
	Crystalcrown = {
		Id = "Crystalcrown",
		Display = "Crystalcrown",
		Description = "A crown of crystal, and a crystal hand that shields its nape.",
		Price = 550,
		LevelRequired = 7,
		Order = 4,
		Height = 32,
		WalkSpeed = 32,
		NapeHealth = 3,
		Look = {
			Body = "Lanky",
			Hair = "Bald",
			Shorts = Color3.fromRGB(70, 90, 130),
			Face = "Stern",
			Brows = "Flat",
			Nose = "Button",
			Ears = "None",
			Beard = false,
			Cheeks = true,
			Steam = true,
			Guard = true,
			Crystal = true,
			Skin = Color3.fromRGB(214, 196, 184),
			EyeColor = Color3.fromRGB(120, 230, 150),
		},
		Powers = {
			{ Key = "Primary", Name = "Punch", Cooldown = 0.9, Action = "Punch", Reach = 0.5, Description = "A quick, solid punch." },
			{ Key = "Secondary", Name = "Crystal Guard", Cooldown = 14, Action = "CrystalGuard", Duration = 4, Radius = 28, Description = "Crystals burst out (dazing giants or pushing hunters) and a crystal hand guards your nape for 4 seconds." },
		},
	},
	Stoneguard = {
		Id = "Stoneguard",
		Display = "Stoneguard",
		Description = "Tall and slow, covered in rock plates that soak up nape hits.",
		Price = 700,
		LevelRequired = 9,
		Order = 5,
		Height = 42,
		WalkSpeed = 22,
		NapeHealth = 4,
		DamageTaken = 0.5,
		Look = {
			Body = "Stocky",
			Hair = "Bald",
			Shorts = Color3.fromRGB(60, 60, 70),
			Face = "Stern",
			Brows = "Heavy",
			Nose = "Wide",
			Beard = false,
			Armor = true,
			Cheeks = true,
			Steam = true,
			Skin = Color3.fromRGB(200, 160, 130),
			EyeColor = Color3.fromRGB(120, 230, 150),
		},
		Powers = {
			{ Key = "Primary", Name = "Stone Fist", Cooldown = 1.3, Action = "Punch", Reach = 0.55, Description = "A heavy, slow punch that shakes the street." },
			{ Key = "Secondary", Name = "Ground Slam", Cooldown = 10, Action = "Slam", Radius = 30, Description = "Both fists into the ground: a shockwave dazes every giant within 30 studs (or knocks hunters back)." },
		},
	},
	Steamwarden = {
		Id = "Steamwarden",
		Display = "Steamwarden",
		Description = "A huge, slow titan wrapped in hot steam.",
		Price = 1000,
		LevelRequired = 12,
		Order = 6,
		Height = 52,
		WalkSpeed = 18,
		NapeHealth = 5,
		Look = {
			Body = "Chubby",
			Hair = "Curly",
			Shorts = Color3.fromRGB(120, 60, 50),
			Face = "Oh",
			Brows = "Raised",
			Nose = "Ball",
			Beard = true,
			Cheeks = true,
			Steam = true,
			Skin = Color3.fromRGB(226, 160, 130),
			HairColor = Color3.fromRGB(176, 176, 172),
			EyeColor = Color3.fromRGB(120, 230, 150),
		},
		Powers = {
			{ Key = "Primary", Name = "Heavy Punch", Cooldown = 1.2, Action = "Punch", Reach = 0.45, Description = "A huge fist with a huge reach." },
			{ Key = "Secondary", Name = "Steam Vent", Cooldown = 16, Action = "Vent", Radius = 45, Duration = 4, Description = "Blasts steam for 4 seconds: giants close by stay dazed and the nearest get scalded; hunters are pushed away." },
		},
	},
} :: { [string]: TitanForm }

-- The form a player transforms into: what they have equipped, if it exists
-- and their level allows it (else the Default).
function Config.TitanFormFor(equipped: unknown, level: unknown): TitanForm
	local form = if type(equipped) == "string" then Config.TitanForms[equipped] else nil
	local lvl = if type(level) == "number" then level else 1
	if form and lvl >= form.LevelRequired then
		return form
	end
	return Config.TitanForms.Default
end

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
	SpeedTolerance = 1.4, -- x the hunter's own top speed (Stats.For(player).MaxSpeed)
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

-- === Progression: Marks, upgrades, daily challenges, cosmetics ===============
-- Marks are a saved currency earned in play (never bought): one per point
-- scored, plus bonuses below. They buy upgrades for the rig at the
-- hunters' headquarters (or from the shop button). See Upgrades.lua for the
-- effective values and ProgressService for the rules.
Config.Marks = {
	PerPoint = 1,
	CleanTakedown = 1, -- extra for a takedown with a clean cut
	Rescue = 2, -- extra for cutting a friend loose
	RoundWon = 10, -- for everyone who sees a round through...
	RoundWonPerRound = 2, -- ...plus this x the round number
	DistrictFallen = 3, -- a little something for trying
}

export type UpgradeTrack = {
	Display: string,
	Info: string,
	Costs: { number }, -- Costs[n]: Marks to go from level n-1 to level n
	Values: { number }, -- Values[n + 1]: the effective value at level n (level 0 first)
	Format: string, -- how the shop shows a value: "Number", "Percent" (a x1.2 multiplier shows +20%) or "Studs"
}

Config.Upgrades = {
	Order = { "GasTank", "GasRegen", "ReelStrength", "HookRange", "BladeCount", "BladeEdge" },
	Tracks = {
		GasTank = {
			Display = "Gas Tank",
			Info = "Bigger tanks: more gas for reeling, boosts and dashes.",
			Costs = { 40, 90, 160, 260 },
			Values = { 100, 115, 130, 145, 160 }, -- Config.Grapple.GasMax
			Format = "Number",
		},
		GasRegen = {
			Display = "Gas Refill",
			Info = "Your tanks refill faster on foot and on a cable.",
			Costs = { 40, 90, 160, 260 },
			Values = { 1, 1.2, 1.4, 1.6, 1.8 }, -- x GasRegenPerSecondGrounded / Swinging
			Format = "Percent",
		},
		ReelStrength = {
			Display = "Reel Strength",
			Info = "The reel winds in faster and pulls harder.",
			Costs = { 50, 110, 190, 300 },
			Values = { 1, 1.06, 1.12, 1.18, 1.24 }, -- x ReelSpeed and ReelAcceleration
			Format = "Percent",
		},
		HookRange = {
			Display = "Hook Range",
			Info = "Longer cables: hooks reach further.",
			Costs = { 50, 110, 190, 300 },
			Values = { 170, 180, 190, 200, 210 }, -- Config.Grapple.Range
			Format = "Studs",
		},
		BladeCount = {
			Display = "Blade Box",
			Info = "More spare blades in each box.",
			Costs = { 60, 140, 260 },
			Values = { 8, 9, 10, 12 }, -- blades per resupply (Config.Blades.Max)
			Format = "Number",
		},
		BladeEdge = {
			Display = "Blade Edge",
			Info = "Finer steel: a clean cut sometimes keeps its blade.",
			Costs = { 80, 180, 320 },
			Values = { 0, 0.15, 0.3, 0.45 }, -- chance a clean nape cut uses no blade
			Format = "Percent",
		},
	} :: { [string]: UpgradeTrack },
	ActionCooldown = 0.25, -- seconds between shop requests the server accepts
	PromptDistance = 10,
}

-- === Levels ==================================================================
-- Experience from play raises a hunter's level (1 to MaxLevel, saved). Each
-- level after the first adds a little speed, gas and nape damage (Stats.lua
-- combines them with upgrades and gear). Published as player attributes
-- "Level", "XP" (progress within the level) and "XPNext" (0 at the top).
-- See LevelService.
Config.Leveling = {
	MaxLevel = 50,
	-- XP from `level` to the next: XPBase + XPPerLevel * level ^ XPExponent, rounded.
	XPBase = 60,
	XPPerLevel = 25,
	XPExponent = 1.35,
	-- Bonuses per level above 1 (at 50: about +30% speed, +50% gas, +40% damage).
	SpeedPerLevel = 0.006, -- x top speed, swing pull, gas boost and dash
	GasPerLevel = 0.01, -- x gas capacity
	DamagePerLevel = 0.008, -- x nape damage (armour plates still crack by hits)
	XP = {
		TakedownPerPoint = 15, -- x the giant's Points
		CleanCut = 4, -- every clean nape hit
		CleanTakedown = 6, -- extra when the finishing cut was clean
		Trip = 5,
		Daze = 5,
		Armor = 8, -- cracking an armour plate
		Rescue = 20,
		Cannon = 3,
		ShifterPoint = 10, -- per point scored as (or against) a titan
		RoundWon = 40, -- for everyone who took part...
		RoundWonPerRound = 10, -- ...plus this x the round number
		DistrictFallen = 15,
		ChallengePerMark = 1, -- a finished challenge: its Marks reward in XP...
		ChallengeMin = 40, -- ...but never less than this
		Dummy = 2, -- a training dummy cut...
		DummyPerMinute = 10, -- ...at most this many count a minute
	},
	MarksPerLevel = 5, -- Marks for every level-up...
	MilestoneEvery = 5, -- ...but every 5th level...
	MilestoneMarks = 50, -- ...pays this many instead
}

-- Three daily challenges a day (UTC), picked from the pool by the date, so
-- everyone gets the same three. Progress is saved; finishing one pays out
-- its Marks straight away.
-- Event: what counts. "CleanCut" (a clean nape hit), "Takedown" (Kind: only
-- that giant), "FastTakedown" (a takedown at Config.Hunters.SpeedKill+),
-- "Assist" (Reason: "Trip", "Daze", "Rescue", "Armor"), "Wave" (reach wave
-- Goal), "RoundWon", "Dummy" (a training dummy cut).
export type Challenge = {
	Id: string,
	Text: string,
	Event: string,
	Goal: number,
	Reward: number,
	Kind: string?,
	Reason: string?,
}

Config.Challenges = {
	PerDay = 3,
	Pool = {
		{ Id = "CleanCuts", Text = "Make 5 clean cuts", Event = "CleanCut", Goal = 5, Reward = 30 },
		{ Id = "Takedowns", Text = "Take down 8 giants", Event = "Takedown", Goal = 8, Reward = 30 },
		{ Id = "Rescue", Text = "Cut a friend loose", Event = "Assist", Reason = "Rescue", Goal = 1, Reward = 40 },
		{ Id = "Sprinter", Text = "Take down a Sprinter", Event = "Takedown", Kind = "Sprinter", Goal = 1, Reward = 40 },
		{ Id = "Crawlers", Text = "Take down 3 Crawlers", Event = "Takedown", Kind = "Crawler", Goal = 3, Reward = 25 },
		{ Id = "Armor", Text = "Crack an Armored Giant's plate", Event = "Assist", Reason = "Armor", Goal = 1, Reward = 40 },
		{ Id = "Wave4", Text = "Reach wave 4", Event = "Wave", Goal = 4, Reward = 30 },
		{ Id = "SaveDistrict", Text = "Save the district", Event = "RoundWon", Goal = 1, Reward = 50 },
		{ Id = "Dummies", Text = "Cut 10 training dummies", Event = "Dummy", Goal = 10, Reward = 20 },
		{ Id = "Trips", Text = "Trip 3 giants (ankle cuts)", Event = "Assist", Reason = "Trip", Goal = 3, Reward = 25 },
		{ Id = "Dazes", Text = "Daze 3 giants (eye cuts)", Event = "Assist", Reason = "Daze", Goal = 3, Reward = 25 },
		{ Id = "FastCut", Text = "Take down a giant at full speed (70+)", Event = "FastTakedown", Goal = 1, Reward = 35 },
	} :: { Challenge },
}

-- Cosmetics: no asset ids, just colours and words. Capes (and their emblem)
-- and titles shown above your head, unlocked by rank, by saved totals, or
-- by finishing daily challenges. Unlock: Rank (a rank name), or Stat (a
-- saved total: "Giants", "CleanCuts", "Rescues", "ChallengesDone",
-- "BestRound") with At (how many).
-- Pass: owned while the player owns that game pass (Config.Monetization.GamePasses key).
export type Unlock = { Rank: string?, Stat: string?, At: number?, Pass: string? }
export type Cape = { Id: string, Display: string, Color: Color3, Emblem: Color3, Unlock: Unlock? }
export type Title = { Id: string, Display: string, Unlock: Unlock }

Config.Cosmetics = {
	DefaultCape = "Corps",
	Capes = {
		{ Id = "Corps", Display = "Corps Green", Color = Color3.fromRGB(46, 84, 58), Emblem = Color3.fromRGB(70, 110, 190) },
		{ Id = "Scout", Display = "Scout Blue", Color = Color3.fromRGB(46, 70, 120), Emblem = Color3.fromRGB(220, 220, 230), Unlock = { Rank = "Scout" } },
		{ Id = "Garrison", Display = "Garrison Red", Color = Color3.fromRGB(130, 44, 44), Emblem = Color3.fromRGB(220, 190, 120), Unlock = { Rank = "Hunter" } },
		{ Id = "Royal", Display = "Royal Purple", Color = Color3.fromRGB(86, 52, 120), Emblem = Color3.fromRGB(230, 200, 110), Unlock = { Rank = "Veteran" } },
		{ Id = "Sunrise", Display = "Sunrise Orange", Color = Color3.fromRGB(200, 110, 40), Emblem = Color3.fromRGB(60, 50, 44), Unlock = { Stat = "ChallengesDone", At = 3 } },
		{ Id = "Snow", Display = "Snow White", Color = Color3.fromRGB(226, 228, 232), Emblem = Color3.fromRGB(58, 92, 150), Unlock = { Stat = "ChallengesDone", At = 12 } },
		{ Id = "Midnight", Display = "Midnight", Color = Color3.fromRGB(30, 32, 44), Emblem = Color3.fromRGB(120, 200, 255), Unlock = { Stat = "Giants", At = 150 } },
		{ Id = "Gold", Display = "Commander Gold", Color = Color3.fromRGB(190, 150, 60), Emblem = Color3.fromRGB(46, 84, 58), Unlock = { Rank = "Commander" } },
	} :: { Cape },
	Titles = {
		{ Id = "GiantSlayer", Display = "Giant Slayer", Unlock = { Stat = "Giants", At = 25 } },
		{ Id = "NapeAce", Display = "Nape Ace", Unlock = { Stat = "CleanCuts", At = 50 } },
		{ Id = "Rescuer", Display = "Rescuer", Unlock = { Stat = "Rescues", At = 5 } },
		{ Id = "WallKeeper", Display = "Wall Keeper", Unlock = { Stat = "BestRound", At = 3 } },
		{ Id = "DailyHero", Display = "Daily Hero", Unlock = { Stat = "ChallengesDone", At = 10 } },
		{ Id = "Legend", Display = "Living Legend", Unlock = { Stat = "Giants", At = 500 } },
		{ Id = "EliteCommander", Display = "Elite Commander", Unlock = { Pass = "CommanderPack" } },
	} :: { Title },
	TitleDistance = 70, -- studs: the title over a hunter's head fades out past this
}

-- === Cosmetic items (looks only: no stats, no asset ids) =====================
-- One item worn per slot. The shop (MonetizationService / SeasonService /
-- ShopService) owns buying, owning and equipping, and sets the player
-- attributes "Cos_Cape", "Cos_Blade", "Cos_Trail", "Cos_Gas", "Cos_Cable",
-- "Cos_Defeat" and "Cos_TitanSkin" to an item Id ("" = the default look).
-- The look code (HunterGear, HunterService, GrappleController,
-- CosmeticsClient, ShifterService) only reads them.
--
-- Source: "Free" (everyone has it), "Marks" (Price), "Robux" (ProductKey,
-- mapped by Config.Monetization.Products.Cosmetics), "Season" (a season
-- reward) or "Pass" (PassKey: "CommanderPack" | "ShifterPack").
-- Preview: one or two colours for a swatch in the shop.
--
-- Precedence: Cos_Cape wins over the rank/Marks cape (Config.Cosmetics,
-- the "CapeColor" attribute); Cos_Blade wins over the gear set's Hilt/Edge
-- colours (Config.Catalog Look) and Cos_Trail over its Edge for the trail.
export type CosmeticCape = {
	Color: Color3,
	Emblem: Color3?, -- the shield on the back (default: the corps' blue)
	Pattern: string?, -- "Stripes" | "Stars" | "Trim" | "Split" | "Glow" (a Neon trim)
	PatternColor: Color3?,
}
export type CosmeticBlade = {
	Color: Color3, -- the blade (sharp)
	Edge: Color3, -- the glowing cutting edge
	Material: Enum.Material?, -- default Metal (Glass, Foil, Ice...)
	Reflectance: number?, -- default 0.35
	Transparency: number?, -- (Glass blades)
	Hilt: Color3?,
}
export type CosmeticTrail = {
	Colors: { Color3 }, -- spread evenly along the trail
	Lifetime: number?, -- seconds (default 0.18)
	LightEmission: number?,
	Transparency: number?, -- at the blade (fades to 1)
	Width: number?, -- x the trail's width at the base (WidthScale)
}
export type CosmeticGas = {
	Color: Color3, -- the puff
	Core: Color3, -- the fast streak inside it
	Color2: Color3?, -- the puff fades to this
	LightEmission: number?,
}
export type CosmeticCable = {
	Color: Color3,
	Color2: Color3?, -- at the hook end
	LightEmission: number?, -- added to the cable's own glow
	Width: number?, -- x the cable's width
}
export type CosmeticDefeat = {
	Shape: string, -- "Confetti" | "Stars" | "Hearts" | "Bubbles" | "Mist"
	Colors: { Color3 },
	Count: number, -- particles (halved on phones and low graphics)
}
export type CosmeticTitanSkin = {
	Skin: Color3,
	HairColor: Color3?,
	EyeColor: Color3?, -- softly glowing eyes
	Shorts: Color3?,
	Material: Enum.Material?, -- the skin's material (Glass for crystal)
	Crystal: boolean?, -- adds the crown of crystal points
}
export type CosmeticItem = {
	Id: string,
	Slot: string, -- "Cape" | "Blade" | "Trail" | "Gas" | "Cable" | "Defeat" | "TitanSkin"
	Display: string,
	Description: string,
	Source: string, -- "Free" | "Marks" | "Robux" | "Season" | "Pass"
	Price: number?, -- Marks (Source "Marks")
	ProductKey: string?, -- (Source "Robux")
	PassKey: string?, -- (Source "Pass")
	Order: number,
	Preview: { Color: Color3, Color2: Color3? },
	Cape: CosmeticCape?,
	Blade: CosmeticBlade?,
	Trail: CosmeticTrail?,
	Gas: CosmeticGas?,
	Cable: CosmeticCable?,
	Defeat: CosmeticDefeat?,
	TitanSkin: CosmeticTitanSkin?,
}

Config.CosmeticSlots = { "Cape", "Blade", "Trail", "Gas", "Cable", "Defeat", "TitanSkin" }

local rgb = Color3.fromRGB
local MIST, MIST_TEAL, MIST_DEEP = rgb(196, 210, 214), rgb(110, 196, 190), rgb(70, 104, 112) -- Season of Mist
local GOLD, GOLD_LIGHT = rgb(214, 170, 64), rgb(255, 226, 140)
local RAINBOW = { rgb(255, 110, 110), rgb(255, 190, 90), rgb(255, 240, 110), rgb(120, 220, 130), rgb(110, 180, 255), rgb(190, 130, 255) }

local cosmeticList: { CosmeticItem } = {
	-- Capes
	{ Id = "SkyStripeCape", Slot = "Cape", Display = "Sky Stripe Cape", Description = "Sky blue with two white stripes.", Source = "Free", Order = 1,
		Preview = { Color = rgb(96, 160, 220), Color2 = rgb(240, 244, 250) }, Cape = { Color = rgb(96, 160, 220), Emblem = rgb(240, 244, 250), Pattern = "Stripes", PatternColor = rgb(240, 244, 250) } },
	{ Id = "MeadowCape", Slot = "Cape", Display = "Meadow Cape", Description = "Leaf green with a sunny yellow trim.", Source = "Free", Order = 2,
		Preview = { Color = rgb(92, 160, 80), Color2 = rgb(250, 214, 90) }, Cape = { Color = rgb(92, 160, 80), Emblem = rgb(250, 214, 90), Pattern = "Trim", PatternColor = rgb(250, 214, 90) } },
	{ Id = "BerryCape", Slot = "Cape", Display = "Berry Cape", Description = "Berry pink on top, cream below.", Source = "Marks", Price = 300, Order = 3,
		Preview = { Color = rgb(200, 70, 120), Color2 = rgb(248, 232, 210) }, Cape = { Color = rgb(200, 70, 120), Emblem = rgb(248, 232, 210), Pattern = "Split", PatternColor = rgb(248, 232, 210) } },
	{ Id = "StarDotCape", Slot = "Cape", Display = "Star Dot Cape", Description = "Deep navy sprinkled with golden dots.", Source = "Marks", Price = 400, Order = 4,
		Preview = { Color = rgb(36, 46, 96), Color2 = rgb(250, 210, 100) }, Cape = { Color = rgb(36, 46, 96), Emblem = rgb(250, 210, 100), Pattern = "Stars", PatternColor = rgb(250, 210, 100) } },
	{ Id = "NightGlowCape", Slot = "Cape", Display = "Night Glow Cape", Description = "Midnight blue with a softly glowing teal hem.", Source = "Robux", ProductKey = "NightGlowCape", Order = 5,
		Preview = { Color = rgb(26, 30, 56), Color2 = rgb(90, 240, 220) }, Cape = { Color = rgb(26, 30, 56), Emblem = rgb(90, 240, 220), Pattern = "Glow", PatternColor = rgb(90, 240, 220) } },
	{ Id = "SunsetSplitCape", Slot = "Cape", Display = "Sunset Cape", Description = "Warm orange fading into evening purple.", Source = "Robux", ProductKey = "SunsetSplitCape", Order = 6,
		Preview = { Color = rgb(240, 140, 60), Color2 = rgb(120, 70, 160) }, Cape = { Color = rgb(240, 140, 60), Emblem = rgb(255, 230, 170), Pattern = "Split", PatternColor = rgb(120, 70, 160) } },
	{ Id = "CommanderCape", Slot = "Cape", Display = "Commander's Cape", Description = "Gold with a white hem. Part of the Commander Pack.", Source = "Pass", PassKey = "CommanderPack", Order = 7,
		Preview = { Color = GOLD, Color2 = rgb(250, 248, 240) }, Cape = { Color = GOLD, Emblem = rgb(250, 248, 240), Pattern = "Trim", PatternColor = rgb(250, 248, 240) } },
	{ Id = "Season1_Cape", Slot = "Cape", Display = "Mistwalker Cape", Description = "Season of Mist: misty silver with teal stars.", Source = "Season", Order = 8,
		Preview = { Color = MIST, Color2 = MIST_TEAL }, Cape = { Color = MIST, Emblem = MIST_DEEP, Pattern = "Stars", PatternColor = MIST_TEAL } },

	-- Blades
	{ Id = "MintBlade", Slot = "Blade", Display = "Mint Blades", Description = "Bright steel with a cool mint edge.", Source = "Free", Order = 11,
		Preview = { Color = rgb(225, 235, 232), Color2 = rgb(150, 255, 210) }, Blade = { Color = rgb(225, 235, 232), Edge = rgb(150, 255, 210) } },
	{ Id = "RoseBlade", Slot = "Blade", Display = "Rose Blades", Description = "Rose-tinted shiny foil with a pink edge.", Source = "Marks", Price = 350, Order = 12,
		Preview = { Color = rgb(240, 180, 200), Color2 = rgb(255, 130, 190) }, Blade = { Color = rgb(240, 180, 200), Edge = rgb(255, 130, 190), Material = Enum.Material.Foil, Reflectance = 0.2 } },
	{ Id = "FrostGlassBlade", Slot = "Blade", Display = "Frost Glass Blades", Description = "Clear ice-blue glass blades.", Source = "Marks", Price = 800, Order = 13,
		Preview = { Color = rgb(180, 225, 255), Color2 = rgb(230, 250, 255) }, Blade = { Color = rgb(180, 225, 255), Edge = rgb(230, 250, 255), Material = Enum.Material.Glass, Reflectance = 0.1, Transparency = 0.3 } },
	{ Id = "LilacFoilBlade", Slot = "Blade", Display = "Lilac Foil Blades", Description = "Shimmering lilac foil, lavender edge.", Source = "Robux", ProductKey = "LilacFoilBlade", Order = 14,
		Preview = { Color = rgb(190, 160, 240), Color2 = rgb(220, 200, 255) }, Blade = { Color = rgb(190, 160, 240), Edge = rgb(220, 200, 255), Material = Enum.Material.Foil, Reflectance = 0.25, Hilt = rgb(80, 60, 120) } },
	{ Id = "LimeSparkBlade", Slot = "Blade", Display = "Lime Spark Blades", Description = "Dark steel with a zesty lime glow.", Source = "Robux", ProductKey = "LimeSparkBlade", Order = 15,
		Preview = { Color = rgb(70, 74, 82), Color2 = rgb(180, 255, 60) }, Blade = { Color = rgb(70, 74, 82), Edge = rgb(180, 255, 60), Reflectance = 0.2 } },
	{ Id = "CommanderBlade", Slot = "Blade", Display = "Commander's Blades", Description = "Golden blades for the corps' leaders. Part of the Commander Pack.", Source = "Pass", PassKey = "CommanderPack", Order = 16,
		Preview = { Color = GOLD, Color2 = GOLD_LIGHT }, Blade = { Color = GOLD, Edge = GOLD_LIGHT, Material = Enum.Material.Foil, Reflectance = 0.3, Hilt = rgb(120, 90, 40) } },
	{ Id = "Season1_Blade", Slot = "Blade", Display = "Mistglass Blades", Description = "Season of Mist: pale teal glass.", Source = "Season", Order = 17,
		Preview = { Color = MIST_TEAL, Color2 = MIST }, Blade = { Color = rgb(170, 220, 215), Edge = MIST, Material = Enum.Material.Glass, Reflectance = 0.15, Transparency = 0.25, Hilt = MIST_DEEP } },

	-- Trails
	{ Id = "BreezeTrail", Slot = "Trail", Display = "Breeze Trail", Description = "A soft mint swish.", Source = "Free", Order = 21,
		Preview = { Color = rgb(180, 255, 220) }, Trail = { Colors = { rgb(180, 255, 220), rgb(240, 255, 250) } } },
	{ Id = "FrostTrail", Slot = "Trail", Display = "Frost Trail", Description = "Icy blue fading to white.", Source = "Marks", Price = 300, Order = 22,
		Preview = { Color = rgb(120, 200, 255), Color2 = rgb(240, 250, 255) }, Trail = { Colors = { rgb(120, 200, 255), rgb(240, 250, 255) }, Lifetime = 0.24 } },
	{ Id = "EmberTrail", Slot = "Trail", Display = "Ember Trail", Description = "Cosy campfire orange and yellow.", Source = "Marks", Price = 500, Order = 23,
		Preview = { Color = rgb(255, 150, 60), Color2 = rgb(255, 230, 110) }, Trail = { Colors = { rgb(255, 230, 110), rgb(255, 150, 60), rgb(240, 90, 50) }, Lifetime = 0.22 } },
	{ Id = "RainbowTrail", Slot = "Trail", Display = "Rainbow Trail", Description = "Every colour, every swing.", Source = "Robux", ProductKey = "RainbowTrail", Order = 24,
		Preview = { Color = RAINBOW[1], Color2 = RAINBOW[5] }, Trail = { Colors = RAINBOW, Lifetime = 0.3, Width = 1.3 } },
	{ Id = "CandyTrail", Slot = "Trail", Display = "Candy Trail", Description = "Pink and white, like a sweet.", Source = "Robux", ProductKey = "CandyTrail", Order = 25,
		Preview = { Color = rgb(255, 140, 200), Color2 = rgb(255, 255, 255) }, Trail = { Colors = { rgb(255, 140, 200), rgb(255, 255, 255), rgb(255, 140, 200), rgb(255, 255, 255) }, Lifetime = 0.26 } },
	{ Id = "CommanderTrail", Slot = "Trail", Display = "Commander's Trail", Description = "A wide golden arc. Part of the Commander Pack.", Source = "Pass", PassKey = "CommanderPack", Order = 26,
		Preview = { Color = GOLD_LIGHT, Color2 = GOLD }, Trail = { Colors = { GOLD_LIGHT, GOLD }, Lifetime = 0.28, Width = 1.2 } },
	{ Id = "Season1_Trail", Slot = "Trail", Display = "Mist Trail", Description = "Season of Mist: a slow silver-teal haze.", Source = "Season", Order = 27,
		Preview = { Color = MIST, Color2 = MIST_TEAL }, Trail = { Colors = { MIST, MIST_TEAL, MIST }, Lifetime = 0.38, LightEmission = 0.5, Transparency = 0.35, Width = 1.4 } },

	-- Gas jets
	{ Id = "SkyGas", Slot = "Gas", Display = "Sky Gas", Description = "Light sky-blue puffs.", Source = "Free", Order = 31,
		Preview = { Color = rgb(190, 225, 255) }, Gas = { Color = rgb(200, 228, 255), Core = rgb(150, 205, 255) } },
	{ Id = "PeachGas", Slot = "Gas", Display = "Peach Gas", Description = "Soft peach clouds.", Source = "Marks", Price = 250, Order = 32,
		Preview = { Color = rgb(255, 200, 170) }, Gas = { Color = rgb(255, 210, 180), Core = rgb(255, 170, 130) } },
	{ Id = "LilacGas", Slot = "Gas", Display = "Lilac Gas", Description = "Lavender puffs with a violet streak.", Source = "Marks", Price = 450, Order = 33,
		Preview = { Color = rgb(210, 190, 255), Color2 = rgb(160, 120, 255) }, Gas = { Color = rgb(215, 200, 255), Core = rgb(160, 120, 255) } },
	{ Id = "BubblegumGas", Slot = "Gas", Display = "Bubblegum Gas", Description = "Bright pink puffs.", Source = "Robux", ProductKey = "BubblegumGas", Order = 34,
		Preview = { Color = rgb(255, 160, 210) }, Gas = { Color = rgb(255, 170, 215), Core = rgb(255, 110, 190), LightEmission = 0.3 } },
	{ Id = "RainbowGas", Slot = "Gas", Display = "Rainbow Gas", Description = "Puffs that run through the rainbow.", Source = "Robux", ProductKey = "RainbowGas", Order = 35,
		Preview = { Color = RAINBOW[2], Color2 = RAINBOW[5] }, Gas = { Color = RAINBOW[1], Color2 = RAINBOW[5], Core = rgb(255, 255, 255), LightEmission = 0.3 } },
	{ Id = "Season1_Gas", Slot = "Gas", Display = "Mist Gas", Description = "Season of Mist: silver puffs with a teal core.", Source = "Season", Order = 36,
		Preview = { Color = MIST, Color2 = MIST_TEAL }, Gas = { Color = MIST, Color2 = MIST_TEAL, Core = MIST_TEAL } },

	-- Cables
	{ Id = "BrassCable", Slot = "Cable", Display = "Brass Cable", Description = "Polished brass wire.", Source = "Free", Order = 41,
		Preview = { Color = rgb(214, 186, 120) }, Cable = { Color = rgb(214, 186, 120) } },
	{ Id = "SignalCable", Slot = "Cable", Display = "Signal Red Cable", Description = "Easy-to-spot bright red.", Source = "Marks", Price = 200, Order = 42,
		Preview = { Color = rgb(230, 70, 70) }, Cable = { Color = rgb(230, 70, 70) } },
	{ Id = "GlowCable", Slot = "Cable", Display = "Glow Wire", Description = "A cable that glows cyan.", Source = "Marks", Price = 600, Order = 43,
		Preview = { Color = rgb(100, 240, 255) }, Cable = { Color = rgb(100, 240, 255), LightEmission = 0.6 } },
	{ Id = "SunbeamCable", Slot = "Cable", Display = "Sunbeam Cable", Description = "A thick, warm, sunny beam.", Source = "Robux", ProductKey = "SunbeamCable", Order = 44,
		Preview = { Color = rgb(255, 220, 90), Color2 = rgb(255, 170, 60) }, Cable = { Color = rgb(255, 230, 110), Color2 = rgb(255, 170, 60), LightEmission = 0.5, Width = 1.3 } },
	{ Id = "RainbowCable", Slot = "Cable", Display = "Rainbow Cable", Description = "A rainbow from your hip to the hook.", Source = "Robux", ProductKey = "RainbowCable", Order = 45,
		Preview = { Color = RAINBOW[1], Color2 = RAINBOW[6] }, Cable = { Color = RAINBOW[1], Color2 = RAINBOW[6], LightEmission = 0.4 } },

	-- Defeat effects (when you take a giant down)
	{ Id = "ConfettiPop", Slot = "Defeat", Display = "Confetti Pop", Description = "A party of confetti.", Source = "Free", Order = 51,
		Preview = { Color = rgb(255, 200, 80), Color2 = rgb(110, 180, 255) }, Defeat = { Shape = "Confetti", Colors = { rgb(255, 110, 110), rgb(255, 210, 80), rgb(110, 200, 255), rgb(140, 230, 130) }, Count = 40 } },
	{ Id = "StarBurst", Slot = "Defeat", Display = "Star Burst", Description = "Twinkling golden stars.", Source = "Marks", Price = 1000, Order = 52,
		Preview = { Color = rgb(255, 230, 120) }, Defeat = { Shape = "Stars", Colors = { rgb(255, 240, 160), rgb(255, 200, 80) }, Count = 30 } },
	{ Id = "HeartBurst", Slot = "Defeat", Display = "Heart Burst", Description = "Pop! A bunch of floating hearts.", Source = "Robux", ProductKey = "HeartBurst", Order = 53,
		Preview = { Color = rgb(255, 110, 150), Color2 = rgb(255, 190, 210) }, Defeat = { Shape = "Hearts", Colors = { rgb(255, 100, 140), rgb(255, 170, 200) }, Count = 24 } },
	{ Id = "BubblePop", Slot = "Defeat", Display = "Bubble Pop", Description = "Big shiny bubbles float up.", Source = "Robux", ProductKey = "BubblePop", Order = 54,
		Preview = { Color = rgb(170, 230, 255), Color2 = rgb(230, 200, 255) }, Defeat = { Shape = "Bubbles", Colors = { rgb(170, 230, 255), rgb(230, 200, 255), rgb(200, 255, 230) }, Count = 22 } },
	{ Id = "Season1_Defeat", Slot = "Defeat", Display = "Mist Swirl", Description = "Season of Mist: a swirl of silver and teal mist.", Source = "Season", Order = 55,
		Preview = { Color = MIST, Color2 = MIST_TEAL }, Defeat = { Shape = "Mist", Colors = { MIST, MIST_TEAL }, Count = 26 } },

	-- Titan skins (worn by any titan form you transform into)
	{ Id = "SandSkin", Slot = "TitanSkin", Display = "Sandstone Titan", Description = "Warm sandy skin and dark hair.", Source = "Free", Order = 61,
		Preview = { Color = rgb(214, 180, 130), Color2 = rgb(70, 50, 40) }, TitanSkin = { Skin = rgb(214, 180, 130), HairColor = rgb(70, 50, 40) } },
	{ Id = "MossSkin", Slot = "TitanSkin", Display = "Mossback Titan", Description = "Mossy green with leafy hair.", Source = "Marks", Price = 1500, Order = 62,
		Preview = { Color = rgb(120, 150, 100), Color2 = rgb(70, 120, 60) }, TitanSkin = { Skin = rgb(130, 160, 110), HairColor = rgb(70, 120, 60), Shorts = rgb(90, 70, 50), Material = Enum.Material.Grass } },
	{ Id = "SnowSkin", Slot = "TitanSkin", Display = "Snowdrift Titan", Description = "Snowy white with icy blue eyes.", Source = "Robux", ProductKey = "SnowSkin", Order = 63,
		Preview = { Color = rgb(235, 240, 248), Color2 = rgb(140, 200, 255) }, TitanSkin = { Skin = rgb(235, 240, 248), HairColor = rgb(200, 220, 240), EyeColor = rgb(140, 200, 255), Shorts = rgb(90, 130, 180), Material = Enum.Material.Snow } },
	{ Id = "CrystalSkin", Slot = "TitanSkin", Display = "Crystal Titan", Description = "Sparkling blue crystal from head to toe. Part of the Shifter Pack.", Source = "Pass", PassKey = "ShifterPack", Order = 64,
		Preview = { Color = rgb(120, 180, 255), Color2 = rgb(200, 235, 255) }, TitanSkin = { Skin = rgb(120, 180, 255), HairColor = rgb(200, 235, 255), EyeColor = rgb(220, 245, 255), Shorts = rgb(50, 80, 140), Material = Enum.Material.Glass, Crystal = true } },
	{ Id = "EmberSkin", Slot = "TitanSkin", Display = "Ember Titan", Description = "Cosy as a campfire: warm orange with golden hair. Part of the Shifter Pack.", Source = "Pass", PassKey = "ShifterPack", Order = 65,
		Preview = { Color = rgb(230, 130, 70), Color2 = rgb(255, 210, 110) }, TitanSkin = { Skin = rgb(230, 140, 80), HairColor = rgb(255, 210, 110), EyeColor = rgb(255, 220, 140), Shorts = rgb(120, 60, 40), Material = Enum.Material.SmoothPlastic } },
	{ Id = "Season1_TitanSkin", Slot = "TitanSkin", Display = "Mist Titan", Description = "Season of Mist: misty silver with teal hair.", Source = "Season", Order = 66,
		Preview = { Color = MIST, Color2 = MIST_TEAL }, TitanSkin = { Skin = MIST, HairColor = MIST_TEAL, EyeColor = MIST_TEAL, Shorts = MIST_DEEP } },
}

Config.CosmeticItems = {} :: { [string]: CosmeticItem }
for _, item in cosmeticList do
	Config.CosmeticItems[item.Id] = item
end

-- The item an attribute value names, if it's an item for that slot.
function Config.CosmeticFor(slot: string, id: unknown): CosmeticItem?
	local item = if type(id) == "string" and id ~= "" then Config.CosmeticItems[id] else nil
	return if item and item.Slot == slot then item else nil
end

-- Defeat effects (CosmeticsClient): one RemoteEvent the server creates,
-- server -> all but the hunter (hunter, itemId, position); the hunter's own
-- burst plays from their SlashResult.
Config.CosmeticFx = {
	Remote = "GH_CosmeticFx",
	Range = 450, -- studs from the camera: other hunters' defeat effects past this are skipped
	Rigs = 4, -- pooled defeat-effect emitters
	Hearts = 8, -- pooled heart shapes (Hearts), at most...
	HeartsLowEnd = 4, -- ...on phones and low graphics
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
	-- (The default character sounds, also shipped with every client.)
	Whoosh = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.45, Pitch = 1.35 }, -- gas dash
	Roar = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 1, Pitch = 0.32 }, -- a giant's grab or roar tell
	Cut = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.55, Pitch = 1.6 }, -- a cut that lands (pitch climbs with the combo)
}

-- === Feel (client-only juice; see Juice.lua and Settings.lua) =================
Config.Feel = {
	HitStop = 0.06, -- seconds the camera and your animations freeze on a hit
	HitStopDefeat = 0.1,
	AimAssistDefault = true,
	AimAssistCone = 6, -- degrees round the crosshair in which a hook snaps to a nape
	AimAssistBodyCone = 3, -- ... or to a giant's head/torso when the hook would miss
	RollMax = 6, -- degrees the camera rolls into a swing
	RollRate = 5,
	FovSpeed = 18, -- extra field of view at top speed
	FovKickReel = 5, -- extra FOV kicks (they decay), x the FOV setting
	FovKickBoost = 4,
	FovKickDash = 8,
	FovKickDecay = 5,
	SpeedLinesFrom = 75, -- studs/s: speed lines start here...
	SpeedLinesFull = 150, -- ...and are at full strength here
	SpeedLines = 18, -- streaks on screen at most (pooled)
	StepReach = 7, -- x a giant's height: how far away its footsteps shake the camera
	StepShake = 0.5, -- shake from a 46-stud giant's step right next to you
	StepDustRange = 320, -- studs from the camera: dust puffs at footsteps
	GrabTellReach = 2.2, -- x a giant's grab reach: you get the red warning this close
	MaxBursts = 6, -- pooled nape bursts (steam + sparks) at once
	FloatingTexts = 8, -- pooled "+8 x3" texts
	BigTextScale = 1.25, -- the "bigger text" setting (on by default on phones)
}

-- === Shop: gear and techniques (ShopService / TechniqueService) ==============
-- Bought once with Marks (never real money), from a hunter level (the
-- player's "Level" attribute; 1 if missing). One gear set and one technique
-- are worn at a time (player attributes "Equip_Gear", "Equip_Technique", and
-- "Equip_Titan" for Config.TitanForms), saved under the profile's "Owned"
-- and "Equip" keys.
--
-- Mods (read by Stats.For for the equipped gear; missing = no change):
--   SpeedMult      x the rig's top speed and boosts
--   GasMult        x the tank size
--   GasRegenMult   x the tank refill
--   ReelMult       x the reel speed and pull
--   DamageMult     x the damage of a nape cut
--   HookRangeAdd   + studs of hook range
--   BladeAdd       + blades per resupply
-- Look: how the gear shows on the hunter (HunterGear.ApplyGearLook).
export type GearMods = {
	SpeedMult: number?,
	GasMult: number?,
	GasRegenMult: number?,
	ReelMult: number?,
	DamageMult: number?,
	HookRangeAdd: number?,
	BladeAdd: number?,
}
export type GearLook = {
	Rig: Color3?, -- the reel box and blade boxes
	Steel: Color3?, -- the drum, launchers, tanks and trim
	TankScale: number?, -- x the gas tanks' size
	Hilt: Color3?, -- the swords' hilts and collars
	Edge: Color3?, -- the swords' glowing edge and their trail
}
-- Every number a technique uses (each uses a few of them).
export type TechniqueSpec = {
	Cooldown: number, -- seconds
	Range: number?, -- studs
	Radius: number?, -- studs
	Distance: number?, -- studs (a dash)
	Speed: number?, -- studs/s
	Duration: number?, -- seconds
	MaxHits: number?,
	BladeCost: number?,
	GasFraction: number?,
	Impulse: number?,
	Kinds: { string }?, -- giant kinds it works on
}
export type CatalogItem = {
	Id: string,
	Category: string, -- "Gear" | "Technique"
	Display: string,
	Description: string,
	Price: number, -- Marks
	LevelRequired: number,
	Order: number,
	Mods: GearMods?,
	Look: GearLook?,
	Technique: TechniqueSpec?,
}

Config.Catalog = {
	-- Gear: every set is a trade-off, except the veteran's.
	SwiftRig = {
		Id = "SwiftRig",
		Category = "Gear",
		Display = "Swift Rig",
		Description = "A slim, light rig: faster swings, smaller tanks.",
		Price = 150,
		LevelRequired = 2,
		Order = 1,
		Mods = { SpeedMult = 1.12, GasMult = 0.9 },
		Look = { Rig = Color3.fromRGB(70, 110, 170), Steel = Color3.fromRGB(205, 220, 235), TankScale = 0.85, Edge = Color3.fromRGB(140, 210, 255) },
	},
	LongHaulTanks = {
		Id = "LongHaulTanks",
		Category = "Gear",
		Display = "Long-Haul Tanks",
		Description = "Big tanks for long patrols: lots more gas, a bit slower.",
		Price = 150,
		LevelRequired = 2,
		Order = 2,
		Mods = { GasMult = 1.25, SpeedMult = 0.93 },
		Look = { Rig = Color3.fromRGB(88, 96, 70), Steel = Color3.fromRGB(150, 160, 130), TankScale = 1.3 },
	},
	HeavyEdge = {
		Id = "HeavyEdge",
		Category = "Gear",
		Display = "Heavy Edge Blades",
		Description = "Thick, heavy blades hit harder; the reel feels the weight.",
		Price = 250,
		LevelRequired = 4,
		Order = 3,
		Mods = { DamageMult = 1.25, ReelMult = 0.9 },
		Look = { Rig = Color3.fromRGB(46, 44, 48), Hilt = Color3.fromRGB(40, 36, 36), Edge = Color3.fromRGB(255, 160, 70) },
	},
	Featherweight = {
		Id = "Featherweight",
		Category = "Gear",
		Display = "Featherweight Set",
		Description = "Everything trimmed down: quick and nimble, but less gas and one blade fewer.",
		Price = 250,
		LevelRequired = 5,
		Order = 4,
		Mods = { SpeedMult = 1.08, ReelMult = 1.08, GasMult = 0.85, BladeAdd = -1 },
		Look = { Rig = Color3.fromRGB(225, 225, 215), Steel = Color3.fromRGB(240, 240, 235), TankScale = 0.8, Hilt = Color3.fromRGB(230, 225, 210), Edge = Color3.fromRGB(200, 255, 230) },
	},
	RangerRig = {
		Id = "RangerRig",
		Category = "Gear",
		Display = "Ranger Rig",
		Description = "Long cables to reach far-off rooftops; the tanks refill slower.",
		Price = 300,
		LevelRequired = 6,
		Order = 5,
		Mods = { HookRangeAdd = 25, GasRegenMult = 0.85 },
		Look = { Rig = Color3.fromRGB(60, 92, 60), Steel = Color3.fromRGB(170, 160, 120), Edge = Color3.fromRGB(170, 255, 150) },
	},
	StormCell = {
		Id = "StormCell",
		Category = "Gear",
		Display = "Storm-Cell Rig",
		Description = "Clever valves catch the wind: much faster refill, smaller tanks.",
		Price = 350,
		LevelRequired = 8,
		Order = 6,
		Mods = { GasRegenMult = 1.35, GasMult = 0.9 },
		Look = { Rig = Color3.fromRGB(64, 70, 110), Steel = Color3.fromRGB(150, 180, 230), TankScale = 0.95, Edge = Color3.fromRGB(190, 170, 255) },
	},
	BulwarkKit = {
		Id = "BulwarkKit",
		Category = "Gear",
		Display = "Bulwark Kit",
		Description = "Extra blade boxes: two more blades a resupply, a little slower.",
		Price = 400,
		LevelRequired = 10,
		Order = 7,
		Mods = { BladeAdd = 2, SpeedMult = 0.94 },
		Look = { Rig = Color3.fromRGB(110, 70, 50), Steel = Color3.fromRGB(190, 160, 110), Hilt = Color3.fromRGB(120, 80, 50) },
	},
	VeteransRig = {
		Id = "VeteransRig",
		Category = "Gear",
		Display = "Veteran's Rig",
		Description = "Fine work, a little better at everything. For seasoned hunters.",
		Price = 900,
		LevelRequired = 20,
		Order = 8,
		Mods = { SpeedMult = 1.05, GasMult = 1.05, GasRegenMult = 1.05, ReelMult = 1.05, DamageMult = 1.05 },
		Look = { Rig = Color3.fromRGB(40, 40, 46), Steel = Color3.fromRGB(214, 186, 120), Hilt = Color3.fromRGB(214, 186, 120), Edge = Color3.fromRGB(255, 230, 150) },
	},

	-- Techniques: one active ability on a key (V / R2 / the "SKILL" button).
	GaleBurst = {
		Id = "GaleBurst",
		Category = "Technique",
		Display = "Gale Burst",
		Description = "A gust of wind throws you where you're heading. Needs no gas.",
		Price = 100,
		LevelRequired = 1,
		Order = 11,
		Technique = { Cooldown = 8, Impulse = 85 },
	},
	SecondWind = {
		Id = "SecondWind",
		Category = "Technique",
		Display = "Second Wind",
		Description = "Crack open the spare valve: half a tank of gas back.",
		Price = 150,
		LevelRequired = 2,
		Order = 12,
		Technique = { Cooldown = 60, GasFraction = 0.5 },
	},
	SmokePellet = {
		Id = "SmokePellet",
		Category = "Technique",
		Display = "Smoke Pellet",
		Description = "A big cloud of smoke: giants close by can't see for a few seconds.",
		Price = 200,
		LevelRequired = 3,
		Order = 13,
		Technique = { Cooldown = 25, Radius = 35 },
	},
	AnchorPull = {
		Id = "AnchorPull",
		Category = "Technique",
		Display = "Anchor Pull",
		Description = "Hook a small or medium giant's ankle and yank: down it goes.",
		Price = 250,
		LevelRequired = 4,
		Order = 14,
		Technique = { Cooldown = 20, Range = 60, Radius = 30, Kinds = { "Small", "Medium" } },
	},
	WhirlwindCut = {
		Id = "WhirlwindCut",
		Category = "Technique",
		Display = "Whirlwind Cut",
		Description = "Spin forward like a top, cutting any nape you pass. Uses one blade.",
		Price = 300,
		LevelRequired = 5,
		Order = 15,
		Technique = { Cooldown = 14, Distance = 40, Speed = 100, Duration = 0.7, MaxHits = 2, BladeCost = 1 },
	},
	FlareLance = {
		Id = "FlareLance",
		Category = "Technique",
		Display = "Flare Lance",
		Description = "Throw a glowing lance at a nape from far away. Cracks armour too.",
		Price = 600,
		LevelRequired = 10,
		Order = 16,
		Technique = { Cooldown = 45, Range = 120, Radius = 6, Speed = 180 },
	},
} :: { [string]: CatalogItem }

Config.Shop = {
	ActionCooldown = 0.25, -- seconds between shop requests the server accepts
	TechniqueKey = Enum.KeyCode.V,
	TechniqueGamepad = Enum.KeyCode.ButtonR2,
	TechniqueSlack = 0.3, -- seconds a technique may arrive early (network jitter)
	-- The second technique slot (the SecondTechnique game pass: a convenience
	-- slot, the techniques themselves are still bought with Marks).
	Technique2Key = Enum.KeyCode.B,
	Technique2Gamepad = Enum.KeyCode.ButtonL2,
}

-- === Robux shop (MonetizationService) ========================================
-- Kid-friendly rules: no stat boosts sold for Robux, no paid random loot,
-- no timers or pop-ups: a purchase prompt only ever opens on a button press
-- in the shop's ROBUX / STYLE / SEASON tabs.
--
-- Paste your ids from the Creator Dashboard (create.roblox.com > your
-- experience > Monetization > Passes / Developer Products). An id of 0 means
-- "not set up": the item is hidden in the shop and refused by the server.
-- Never use someone else's ids.
Config.Monetization = {
	-- Game passes (bought once, kept forever).
	GamePasses = {
		DoubleMarks = 0, -- x2 Marks from play
		CommanderPack = 0, -- the cosmetics with PassKey "CommanderPack" + the "Elite Commander" title
		SecondTechnique = 0, -- a second technique slot (B / L2 / a second SKILL button)
		ShifterPack = 0, -- the TitanSkin cosmetics with PassKey "ShifterPack"
		SeasonPremium = 0, -- the premium track of the season (Config.Season)
	} :: { [string]: number },
	-- Developer products (bought as often as you like).
	Products = {
		MarksSmall = 0, -- MarksBags.MarksSmall Marks
		MarksMedium = 0,
		MarksLarge = 0,
		ServerXPBoost = 0, -- x2 XP for the whole server for XPBoost.Duration (stacks)
		ChallengeReroll = 0, -- swap one of your daily challenges for another
		Fireworks = 0, -- a firework show over you, for everyone to see
		-- Single Robux styles: Config.CosmeticItems entries with Source =
		-- "Robux", by their ProductKey (= the item id).
		Cosmetics = {
			NightGlowCape = 0,
			SunsetSplitCape = 0,
			LilacFoilBlade = 0,
			LimeSparkBlade = 0,
			RainbowTrail = 0,
			CandyTrail = 0,
			BubblegumGas = 0,
			RainbowGas = 0,
			SunbeamCable = 0,
			RainbowCable = 0,
			HeartBurst = 0,
			BubblePop = 0,
			SnowSkin = 0,
		} :: { [string]: number },
	},
	MarksBags = { MarksSmall = 500, MarksMedium = 1500, MarksLarge = 5000 } :: { [string]: number },
	DoubleMarksMultiplier = 2, -- (Marks from play only: not bags, not season rewards)
	XPBoost = { Multiplier = 2, Duration = 30 * 60 }, -- seconds; Workspace attribute "XPBoostUntil"
	Fireworks = { Height = 55, Bursts = 7 },
	PromptCooldown = 1, -- seconds between purchase prompts the server opens for one player
	-- What the ROBUX tab shows (Key: a GamePasses or Products key).
	Cards = {
		{ Key = "DoubleMarks", Kind = "Pass", Display = "Double Marks", Description = "Earn twice the Marks from play, forever. Items still unlock by level." },
		{ Key = "SecondTechnique", Kind = "Pass", Display = "Second Technique Slot", Description = "Wear two of your techniques at once (B, L2, or a second SKILL button)." },
		{ Key = "CommanderPack", Kind = "Pass", Display = "Commander Pack", Description = "Commander styles and the Elite Commander title." },
		{ Key = "ShifterPack", Kind = "Pass", Display = "Shifter Pack", Description = "Special titan looks for when you transform." },
		{ Key = "SeasonPremium", Kind = "Pass", Display = "Season Premium", Description = "Unlocks the premium season track (styles and Marks)." },
		{ Key = "MarksSmall", Kind = "Product", Display = "Bag of Marks", Description = "500 Marks. Items still unlock by level." },
		{ Key = "MarksMedium", Kind = "Product", Display = "Chest of Marks", Description = "1,500 Marks. Items still unlock by level." },
		{ Key = "MarksLarge", Kind = "Product", Display = "Vault of Marks", Description = "5,000 Marks. Items still unlock by level." },
		{ Key = "ServerXPBoost", Kind = "Product", Display = "Server XP Boost", Description = "Double XP for EVERYONE in the server for 30 minutes." },
		{ Key = "ChallengeReroll", Kind = "Product", Display = "Challenge Reroll", Description = "Swap one of today's daily challenges for a new one." },
		{ Key = "Fireworks", Kind = "Product", Display = "Fireworks Show", Description = "A firework show over you that everyone can see!" },
	},
	-- (Premium Payouts: Roblox also pays you for the time Premium members
	-- spend in your experience; nothing to set up here.)
	PremiumPayoutNote = "Premium Payouts are automatic: no code needed.",
}

-- === The season pass (SeasonService) =========================================
-- Season XP is a share of the normal XP earned. Tiers: cumulative season XP,
-- each with an optional Free and Premium reward ({ Marks } or { Cosmetic =
-- a Config.CosmeticItems id with Source = "Season" }), claimed with a button.
-- Saved in the profile's "Season" (it starts over when Id changes).
export type SeasonReward = { Marks: number?, Cosmetic: string? }
export type SeasonTier = { XP: number, Free: SeasonReward?, Premium: SeasonReward? }

Config.Season = {
	Id = "S1",
	Name = "Season of Mist",
	EndsUtc = nil :: number?, -- os.time() when it ends (nil: no end shown)
	XPShare = 0.5, -- season XP per XP earned
	Tiers = {
		{ XP = 200, Free = { Marks = 25 }, Premium = { Cosmetic = "Season1_Cape" } }, -- 1
		{ XP = 450, Premium = { Marks = 50 } },
		{ XP = 700, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 1000, Premium = { Marks = 50 } },
		{ XP = 1300, Free = { Marks = 75 }, Premium = { Marks = 150 } }, -- 5
		{ XP = 1650, Premium = { Marks = 50 } },
		{ XP = 2000, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 2350, Premium = { Cosmetic = "Season1_Gas" } },
		{ XP = 2750, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 3200, Free = { Marks = 75 }, Premium = { Marks = 150 } }, -- 10
		{ XP = 3650, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 4150, Free = { Cosmetic = "Season1_Trail" }, Premium = { Marks = 50 } },
		{ XP = 4650, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 5150, Premium = { Marks = 50 } },
		{ XP = 5700, Free = { Marks = 75 }, Premium = { Cosmetic = "Season1_Blade" } }, -- 15
		{ XP = 6250, Premium = { Marks = 50 } },
		{ XP = 6850, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 7500, Premium = { Marks = 50 } },
		{ XP = 8150, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 8800, Free = { Marks = 75 }, Premium = { Marks = 150 } }, -- 20
		{ XP = 9500, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 10200, Premium = { Cosmetic = "Season1_Defeat" } },
		{ XP = 10950, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 11700, Premium = { Marks = 50 } },
		{ XP = 12500, Free = { Marks = 75 }, Premium = { Marks = 150 } }, -- 25
		{ XP = 13300, Premium = { Marks = 50 } },
		{ XP = 14150, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 15000, Premium = { Marks = 50 } },
		{ XP = 15900, Free = { Marks = 25 }, Premium = { Marks = 50 } },
		{ XP = 16800, Free = { Marks = 75 }, Premium = { Cosmetic = "Season1_TitanSkin" } }, -- 30
	} :: { SeasonTier },
}

return Config
