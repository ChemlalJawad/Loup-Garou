--!strict
-- New-player guide: three steps from spawn to "I own a Brainrot and know
-- where to get more", with a glowing trail on the ground showing the way.
-- The genre's top games get a new player to their first reward inside ~30
-- seconds; this is that path for this map.
--
-- Server-authoritative (TutorialService checks each step's condition and
-- saves progress); the client only draws the card and the trail for the
-- step the server says it's on.

local WorldLayout = require(script.Parent.Parent.WorldLayout)

export type Step = {
	Id: string,
	Title: string,
	Hint: string,
	-- Where the trail points (ground level). Kept in sync with the world via
	-- WorldLayout, never hardcoded twice.
	Target: Vector3,
	-- Zone the player must enter to finish the step (nil = finished by an
	-- event instead, see TutorialService).
	Zone: string?,
}

local TutorialConfig = {}

-- The Basic Egg podium in the Hatchery (see HatcheryZone.buildEggPodium).
local BASIC_EGG_PODIUM = Vector3.new(-32, WorldLayout.GroundY, -188)

TutorialConfig.Steps = {
	{
		Id = "WalkToHatchery",
		Title = "Walk to the Hatchery",
		Hint = "Follow the glowing trail south!",
		Target = Vector3.new(0, WorldLayout.GroundY, WorldLayout.Get("Hatchery").Center.Z + 50),
		Zone = "Hatchery",
	},
	{
		Id = "HatchEgg",
		Title = "Hatch your first egg",
		Hint = "Tap the Basic Egg (or the egg button) - it's only 100 Coins!",
		Target = BASIC_EGG_PODIUM,
		Zone = nil,
	},
	{
		Id = "VisitParade",
		Title = "Visit the Brainrot Parade",
		Hint = "Your Brainrot follows you now! Buy more on the red carpet.",
		Target = WorldLayout.Get("Parade").Center,
		Zone = "Parade",
	},
} :: { Step }

TutorialConfig.Reward = { Coins = 250, XP = 100 }

-- Progress value meaning "finished or skipped".
TutorialConfig.DONE = 0

return TutorialConfig
