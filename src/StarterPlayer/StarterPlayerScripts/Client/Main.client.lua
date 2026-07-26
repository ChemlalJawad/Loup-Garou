--!strict
-- Client boot script. Requires + Inits every controller in dependency order.
-- The HUD shell goes first so other controllers have somewhere to mount their
-- nav buttons and panels.
--
-- Owned by the integration pass (docs/ARCHITECTURE.md) — individual systems
-- should not edit this file; they expose an `Init()` on their own module and
-- get wired in here once.

local StarterPlayer = game:GetService("StarterPlayer")
local Client = StarterPlayer.StarterPlayerScripts.Client
local Controllers = Client.Controllers
local UI = Client:FindFirstChild("UI")

if UI then
	local Shell = UI:FindFirstChild("Shell")
	if Shell then
		require(Shell).Init()
	end
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
