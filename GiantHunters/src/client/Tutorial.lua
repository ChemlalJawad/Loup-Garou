--!strict
-- The first-join tutorial: four short steps, each with a hint card under
-- the wave banner and an arrow that points the way.
--
--   1. Hook a roof (fire a hook at anything).
--   2. Reel in (hold the gas while hooked).
--   3. Slash a training dummy: the Training Grounds are just north of the
--      north wall, where you start. The arrow and a marker lead you to the
--      nearest dummy's target.
--   4. Resupply at a crate (the blue beams).
--
-- The hints follow whatever you're playing with (keyboard, gamepad, touch).
-- It can be skipped at any time. Once finished or skipped, the server saves
-- it (DataService) and it never shows again.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Tutorial = {}

local player = Players.LocalPlayer

type Device = "Keys" | "Pad" | "Touch"

local function device(): Device
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last == Enum.UserInputType.Gamepad1 or last == Enum.UserInputType.Gamepad2 or last == Enum.UserInputType.Gamepad3 or last == Enum.UserInputType.Gamepad4 then
		return "Pad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keys"
end

-- The control names, per device.
local KEYS = {
	Keys = { Hook = "HOLD Q or E", Reel = "HOLD SPACE", Slash = "CLICK or press F", Prompt = "press R" },
	Pad = { Hook = "HOLD L1 or R1", Reel = "HOLD A", Slash = "press X", Prompt = "press D-pad DOWN" },
	Touch = { Hook = "HOLD the L HOOK or R HOOK button", Reel = "HOLD the GAS button", Slash = "tap SLASH", Prompt = "tap the prompt" },
}

local function nearest(tag: string, from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
			local d = (instance.Position - from).Magnitude
			if d < bestDistance then
				best, bestDistance = instance, d
			end
		end
	end
	return best
end

type Step = {
	Title: string,
	Text: (keys: { [string]: string }) -> string,
	Target: string?, -- a tag to point at (the nearest one)
	Done: () -> boolean,
}

function Tutorial.Init(gui: ScreenGui, grapple: any, scaled: (GuiObject) -> ())
	-- Wait for the saved flag (the server sets it once your data has loaded).
	local waited = 0
	while player:GetAttribute("DataLoaded") == nil and waited < 20 do
		waited += task.wait(0.5)
	end
	if player:GetAttribute("TutorialDone") == true then
		return
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local tutorialRemote = remotes:WaitForChild(Config.Remotes.Tutorial) :: RemoteEvent

	local cutDummy, resupplied = false, false
	local slashResult = remotes:WaitForChild(Config.Remotes.SlashResult) :: RemoteEvent
	local resupplyEvent = remotes:WaitForChild(Config.Remotes.Resupplied) :: RemoteEvent
	local connections: { RBXScriptConnection } = {}
	table.insert(connections, slashResult.OnClientEvent:Connect(function(result)
		if result == "Training" then
			cutDummy = true
		end
	end))

	local steps: { Step } = {
		{
			Title = "HOOK A ROOF",
			Text = function(keys)
				return `Aim at a rooftop or the wall and {keys.Hook} to fire a hook. Keep holding to swing!`
			end,
			Done = function()
				return grapple.IsHooked()
			end,
		},
		{
			Title = "REEL IN",
			Text = function(keys)
				return `While hooked, {keys.Reel} to reel yourself in fast. Let go of the hook to fly!`
			end,
			Done = function()
				return grapple.ReelTime() > 0.5
			end,
		},
		{
			Title = "SLASH A DUMMY",
			Text = function(keys)
				return `The Training Grounds are just north of the wall. Swing over, get behind a dummy and {keys.Slash} on the orange target on its neck.`
			end,
			Target = Config.Tags.DummyNape,
			Done = function()
				return cutDummy
			end,
		},
		{
			Title = "RESUPPLY",
			Text = function(keys)
				return `Fresh gas and blades: stand by a supply crate (the blue beams) and {keys.Prompt}.`
			end,
			Target = Config.Tags.Supply,
			Done = function()
				return resupplied
			end,
		},
	}
	-- (Resupplying only counts once you're on that step.)
	local index = 1
	table.insert(connections, resupplyEvent.OnClientEvent:Connect(function()
		if index == #steps then
			resupplied = true
		end
	end))

	-- The card, under the wave banner and the district bar.
	local card = Instance.new("Frame")
	card.Name = "Tutorial"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 122)
	card.Size = UDim2.fromOffset(560, 104)
	card.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	card.BackgroundTransparency = 0.15
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(140, 230, 255)
	stroke.Thickness = 2
	stroke.Parent = card
	scaled(card)

	local function text(props: { [string]: any }): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.fromRGB(235, 240, 250)
		l.TextStrokeTransparency = 0.6
		for key, value in props do
			(l :: any)[key] = value
		end
		l.Parent = card
		return l
	end
	local title = text({ Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(400, 24), Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = Color3.fromRGB(140, 230, 255), TextXAlignment = Enum.TextXAlignment.Left })
	local body = text({ Position = UDim2.fromOffset(16, 36), Size = UDim2.fromOffset(470, 60), Font = Enum.Font.GothamMedium, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	-- Which way to go: an arrow that turns with the camera (up = ahead).
	local arrow = text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -38, 0, 62), Size = UDim2.fromOffset(40, 40), Text = "▲", TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 215, 110), Visible = false })
	local distance = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(1, -38, 0, 84), Size = UDim2.fromOffset(70, 16), Font = Enum.Font.GothamBold, TextSize = 12, Visible = false })
	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -10, 0, 8)
	skip.Size = UDim2.fromOffset(110, 26)
	skip.BackgroundColor3 = Color3.fromRGB(60, 62, 76)
	skip.Text = "SKIP TUTORIAL"
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 12
	skip.TextColor3 = Color3.fromRGB(235, 240, 250)
	skip.Parent = card
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 8)
	skipCorner.Parent = skip

	-- A marker over the thing to reach, seen through walls.
	local marker = Instance.new("BillboardGui")
	marker.Name = "TutorialMarker"
	marker.AlwaysOnTop = true
	marker.Size = UDim2.fromOffset(60, 60)
	marker.StudsOffset = Vector3.new(0, 6, 0)
	marker.MaxDistance = 100000
	local markerText = Instance.new("TextLabel")
	markerText.BackgroundTransparency = 1
	markerText.Size = UDim2.fromScale(1, 1)
	markerText.Text = "▼"
	markerText.TextScaled = true
	markerText.Font = Enum.Font.GothamBlack
	markerText.TextColor3 = Color3.fromRGB(255, 215, 110)
	markerText.TextStrokeTransparency = 0.3
	markerText.Parent = marker

	local finished = false
	local loop: RBXScriptConnection? = nil
	local function finish(completed: boolean)
		if finished then
			return
		end
		finished = true
		if loop then
			loop:Disconnect()
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		marker:Destroy()
		tutorialRemote:FireServer("Done")
		if completed then
			title.Text = "YOU'RE READY, HUNTER!"
			body.Text = "Now defend the district: the giants come through the south gate. Attack from behind, and go for the neck!"
			arrow.Visible = false
			distance.Visible = false
			skip.Visible = false
			task.delay(6, function()
				card:Destroy()
			end)
		else
			card:Destroy()
		end
	end
	skip.Activated:Connect(function()
		finish(false)
	end)

	local elapsed = 0
	loop = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		local step = steps[index]
		if step.Done() then
			index += 1
			if index > #steps then
				finish(true)
				return
			end
			step = steps[index]
		end
		local keys = KEYS[device()]
		title.Text = `TUTORIAL {index}/{#steps}  -  {step.Title}`
		body.Text = step.Text(keys)

		-- Point the way.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local target = if step.Target and root and root:IsA("BasePart") then nearest(step.Target, root.Position) else nil
		local camera = Workspace.CurrentCamera
		if target and root and root:IsA("BasePart") and camera then
			marker.Adornee = target
			marker.Parent = player:FindFirstChildOfClass("PlayerGui")
			local offset = camera.CFrame:VectorToObjectSpace(target.Position - camera.CFrame.Position)
			arrow.Rotation = math.deg(math.atan2(offset.X, -offset.Z))
			arrow.Visible = true
			distance.Text = `{math.floor((target.Position - root.Position).Magnitude)} studs`
			distance.Visible = true
		else
			marker.Parent = nil
			arrow.Visible = false
			distance.Visible = false
		end
	end)
end

return Tutorial
