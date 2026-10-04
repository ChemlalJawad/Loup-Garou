--!strict
-- Client boot.

local Effects = require(script.Parent.Effects)
local Grapple = require(script.Parent.GrappleController)
local Hud = require(script.Parent.Hud)
local GiantAnimator = require(script.Parent.GiantAnimator)
local SkyController = require(script.Parent.SkyController)
local ShifterController = require(script.Parent.ShifterController)
local UpgradeShop = require(script.Parent.UpgradeShop)

task.spawn(Effects.Init)
Grapple.Init()
GiantAnimator.Init()
task.spawn(Hud.Init, Grapple)
task.spawn(SkyController.Init)
task.spawn(ShifterController.Init)
task.spawn(UpgradeShop.Init)

-- Feel & settings: the settings panel (gear, top right) and the client-only
-- juice (hit-stop, flashes, floating score, speed lines, grab tells...).
local Settings = require(script.Parent.Settings)
local Juice = require(script.Parent.Juice)
task.spawn(Settings.Init)
task.spawn(Juice.Init, Grapple)

-- The living world: weather, townsfolk, birds and the breeze (all client-side).
local Weather = require(script.Parent.Weather)
task.spawn(Weather.Init)
task.spawn(require(script.Parent.Townsfolk).Init)
task.spawn(require(script.Parent.Birds).Init)
task.spawn(require(script.Parent.Breeze).Init)

-- The shop technique: its key (V / R2), SKILL button and cooldown ring.
task.spawn(require(script.Parent.TechniqueController).Init, Grapple)

-- Cosmetic items: defeat effects (other hunters' too); gas and cable colours.
task.spawn(require(script.Parent.CosmeticsClient).Init)
