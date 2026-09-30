--!strict
-- Uploaded model/texture asset ids for the art in assets/models/. Written by
-- tools/models/upload_models.py (or paste ids in by hand). Empty = not
-- uploaded yet: the built-in part model is used, which is always safe.
--
-- Model   = the Model asset created from the .fbx ("rbxassetid://123").
-- Texture = the texture, as an Image id ("rbxassetid://456") or, when only
--           a Decal could be created, "decal:789" (resolved at runtime).

export type ModelEntry = { Model: string, Texture: string }

return {
	Brainrots = {
		CrocobrividoVulcanico = { Model = "", Texture = "" },
		TralaleroAstrale = { Model = "", Texture = "" },
		TungTungTamburo = { Model = "", Texture = "" },
	} :: { [string]: ModelEntry },
}
