--!strict
-- Where every hunter really is, as the server sees it.
--
-- Movement is simulated on each player's own client, so a cheater could
-- report any velocity, or pop their character straight onto a nape. The
-- server never asks: every Heartbeat it notes each hunter's position, works
-- out the speed itself (for clean cuts), and if someone covers more ground
-- than the grapple rig ever could (Config.Grapple.MaxSpeed, with room for
-- lag), their cuts don't count for a couple of seconds.
--
-- Whenever the server moves a hunter itself (respawn, a giant's hand, back
-- onto the wall), it calls Motion.Reset so that jump isn't held against them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Motion = {}

type Sample = { Time: number, Position: Vector3 }
type Track = {
	Root: BasePart?,
	Samples: { Sample }, -- oldest first, about the last second
	LastMove: Sample?, -- the last time the position changed
	SuspectUntil: number,
}

local HISTORY = 1 -- seconds kept
local SPEED_WINDOW = 0.2 -- speed is measured over about this long

local tracks: { [Player]: Track } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function track(player: Player): Track
	local t = tracks[player]
	if not t then
		t = { Root = nil, Samples = {}, SuspectUntil = 0 }
		tracks[player] = t
	end
	return t :: Track
end

-- Forget the history: the server just moved this hunter itself.
function Motion.Reset(player: Player)
	local t = tracks[player]
	if t then
		table.clear(t.Samples)
		t.LastMove = nil
	end
end

-- The oldest sample at least `window` seconds before the newest, or the
-- oldest there is.
local function sampleBefore(samples: { Sample }, window: number): Sample?
	local newest = samples[#samples]
	if not newest then
		return nil
	end
	for i = #samples - 1, 1, -1 do
		if newest.Time - samples[i].Time >= window then
			return samples[i]
		end
	end
	return samples[1]
end

-- Velocity measured by the server over the last moment (zero if unknown).
function Motion.Velocity(player: Player): Vector3
	local t = tracks[player]
	local samples = t and t.Samples
	if not samples or #samples < 2 then
		return Vector3.zero
	end
	local newest = samples[#samples]
	local before = sampleBefore(samples, SPEED_WINDOW) :: Sample
	local dt = newest.Time - before.Time
	if dt <= 1e-3 then
		return Vector3.zero
	end
	return (newest.Position - before.Position) / dt
end

-- Speed for a clean cut: sideways and climbing count fully, just dropping
-- only a little (falling off a roof isn't a clean cut).
function Motion.CutSpeed(player: Player): number
	local v = Motion.Velocity(player)
	local flat = Vector3.new(v.X, 0, v.Z).Magnitude
	local vertical = if v.Y > 0 then v.Y else -v.Y * Config.Blades.FallSpeedWeight
	return math.sqrt(flat * flat + vertical * vertical)
end

-- False for a couple of seconds after a hunter moved impossibly fast.
function Motion.Trusted(player: Player): boolean
	local t = tracks[player]
	return not t or os.clock() >= t.SuspectUntil
end

local function step()
	local now = os.clock()
	local limit = Config.Grapple.MaxSpeed * Config.AntiCheat.SpeedTolerance
	for _, player in Players:GetPlayers() do
		local t = track(player)
		local root = rootOf(player)
		if root ~= t.Root then
			-- A new character (or none): start afresh.
			t.Root = root
			table.clear(t.Samples)
		end
		if not root then
			continue
		end
		if root.Anchored then
			-- In a giant's hand: the server is moving it.
			table.clear(t.Samples)
			continue
		end
		local position = root.Position
		local samples = t.Samples
		-- Judge each move against where the hunter last was *seen to move*:
		-- positions arrive from the client in bursts, and a lag spike looks
		-- like standing still and then a jump.
		local last = t.LastMove
		if not last or #samples == 0 then
			t.LastMove = { Time = now, Position = position }
		elseif (position - last.Position).Magnitude > 0.05 then
			local allowed = limit * (now - last.Time) + Config.AntiCheat.TeleportSlack
			if (position - last.Position).Magnitude > allowed then
				t.SuspectUntil = now + Config.AntiCheat.SuspectTime
				table.clear(samples) -- no speed across the jump
			end
			t.LastMove = { Time = now, Position = position }
		end
		table.insert(samples, { Time = now, Position = position })
		while #samples > 2 and now - samples[1].Time > HISTORY do
			table.remove(samples, 1)
		end
	end
end

function Motion.Init()
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
end

return Motion
