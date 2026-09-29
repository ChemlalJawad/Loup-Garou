--!strict
-- Brainrot mutations: rare variants of a species that earn more idle income,
-- sell for more, and look visibly different (gold, diamond, rainbow, galaxy).
--
-- Modeled on what players already know from the genre's biggest games
-- (Gold x1.25 at ~10%, Diamond x1.5 at ~5%, Rainbow x10 at ~1% on the red
-- carpet), plus one night-only variant that gives the day/night cycle a
-- gameplay reason to exist. Mutations come from the Brainrot Parade only -
-- eggs stay the "which species?" gacha, the Parade is "which variant?", so
-- each activity has its own reason to be played.
--
-- Shared module: the server rolls and persists mutations; both sides apply
-- visuals (server for followers, client for Parade walkers).

local CollectionService = game:GetService("CollectionService")

local Mutations = {}

export type MutationDef = {
	Id: string,
	DisplayName: string,
	IncomeMultiplier: number, -- idle income + sell value
	PriceMultiplier: number, -- Parade purchase price
	Color: Color3,
	NightOnly: boolean,
}

local defs: { [string]: MutationDef } = {
	Gold = {
		Id = "Gold",
		DisplayName = "Gold",
		IncomeMultiplier = 1.25,
		PriceMultiplier = 1.5,
		Color = Color3.fromRGB(255, 200, 60),
		NightOnly = false,
	},
	Diamond = {
		Id = "Diamond",
		DisplayName = "Diamond",
		IncomeMultiplier = 1.5,
		PriceMultiplier = 2,
		Color = Color3.fromRGB(140, 230, 255),
		NightOnly = false,
	},
	Galaxy = {
		Id = "Galaxy",
		DisplayName = "Galaxy",
		IncomeMultiplier = 4,
		PriceMultiplier = 4,
		Color = Color3.fromRGB(130, 90, 255),
		NightOnly = true,
	},
	Rainbow = {
		Id = "Rainbow",
		DisplayName = "Rainbow",
		IncomeMultiplier = 10,
		PriceMultiplier = 8,
		Color = Color3.fromRGB(255, 120, 220),
		NightOnly = false,
	},
}
Mutations.Defs = defs

-- Rarest first: a single uniform roll walks this list accumulating chances,
-- so each mutation's configured chance is exactly its probability.
Mutations.RollOrder = { "Rainbow", "Galaxy", "Diamond", "Gold" }

local SPARKLE_TAG = "DecorEmitter" -- mirrors LightingConfig.DECOR_EMITTER_TAG

function Mutations.Get(mutationId: string?): MutationDef?
	if not mutationId then
		return nil
	end
	return defs[mutationId]
end

function Mutations.IncomeMultiplier(mutationId: string?): number
	local def = Mutations.Get(mutationId)
	return if def then def.IncomeMultiplier else 1
end

function Mutations.PriceMultiplier(mutationId: string?): number
	local def = Mutations.Get(mutationId)
	return if def then def.PriceMultiplier else 1
end

-- "Gold Spaghettoro", or just the base name when not mutated.
function Mutations.DecorateName(baseName: string, mutationId: string?): string
	local def = Mutations.Get(mutationId)
	return if def then `{def.DisplayName} {baseName}` else baseName
end

-- `chances` maps mutation id -> probability (0..1). Returns nil for "no
-- mutation". Unknown ids in `chances` are ignored.
function Mutations.Roll(chances: { [string]: number }, rng: Random): string?
	local roll = rng:NextNumber()
	local accumulated = 0
	for _, mutationId in Mutations.RollOrder do
		local chance = chances[mutationId]
		if chance and chance > 0 and defs[mutationId] then
			accumulated += chance
			if roll < accumulated then
				return mutationId
			end
		end
	end
	return nil
end

-- Visuals -----------------------------------------------------------------

local function visibleParts(model: Model): { BasePart }
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			table.insert(parts, descendant)
		end
	end
	-- Stable order so a rainbow's hue bands land on the same parts every
	-- time the same species is built.
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	return parts
end

local function addSparkles(model: Model, color: Color3, rate: number)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MutationSparkles"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Decorative: disabled on low graphics quality by LightingController.
	emitter:SetAttribute("BaseRate", rate)
	CollectionService:AddTag(emitter, SPARKLE_TAG)
	emitter.Parent = primary
end

-- Recolors an already-built Brainrot model in place. Safe to call with nil
-- (no-op). Keeps each part's own shading by blending toward the mutation
-- color rather than flat-filling, so the species stays recognisable - a Gold
-- Spaghettoro must still read as Spaghettoro.
function Mutations.ApplyVisual(model: Model, mutationId: string?)
	local def = Mutations.Get(mutationId)
	if not def then
		return
	end
	model:SetAttribute("Mutation", def.Id)

	local parts = visibleParts(model)
	for index, part in parts do
		local isNeon = part.Material == Enum.Material.Neon
		if def.Id == "Gold" then
			part.Color = part.Color:Lerp(def.Color, 0.7)
			if not isNeon then
				part.Material = Enum.Material.Metal
				part.Reflectance = 0.12
			end
		elseif def.Id == "Diamond" then
			part.Color = part.Color:Lerp(def.Color, 0.65)
			if not isNeon then
				part.Material = Enum.Material.Glass
				part.Transparency = math.max(part.Transparency, 0.12)
				part.Reflectance = 0.2
			end
		elseif def.Id == "Rainbow" then
			-- Static hue bands across the body: reads instantly as "rainbow"
			-- without any per-frame color cycling cost.
			part.Color = Color3.fromHSV(((index - 1) * 0.14) % 1, 0.7, 1)
		elseif def.Id == "Galaxy" then
			part.Color = part.Color:Lerp(Color3.fromRGB(45, 25, 95), 0.75)
			if isNeon then
				part.Color = def.Color
			end
		end
	end

	if def.Id == "Diamond" then
		addSparkles(model, def.Color, 4)
	elseif def.Id == "Rainbow" then
		addSparkles(model, def.Color, 8)
	elseif def.Id == "Galaxy" then
		addSparkles(model, Color3.fromRGB(220, 210, 255), 7)
	end
end

return Mutations
