--!strict
-- Brain-Rot CTF ability roster. Maps every `Id` in docs/BRAINROT_ROSTER.md to
-- one of a small set of reusable ability *archetypes* (see CTFService.lua for
-- the archetype implementations) so we don't hand-write 16 bespoke effects.
--
-- Pure data + pure lookup helpers only (no Net/DataService access) so both
-- server (CTFService, authoritative effect application) and, in principle,
-- client UI (ability button icon/cooldown display) can require this safely.
--
-- The `Id` strings MUST match docs/BRAINROT_ROSTER.md and EggConfig.lua
-- exactly - equipping a brainrot in the Egg system is what selects the
-- ability CTFService looks up here.

local CTFConfig = {}

export type AbilityArchetype =
	"SpeedBurst" -- temporary self WalkSpeed multiplier
	| "Dash" -- instant forward impulse in look-direction
	| "AreaEffect" -- AoE around self, hits nearby enemies (slow or stun)
	| "ShieldImmunity" -- self tag-immune for N seconds
	| "RangedProjectile" -- fast-moving part, stuns/knocks back first enemy it touches
	| "Teleport" -- raycast-clamped blink forward

export type AbilityDefinition = {
	Id: string,
	DisplayName: string,
	Archetype: AbilityArchetype,
	Cooldown: number, -- seconds

	-- SpeedBurst (self buff) / also reused as the "effect duration" field for
	-- AreaEffect (how long hit enemies are slowed/stunned) and ShieldImmunity
	-- (how long the shield lasts).
	SpeedMultiplier: number?,
	Duration: number?,

	-- Dash
	DashSpeed: number?, -- studs/second impulse magnitude
	DashTime: number?, -- how long the impulse is applied for
	UpwardBoost: number?, -- optional vertical lift (e.g. "jump"/"glide" flavored dashes)
	SelfImmuneDuringDash: boolean?, -- brief tag-immunity for the duration of the dash
	ImmuneDuration: number?, -- overrides DashTime for how long that immunity lasts

	-- AreaEffect
	Radius: number?,
	SlowMultiplier: number?, -- WalkSpeed multiplier applied to enemies caught in the pulse
	Stun: boolean?, -- true = zero WalkSpeed/JumpPower instead of just slowing

	-- RangedProjectile
	ProjectileSpeed: number?, -- studs/second
	ProjectileRange: number?, -- studs before the projectile despawns
	StunSeconds: number?,
	Knockback: boolean?,
	KnockbackForce: number?,

	-- Teleport
	Distance: number?,
}

-- Ordered so DisplayName/Archetype/Cooldown always read together; tuning
-- follows docs/BRAINROT_ROSTER.md's "Ability power budget" section:
--   Common    -> ~4-6s cooldown, mobility/self-buff only, no enemy CC.
--   Rare      -> light utility, may briefly slow.
--   Epic      -> ranged hit or small AoE.
--   Legendary -> strong AoE/ranged tool built for attacking/defending the flag stand.
--   Secret    -> pure mobility (teleport), longest cooldown in the game.
local abilities: { [string]: AbilityDefinition } = {
	-- Common ------------------------------------------------------------
	Spaghettoro = {
		Id = "Spaghettoro",
		DisplayName = "Meatball Dash",
		Archetype = "SpeedBurst",
		Cooldown = 5,
		SpeedMultiplier = 1.3,
		Duration = 3,
	},
	CannoliniVolpe = {
		Id = "CannoliniVolpe",
		DisplayName = "Sugar Rush",
		Archetype = "SpeedBurst",
		Cooldown = 6,
		SpeedMultiplier = 1.15,
		Duration = 5,
	},
	PolpoMotorino = {
		Id = "PolpoMotorino",
		DisplayName = "Turbo Squirt",
		Archetype = "Dash",
		Cooldown = 5,
		DashSpeed = 55,
		DashTime = 0.25,
	},
	PinguinoMandolino = {
		Id = "PinguinoMandolino",
		DisplayName = "Sonata Slow",
		Archetype = "AreaEffect",
		Cooldown = 6,
		Radius = 14,
		SlowMultiplier = 0.6,
		Duration = 2.5,
		Stun = false,
	},
	BroccolinoTurbanti = {
		Id = "BroccolinoTurbanti",
		DisplayName = "Steam Cloud",
		Archetype = "AreaEffect",
		Cooldown = 6,
		Radius = 12,
		SlowMultiplier = 0.65,
		Duration = 2,
		Stun = false,
	},
	LucertolaFocaccina = {
		Id = "LucertolaFocaccina",
		DisplayName = "Bread Shield",
		Archetype = "ShieldImmunity",
		Cooldown = 5,
		Duration = 1.5,
	},

	-- Rare ----------------------------------------------------------------
	GirafferroEspressone = {
		Id = "GirafferroEspressone",
		DisplayName = "Espresso Shot",
		Archetype = "SpeedBurst",
		Cooldown = 8,
		SpeedMultiplier = 1.45,
		Duration = 3,
	},
	RondineRavioli = {
		Id = "RondineRavioli",
		DisplayName = "Ravioli Toss",
		Archetype = "RangedProjectile",
		Cooldown = 9,
		ProjectileSpeed = 90,
		ProjectileRange = 60,
		StunSeconds = 1.5,
		Knockback = false,
	},
	ScoiattoloCannoncino = {
		Id = "ScoiattoloCannoncino",
		DisplayName = "Nut Barrage",
		Archetype = "Dash",
		Cooldown = 8,
		DashSpeed = 65,
		DashTime = 0.3,
		UpwardBoost = 10,
	},
	TartarugaVespaccia = {
		Id = "TartarugaVespaccia",
		DisplayName = "Shell Sprint",
		Archetype = "SpeedBurst",
		Cooldown = 9,
		SpeedMultiplier = 1.6,
		Duration = 4,
	},

	-- Epic ------------------------------------------------------------------
	FenicotteroPizzaiolo = {
		Id = "FenicotteroPizzaiolo",
		DisplayName = "Dough Toss",
		Archetype = "RangedProjectile",
		Cooldown = 12,
		ProjectileSpeed = 95,
		ProjectileRange = 65,
		StunSeconds = 2.5,
		Knockback = false,
	},
	PipistrelloMarinaro = {
		Id = "PipistrelloMarinaro",
		DisplayName = "Night Glide",
		Archetype = "Dash",
		Cooldown = 12,
		DashSpeed = 60,
		DashTime = 0.6,
		UpwardBoost = 18,
	},
	CannoloTrombonini = {
		Id = "CannoloTrombonini",
		DisplayName = "Brass Boom",
		Archetype = "RangedProjectile",
		Cooldown = 12,
		ProjectileSpeed = 80,
		ProjectileRange = 40,
		StunSeconds = 0.5,
		Knockback = true,
		KnockbackForce = 90,
	},

	-- Legendary -----------------------------------------------------------
	CrocobrividoVulcanico = {
		Id = "CrocobrividoVulcanico",
		DisplayName = "Magma Slam",
		Archetype = "AreaEffect",
		Cooldown = 18,
		Radius = 18,
		SlowMultiplier = 0,
		Duration = 2,
		Stun = true,
	},
	SqualezzaFerroviaria = {
		Id = "SqualezzaFerroviaria",
		DisplayName = "Rail Charge",
		Archetype = "Dash",
		Cooldown = 18,
		DashSpeed = 85,
		DashTime = 0.4,
		SelfImmuneDuringDash = true,
		ImmuneDuration = 0.6,
	},

	-- Secret ----------------------------------------------------------------
	TralaleroAstrale = {
		Id = "TralaleroAstrale",
		DisplayName = "Starlight Warp",
		Archetype = "Teleport",
		Cooldown = 24,
		Distance = 55,
	},
}
CTFConfig.Abilities = abilities

function CTFConfig.GetAbility(id: string): AbilityDefinition?
	return abilities[id]
end

-- Rarity's effect on CTF combat -----------------------------------------
--
-- Deliberate design call: rarity gives only a small ability-cooldown discount
-- (max 10% at Secret), never extra move speed, damage, stun duration, or
-- range. Those stay a pure function of the equipped species/ability archetype
-- above, which anyone can equip regardless of rarity. Idle income and sell
-- value already reward pulling higher rarities; letting rarity also swing PvP
-- combat power would make the Robux-purchased luck boost pay-to-win, which we
-- want to avoid. A slightly faster ability cycle is a felt reward without
-- being "stronger hits" or "more health".
local rarityCooldownMultiplier: { [string]: number } = {
	Common = 1.0,
	Rare = 0.97,
	Epic = 0.94,
	Legendary = 0.92,
	Secret = 0.9,
}
CTFConfig.RarityCooldownMultiplier = rarityCooldownMultiplier

-- Battlefield powerups ----------------------------------------------------
--
-- Pure data: CTFService owns spawning (deriving points from WorldLayout's
-- Arena rect) and effect application; the client only needs Id/DisplayName
-- for feedback since the server sends Duration on pickup.

export type PowerupArchetype = "Speed" | "Shield" | "Haste" | "Reveal"

export type PowerupDefinition = {
	Id: string,
	DisplayName: string,
	Color: Color3,
	Duration: number, -- seconds the effect lasts (Haste is instantaneous; kept for UI countdown flavor)
	Archetype: PowerupArchetype,
	SpeedMultiplier: number?, -- Speed archetype
}

local powerups: { [string]: PowerupDefinition } = {
	Speed = {
		Id = "Speed",
		DisplayName = "Speed Surge",
		Color = Color3.fromRGB(80, 220, 255),
		Duration = 6,
		Archetype = "Speed",
		SpeedMultiplier = 1.35,
	},
	Shield = {
		Id = "Shield",
		DisplayName = "Shield",
		Color = Color3.fromRGB(255, 220, 80),
		Duration = 3,
		Archetype = "Shield",
	},
	Haste = {
		Id = "Haste",
		DisplayName = "Haste",
		Color = Color3.fromRGB(180, 80, 255),
		Duration = 1, -- flavor only; the effect (cooldown reset) is instant
		Archetype = "Haste",
	},
	Reveal = {
		Id = "Reveal",
		DisplayName = "Enemy Vision",
		Color = Color3.fromRGB(255, 80, 140),
		Duration = 8,
		Archetype = "Reveal",
	},
}
CTFConfig.Powerups = powerups

-- Fixed draw order so the spawner cycles predictably rather than relying on
-- table iteration order (which pairs() does not guarantee).
CTFConfig.PowerupOrder = { "Speed", "Shield", "Haste", "Reveal" }

function CTFConfig.GetPowerup(id: string): PowerupDefinition?
	return powerups[id]
end

-- Spawn points as fractional (x, z) coordinates inside the Arena zone rect
-- (see WorldLayout.PointIn), not hardcoded studs - the arena is built by a
-- separate world-design agent and its geometry isn't visible from here.
CTFConfig.PowerupSpawnFractions = {
	{ 0.5, 0.5 },
	{ 0.25, 0.3 },
	{ 0.75, 0.3 },
	{ 0.25, 0.7 },
	{ 0.75, 0.7 },
	{ 0.5, 0.15 },
}
CTFConfig.PowerupRespawnSeconds = 20

return CTFConfig
