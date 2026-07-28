--!strict
-- Client-side audio playback: listens for Audio_PlaySfx, resolves the cue id
-- against AudioConfig, and plays it through a small pooled set of Sound
-- instances rather than creating/destroying one Sound per cue (hundreds of
-- cues can fire over a match; churning that many instances is a real perf
-- problem). Also owns background music crossfade and, best-effort, a generic
-- UIClick hook over the Shell's ScreenGui.
--
-- Settings note: `DataService.Profile.Settings.Music` / `.SFX` already exist
-- server-side, but nothing currently broadcasts them to the client (no
-- remote, no Shell state) and this file may not edit any other system's
-- files to add one. Per the mission spec's guidance for exactly this case,
-- this controller defaults both Music and SFX to ON. `AudioController.SetSfxEnabled`
-- / `AudioController.SetMusicEnabled` are exposed so a future settings UI
-- (or a small addition to whichever system owns Settings) can flip them
-- without touching this file's internals.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local AudioConfig = require(ReplicatedStorage.Shared.Audio.AudioConfig)

local Client = StarterPlayer.StarterPlayerScripts.Client

local AudioController = {}

local sfxEnabled = true
local musicEnabled = true

-- === Pooled 2D (non-positional) sounds ======================================
-- A handful of reusable Sound instances parented to nothing in particular
-- (SoundService-less: parented directly under a throwaway folder in
-- PlayerGui-less client scope is unnecessary — Sound instances play fine
-- parented anywhere client-side reachable) so overlapping cues don't cut each
-- other off, without allocating a new Sound per play.
local POOL_SIZE = 8
local soundPool: { Sound } = {}
local poolCursor = 1

local function getPoolHome(): Instance
	local player = Players.LocalPlayer
	if player then
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			return playerGui
		end
	end
	return Workspace
end

local function ensurePool()
	if #soundPool > 0 then
		return
	end
	local home = getPoolHome()
	for i = 1, POOL_SIZE do
		local sound = Instance.new("Sound")
		sound.Name = `PooledSfx_{i}`
		sound.Parent = home
		table.insert(soundPool, sound)
	end
end

local function nextPooledSound(): Sound
	ensurePool()
	local sound = soundPool[poolCursor]
	poolCursor = (poolCursor % #soundPool) + 1
	return sound
end

-- === Cue resolution ==========================================================

local function resolvePitch(cue: AudioConfig.SoundCue, pitchOverride: number?): number
	if pitchOverride then
		return pitchOverride
	end
	if cue.PitchRange then
		return cue.PitchRange.Min + math.random() * (cue.PitchRange.Max - cue.PitchRange.Min)
	end
	return cue.PlaybackSpeed or 1
end

-- Plays a resolved cue as a flat, non-positional 2D sound via the pool.
-- No-ops silently if the cue is unknown or its SoundId is still a placeholder.
local function playPooled(cueId: string, volumeOverride: number?, pitchOverride: number?)
	local cue = AudioConfig.GetCue(cueId)
	if not cue or cue.SoundId == "" then
		return
	end

	local sound = nextPooledSound()
	sound.SoundId = cue.SoundId
	sound.Volume = volumeOverride or cue.Volume
	sound.PlaybackSpeed = resolvePitch(cue, pitchOverride)
	sound.Playing = false
	sound:Play()
end

-- Plays a resolved cue positionally: a temporary anchored part is created at
-- `position`, the Sound is parented to it, and both are destroyed once the
-- sound finishes (or after a safety timeout, in case Ended never fires).
local function playPositional(position: Vector3, cueId: string, volumeOverride: number?, pitchOverride: number?)
	local cue = AudioConfig.GetCue(cueId)
	if not cue or cue.SoundId == "" then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "AudioPositionalAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = cue.SoundId
	sound.Volume = volumeOverride or cue.Volume
	sound.PlaybackSpeed = resolvePitch(cue, pitchOverride)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 220
	sound.RollOffMinDistance = 8
	sound.Parent = anchor
	sound:Play()

	local cleaned = false
	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		if anchor.Parent then
			anchor:Destroy()
		end
	end

	sound.Ended:Connect(cleanup)
	task.delay(10, cleanup) -- safety net in case Ended never fires (looping/placeholder edge cases)
end

local function onPlaySfx(cueId: string, options: { Position: Vector3?, PitchOverride: number?, VolumeOverride: number? }?)
	if not sfxEnabled then
		return
	end
	if type(cueId) ~= "string" then
		return
	end

	local position = options and options.Position
	local pitchOverride = options and options.PitchOverride
	local volumeOverride = options and options.VolumeOverride

	if position then
		playPositional(position, cueId, volumeOverride, pitchOverride)
	else
		playPooled(cueId, volumeOverride, pitchOverride)
	end
end

-- === Background music crossfade =============================================

local currentMusicTrack: string? = nil
local musicSoundA: Sound? = nil
local musicSoundB: Sound? = nil
local activeIsA = true
local MUSIC_CROSSFADE_SECONDS = 1.2

local function ensureMusicSounds()
	if musicSoundA and musicSoundB then
		return
	end
	local home = getPoolHome()
	musicSoundA = Instance.new("Sound")
	musicSoundA.Name = "MusicTrackA"
	musicSoundA.Looped = true
	musicSoundA.Volume = 0
	musicSoundA.Parent = home

	musicSoundB = Instance.new("Sound")
	musicSoundB.Name = "MusicTrackB"
	musicSoundB.Looped = true
	musicSoundB.Volume = 0
	musicSoundB.Parent = home
end

-- Crossfades to `trackId` (a key in AudioConfig.Music), e.g. "Hub" or
-- "Arena". Safe to call repeatedly with the same id (no-ops if already
-- playing) and safe to call with a placeholder (empty SoundId) track, in
-- which case it just fades out whatever was playing.
function AudioController.PlayMusic(trackId: string)
	if currentMusicTrack == trackId then
		return
	end
	currentMusicTrack = trackId

	ensureMusicSounds()
	local track = AudioConfig.GetMusic(trackId)

	local incoming = if activeIsA then musicSoundB else musicSoundA
	local outgoing = if activeIsA then musicSoundA else musicSoundB
	activeIsA = not activeIsA

	if not incoming or not outgoing then
		return
	end

	if track and track.SoundId ~= "" and musicEnabled then
		incoming.SoundId = track.SoundId
		incoming.Looped = track.Looped
		incoming.Volume = 0
		incoming.Playing = false
		incoming:Play()
		TweenService:Create(incoming, TweenInfo.new(MUSIC_CROSSFADE_SECONDS), { Volume = track.Volume }):Play()
	end

	local fadeOutTween = TweenService:Create(outgoing, TweenInfo.new(MUSIC_CROSSFADE_SECONDS), { Volume = 0 })
	fadeOutTween:Play()
	fadeOutTween.Completed:Connect(function()
		if outgoing.Playing then
			outgoing:Stop()
		end
	end)
end

function AudioController.StopMusic()
	currentMusicTrack = nil
	for _, sound in { musicSoundA, musicSoundB } do
		if sound then
			TweenService:Create(sound, TweenInfo.new(MUSIC_CROSSFADE_SECONDS), { Volume = 0 }):Play()
		end
	end
end

-- === Settings (see file header note on why these default to true) ==========

function AudioController.SetSfxEnabled(enabled: boolean)
	sfxEnabled = enabled
end

function AudioController.SetMusicEnabled(enabled: boolean)
	musicEnabled = enabled
	if not enabled then
		AudioController.StopMusic()
	end
end

-- === Generic UIClick hook (best-effort, non-invasive) =======================
-- Hooks `Activated` on every GuiButton under the Shell's ScreenGui via a
-- descendant scan, so every system's buttons get a click cue for free
-- without this file editing any other system's UI code. If Shell isn't
-- present yet (boot ordering) this silently skips - it is a nice-to-have,
-- not a dependency other systems rely on.
local function hookButtonSounds()
	local ok, Shell = pcall(function()
		local UI = Client:FindFirstChild("UI")
		local shellModule = UI and UI:FindFirstChild("Shell")
		if shellModule and shellModule:IsA("ModuleScript") then
			return require(shellModule)
		end
		return nil
	end)
	if not ok or not Shell or type(Shell.GetScreenGui) ~= "function" then
		return
	end

	local screenGuiOk, screenGui = pcall(Shell.GetScreenGui)
	if not screenGuiOk or not screenGui then
		return
	end

	local function connectButton(button: GuiButton)
		button.Activated:Connect(function()
			playPooled("UIClick")
		end)
	end

	for _, descendant in screenGui:GetDescendants() do
		if descendant:IsA("GuiButton") then
			connectButton(descendant)
		end
	end

	screenGui.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") then
			connectButton(descendant)
		end
	end)
end

function AudioController.Init()
	local playSfxEvent = Net.GetEvent(Constants.REMOTE_NAMES.Audio.PlaySfx)
	playSfxEvent.OnClientEvent:Connect(onPlaySfx)

	-- Best-effort generic UI click sound; Shell boots before controllers per
	-- Main.client.lua, but guard with pcall/task.defer regardless in case
	-- ordering ever changes.
	task.defer(hookButtonSounds)
end

return AudioController
