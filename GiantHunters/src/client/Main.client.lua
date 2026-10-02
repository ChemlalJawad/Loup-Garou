--!strict
-- Client boot.

local Effects = require(script.Parent.Effects)
local Grapple = require(script.Parent.GrappleController)
local Hud = require(script.Parent.Hud)
local GiantAnimator = require(script.Parent.GiantAnimator)

task.spawn(Effects.Init)
Grapple.Init()
GiantAnimator.Init()
task.spawn(Hud.Init, Grapple)
