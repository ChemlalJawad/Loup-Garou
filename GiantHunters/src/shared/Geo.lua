--!strict
-- Shared geometry of the walled district: polar placement, inside/outside
-- the Great Wall, the gateway, the river, and how a giant gets from A to B
-- (round the wall, and only through the gate once it's been breached).
-- Pure functions of Config.World, used by the map builder, the giant AI and
-- the client radar alike.

local Config = require(script.Parent.Config)

local Geo = {}

local W = Config.World
local R = W.WallRadius
local T = W.WallThickness

Geo.INSIDE_LIMIT = R - 14 -- giants inside stay this far from the wall's face
Geo.OUTSIDE_LIMIT = R + T + 14 -- ...and outside, this far out
Geo.LAND_LIMIT = W.LandRadius - 120 -- ...and never walk into the hill ring

-- Angle from +Z (south) toward +X (east).
function Geo.Polar(angle: number, radius: number, y: number?): Vector3
	return Vector3.new(math.sin(angle) * radius, y or 0, math.cos(angle) * radius)
end

function Geo.AngleOf(p: Vector3): number
	return math.atan2(p.X, p.Z)
end

function Geo.Flat(p: Vector3): Vector3
	return Vector3.new(p.X, 0, p.Z)
end

function Geo.RadiusOf(p: Vector3): number
	return math.sqrt(p.X * p.X + p.Z * p.Z)
end

-- Smallest signed difference between two angles, in [-pi, pi).
function Geo.AngleDelta(from: number, to: number): number
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

-- Which side of the wall a point is on (split down the wall's middle).
function Geo.IsInside(p: Vector3): boolean
	return Geo.RadiusOf(p) < R + T / 2
end

local function gateAxis(): (Vector3, Vector3)
	local along = Geo.Polar(W.GateAngle, 1)
	local across = Vector3.new(along.Z, 0, -along.X)
	return along, across
end

function Geo.GateOuter(): Vector3
	return Geo.Polar(W.GateAngle, R + T + 34)
end

function Geo.GateInner(): Vector3
	return Geo.Polar(W.GateAngle, R - 34)
end

-- In the corridor that runs through the gate, from just inside to just out.
function Geo.InGateway(p: Vector3): boolean
	local along, across = gateAxis()
	local flat = Geo.Flat(p)
	local depth = flat:Dot(along)
	local side = math.abs(flat:Dot(across))
	return side < W.GateWidth / 2 - 3 and depth > R - 40 and depth < R + T + 44
end

function Geo.ClampInside(p: Vector3): Vector3
	local r = Geo.RadiusOf(p)
	if r <= Geo.INSIDE_LIMIT then
		return Geo.Flat(p)
	end
	return Geo.Flat(p) * (Geo.INSIDE_LIMIT / r)
end

function Geo.ClampOutside(p: Vector3): Vector3
	local r = Geo.RadiusOf(p)
	if r < 1 then
		return Geo.Polar(W.GateAngle, Geo.OUTSIDE_LIMIT)
	end
	local clamped = math.clamp(r, Geo.OUTSIDE_LIMIT, Geo.LAND_LIMIT)
	return Geo.Flat(p) * (clamped / r)
end

-- Closest the straight line a -> b passes to the centre (flat).
local function closestApproach(a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return Geo.RadiusOf(a)
	end
	local t = math.clamp(-a:Dot(ab) / lengthSq, 0, 1)
	return Geo.RadiusOf(a + ab * t)
end

-- Outside the wall: a step round the ring toward `goal` if the straight
-- line would cut through the wall, otherwise straight there.
local function aroundOutside(from: Vector3, goal: Vector3): Vector3
	if closestApproach(from, goal) < R + T + 12 then
		local start = Geo.AngleOf(from)
		local step = math.clamp(Geo.AngleDelta(start, Geo.AngleOf(goal)), -0.45, 0.45)
		return Geo.Polar(start + step, math.max(Geo.RadiusOf(from), Geo.OUTSIDE_LIMIT + 24))
	end
	return Geo.ClampOutside(goal)
end

-- Where a giant at `from` should walk next to reach `to` (both flattened).
-- nil: it can't get there - the target is on the other side of a closed
-- gate.
function Geo.NextWaypoint(from: Vector3, to: Vector3, breached: boolean): Vector3?
	from, to = Geo.Flat(from), Geo.Flat(to)
	local fromInside, toInside = Geo.IsInside(from), Geo.IsInside(to)
	if Geo.InGateway(from) and breached then
		-- Already in the gateway: carry on through to the target's side.
		if toInside then
			if Geo.RadiusOf(from) <= R - 30 then
				return Geo.ClampInside(to)
			end
			return Geo.GateInner()
		end
		if Geo.RadiusOf(from) >= R + T + 30 then
			return aroundOutside(from, to)
		end
		return Geo.GateOuter()
	end
	if fromInside and toInside then
		return Geo.ClampInside(to)
	end
	if not fromInside and not toInside then
		return aroundOutside(from, to)
	end
	if not breached then
		return nil
	end
	if fromInside then
		return Geo.GateInner()
	end
	local mouth = Geo.GateOuter()
	if (from - mouth).Magnitude < 12 then
		return Geo.GateInner()
	end
	return aroundOutside(from, mouth)
end

-- The river: west to east across the north of town, gently winding.
function Geo.RiverZ(x: number): number
	local river = W.River
	return river.Z + river.Wave * math.sin(x / river.WaveLength)
end

-- In the river or one of the round pools it ends in (|x| = River.Reach).
function Geo.InRiver(x: number, z: number, margin: number?): boolean
	local river = W.River
	local extra = margin or 0
	local reach = river.Reach
	if math.abs(x) <= reach then
		return math.abs(z - Geo.RiverZ(x)) < river.Width / 2 + extra
	end
	local endX = if x > 0 then reach else -reach
	local dx, dz = x - endX, z - Geo.RiverZ(endX)
	return math.sqrt(dx * dx + dz * dz) < river.PoolRadius + extra
end

-- The old castle's hill (west): its centre on the ground, and whether a
-- point is on the hill (flat distance; `margin` widens it). Giants should
-- keep off it.
function Geo.CastleCentre(): Vector3
	local castle = W.Castle
	return Geo.Polar(castle.Angle, castle.Radius)
end

function Geo.InCastleHill(p: Vector3, margin: number?): boolean
	local centre = Geo.CastleCentre()
	local dx, dz = p.X - centre.X, p.Z - centre.Z
	return math.sqrt(dx * dx + dz * dz) < W.Castle.HillRadius + (margin or 0)
end

return Geo
