--!strict
-- Client boot.

local Effects = require(script.Parent.Effects)
local Grapple = require(script.Parent.GrappleController)
local Hud = require(script.Parent.Hud)
local GiantAnimator = require(script.Parent.GiantAnimator)
local SkyController = require(script.Parent.SkyController)
local ShifterController = require(script.Parent.ShifterController)

task.spawn(Effects.Init)
Grapple.Init()
GiantAnimator.Init()
task.spawn(Hud.Init, Grapple)
task.spawn(SkyController.Init)
task.spawn(ShifterController.Init)

-- The living world: weather, townsfolk, birds and the breeze (all client-side).
local Weather = require(script.Parent.Weather)
task.spawn(Weather.Init)
task.spawn(require(script.Parent.Townsfolk).Init)
task.spawn(require(script.Parent.Birds).Init)
task.spawn(require(script.Parent.Breeze).Init)
