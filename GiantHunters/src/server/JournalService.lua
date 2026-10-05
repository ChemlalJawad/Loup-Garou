--!strict
-- Lost Journals: the pages of the district's story (Config.Journals.Pages),
-- hidden in high, hard-to-reach spots.
--
--   * Placed once, when the server starts: round the named places
--     (Config.Tags.POI), supply crates and wall cannons, a ray is cast down
--     at spots picked from a fixed seed, looking for a flat top high up (a
--     rooftop, a tree platform, a landmark's top). No such spot nearby:
--     lower ones, then the anchor's own top. Never two pages close together
--     nor right next to a supply crate (both use key R).
--   * Each page is a small glowing book (a Model in Workspace.LostJournals
--     with the attribute JournalId). Walk into it or use its prompt (R /
--     d-pad down / tap) to pick it up. Everyone sees the books; each client
--     hides the ones it has already found (MapScreen).
--   * Picked-up pages are saved in the profile's "Journals" ({ [Id] = true })
--     and pay XP and Marks; all of them pay a bonus. The pages are read in
--     the map screen's JOURNAL tab.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Geo = require(ReplicatedStorage.Shared.Geo)
local DataService = require(script.Parent.DataService)
local Motion = require(script.Parent.Motion)
local LevelService = require(script.Parent.LevelService)
local ProgressService = require(script.Parent.ProgressService)
local DiscoveryService = require(script.Parent.DiscoveryService)
local Broadcast = require(script.Parent.Broadcast)

local JournalService = {}

type Book = { Page: Config.JournalPage, Model: Model, Position: Vector3 }

local J = Config.Journals

local books: { Book } = {}
local folder: Folder

local function ready(player: Player): DataService.Profile?
	if player:GetAttribute("DataLoaded") ~= true then
		return nil
	end
	return DataService.Get(player)
end

local function pageIndex(id: string): number
	for i, page in J.Pages do
		if page.Id == id then
			return i
		end
	end
	return 0
end

-- === Picking a page up =======================================================

local function collect(player: Player, book: Book)
	local profile = ready(player)
	local id = book.Page.Id
	if not profile or profile.Journals[id] then
		return
	end
	profile.Journals[id] = true
	DataService.Touch(player)
	LevelService.Add(player, J.XP, "Journal")
	ProgressService.GrantMarks(player, J.Marks)
	local found = 0
	for _, page in J.Pages do
		if profile.Journals[page.Id] then
			found += 1
		end
	end
	Broadcast.Announce("LOST JOURNAL FOUND", `"{book.Page.Title}"  -  page {pageIndex(id)} ({found}/{#J.Pages} found, read it on the map: M)`, "Gold", player)
	if found >= #J.Pages then
		LevelService.Add(player, J.AllXP, "Journals")
		ProgressService.GrantMarks(player, J.AllMarks)
		Broadcast.Announce("THE WHOLE STORY!", `Every Lost Journal page found: +{J.AllMarks} Marks`, "Gold", player)
		Broadcast.Feed(`{player.DisplayName} found every Lost Journal page!`, "Gold")
	end
	DiscoveryService.Send(player)
end

-- === Placing the pages =======================================================

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function buildBook(page: Config.JournalPage, position: Vector3, rng: Random): Book
	local model = Instance.new("Model")
	model.Name = `LostJournal_{page.Id}`
	model:SetAttribute("JournalId", page.Id)
	local base = CFrame.new(position + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local cover = part(model, "Cover", Vector3.new(1.9, 0.5, 2.5), base, Color3.fromRGB(110, 62, 40), Enum.Material.Fabric)
	cover.CanQuery = true -- (the prompt's part)
	part(model, "Pages", Vector3.new(1.7, 0.36, 2.3), base * CFrame.new(0.06, 0.08, 0), Color3.fromRGB(255, 236, 180), Enum.Material.Neon)
	part(model, "Clasp", Vector3.new(0.3, 0.56, 0.5), base * CFrame.new(-0.9, 0, 0), Color3.fromRGB(214, 186, 120), Enum.Material.Metal)
	model.PrimaryPart = cover

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 140)
	light.Range = 12
	light.Brightness = 1.4
	light.Parent = cover
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(1.2, 2)
	sparkle.Speed = NumberRange.new(1, 2.5)
	sparkle.SpreadAngle = Vector2.new(25, 25)
	sparkle.EmissionDirection = Enum.NormalId.Top
	sparkle.Rate = 4
	sparkle.Parent = cover
	-- A little gold star over it, seen from a way off.
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(28, 28)
	tag.StudsOffset = Vector3.new(0, 3, 0)
	tag.MaxDistance = 160
	tag.LightInfluence = 0
	tag.Parent = cover
	local star = Instance.new("TextLabel")
	star.Size = UDim2.fromScale(1, 1)
	star.BackgroundTransparency = 1
	star.Text = "✦"
	star.TextScaled = true
	star.TextColor3 = Color3.fromRGB(255, 220, 120)
	star.TextStrokeTransparency = 0.4
	star.Font = Enum.Font.GothamBlack
	star.Parent = tag

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = "Lost Journal"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = J.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Config.Prompts.Key
	prompt.GamepadKeyCode = Config.Prompts.Gamepad
	prompt.Parent = cover

	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = folder
	local book: Book = { Page = page, Model = model, Position = cover.Position }
	prompt.Triggered:Connect(function(player: Player)
		collect(player, book)
	end)
	return book
end

local function inGiant(instance: Instance): boolean
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		if CollectionService:HasTag(model, Config.Tags.Giant) then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- The anchors, in a fixed order (by position), so the same map always gets
-- the same spots.
local function anchors(): { Vector3 }
	local list: { Vector3 } = {}
	local seen: { [string]: boolean } = {}
	for _, tag in { Config.Tags.POI, Config.Tags.Supply, Config.Tags.Cannon } do
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("BasePart") then
				local p = instance.Position
				local key = `{math.round(p.X)},{math.round(p.Z)}`
				if not seen[key] and Geo.RadiusOf(p) < Config.World.LandRadius - 60 then
					seen[key] = true
					table.insert(list, p + Vector3.new(0, instance.Size.Y / 2, 0))
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if math.round(a.X) ~= math.round(b.X) then
			return a.X < b.X
		end
		return a.Z < b.Z
	end)
	if #list == 0 then
		table.insert(list, Vector3.new(0, 4, 0)) -- (an empty map: the plaza)
	end
	return list
end

local function place()
	local rng = Random.new(J.Seed)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { folder }
	for _, boundary in CollectionService:GetTagged(Config.Tags.MapBoundary) do
		table.insert(skip, boundary)
	end
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true

	local crates: { Vector3 } = {}
	for _, crate in CollectionService:GetTagged(Config.Tags.Supply) do
		if crate:IsA("BasePart") then
			table.insert(crates, crate.Position)
		end
	end
	local taken: { Vector3 } = {}
	local function clear(p: Vector3): boolean
		for _, q in taken do
			if (q - p).Magnitude < J.Spacing then
				return false
			end
		end
		for _, c in crates do
			if (c - p).Magnitude < J.PromptDistance + 6 then
				return false
			end
		end
		return Geo.RadiusOf(p) < Config.World.LandRadius - 40 and not Geo.InRiver(p.X, p.Z, 4)
	end
	-- A flat top near `anchor`, at least `minY` high (parts only, or terrain too).
	local function spotNear(anchor: Vector3, minY: number, terrain: boolean): Vector3?
		for _ = 1, 10 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(J.SearchRadius[1], J.SearchRadius[2])
			local x, z = anchor.X + math.sin(angle) * distance, anchor.Z + math.cos(angle) * distance
			local hit = Workspace:Raycast(Vector3.new(x, anchor.Y + 300, z), Vector3.new(0, -700, 0), params)
			if hit and hit.Normal.Y > 0.8 and hit.Position.Y >= minY and hit.Material ~= Enum.Material.Water then
				local isTerrain = hit.Instance:IsA("Terrain")
				if (terrain or not isTerrain) and not inGiant(hit.Instance) and clear(hit.Position) then
					return hit.Position
				end
			end
		end
		return nil
	end

	local list = anchors()
	for _, page in J.Pages do
		local spot: Vector3? = nil
		for pass = 1, 3 do
			for _ = 1, 4 do
				local anchor = list[rng:NextInteger(1, #list)]
				spot = if pass == 1 then spotNear(anchor, J.MinHeight, false) elseif pass == 2 then spotNear(anchor, 6, false) else spotNear(anchor, -20, true)
				if spot then
					break
				end
			end
			if spot then
				break
			end
		end
		if not spot then
			-- Last resort: on top of an anchor.
			spot = list[rng:NextInteger(1, #list)] + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		end
		local p = spot :: Vector3
		table.insert(taken, p)
		table.insert(books, buildBook(page, p, rng))
	end
end

-- How many pages are out there (StudioCheck).
function JournalService.Placed(): number
	return #books
end

function JournalService.Init()
	folder = Instance.new("Folder")
	folder.Name = "LostJournals"
	folder.Parent = Workspace
	place()

	-- Walking into a page picks it up (the prompt does too).
	task.spawn(function()
		local reach = J.PickupDistance
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				local profile = ready(player)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if profile and root and root:IsA("BasePart") and Motion.Trusted(player) then
					local p = root.Position
					for _, book in books do
						if not profile.Journals[book.Page.Id] and (book.Position - p).Magnitude <= reach then
							collect(player, book)
						end
					end
				end
			end
		end
	end)
end

return JournalService
