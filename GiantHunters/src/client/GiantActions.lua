--!strict
-- The giants' one-shot moves (Stomp, Swipe, Lunge, Climb...) as data: each
-- is a list of key poses (joint deltas on top of the walk) at times in
-- seconds, eased between, plus an optional procedural extra (a shake, a
-- sniff, a flinch away from the hit). Timings (Duration, Windup, Impact,
-- Loop, Gait) live in Config.GiantActions so the server reads the same ones.
-- Pure: GiantAnimator.Pose adds them in; nothing here touches instances.
--
-- Channels (radians unless noted), as GiantAnimator.Pose uses them:
--   WX/WY/WZ   waist: + leans back / + turns left / + tilts left
--   WUp/WFwd   waist offset, x the giant's height: up / forward
--   NX/NY/NZ   head: + looks up / + turns left / + tilts left
--   LHX/RHX    hips: + leg forward;  LHZ/RHZ: leg out (- left, + right)
--   LK/RK      knees: - bends back
--   LSX/RSX    shoulders: + arm forward (1.57 level, ~2.9 overhead)
--   LSY/RSY    upper-arm twist;  LSZ/RSZ: arm out (- left, + right)
--   LE/RE      elbows: + bends
-- Moves are authored for the right side; a "Sided" move whose target is on
-- the left (ActionDir) plays mirrored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GiantActions = {}

local CHANNELS = { "WX", "WY", "WZ", "WUp", "WFwd", "NX", "NY", "NZ", "LHX", "LHZ", "LK", "RHX", "RHZ", "RK", "LSX", "LSY", "LSZ", "LE", "RSX", "RSY", "RSZ", "RE" }
local N = #CHANNELS
local INDEX: { [string]: number } = {}
for i, name in CHANNELS do
	INDEX[name] = i
end
GiantActions.Count = N
GiantActions.Index = INDEX

-- Mirroring: left and right swap; sideways turns and tilts flip sign.
local MIRROR: { number } = table.create(N, 0)
local FLIP: { number } = table.create(N, 1)
for i, name in CHANNELS do
	local first = string.sub(name, 1, 1)
	local other = name
	if first == "L" and #name <= 3 then
		other = "R" .. string.sub(name, 2)
	elseif first == "R" and #name <= 3 then
		other = "L" .. string.sub(name, 2)
	end
	MIRROR[i] = INDEX[other]
	local last = string.sub(name, -1)
	if name == "WY" or name == "WZ" or name == "NY" or name == "NZ" or (other ~= name and (last == "Z" or last == "Y")) then
		FLIP[i] = -1
	end
end

type Key = { T: number, V: { number }, In: boolean }
type Extra = (t: number, d: { number }, dir: Vector3) -> ()
type Def = { Keys: { Key }, Sided: boolean, Extra: Extra?, Blend: number }

-- Smooth 0..1..0: up over `ramp` from `a`, down over `ramp` to `b`.
local function window(t: number, a: number, b: number, ramp: number): number
	local u = math.clamp(math.min(t - a, b - t) / ramp, 0, 1)
	return u * u * (3 - 2 * u)
end
GiantActions.Window = window

local defs: { [string]: Def } = {}

-- keys: { { time, { Channel = value, ... }, "in"? } ...}; "in" eases into
-- that key accelerating (a blow landing) instead of smoothly.
local function define(name: string, keys: { { any } }, opts: { Sided: boolean?, Extra: Extra?, Blend: number? }?)
	local compiled: { Key } = {}
	for _, key in keys do
		local values: { number } = table.create(N, 0)
		for channel, value in key[2] :: { [string]: number } do
			local i = INDEX[channel]
			assert(i, `GiantActions: unknown channel {channel}`)
			values[i] = value
		end
		table.insert(compiled, { T = key[1] :: number, V = values, In = key[3] == "in" })
	end
	defs[name] = {
		Keys = compiled,
		Sided = opts ~= nil and opts.Sided == true,
		Extra = opts and opts.Extra,
		Blend = (opts and opts.Blend) or 12,
	}
end

-- === The moves ===============================================================

-- Stomp: the right foot (the target's side) up high, arms out for balance,
-- then slammed down, knees giving under the weight.
local STOMP_UP = { RHX = 1.15, RK = -1.35, LK = -0.12, WX = 0.12, WZ = 0.08, LSX = 0.3, RSX = 0.3, LSZ = -0.55, RSZ = 0.55, LE = 0.4, RE = 0.4, NX = -0.1 }
define("Stomp", {
	{ 0, {} },
	{ 0.45, STOMP_UP },
	{ 0.55, { RHX = 1.25, RK = -1.45, LK = -0.15, WX = 0.16, WZ = 0.09, LSX = 0.35, RSX = 0.35, LSZ = -0.6, RSZ = 0.6, LE = 0.45, RE = 0.45, NX = -0.12 } },
	{ 0.6, { RHX = 0.15, RK = -0.05, LK = -0.35, WX = -0.2, WUp = -0.012, LSX = 0.6, RSX = 0.6, LSZ = -0.3, RSZ = 0.3, LE = 0.6, RE = 0.6, NX = -0.15 }, "in" },
	{ 0.82, { RHX = 0.2, RK = -0.25, LK = -0.25, WX = -0.12, LSX = 0.4, RSX = 0.4, LSZ = -0.25, RSZ = 0.25, LE = 0.4, RE = 0.4, NX = -0.1 } },
	{ 1.2, {} },
}, { Sided = true })

-- Swipe: the arm wound out wide and back (the tell), then swept right across
-- the front at roof height, the trunk twisting into it.
local SWIPE_BACK = { RSX = 1.25, RSY = -0.55, RSZ = 1.6, RE = 0.45, WY = -0.45, WZ = 0.08, NY = -0.15, LSX = 0.5, LSZ = -0.4, LE = 0.5, RHZ = 0.08 }
define("Swipe", {
	{ 0, {} },
	{ 0.36, SWIPE_BACK },
	{ 0.42, { RSX = 1.3, RSY = -0.6, RSZ = 1.7, RE = 0.4, WY = -0.5, WZ = 0.09, NY = -0.18, LSX = 0.5, LSZ = -0.45, LE = 0.5, RHZ = 0.08 } },
	{ 0.55, { RSX = 1.5, RSZ = -0.5, RE = 0.15, WY = 0.5, WX = -0.05, NY = 0.2, LSX = -0.2, LSZ = -0.6, LE = 0.3, LHZ = -0.06 }, "in" },
	{ 0.7, { RSX = 1.3, RSZ = -0.7, RE = 0.4, WY = 0.55, WX = -0.08, NY = 0.15, LSX = -0.1, LSZ = -0.5, LE = 0.3 } },
	{ 1.0, {} },
}, { Sided = true })

-- Lunge: rears back with both arms wide (the tell), then dives forward,
-- both hands reaching together.
define("Lunge", {
	{ 0, {} },
	{ 0.45, { WX = 0.22, LSX = 1.0, RSX = 1.0, LSZ = -0.75, RSZ = 0.75, LE = 0.6, RE = 0.6, RHX = 0.3, RK = -0.5, LHX = -0.05, LK = -0.4, NX = -0.05 } },
	{ 0.62, { WX = -0.75, WFwd = 0.06, WUp = -0.03, LSX = 1.65, RSX = 1.65, LSZ = 0.12, RSZ = -0.12, LE = 0.05, RE = 0.05, RHX = 0.7, RK = -0.6, LHX = -0.35, LK = -0.1, NX = 0.55 }, "in" },
	{ 0.85, { WX = -0.62, WFwd = 0.05, WUp = -0.025, LSX = 1.5, RSX = 1.5, LSZ = 0.05, RSZ = -0.05, LE = 0.2, RE = 0.2, RHX = 0.6, RK = -0.55, LHX = -0.3, LK = -0.15, NX = 0.45 } },
	{ 1.1, {} },
}, { Blend = 10 })

-- Climb (looped): hands up the wall in turn, the opposite leg pushing.
local CLIMB_A = { RSX = 2.9, RSZ = 0.15, RE = 0.3, LSX = 1.75, LSZ = -0.2, LE = 1.35, LHX = 0.95, LK = -1.35, RHX = 0.05, RK = -0.15, WX = -0.22, WZ = 0.06, NX = 0.45 }
local CLIMB_B = { LSX = 2.9, LSZ = -0.15, LE = 0.3, RSX = 1.75, RSZ = 0.2, RE = 1.35, RHX = 0.95, RK = -1.35, LHX = 0.05, LK = -0.15, WX = -0.22, WZ = -0.06, NX = 0.45 }
define("Climb", {
	{ 0, CLIMB_A },
	{ 0.8, CLIMB_B },
	{ 1.6, CLIMB_A },
}, { Blend = 5 })

-- Shake: like a wet dog - the trunk whips side to side, arms flopping.
local SHAKE_HOLD = { LSX = 0.3, RSX = 0.3, LSZ = -0.55, RSZ = 0.55, LE = 0.5, RE = 0.5, LK = -0.2, RK = -0.2, WX = -0.06 }
define("Shake", {
	{ 0, {} },
	{ 0.15, SHAKE_HOLD },
	{ 0.8, SHAKE_HOLD },
	{ 1.0, {} },
}, {
	Extra = function(t: number, d: { number }, _dir: Vector3)
		local w = window(t, 0.05, 0.95, 0.15)
		local s = math.sin(t * 27)
		d[INDEX.WY] += s * 0.28 * w
		d[INDEX.WZ] += math.sin(t * 27 + 1) * 0.12 * w
		d[INDEX.NY] -= s * 0.45 * w
		d[INDEX.NZ] += math.sin(t * 31) * 0.15 * w
		d[INDEX.LSZ] -= math.abs(s) * 0.4 * w
		d[INDEX.RSZ] += math.abs(math.sin(t * 27 + 1.2)) * 0.4 * w
		d[INDEX.LE] += s * 0.4 * w
		d[INDEX.RE] -= s * 0.4 * w
	end,
})

-- Search: lost you - a hand over its eyes, peering slowly left and right.
local function shade(extra: { [string]: number }): { [string]: number }
	local pose: { [string]: number } = { RSX = 2.35, RSZ = -0.25, RE = 1.95, NX = 0.1, WX = 0.05, LSX = 0.15, LSZ = -0.15 }
	for k, v in extra do
		pose[k] = v
	end
	return pose
end
define("Search", {
	{ 0, {} },
	{ 0.35, shade({}) },
	{ 0.85, shade({ NY = 0.85, WY = 0.25 }) },
	{ 1.55, shade({ NY = -0.85, WY = -0.25 }) },
	{ 2.05, shade({ NY = 0.15 }) },
	{ 2.5, {} },
})

-- Sniff: leans toward ActionDir, nose up, little quick sniffs.
local SNIFF = { WX = -0.25, NX = 0.3, LSX = -0.25, RSX = -0.25, LSZ = -0.15, RSZ = 0.15, LE = 0.4, RE = 0.4 }
define("Sniff", {
	{ 0, {} },
	{ 0.35, SNIFF },
	{ 1.15, SNIFF },
	{ 1.5, {} },
}, {
	Extra = function(t: number, d: { number }, dir: Vector3)
		local w = window(t, 0, 1.5, 0.35)
		local yaw = math.clamp(math.atan2(-dir.X, -dir.Z), -1.1, 1.1)
		d[INDEX.NY] += yaw * 0.6 * w
		d[INDEX.WY] += yaw * 0.35 * w
		d[INDEX.NX] += math.max(math.sin(t * 12), 0) * 0.07 * w
	end,
})

-- Flinch: a quick recoil away from where the cut came from, arms up.
define("Flinch", {
	{ 0, {} },
	{ 0.1, { NX = 0.12, LSX = 0.6, RSX = 0.6, LSZ = -0.3, RSZ = 0.3, LE = 0.9, RE = 0.9, LK = -0.15, RK = -0.15 }, "in" },
	{ 0.4, {} },
}, {
	Blend = 20,
	Extra = function(t: number, d: { number }, dir: Vector3)
		local w = window(t, 0, 0.4, 0.1)
		d[INDEX.WX] -= dir.Z * 0.22 * w
		d[INDEX.WZ] += dir.X * 0.18 * w
		d[INDEX.NY] += dir.X * 0.35 * w
		d[INDEX.NX] -= dir.Z * 0.1 * w
	end,
})

-- Stagger: a big stumble back, arms windmilling, a step back to catch itself.
define("Stagger", {
	{ 0, {} },
	{ 0.15, { WX = 0.35, NX = -0.2, LSX = 0.9, RSX = 0.6, LSZ = -0.9, RSZ = 1.0, LE = 0.4, RE = 0.6, RHX = -0.35, RK = -0.3, LHX = 0.25, LK = -0.2 }, "in" },
	{ 0.4, { WX = 0.25, WZ = 0.12, NX = -0.1, NZ = 0.15, LSX = 1.4, RSX = 0.3, LSZ = -1.1, RSZ = 1.2, LE = 0.3, RE = 0.5, RHX = -0.2, RK = -0.2, LHX = -0.3, LK = -0.5 } },
	{ 0.65, { WX = 0.08, WZ = -0.06, LSZ = -0.5, RSZ = 0.5, LK = -0.25, RK = -0.25 } },
	{ 0.9, {} },
}, { Blend = 20 })

-- Taunt (abnormals): beats its chest, then a big goofy wave.
local BEAT = { LSX = 1.3, RSX = 1.3, LSZ = 0.35, RSZ = -0.35, LE = 1.6, RE = 1.6, WX = 0.12, NX = 0.25 }
local WAVE = { RSX = 2.8, RSZ = 0.6, RE = 0.4, LSX = 0.2, LSZ = -0.6, WZ = 0.12, NZ = 0.2, NX = 0.15 }
define("Taunt", {
	{ 0, {} },
	{ 0.2, BEAT },
	{ 0.75, BEAT },
	{ 0.95, WAVE },
	{ 1.32, WAVE },
	{ 1.5, {} },
}, {
	Extra = function(t: number, d: { number }, _dir: Vector3)
		local beat = window(t, 0.2, 0.75, 0.08)
		local s = math.sin(t * 24)
		d[INDEX.LSX] += s * 0.28 * beat
		d[INDEX.RSX] -= s * 0.28 * beat
		d[INDEX.LK] -= math.abs(s) * 0.12 * beat
		d[INDEX.RK] -= math.abs(s) * 0.12 * beat
		local wave = window(t, 0.95, 1.32, 0.08)
		d[INDEX.RSZ] += math.sin(t * 16) * 0.4 * wave
		d[INDEX.NZ] += math.sin(t * 8) * 0.12 * wave
	end,
})

-- Crouch: bends low (mostly at the waist; the feet stay down), one hand
-- scooping at the ground.
local CROUCH = { WX = -0.95, LHX = 0.3, RHX = 0.3, LK = -0.6, RK = -0.6, RSX = 1.2, RSZ = -0.1, RE = 0.05, LSX = 0.6, LSZ = -0.3, LE = 0.3, NX = 0.7 }
define("Crouch", {
	{ 0, {} },
	{ 0.4, { WX = -0.7, LHX = 0.22, RHX = 0.22, LK = -0.45, RK = -0.45, RSX = 0.9, RE = 0.35, LSX = 0.5, LSZ = -0.3, LE = 0.3, NX = 0.55 } },
	{ 0.5, CROUCH, "in" },
	{ 0.75, CROUCH },
	{ 1.0, {} },
}, { Sided = true })

-- Roar: hunches to gather breath, then head back, arms flung out, trembling.
local ROAR = { WX = 0.3, NX = 0.55, LSX = 0.5, RSX = 0.5, LSZ = -1.3, RSZ = 1.3, LE = 0.25, RE = 0.25, LK = -0.1, RK = -0.1 }
define("Roar", {
	{ 0, {} },
	{ 0.35, { WX = -0.25, NX = -0.25, LSX = 0.6, RSX = 0.6, LSZ = -0.2, RSZ = 0.2, LE = 1.2, RE = 1.2, LK = -0.2, RK = -0.2 } },
	{ 0.5, ROAR, "in" },
	{ 1.15, ROAR },
	{ 1.4, {} },
}, {
	Extra = function(t: number, d: { number }, _dir: Vector3)
		local w = window(t, 0.5, 1.15, 0.1)
		d[INDEX.NZ] += math.sin(t * 30) * 0.04 * w
		d[INDEX.LSZ] += math.sin(t * 25) * 0.06 * w
		d[INDEX.RSZ] -= math.sin(t * 25) * 0.06 * w
	end,
})

-- Turn (toward someone behind it, right as authored): the head snaps round
-- first, the trunk follows, leaning in, the feet shuffle round.
define("Turn", {
	{ 0, {} },
	{ 0.12, { NY = -0.6, WY = -0.15 } },
	{ 0.3, { NY = -0.45, WY = -0.45, WZ = -0.08, RHZ = 0.22, RHX = 0.3, RK = -0.5, LSX = -0.3, RSX = 0.4, LSZ = -0.4, RSZ = 0.3 } },
	{ 0.45, { NY = -0.15, WY = -0.2, LHZ = -0.12, LHX = 0.25, LK = -0.4 } },
	{ 0.6, {} },
}, { Sided = true, Blend = 16 })

-- Kick (the Wallbreaker at the gate): a slow, heavy wind-up with the leg
-- drawn back, the kick, a hold, then the foot planted again.
define("Kick", {
	{ 0, {} },
	{ 0.45, { RHX = -0.45, RK = -1.1, WX = -0.12, LK = -0.3, LSX = 0.5, RSX = -0.4, LSZ = -0.6, RSZ = 0.7, NX = 0.1 } },
	{ 0.6, { RHX = -0.5, RK = -1.2, WX = -0.15, LK = -0.32, LSX = 0.55, RSX = -0.45, LSZ = -0.65, RSZ = 0.75, NX = 0.1 } },
	{ 0.75, { RHX = 1.35, RK = -0.1, WX = 0.25, LK = -0.35, LSX = 0.3, RSX = 0.6, LSZ = -1.1, RSZ = 1.1, NX = -0.25 }, "in" },
	{ 1.5, { RHX = 1.25, RK = -0.15, WX = 0.22, LK = -0.35, LSX = 0.3, RSX = 0.5, LSZ = -1.0, RSZ = 1.0, NX = -0.2 } },
	{ 1.95, { RHX = 0.3, RK = -0.3, WX = -0.05, LK = -0.25, LSZ = -0.3, RSZ = 0.3 } },
	{ 2.35, {} },
}, { Blend = 6 })

-- Peek (looped; the Wallbreaker before its kick): leaning in over the wall,
-- hands on the top, the head turning slowly from side to side.
local PEEK = { WX = -0.35, WFwd = 0.02, LSX = 1.25, RSX = 1.25, LSZ = -0.15, RSZ = 0.15, LE = 0.7, RE = 0.7, NX = 0.25 }
local function peek(yaw: number): { [string]: number }
	local pose = table.clone(PEEK)
	pose.NY = yaw
	pose.WY = yaw * 0.2
	return pose
end
define("Peek", {
	{ 0, peek(0.5) },
	{ 2, peek(-0.5) },
	{ 4, peek(0.5) },
}, { Blend = 2 })

-- === Evaluation ==============================================================

local scratch: { number } = table.create(N, 0)

function GiantActions.Has(name: string): boolean
	return defs[name] ~= nil and Config.GiantActions[name] ~= nil
end

-- How fast a move fades in (and out when cut short), per second.
function GiantActions.Blend(name: string): number
	local def = defs[name]
	return if def then def.Blend else 12
end

-- How much of the walk shows under a move (Config Gait; 1 if unknown).
function GiantActions.Gait(name: string): number
	local spec = Config.GiantActions[name]
	return if spec then spec.Gait else 1
end

-- Adds move `name`, `t` seconds in, at weight `w` into `out` (channel
-- deltas). `dir`: toward the target / the hit, in the giant's own frame.
-- Allocates nothing.
function GiantActions.Add(name: string, t: number, w: number, dir: Vector3?, out: { number })
	local def = defs[name]
	local spec = Config.GiantActions[name]
	if not def or not spec or w <= 0.001 or t < 0 then
		return
	end
	local duration = spec.Duration
	if spec.Loop then
		t %= duration
	elseif t >= duration then
		return
	end
	local keys = def.Keys
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t < keys[i + 1].T then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	local span = b.T - a.T
	local u = if span > 0 then math.clamp((t - a.T) / span, 0, 1) else 1
	u = if b.In then u * u else u * u * (3 - 2 * u)
	local av, bv = a.V, b.V
	for c = 1, N do
		scratch[c] = av[c] + (bv[c] - av[c]) * u
	end
	local direction = dir or Vector3.new(0, 0, -1)
	local side = if def.Sided and direction.X < -0.05 then -1 else 1
	if def.Extra then
		def.Extra(t, scratch, Vector3.new(direction.X * side, direction.Y, direction.Z))
	end
	if side > 0 then
		for c = 1, N do
			out[c] += scratch[c] * w
		end
	else
		for c = 1, N do
			out[MIRROR[c]] += scratch[c] * w * FLIP[c]
		end
	end
end

return GiantActions
