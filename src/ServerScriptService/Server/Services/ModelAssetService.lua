--!strict
-- Loads uploaded Brainrot art (Shared/Assets/ModelIds.lua) into
-- ReplicatedStorage.AssetOverrides.Brainrots at server start, so nobody has
-- to import models into Studio by hand: run tools/models/upload_models.py
-- once, commit the ids, done. BrainrotModels picks the art up everywhere
-- (companions, Parade, wanderers, statues via WatchOverride).
--
-- InsertService:LoadAsset only works for assets owned by the game's owner
-- (or group) - which is exactly what upload_models.py creates. A model you
-- dropped into AssetOverrides by hand always wins over an uploaded one.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelIds = require(ReplicatedStorage.Shared.Assets.ModelIds)

local ModelAssetService = {}

local function assetNumber(id: string): number?
	return tonumber(string.match(id, "(%d+)$"))
end

-- An Image id is usable as-is; a Decal id has to be loaded to find the
-- image it wraps.
local function resolveTexture(texture: string): string?
	if texture == "" then
		return nil
	end
	if string.sub(texture, 1, 6) ~= "decal:" then
		return texture
	end
	local id = assetNumber(texture)
	if not id then
		return nil
	end
	local ok, container = pcall(InsertService.LoadAsset, InsertService, id)
	if not ok then
		warn(`[ModelAssetService] couldn't load decal {id}: {container}`)
		return nil
	end
	local decal = (container :: Instance):FindFirstChildWhichIsA("Decal", true)
	local image = decal and decal.Texture
	container:Destroy()
	return image
end

local function loadOne(folder: Folder, brainrotId: string, entry: ModelIds.ModelEntry)
	local id = assetNumber(entry.Model)
	if not id or folder:FindFirstChild(brainrotId) then
		return
	end
	local ok, container = pcall(InsertService.LoadAsset, InsertService, id)
	if not ok then
		warn(`[ModelAssetService] couldn't load model {id} for {brainrotId}: {container}`)
		return
	end
	local root = container :: Model
	-- LoadAsset wraps the asset in a Model; unwrap a single inner Model.
	local children = root:GetChildren()
	local model: Model = if #children == 1 and children[1]:IsA("Model") then children[1] :: Model else root

	local texture = resolveTexture(entry.Texture)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif texture and descendant:IsA("MeshPart") and descendant.TextureID == "" then
			descendant.TextureID = texture
		end
	end
	model.Name = brainrotId
	model.Parent = folder
	if model ~= root then
		root:Destroy()
	end
	print(`[ModelAssetService] loaded art for {brainrotId}`)
end

function ModelAssetService.Init()
	local overrides = ReplicatedStorage:FindFirstChild("AssetOverrides")
	local folder = overrides and overrides:FindFirstChild("Brainrots")
	if not folder or not folder:IsA("Folder") then
		return
	end
	-- LoadAsset yields on the network: never hold up the other services.
	task.spawn(function()
		for brainrotId, entry in ModelIds.Brainrots do
			loadOne(folder :: Folder, brainrotId, entry)
		end
	end)
end

return ModelAssetService
