--!strict
-- Client boot.

local Grapple = require(script.Parent.GrappleController)
local Hud = require(script.Parent.Hud)
local GiantAnimator = require(script.Parent.GiantAnimator)

Grapple.Init()
GiantAnimator.Init()
task.spawn(Hud.Init, Grapple)
