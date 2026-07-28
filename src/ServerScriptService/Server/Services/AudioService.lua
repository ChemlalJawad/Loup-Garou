--!strict
-- Thin server-side audio API for every other system to call into. Nobody
-- else creates the `Audio_PlaySfx` remote or touches Sound instances
-- directly — they call AudioService.PlayFor / PlayForAll / PlayAt with a cue
-- id from AudioConfig, and this service handles firing the remote.
--
-- Deliberately dumb: no mixing, no cooldown/dedup logic, no volume ducking.
-- AudioConfig.GetCue already no-ops gracefully for unknown/empty-SoundId cues
-- on the client side, so this service doesn't need to validate cue ids
-- either — it just forwards the request.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

export type PlayOptions = {
	Position: Vector3?, -- if set, client plays this cue positionally (parented to a temp part there)
	PitchOverride: number?,
	VolumeOverride: number?,
}

local AudioService = {}

local playSfxEvent: RemoteEvent

-- Plays `cueId` for a single player. `options.Position`, when present, makes
-- the client play the sound from that world position instead of as a flat
-- 2D UI sound (e.g. a nearby flag capture should be audible with rolloff).
function AudioService.PlayFor(player: Player, cueId: string, options: PlayOptions?)
	if not playSfxEvent then
		return
	end
	playSfxEvent:FireClient(player, cueId, options)
end

-- Plays `cueId` for every currently connected player. Use for global cues
-- (round start/win, server-wide announcements) — for per-player feedback
-- (purchase result, quest complete) prefer PlayFor.
function AudioService.PlayForAll(cueId: string, options: PlayOptions?)
	if not playSfxEvent then
		return
	end
	for _, player in Players:GetPlayers() do
		playSfxEvent:FireClient(player, cueId, options)
	end
end

-- Plays `cueId` positionally, audible to every player, from a world
-- position — e.g. so a flag capture can be heard from where it happened
-- rather than as a flat 2D sound for everyone regardless of distance.
function AudioService.PlayAt(position: Vector3, cueId: string, options: PlayOptions?)
	if not playSfxEvent then
		return
	end
	local merged: PlayOptions = { Position = position }
	if options then
		merged.PitchOverride = options.PitchOverride
		merged.VolumeOverride = options.VolumeOverride
	end
	for _, player in Players:GetPlayers() do
		playSfxEvent:FireClient(player, cueId, merged)
	end
end

function AudioService.Init()
	playSfxEvent = Net.GetEvent(Constants.REMOTE_NAMES.Audio.PlaySfx)
end

return AudioService
