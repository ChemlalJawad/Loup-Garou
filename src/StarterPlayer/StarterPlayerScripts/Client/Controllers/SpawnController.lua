--!strict
-- Arrival juice: every time your character spawns, a burst of sparkles and a
-- shockwave ring at your feet, so appearing in the world feels like an
-- entrance instead of a pop-in. The very first spawn of the session also
-- gets a welcome toast. Client-only, zero network traffic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local FX = require(ReplicatedStorage.Shared.Effects.FX)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Constants = require(ReplicatedStorage.Shared.Constants)

local Client = StarterPlayer.StarterPlayerScripts.Client
local Shell = require(Client.UI.Shell)

local SpawnController = {}

local localPlayer = Players.LocalPlayer
local welcomed = false
local CONFETTI = {
	Color3.fromRGB(255, 120, 150),
	Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(130, 220, 150),
	Color3.fromRGB(120, 190, 255),
	Color3.fromRGB(200, 150, 255),
}

local function onCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end
	-- One frame for the character to settle on the pad.
	task.wait(0.1)
	local feet = root.Position - Vector3.new(0, 2.5, 0)
	FX.Burst(feet + Vector3.new(0, 1, 0), Color3.fromRGB(255, 230, 140), 24)
	FX.Shockwave(feet + Vector3.new(0, 0.2, 0), Theme.Color.AccentPrimary)
	if not welcomed then
		welcomed = true
		-- First arrival of the session: a confetti pop in party colours.
		for i, color in CONFETTI do
			task.delay(i * 0.08, function()
				FX.Burst(feet + Vector3.new(0, 4 + i * 0.4, 0), color, 16)
			end)
		end
		Shell.Notify(`Welcome to {Constants.GAME_NAME}!`, "Success")
	end
end

function SpawnController.Init()
	-- Init must not yield: character handling runs in its own thread.
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(function(character)
		task.spawn(onCharacter, character)
	end)
end

return SpawnController
