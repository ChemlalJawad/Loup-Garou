--!strict
-- Server boot. Services are AUTO-DISCOVERED: every ModuleScript under
-- Services/ that returns a table with an `Init()` function is started, so
-- adding a system never requires editing this file.
--
-- Ordering matters for a few of them (DataService owns persistence that every
-- other service reads; EconomyService owns the reward funnel; the map has to
-- exist before CTFService looks for flag stands), so those are listed
-- explicitly in BOOT_ORDER and everything else follows alphabetically.

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.Server
local Services = Server.Services
local World = Server:FindFirstChild("World")

-- Services named here start first, in this order. Anything not listed starts
-- afterwards in alphabetical order.
local BOOT_ORDER = {
	"DataService",
	"EconomyService",
	"ShopService",
	"StoreService",
}

local started: { [string]: boolean } = {}
local failures = 0

local function startService(moduleScript: Instance)
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
		-- Not every module under Services/ has to be a service (helpers are
		-- fine); silently skip anything without an Init.
		return
	end

	-- One broken service must not stop the rest of the game from booting.
	local initOk, initError = pcall(moduleOrError.Init)
	if not initOk then
		failures += 1
		warn(`[Boot] {moduleScript.Name}.Init() errored: {initError}`)
	end
end

for _, name in BOOT_ORDER do
	local moduleScript = Services:FindFirstChild(name)
	if moduleScript then
		startService(moduleScript)
	end
end

-- The world must exist before gameplay services look for named parts in it
-- (CTF flag stands, team spawns).
if World then
	local mapBuilder = World:FindFirstChild("MapBuilder")
	if mapBuilder and mapBuilder:IsA("ModuleScript") then
		local ok, result = pcall(require, mapBuilder)
		if ok and type(result) == "table" and type(result.Init) == "function" then
			local initOk, initError = pcall(result.Init)
			if not initOk then
				failures += 1
				warn(`[Boot] MapBuilder.Init() errored: {initError}`)
			end
		else
			failures += 1
			warn(`[Boot] MapBuilder could not be loaded: {result}`)
		end
	end
end

local remaining = {}
for _, child in Services:GetChildren() do
	if child:IsA("ModuleScript") and not started[child.Name] then
		table.insert(remaining, child)
	end
end
table.sort(remaining, function(a, b)
	return a.Name < b.Name
end)
for _, moduleScript in remaining do
	startService(moduleScript)
end

local count = 0
for _ in started do
	count += 1
end

if failures > 0 then
	warn(`[BrainrotHatchWars] Server boot finished with {failures} failure(s) across {count} module(s).`)
else
	print(`[BrainrotHatchWars] Server boot complete - {count} module(s) started.`)
end
