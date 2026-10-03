--!strict
-- Telling players what's happening: the kill feed, big centre-screen
-- announcements, and camera shakes (strength falls off with distance on
-- each client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Broadcast = {}

export type Tone = "Info" | "Good" | "Danger" | "Gold"

local function remote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

-- A line in the kill feed, for everyone (or just `player`).
function Broadcast.Feed(text: string, tone: Tone?, player: Player?)
	local event = remote(Config.Remotes.Feed)
	if player then
		event:FireClient(player, text, tone or "Info")
	else
		event:FireAllClients(text, tone or "Info")
	end
end

-- A big title across the screen.
function Broadcast.Announce(title: string, subtitle: string?, tone: Tone?, player: Player?)
	local event = remote(Config.Remotes.Announce)
	if player then
		event:FireClient(player, title, subtitle or "", tone or "Info")
	else
		event:FireAllClients(title, subtitle or "", tone or "Info")
	end
end

function Broadcast.Shake(origin: Vector3, strength: number)
	remote(Config.Remotes.Shake):FireAllClients(origin, strength)
end

return Broadcast
