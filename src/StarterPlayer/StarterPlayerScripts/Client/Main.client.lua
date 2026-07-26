--!strict
-- Client boot script. Requires + Inits every controller in dependency order.
-- The HUD shell goes first so other controllers have somewhere to mount their
-- nav buttons and panels.
--
-- Owned by the integration pass (docs/ARCHITECTURE.md) — individual systems
-- should not edit this file; they expose an `Init()` on their own module and
-- get wired in here once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Client = StarterPlayer.StarterPlayerScripts.Client
local Controllers = Client.Controllers
local UI = Client:FindFirstChild("UI")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local ShellModule = nil
if UI then
	local Shell = UI:FindFirstChild("Shell")
	if Shell then
		ShellModule = require(Shell)
		ShellModule.Init()
	end
end

-- Cross-cutting toast pipe: any server system can `Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireClient(player, message, kind)`
-- without needing its own client-side listener wiring.
if ShellModule then
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify).OnClientEvent:Connect(function(message: string, kind: string?)
		ShellModule.Notify(message, kind)
	end)
end

local function initController(name: string)
	local controllerModule = Controllers:FindFirstChild(name)
	if controllerModule then
		require(controllerModule).Init()
	end
end

initController("EggController")
initController("ShopController")
initController("CTFController")

print("[BrainrotHatchWars] Client boot complete.")
