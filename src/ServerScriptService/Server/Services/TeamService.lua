--!strict
-- Team assignment for Brain-Rot CTF. Creates the two Teams instances that
-- match Constants.TEAMS, auto-balances join requests (no team choice from the
-- client), and teleports players to their team's base spawn - both on first
-- join and on every respawn while they're on a team.
--
-- Flag pickup/drop/capture and the round loop live in CTFService.lua; this
-- module only owns *who is on which team* and *where they spawn*.

local Players = game:GetService("Players")
local TeamsService = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)

export type TeamDef = {
	Id: string,
	Name: string,
	Color: Color3,
	BaseSpawnName: string,
	FlagStandName: string,
}

local TeamService = {}

-- TeamId ("Red"/"Blue") -> Team instance.
local teamInstances: { [string]: Team } = {}
-- Team instance Name -> TeamId, for mapping player.Team back to our ids.
local teamIdByName: { [string]: string } = {}

local function teamDefById(teamId: string): TeamDef?
	for _, def in Constants.TEAMS do
		if def.Id == teamId then
			return def :: TeamDef
		end
	end
	return nil
end

-- Recursive descendant search: the world-design agent's map may nest
-- RedBaseSpawn/BlueBaseSpawn parts under any folder structure, so we can't
-- rely on a fixed path. Results are cached by name once found, since this is
-- called on every CTF join AND every respawn while on a team - a per-call
-- Workspace-wide recursive scan would mean every death in an active match
-- re-walks the whole world tree. The cache is invalidated automatically if
-- the cached instance is ever destroyed/reparented (`.Parent == nil`), so a
-- future world rebuild still self-heals instead of teleporting to a stale
-- reference.
local worldPartCache: { [string]: BasePart } = {}

local function findWorldPart(name: string): BasePart?
	local cached = worldPartCache[name]
	if cached and cached.Parent then
		return cached
	end

	local found = Workspace:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		worldPartCache[name] = found
		return found
	end
	worldPartCache[name] = nil
	return nil
end

local function createTeams()
	for _, def in Constants.TEAMS do
		local existing = TeamsService:FindFirstChild(def.Name)
		local team: Team
		if existing and existing:IsA("Team") then
			team = existing
		else
			team = Instance.new("Team")
			team.Name = def.Name
			team.TeamColor = BrickColor.new(def.Color)
			team.AutoAssignable = false
			team.Parent = TeamsService
		end
		teamInstances[def.Id] = team
		teamIdByName[def.Name] = def.Id
	end
end

local function pickTeamId(): string
	local red = teamInstances.Red
	local blue = teamInstances.Blue
	if not red or not blue then
		return "Red"
	end

	local redCount = #red:GetPlayers()
	local blueCount = #blue:GetPlayers()

	if redCount < blueCount then
		return "Red"
	elseif blueCount < redCount then
		return "Blue"
	end
	return if math.random() < 0.5 then "Red" else "Blue"
end

-- Waits briefly for a character/HumanoidRootPart to exist rather than
-- blocking forever, then snaps it to the given base spawn part.
local function teleportToBase(player: Player, teamId: string)
	local def = teamDefById(teamId)
	if not def then
		return
	end

	local spawnPart = findWorldPart(def.BaseSpawnName)
	if not spawnPart then
		warn(`[TeamService] Could not find spawn part "{def.BaseSpawnName}" - is the world built yet?`)
		return
	end

	local character = player.Character
	local elapsed = 0
	while not character and elapsed < 5 do
		task.wait(0.1)
		elapsed += 0.1
		character = player.Character
	end
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		hrp = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	end
	if hrp then
		hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 5, 0)
	end
end

local function onRequestJoinTeam(player: Player)
	local teamId = pickTeamId()
	local team = teamInstances[teamId]
	if not team then
		warn("[TeamService] RequestJoinTeam received before teams were created")
		return
	end

	player.Team = team
	player.Neutral = false

	teleportToBase(player, teamId)

	Net.GetEvent(Constants.REMOTE_NAMES.CTF.TeamAssigned):FireClient(player, teamId)
end

local function onCharacterAdded(player: Player, character: Model)
	if not player.Team then
		return
	end
	local teamId = teamIdByName[player.Team.Name]
	if not teamId then
		return
	end
	-- Let the default Roblox spawn placement happen first, then override.
	task.wait(0.15)
	if character.Parent then
		teleportToBase(player, teamId)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

function TeamService.Init()
	createTeams()

	Net.GetEvent(Constants.REMOTE_NAMES.CTF.RequestJoinTeam).OnServerEvent:Connect(onRequestJoinTeam)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return TeamService
