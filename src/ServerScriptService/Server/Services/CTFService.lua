--!strict
-- Server-authoritative Brain-Rot Capture-the-Flag game loop: flags, tagging,
-- the round state machine, and ability resolution. Never trusts a client for
-- flag state, scores, or which ability is equipped - abilities are looked up
-- server-side from DataService + CTFConfig on every CTF_UseAbility request.
--
-- Internal helpers are namespaced under `Impl` (indexed at call time, not
-- captured as upvalues) so the many mutually-referencing functions below
-- (tagging -> stun -> drop flag -> broadcast -> ...) don't run into Lua's
-- "local function defined after first use" scoping trap.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require(ReplicatedStorage.Shared.Net)
local CTFConfig = require(ReplicatedStorage.Shared.CTF.CTFConfig)
local DataService = require(script.Parent.DataService)

export type FlagStateName = "AtBase" | "Carried" | "Dropped"
export type RoundStateName = "Waiting" | "InProgress" | "RoundOver"

type FlagData = {
	TeamId: string,
	Part: BasePart,
	HomeCFrame: CFrame,
	State: FlagStateName,
	Carrier: Player?,
	Weld: WeldConstraint?,
}

local CTFService = {}
local Impl = {}

-- Tuning ----------------------------------------------------------------
local FLAG_STAND_SEARCH_RETRIES = 10
local FLAG_STAND_SEARCH_DELAY = 1
local TAG_CHECK_INTERVAL = 0.2
local TAG_RADIUS = 6
local TAG_PAIR_COOLDOWN = 2
local ROUND_OVER_DELAY = 8
local CAPTURE_COIN_REWARD = 100
local RETURN_COIN_REWARD = 40
local TAG_COIN_REWARD = 30

-- State -------------------------------------------------------------------
local flags: { [string]: FlagData } = {}
local carrierOf: { [Player]: string } = {} -- Player -> TeamId of the flag they're carrying
local teamRefs: { [string]: Team } = {}
local teamIdByName: { [string]: string } = {}
local teamNameById: { [string]: string } = {}

local characterBaseline: { [Player]: { WalkSpeed: number, JumpPower: number, JumpHeight: number } } = {}
local effectToken: { [Player]: number } = {}
local shieldUntil: { [Player]: number } = {}
local abilityCooldowns: { [Player]: number } = {} -- next-usable os.clock()
local tagCooldowns: { [Player]: number } = {} -- last time this player (as carrier) was tagged

local redScore = 0
local blueScore = 0
local roundState: RoundStateName = "Waiting"
local timeRemaining = Constants.CTF_ROUND_LENGTH_SECONDS

for _, def in Constants.TEAMS do
	teamIdByName[def.Name] = def.Id
	teamNameById[def.Id] = def.Name
end

-- Small utils ---------------------------------------------------------------

function Impl.TeamDefById(teamId: string)
	for _, def in Constants.TEAMS do
		if def.Id == teamId then
			return def
		end
	end
	return nil
end

function Impl.FindWorldPart(name: string): BasePart?
	local found = Workspace:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

function Impl.TeamIdOf(player: Player): string?
	local team = player.Team
	if not team then
		return nil
	end
	return teamIdByName[team.Name]
end

function Impl.GetTeamRef(teamId: string): Team?
	if teamRefs[teamId] then
		return teamRefs[teamId]
	end
	local def = Impl.TeamDefById(teamId)
	if not def then
		return nil
	end
	local inst = game:GetService("Teams"):FindFirstChild(def.Name)
	if inst and inst:IsA("Team") then
		teamRefs[teamId] = inst
		return inst
	end
	return nil
end

function Impl.HasPlayersOnBothTeams(): boolean
	local red = Impl.GetTeamRef("Red")
	local blue = Impl.GetTeamRef("Blue")
	if not red or not blue then
		return false
	end
	return #red:GetPlayers() > 0 and #blue:GetPlayers() > 0
end

function Impl.Announce(message: string, kind: string?)
	Net.GetEvent(Constants.REMOTE_NAMES.Shared.Notify):FireAllClients(message, kind)
end

-- Movement effects (speed buffs / slows / stuns) ---------------------------

function Impl.CaptureBaseline(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	characterBaseline[player] = {
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
	}
end

function Impl.IsShielded(player: Player): boolean
	local until_ = shieldUntil[player]
	return until_ ~= nil and os.clock() < until_
end

-- Applies a temporary WalkSpeed multiplier (or a full stun) to `player`,
-- restoring to their captured baseline afterward. Uses a per-player token so
-- an effect that expires early never clobbers a longer effect applied after
-- it (e.g. a short slow expiring mid-way through a longer stun).
function Impl.ApplyMovementEffect(player: Player, opts: { SpeedMultiplier: number?, Stun: boolean?, Duration: number })
	local baseline = characterBaseline[player]
	if not baseline then
		return
	end

	local token = (effectToken[player] or 0) + 1
	effectToken[player] = token

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if opts.Stun then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	else
		humanoid.WalkSpeed = baseline.WalkSpeed * (opts.SpeedMultiplier or 1)
	end

	task.delay(opts.Duration, function()
		if effectToken[player] ~= token then
			return
		end
		local currentCharacter = player.Character
		local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
		if currentHumanoid then
			currentHumanoid.WalkSpeed = baseline.WalkSpeed
			currentHumanoid.JumpPower = baseline.JumpPower
			currentHumanoid.JumpHeight = baseline.JumpHeight
		end
	end)
end

-- Stuns `player`, drops any flag they're carrying, and respects shields.
function Impl.ApplyStun(player: Player, duration: number)
	if Impl.IsShielded(player) then
		return
	end
	Impl.ApplyMovementEffect(player, { Stun = true, Duration = duration })

	local carriedTeamId = carrierOf[player]
	if carriedTeamId then
		local flag = flags[carriedTeamId]
		if flag and flag.Carrier == player then
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			Impl.DropFlag(flag, if hrp then (hrp :: BasePart).CFrame else flag.Part.CFrame)
		end
	end
end

-- Flags ---------------------------------------------------------------------

function Impl.BuildFlagPayload()
	local payload = {}
	for teamId, flag in flags do
		payload[teamId] = {
			State = flag.State,
			CarrierName = if flag.Carrier then flag.Carrier.Name else nil,
		}
	end
	return payload
end

function Impl.BroadcastFlagState()
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.FlagStateUpdated):FireAllClients(Impl.BuildFlagPayload())
end

function Impl.BroadcastScore()
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.ScoreUpdated):FireAllClients(redScore, blueScore)
end

function Impl.BroadcastRoundState()
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.RoundStateUpdated):FireAllClients(roundState, timeRemaining, redScore, blueScore)
end

function Impl.CreateFlagPart(teamId: string, def, homeCFrame: CFrame): FlagData
	local part = Instance.new("Part")
	part.Name = teamId .. "Flag"
	part.Size = Vector3.new(1.2, 5, 1.2)
	part.Color = def.Color
	part.Material = Enum.Material.Neon
	part.CanCollide = false
	part.Anchored = true
	part.CFrame = homeCFrame

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FlagLabel"
	billboard.Size = UDim2.new(0, 140, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = `{def.Name} Flag`
	label.TextColor3 = def.Color
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = billboard

	return {
		TeamId = teamId,
		Part = part,
		HomeCFrame = homeCFrame,
		State = "AtBase",
		Carrier = nil,
		Weld = nil,
	}
end

function Impl.PickupFlag(flag: FlagData, player: Player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	flag.State = "Carried"
	flag.Carrier = player
	carrierOf[player] = flag.TeamId

	flag.Part.Anchored = false
	flag.Part.CFrame = hrp.CFrame * CFrame.new(0, 2.5, -1.5)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = flag.Part
	weld.Part1 = hrp
	weld.Parent = flag.Part
	flag.Weld = weld

	Impl.BroadcastFlagState()
end

function Impl.ReturnFlag(flag: FlagData, player: Player)
	flag.State = "AtBase"
	flag.Part.Anchored = true
	flag.Part.CFrame = flag.HomeCFrame

	DataService.IncrementStat(player, "FlagReturns")
	DataService.AddCoins(player, RETURN_COIN_REWARD)
	Impl.Announce(`{player.Name} returned the {teamNameById[flag.TeamId]} flag!`, "Info")

	Impl.BroadcastFlagState()
end

function Impl.DropFlag(flag: FlagData, atCFrame: CFrame)
	if flag.Weld then
		flag.Weld:Destroy()
		flag.Weld = nil
	end
	if flag.Carrier then
		carrierOf[flag.Carrier] = nil
	end
	flag.Carrier = nil
	flag.State = "Dropped"
	flag.Part.Anchored = true
	flag.Part.CFrame = atCFrame

	Impl.BroadcastFlagState()
end

function Impl.CaptureFlag(flag: FlagData, player: Player, standTeamId: string)
	if flag.Weld then
		flag.Weld:Destroy()
		flag.Weld = nil
	end
	carrierOf[player] = nil
	flag.Carrier = nil
	flag.State = "AtBase"
	flag.Part.Anchored = true
	flag.Part.CFrame = flag.HomeCFrame

	if standTeamId == "Red" then
		redScore += 1
	else
		blueScore += 1
	end

	DataService.IncrementStat(player, "FlagCaptures")
	DataService.AddCoins(player, CAPTURE_COIN_REWARD)
	Impl.Announce(`{teamNameById[standTeamId]} captured the flag!`, "Success")

	Impl.BroadcastScore()
	Impl.BroadcastFlagState()
end

function Impl.ResetFlag(flag: FlagData)
	if flag.Weld then
		flag.Weld:Destroy()
		flag.Weld = nil
	end
	if flag.Carrier then
		carrierOf[flag.Carrier] = nil
	end
	flag.Carrier = nil
	flag.State = "AtBase"
	flag.Part.Anchored = true
	flag.Part.CFrame = flag.HomeCFrame
end

function Impl.ResetAllFlags()
	for _, flag in flags do
		Impl.ResetFlag(flag)
	end
	Impl.BroadcastFlagState()
end

function Impl.OnFlagTouched(teamId: string, hit: BasePart)
	local flag = flags[teamId]
	if not flag then
		return
	end
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local playerTeamId = Impl.TeamIdOf(player)
	if not playerTeamId then
		return
	end

	if flag.State == "AtBase" then
		if playerTeamId ~= teamId then
			Impl.PickupFlag(flag, player)
		end
	elseif flag.State == "Dropped" then
		if playerTeamId == teamId then
			Impl.ReturnFlag(flag, player)
		else
			Impl.PickupFlag(flag, player)
		end
	end
end

function Impl.OnFlagStandTouched(standTeamId: string, hit: BasePart)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	if Impl.TeamIdOf(player) ~= standTeamId then
		return
	end

	local carriedTeamId = carrierOf[player]
	if not carriedTeamId or carriedTeamId == standTeamId then
		return
	end

	local flag = flags[carriedTeamId]
	if flag and flag.State == "Carried" and flag.Carrier == player then
		Impl.CaptureFlag(flag, player, standTeamId)
	end
end

function Impl.SetupFlags()
	local flagsFolder = Instance.new("Folder")
	flagsFolder.Name = "CTFFlags"
	flagsFolder.Parent = Workspace

	for _, def in Constants.TEAMS do
		local standPart: BasePart? = nil
		for _ = 1, FLAG_STAND_SEARCH_RETRIES do
			standPart = Impl.FindWorldPart(def.FlagStandName)
			if standPart then
				break
			end
			task.wait(FLAG_STAND_SEARCH_DELAY)
		end

		local homeCFrame: CFrame
		if standPart then
			homeCFrame = standPart.CFrame + Vector3.new(0, 3, 0)
		else
			warn(`[CTFService] Could not find "{def.FlagStandName}" after {FLAG_STAND_SEARCH_RETRIES} retries - placing {def.Id} flag at a fallback position`)
			homeCFrame = CFrame.new(0, 10, 0)
		end

		local flagData = Impl.CreateFlagPart(def.Id, def, homeCFrame)
		flagData.Part.Parent = flagsFolder
		flags[def.Id] = flagData

		flagData.Part.Touched:Connect(function(hit)
			Impl.OnFlagTouched(def.Id, hit)
		end)

		if standPart then
			standPart.Touched:Connect(function(hit)
				Impl.OnFlagStandTouched(def.Id, hit)
			end)
		end
	end

	Impl.BroadcastFlagState()
end

-- Tagging ---------------------------------------------------------------

function Impl.TryTag(tagger: Player, target: Player)
	local now = os.clock()
	local lastTime = tagCooldowns[target]
	if lastTime and (now - lastTime) < TAG_PAIR_COOLDOWN then
		return
	end
	if Impl.IsShielded(target) then
		return
	end

	tagCooldowns[target] = now
	Impl.ApplyStun(target, Constants.CTF_TAG_STUN_SECONDS)

	DataService.IncrementStat(tagger, "Tags")
	DataService.AddCoins(tagger, TAG_COIN_REWARD)
end

function Impl.CheckTags()
	for teamId, flag in flags do
		if flag.State == "Carried" and flag.Carrier then
			local carrier = flag.Carrier :: Player
			local carrierChar = carrier.Character
			local carrierHrp = carrierChar and carrierChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if carrierHrp then
				for _, enemy in Players:GetPlayers() do
					if enemy ~= carrier then
						local enemyTeamId = Impl.TeamIdOf(enemy)
						if enemyTeamId and enemyTeamId ~= teamId then
							local enemyChar = enemy.Character
							local enemyHrp = enemyChar and enemyChar:FindFirstChild("HumanoidRootPart") :: BasePart?
							if enemyHrp and (enemyHrp.Position - carrierHrp.Position).Magnitude <= TAG_RADIUS then
								Impl.TryTag(enemy, carrier)
							end
						end
					end
				end
			end
		end
	end
end

function Impl.TagCheckLoop()
	while true do
		task.wait(TAG_CHECK_INTERVAL)
		if roundState == "InProgress" then
			local ok, err = pcall(Impl.CheckTags)
			if not ok then
				warn("[CTFService] tag check error:", err)
			end
		end
	end
end

-- Round loop ------------------------------------------------------------

function Impl.RoundLoop()
	while true do
		roundState = "Waiting"
		timeRemaining = Constants.CTF_ROUND_LENGTH_SECONDS
		redScore = 0
		blueScore = 0
		Impl.ResetAllFlags()
		Impl.BroadcastScore()
		Impl.BroadcastRoundState()

		while not Impl.HasPlayersOnBothTeams() do
			task.wait(1)
			Impl.BroadcastRoundState()
		end

		roundState = "InProgress"
		Impl.BroadcastRoundState()
		Impl.Announce("A new Brain-Rot CTF round has begun!", "Info")

		while timeRemaining > 0 and redScore < Constants.CTF_SCORE_TO_WIN and blueScore < Constants.CTF_SCORE_TO_WIN do
			task.wait(1)
			timeRemaining = math.max(0, timeRemaining - 1)
			Impl.BroadcastRoundState()
		end

		roundState = "RoundOver"
		Impl.BroadcastRoundState()

		local winnerMessage: string
		if redScore > blueScore then
			winnerMessage = `{teamNameById.Red} wins {redScore} - {blueScore}!`
		elseif blueScore > redScore then
			winnerMessage = `{teamNameById.Blue} wins {blueScore} - {redScore}!`
		else
			winnerMessage = `Round ended in a draw, {redScore} - {blueScore}.`
		end
		Impl.Announce(winnerMessage, "Info")

		task.wait(ROUND_OVER_DELAY)
	end
end

-- Abilities ---------------------------------------------------------------

function Impl.GetEquippedAbilityId(player: Player): string?
	local profile = DataService.Get(player)
	if not profile or not profile.EquippedBrainrotUid then
		return nil
	end
	for _, owned in profile.OwnedBrainrots do
		if owned.Uid == profile.EquippedBrainrotUid then
			return owned.Id
		end
	end
	return nil
end

-- Flattens a (possibly non-flat) look vector to the XZ plane, falling back to
-- -Z if the look vector is (near) straight up/down.
local function safeFlatDirection(lookVector: Vector3): Vector3
	local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function Impl.ApplySpeedBurst(player: Player, ability: CTFConfig.AbilityDefinition)
	Impl.ApplyMovementEffect(player, { SpeedMultiplier = ability.SpeedMultiplier or 1.3, Duration = ability.Duration or 3 })
end

function Impl.ApplyDash(player: Player, character: Model, ability: CTFConfig.AbilityDefinition)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local direction = safeFlatDirection(hrp.CFrame.LookVector)
	local velocity = direction * (ability.DashSpeed or 50)
	if ability.UpwardBoost and ability.UpwardBoost > 0 then
		velocity += Vector3.new(0, ability.UpwardBoost, 0)
	end

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bodyVelocity.Velocity = velocity
	bodyVelocity.Parent = hrp
	Debris:AddItem(bodyVelocity, ability.DashTime or 0.3)

	if ability.SelfImmuneDuringDash then
		shieldUntil[player] = os.clock() + (ability.ImmuneDuration or ability.DashTime or 0.3)
	end
end

function Impl.ApplyAreaEffect(player: Player, character: Model, ability: CTFConfig.AbilityDefinition)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local casterTeamId = Impl.TeamIdOf(player)
	local radius = ability.Radius or 12

	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherTeamId = Impl.TeamIdOf(other)
			if otherTeamId and otherTeamId ~= casterTeamId then
				local otherChar = other.Character
				local otherHrp = otherChar and otherChar:FindFirstChild("HumanoidRootPart") :: BasePart?
				if otherHrp and (otherHrp.Position - hrp.Position).Magnitude <= radius then
					if ability.Stun then
						Impl.ApplyStun(other, ability.Duration or 2)
					else
						Impl.ApplyMovementEffect(other, { SpeedMultiplier = ability.SlowMultiplier or 0.6, Duration = ability.Duration or 2 })
					end
				end
			end
		end
	end
end

function Impl.SpawnProjectile(player: Player, character: Model, ability: CTFConfig.AbilityDefinition)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local direction = safeFlatDirection(hrp.CFrame.LookVector)
	local speed = ability.ProjectileSpeed or 80
	local range = ability.ProjectileRange or 50

	local projectile = Instance.new("Part")
	projectile.Name = "CTFProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(1.2, 1.2, 1.2)
	projectile.Color = Color3.fromRGB(255, 230, 150)
	projectile.Material = Enum.Material.Neon
	projectile.CanCollide = false
	projectile.Anchored = false
	projectile.CFrame = hrp.CFrame * CFrame.new(0, 0, -3)
	projectile.Parent = Workspace

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bodyVelocity.Velocity = direction * speed
	bodyVelocity.Parent = projectile

	local casterTeamId = Impl.TeamIdOf(player)
	local resolved = false

	local connection: RBXScriptConnection
	connection = projectile.Touched:Connect(function(hit)
		if resolved then
			return
		end
		local hitCharacter = hit.Parent
		local hitPlayer = hitCharacter and Players:GetPlayerFromCharacter(hitCharacter)
		if not hitPlayer or hitPlayer == player then
			return
		end
		local hitTeamId = Impl.TeamIdOf(hitPlayer)
		if not hitTeamId or hitTeamId == casterTeamId then
			return
		end

		resolved = true

		if ability.Knockback then
			local enemyHrp = hitCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
			if enemyHrp then
				local knockback = Instance.new("BodyVelocity")
				knockback.MaxForce = Vector3.new(1e5, 1e5, 1e5)
				knockback.Velocity = direction * (ability.KnockbackForce or 80) + Vector3.new(0, 15, 0)
				knockback.Parent = enemyHrp
				Debris:AddItem(knockback, 0.3)
			end
		end

		if ability.StunSeconds and ability.StunSeconds > 0 then
			Impl.ApplyStun(hitPlayer, ability.StunSeconds)
		end

		connection:Disconnect()
		projectile:Destroy()
	end)

	local lifetime = range / math.max(speed, 1)
	Debris:AddItem(projectile, lifetime + 0.25)
end

function Impl.ApplyTeleport(character: Model, distance: number)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local origin = hrp.Position
	local direction = safeFlatDirection(hrp.CFrame.LookVector)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(origin, direction * distance, raycastParams)
	local finalPosition = origin + direction * distance
	if result then
		finalPosition = result.Position - direction * 2
	end

	hrp.CFrame = CFrame.new(finalPosition, finalPosition + direction)
end

function Impl.ApplyAbilityEffect(player: Player, character: Model, ability: CTFConfig.AbilityDefinition)
	if ability.Archetype == "SpeedBurst" then
		Impl.ApplySpeedBurst(player, ability)
	elseif ability.Archetype == "Dash" then
		Impl.ApplyDash(player, character, ability)
	elseif ability.Archetype == "AreaEffect" then
		Impl.ApplyAreaEffect(player, character, ability)
	elseif ability.Archetype == "ShieldImmunity" then
		shieldUntil[player] = os.clock() + (ability.Duration or 1.5)
	elseif ability.Archetype == "RangedProjectile" then
		Impl.SpawnProjectile(player, character, ability)
	elseif ability.Archetype == "Teleport" then
		Impl.ApplyTeleport(character, ability.Distance or 40)
	end
end

function Impl.FireAbilityFeedback(player: Player, payload: { [string]: any })
	Net.GetEvent(Constants.REMOTE_NAMES.CTF.AbilityFeedback):FireClient(player, payload)
end

function Impl.OnUseAbility(player: Player)
	local teamId = Impl.TeamIdOf(player)
	if not teamId then
		Impl.FireAbilityFeedback(player, { Success = false, Reason = "NotOnTeam" })
		return
	end

	local abilityId = Impl.GetEquippedAbilityId(player)
	if not abilityId then
		Impl.FireAbilityFeedback(player, { Success = false, Reason = "NoBrainrotEquipped" })
		return
	end

	local ability = CTFConfig.GetAbility(abilityId)
	if not ability then
		Impl.FireAbilityFeedback(player, { Success = false, Reason = "NoBrainrotEquipped" })
		return
	end

	local now = os.clock()
	local readyAt = abilityCooldowns[player] or 0
	if now < readyAt then
		Impl.FireAbilityFeedback(player, { Success = false, Reason = "OnCooldown", RemainingSeconds = readyAt - now })
		return
	end

	local character = player.Character
	if not character then
		Impl.FireAbilityFeedback(player, { Success = false, Reason = "NotOnTeam" })
		return
	end

	Impl.ApplyAbilityEffect(player, character, ability)
	abilityCooldowns[player] = now + ability.Cooldown
	Impl.FireAbilityFeedback(player, { Success = true, Cooldown = ability.Cooldown })
end

-- Player lifecycle --------------------------------------------------------

function Impl.OnPlayerRemoving(player: Player)
	local carriedTeamId = carrierOf[player]
	if carriedTeamId then
		local flag = flags[carriedTeamId]
		if flag and flag.Carrier == player then
			Impl.DropFlag(flag, flag.Part.CFrame)
		end
	end

	characterBaseline[player] = nil
	effectToken[player] = nil
	shieldUntil[player] = nil
	abilityCooldowns[player] = nil
	tagCooldowns[player] = nil
end

function Impl.OnPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		Impl.CaptureBaseline(player, character)
	end)
	if player.Character then
		Impl.CaptureBaseline(player, player.Character)
	end
end

-- Public API ----------------------------------------------------------------

function CTFService.Init()
	task.spawn(Impl.SetupFlags)

	Players.PlayerAdded:Connect(Impl.OnPlayerAdded)
	for _, player in Players:GetPlayers() do
		Impl.OnPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(Impl.OnPlayerRemoving)

	Net.GetEvent(Constants.REMOTE_NAMES.CTF.UseAbility).OnServerEvent:Connect(Impl.OnUseAbility)

	task.spawn(Impl.TagCheckLoop)
	task.spawn(Impl.RoundLoop)
end

return CTFService
