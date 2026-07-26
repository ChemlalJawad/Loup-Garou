--!strict
-- Server boot script. Requires + Inits every service in dependency order.
-- DataService must go first: every other service reads/writes through it.
--
-- Owned by the integration pass (docs/ARCHITECTURE.md) — individual systems
-- should not edit this file; they expose an `Init()` on their own module and
-- get wired in here once.

local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

local DataService = require(Services.DataService)
DataService.Init()

local World = ServerScriptService.Server:FindFirstChild("World")
if World then
	local MapBuilder = World:FindFirstChild("MapBuilder")
	if MapBuilder then
		require(MapBuilder).Init()
	end
end

local EggService = Services:FindFirstChild("EggService")
if EggService then
	require(EggService).Init()
end

local ShopService = Services:FindFirstChild("ShopService")
if ShopService then
	require(ShopService).Init()
end

local TeamService = Services:FindFirstChild("TeamService")
if TeamService then
	require(TeamService).Init()
end

local CTFService = Services:FindFirstChild("CTFService")
if CTFService then
	require(CTFService).Init()
end

print(`[{game.Name ~= "" and game.Name or "BrainrotHatchWars"}] Server boot complete.`)
