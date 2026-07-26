--!strict
-- Thin, dependency-free wrapper around RemoteEvents/RemoteFunctions.
--
-- Any script (server or client) can call Net.GetEvent("Some_Name") and get a
-- working RemoteEvent back: the server lazily creates it on first access, the
-- client waits for it. There is no shared registry file to edit, so systems
-- built independently never collide on the same file.
--
-- Prefer names from Constants.REMOTE_NAMES so every system uses one naming
-- convention: "<Domain>_<Action>".

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()

local Net = {}

local remotesFolder: Folder? = nil

local function getFolder(): Folder
	if remotesFolder then
		return remotesFolder
	end

	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing and existing:IsA("Folder") then
			remotesFolder = existing
		else
			local folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
			remotesFolder = folder
		end
	else
		remotesFolder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end

	return remotesFolder :: Folder
end

function Net.GetEvent(name: string): RemoteEvent
	local folder = getFolder()
	local instance = folder:FindFirstChild(name)

	if not instance then
		if IS_SERVER then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
			instance = event
		else
			instance = folder:WaitForChild(name, 10)
		end
	end

	assert(instance and instance:IsA("RemoteEvent"), `Net.GetEvent: "{name}" is missing or not a RemoteEvent`)
	return instance
end

function Net.GetFunction(name: string): RemoteFunction
	local folder = getFolder()
	local instance = folder:FindFirstChild(name)

	if not instance then
		if IS_SERVER then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = folder
			instance = fn
		else
			instance = folder:WaitForChild(name, 10)
		end
	end

	assert(instance and instance:IsA("RemoteFunction"), `Net.GetFunction: "{name}" is missing or not a RemoteFunction`)
	return instance
end

return Net
