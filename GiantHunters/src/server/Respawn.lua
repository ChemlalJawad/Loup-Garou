--!strict
-- Putting a hunter (back) on the wall. LoadCharacterAsync can fail (the
-- avatar service hiccups, the player is leaving): it's retried a few times
-- with a pause, and never takes the calling thread down with it.

local Motion = require(script.Parent.Motion)

local Respawn = {}

local loading: { [Player]: boolean } = {}

-- Spawns `player` a fresh character. Returns at once; runs in its own thread.
function Respawn.Load(player: Player)
	if loading[player] then
		return -- already on its way
	end
	loading[player] = true
	task.spawn(function()
		for attempt = 1, 4 do
			if not player.Parent then
				break
			end
			local ok, err = pcall(player.LoadCharacterAsync, player)
			if ok then
				Motion.Reset(player)
				break
			end
			warn(`[Respawn] LoadCharacterAsync failed for {player.Name} (try {attempt}): {err}`)
			task.wait(attempt)
		end
		loading[player] = nil
	end)
end

return Respawn
