--!strict
-- Client boot. Controllers are AUTO-DISCOVERED: every ModuleScript under
-- Controllers/ that returns a table with an `Init()` function is started, so
-- adding a system never requires editing this file.
--
-- The HUD shell starts first: every controller mounts its panel into the
-- ScreenGui the shell owns and registers a nav icon with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Client = StarterPlayer.StarterPlayerScripts.Client
local Controllers = Client.Controllers
local UI = Client:FindFirstChild("UI")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

local Shell = nil
if UI then
	local shellModule = UI:FindFirstChild("Shell")
	if shellModule and shellModule:IsA("ModuleScript") then
		Shell = require(shellModule)
		Shell.Init()
	end
end

-- Cross-cutting toast pipe: any server system can fire Shared.Notify without
-- needing its own client-side listener wiring.
if Shell then
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify).OnClientEvent:Connect(function(message: string, kind: string?)
		Shell.Notify(message, kind)
	end)

	-- Economy state drives the persistent HUD (currency, level, multiplier)
	-- for every system at once, so no individual controller has to.
	Net.GetEvent(Constants.REMOTE_NAMES.Economy.StateUpdated).OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		Shell.SetCurrency(Constants.CURRENCY.SOFT, state.Coins or 0)
		Shell.SetCurrency(Constants.CURRENCY.HARD, state.Gems or 0)
		Shell.SetLevel(state.Level or 1, state.XP or 0, state.XPForNext or 0)
		Shell.SetMultiplier(state.CoinMultiplier or 1)
	end)
end

-- Controllers named here start first, in this order; everything else follows
-- alphabetically.
local BOOT_ORDER = { "EconomyController" }

local started: { [string]: boolean } = {}
local failures = 0

local function startController(moduleScript: Instance)
	if not moduleScript:IsA("ModuleScript") or started[moduleScript.Name] then
		return
	end
	started[moduleScript.Name] = true

	local ok, moduleOrError = pcall(require, moduleScript)
	if not ok then
		failures += 1
		warn(`[Boot] failed to require {moduleScript.Name}: {moduleOrError}`)
		return
	end

	if type(moduleOrError) ~= "table" or type(moduleOrError.Init) ~= "function" then
		return
	end

	-- One broken controller must not blank the whole HUD.
	local initOk, initError = pcall(moduleOrError.Init)
	if not initOk then
		failures += 1
		warn(`[Boot] {moduleScript.Name}.Init() errored: {initError}`)
	end
end

for _, name in BOOT_ORDER do
	local moduleScript = Controllers:FindFirstChild(name)
	if moduleScript then
		startController(moduleScript)
	end
end

local remaining = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") and not started[child.Name] then
		table.insert(remaining, child)
	end
end
table.sort(remaining, function(a, b)
	return a.Name < b.Name
end)
for _, moduleScript in remaining do
	startController(moduleScript)
end

local count = 0
for _ in started do
	count += 1
end

if failures > 0 then
	warn(`[BrainrotHatchWars] Client boot finished with {failures} failure(s) across {count} controller(s).`)
else
	print(`[BrainrotHatchWars] Client boot complete - {count} controller(s) started.`)
end
