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

-- Feel & settings: the settings panel (gear, top right) and the client-only
-- juice (hit-stop, flashes, floating score, speed lines, grab tells...).
local Settings = require(script.Parent.Settings)
local Juice = require(script.Parent.Juice)
task.spawn(Settings.Init)
task.spawn(Juice.Init, Grapple)
