--!strict
-- A giant's mind as plain data: its mood, what it's doing about the hunters
-- (its plan), and which attack fits where a hunter is. Pure functions of
-- numbers and flags, no Roblox calls, so they can be tested offline;
-- GiantService senses the world, feeds them, and acts on the result.
--
-- Plans (what the giant is up to):
--   Wander       nobody about: roams, strolls into town                 (Calm)
--   Notice       just spotted someone: stops, turns to look (reaction)  (Alert)
--   Chase        after its target                                     (Hunting)
--   Listen       heard something: stops and looks toward it             (Alert)
--   Investigate  walks to where it last saw / heard someone             (Alert)
--   Search       there, looking round ("Search")                        (Alert)
--   Sniff        a last sniff of the air ("Sniff"), then back to Wander  (Alert)
--   Ambush       (intelligent) crouched still where it lost someone    (Alert)
--   Retreat / Brace / Climb / Taunt: set by GiantService for a while (PlanUntil)
-- Enraged (2+ hits, or a friend falling close by) overrides the mood for a
-- while: faster, shorter cooldowns.

local GiantBrain = {}

export type Mood = "Calm" | "Alert" | "Hunting" | "Enraged"
export type Plan = "Wander" | "Notice" | "Chase" | "Listen" | "Investigate" | "Search" | "Sniff" | "Ambush" | "Retreat" | "Brace" | "Climb" | "Taunt"

export type State = {
	Mood: Mood,
	Plan: Plan,
	PlanUntil: number,
	EnragedUntil: number,
	Hits: number,
	HitsUntil: number,
	LastSeenAt: number,
	Memory: boolean, -- it remembers somewhere to look
}

-- What GiantService sensed this think (one table per giant, reused).
export type Sense = {
	Sees: boolean, -- a target in sight
	Heard: boolean, -- a fresh noise it can hear
	Arrived: boolean, -- at the point it was heading for
	InStrike: boolean, -- (ambushing) the target is in lunge range in front
	Reaction: number, -- seconds to react to a hunter it spots (mind and round)
	Roll: number, -- a fresh random number in [0, 1)
}

-- The per-mind numbers the state machine needs (Config.GiantAI.Minds[mind]).
export type Mind = {
	Memory: number, -- seconds it keeps looking for someone it lost (0: forgets at once)
	TrackGrace: number, -- seconds out of sight before a chase counts as lost
	Hearing: boolean,
	AmbushChance: number,
	AmbushTime: number,
	ListenTime: number,
	SearchTime: number,
	SniffTime: number,
}

-- How strongly an attack is wanted, as GiantService measures the target.
export type Facts = {
	Size: number, -- the giant's height
	GrabReach: number,
	Flat: number, -- flat distance, giant root to hunter
	Above: number, -- the hunter's height above the land
	Dot: number, -- how squarely in front (1 dead ahead, -1 behind)
	Perched: boolean, -- standing still on something (a roof, a wall)
	ChestDist: number, -- to the giant's chest (the plain grab)
	NearFeet: number, -- hunters on the ground close to its feet
	Lift: number, -- how far it has climbed up a facade
	-- Off cooldown, and in this mind's repertoire:
	Grab: boolean,
	Stomp: boolean,
	Swipe: boolean,
	Lunge: boolean,
	Crouch: boolean,
}

export type AttackTuning = {
	Stomp: { Radius: number, MaxAbove: number, Force: number },
	Swipe: { Reach: number, MinAbove: number, Force: number },
	Lunge: { Reach: number, MaxAbove: number, FrontDot: number, Speed: number },
	Crouch: { Reach: number, MaxAbove: number, FrontDot: number },
	FrontDot: number,
}

local OVERRIDES: { [string]: boolean } = { Retreat = true, Brace = true, Climb = true, Taunt = true }
local MOOD_OF: { [string]: Mood } = {
	Wander = "Calm",
	Notice = "Alert",
	Listen = "Alert",
	Investigate = "Alert",
	Search = "Alert",
	Sniff = "Alert",
	Ambush = "Alert",
	Brace = "Alert",
	Chase = "Hunting",
	Climb = "Hunting",
	Retreat = "Hunting",
	Taunt = "Hunting",
}

function GiantBrain.New(now: number): State
	return { Mood = "Calm", Plan = "Wander", PlanUntil = now, EnragedUntil = 0, Hits = 0, HitsUntil = 0, LastSeenAt = -math.huge, Memory = false }
end

function GiantBrain.NewSense(): Sense
	return { Sees = false, Heard = false, Arrived = false, InStrike = false, Reaction = 0.5, Roll = 0 }
end

function GiantBrain.Lerp(range: { number }, k: number): number
	return range[1] + (range[2] - range[1]) * k
end

-- 0 in round 1, 1 from round `full` on.
function GiantBrain.Difficulty(round: number, full: number): number
	return math.clamp((round - 1) / math.max(full - 1, 1), 0, 1)
end

function GiantBrain.SetPlan(s: State, plan: Plan, untilTime: number)
	s.Plan = plan
	s.PlanUntil = untilTime
	if s.Mood ~= "Enraged" then
		s.Mood = MOOD_OF[plan]
	end
end

function GiantBrain.IsOverride(plan: Plan): boolean
	return OVERRIDES[plan] == true
end

-- Somebody it can't see any more: look for them (with a memory), or just
-- forget them (mindless).
local function lose(s: State, sense: Sense, mind: Mind, now: number)
	if mind.Memory <= 0 then
		s.Memory = false
		GiantBrain.SetPlan(s, "Wander", now)
	elseif sense.Roll < mind.AmbushChance then
		GiantBrain.SetPlan(s, "Ambush", now + mind.AmbushTime)
	else
		GiantBrain.SetPlan(s, "Investigate", now + mind.Memory)
	end
end

-- One think. Returns true when the mood changed.
function GiantBrain.Update(s: State, sense: Sense, mind: Mind, now: number): boolean
	local before = s.Mood
	if s.Mood == "Enraged" and now >= s.EnragedUntil then
		s.Mood = MOOD_OF[s.Plan] -- calmed down
	end
	local plan = s.Plan
	if OVERRIDES[plan] then
		if now >= s.PlanUntil then
			if sense.Sees then
				s.LastSeenAt = now
				GiantBrain.SetPlan(s, "Chase", now)
			elseif s.Memory and mind.Memory > 0 then
				GiantBrain.SetPlan(s, "Investigate", now + mind.Memory)
			else
				GiantBrain.SetPlan(s, "Wander", now)
			end
		elseif sense.Sees then
			s.LastSeenAt = now
			s.Memory = true
		end
	elseif sense.Sees then
		s.LastSeenAt = now
		s.Memory = true
		if plan == "Chase" then
			-- (still on it)
		elseif plan == "Notice" then
			if now >= s.PlanUntil then
				GiantBrain.SetPlan(s, "Chase", now)
			end
		elseif plan == "Ambush" and sense.InStrike and now < s.PlanUntil then
			-- (GiantService springs the lunge)
		else
			-- Spotted someone: a beat to turn and look first (quicker when it
			-- was already on edge, or angry).
			local edgy = plan ~= "Wander" or s.Mood == "Enraged"
			GiantBrain.SetPlan(s, "Notice", now + sense.Reaction * (if edgy then 0.5 else 1))
		end
	elseif plan == "Chase" then
		if now - s.LastSeenAt > mind.TrackGrace then
			lose(s, sense, mind, now)
		end
	elseif plan == "Notice" then
		if now >= s.PlanUntil + mind.TrackGrace then
			lose(s, sense, mind, now)
		end
	elseif plan == "Wander" then
		if sense.Heard and mind.Hearing then
			s.Memory = true
			s.LastSeenAt = now
			GiantBrain.SetPlan(s, "Listen", now + mind.ListenTime)
		end
	elseif sense.Heard and mind.Hearing and plan ~= "Listen" then
		-- Another noise: off to look there instead.
		s.LastSeenAt = now
		GiantBrain.SetPlan(s, "Investigate", now + mind.Memory)
	elseif plan == "Listen" then
		if now >= s.PlanUntil then
			GiantBrain.SetPlan(s, "Investigate", now + math.max(mind.Memory, mind.ListenTime))
		end
	elseif plan == "Investigate" then
		if sense.Arrived or now >= s.PlanUntil then
			GiantBrain.SetPlan(s, "Search", now + mind.SearchTime)
		end
	elseif plan == "Ambush" then
		if now >= s.PlanUntil then
			GiantBrain.SetPlan(s, "Search", now + mind.SearchTime)
		end
	elseif plan == "Search" then
		if now >= s.PlanUntil then
			GiantBrain.SetPlan(s, "Sniff", now + mind.SniffTime)
		end
	elseif plan == "Sniff" then
		if now >= s.PlanUntil then
			s.Memory = false
			GiantBrain.SetPlan(s, "Wander", now)
		end
	end
	return s.Mood ~= before
end

-- A hunter's cut (or a cannonball) landed. True when that made it Enraged.
function GiantBrain.Hit(s: State, now: number, hitsToEnrage: number, window: number, enrageFor: number): boolean
	if now >= s.HitsUntil then
		s.Hits = 0
	end
	s.Hits += 1
	s.HitsUntil = now + window
	if s.Hits >= hitsToEnrage then
		s.Hits = 0
		return GiantBrain.Enrage(s, now, enrageFor)
	end
	return false
end

-- True when it wasn't already Enraged.
function GiantBrain.Enrage(s: State, now: number, duration: number): boolean
	local fresh = s.Mood ~= "Enraged"
	s.Mood = "Enraged"
	s.EnragedUntil = math.max(s.EnragedUntil, now + duration)
	return fresh
end

-- Another giant's roar calls it to a hunter (pack behaviour).
function GiantBrain.Called(s: State, mind: Mind, now: number)
	if s.Plan == "Chase" or s.Plan == "Notice" or OVERRIDES[s.Plan] or mind.Memory <= 0 then
		return
	end
	s.Memory = true
	s.LastSeenAt = now
	GiantBrain.SetPlan(s, "Investigate", now + mind.Memory)
	if s.Mood ~= "Enraged" then
		s.Mood = "Hunting"
	end
end

-- Which attack fits where the hunter is (nil: none, keep moving). The plain
-- grab first, then the new moves; every one has its own wind-up.
function GiantBrain.PickAttack(f: Facts, t: AttackTuning): string?
	local h = f.Size
	if f.Grab and f.ChestDist <= f.GrabReach then
		return "Grab"
	end
	-- Perched on a roof or a wall at arm height, in front: swipe them off.
	local top = h * 1.05 + f.Lift
	if f.Swipe and f.Perched and f.Above >= h * t.Swipe.MinAbove and f.Above <= top and f.Flat <= h * t.Swipe.Reach and f.Dot > t.FrontDot then
		return "Swipe"
	end
	local onGround = f.Above <= t.Stomp.MaxAbove
	-- A crowd round its feet: stomp.
	if f.Stomp and f.NearFeet >= 2 then
		return "Stomp"
	end
	-- Low and right in front of it: crouch and scoop.
	if f.Crouch and f.Above <= h * t.Crouch.MaxAbove and f.Flat <= h * t.Crouch.Reach and f.Dot > t.Crouch.FrontDot then
		return "Crouch"
	end
	if f.Stomp and onGround and f.Flat <= h * t.Stomp.Radius then
		return "Stomp"
	end
	-- In front, a little too far for a grab: a dive.
	if f.Lunge and f.Dot > t.Lunge.FrontDot and f.Above <= h * t.Lunge.MaxAbove and f.Flat > f.GrabReach and f.Flat <= f.GrabReach + h * t.Lunge.Reach then
		return "Lunge"
	end
	return nil
end

-- Lower is a better target. Smart minds prefer a hunter on their own, or
-- one cutting a friend loose, stick with the one they have, and leave a
-- hunter alone if `maxAttackers` giants are already on them.
function GiantBrain.TargetScore(distance: number, smart: boolean, alone: boolean, rescuer: boolean, current: boolean, attackers: number, maxAttackers: number, bonus: number): number
	local score = distance
	if smart then
		if alone then
			score -= bonus
		end
		if rescuer then
			score -= bonus * 1.5
		end
		if current then
			score -= bonus * 0.5
		end
		if attackers >= maxAttackers then
			score += 100000 -- taken: only if there's nobody else (then it circles)
		end
	end
	return score
end

return GiantBrain
