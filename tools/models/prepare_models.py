import bpy, bmesh, sys, glob, os, math
from mathutils import Vector

W = sys.argv[-1]
OUT = os.path.join(W, "out"); os.makedirs(OUT, exist_ok=True)
TARGET_TRIS = 15000
HEIGHT = 5.0

# Which way each source model faces (checked on preview renders). Everything
# is turned to face Blender +Y, which both exporters map to Roblox's -Z
# (LookVector), the convention BrainrotModels uses.
FRONT_YAW = {"CrocobrividoVulcanico": -math.pi / 2, "TralaleroAstrale": math.pi, "TungTungTamburo": math.pi}

JOBS = {
    "bombardiro-crocodilo": "CrocobrividoVulcanico",
    "tralalero-tralala": "TralaleroAstrale",
    "tung-tung-tung-sahur": "TungTungTamburo",
}

def tri_count(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)

for folder, game_id in JOBS.items():
    fbx = glob.glob(os.path.join(W, folder, "source", "*.fbx"))[0]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fbx)
    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    for o in list(bpy.context.scene.objects):
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    obj.parent = None
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = obj.data

    # One textured material: drop empty material slots.
    used = {p.material_index for p in me.polygons}
    for i in reversed(range(len(me.materials))):
        if i not in used:
            obj.active_material_index = i
            bpy.ops.object.material_slot_remove()
    # One UV layer: keep the render-active one.
    keep = next((u for u in me.uv_layers if u.active_render), me.uv_layers[0])
    for u in list(me.uv_layers):
        if u.name != keep.name:
            me.uv_layers.remove(u)

    obj.rotation_euler = (0, 0, FRONT_YAW[game_id])
    bpy.ops.object.transform_apply(rotation=True)

    # Normalize: longest side = HEIGHT (a flat plane-shaped croc must not
    # come out 15 studs wide), centred on X/Y, feet at Z=0.
    dims = obj.dimensions
    s = HEIGHT / max(dims)
    obj.scale = (s, s, s)
    bpy.ops.object.transform_apply(scale=True)
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    minv = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    maxv = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    obj.location -= Vector(((minv.x + maxv.x) / 2, (minv.y + maxv.y) / 2, minv.z))
    bpy.ops.object.transform_apply(location=True)

    before = tri_count(me)
    if before > TARGET_TRIS:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = TARGET_TRIS / before
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=tri.name)
    after = tri_count(me)
    obj.name = game_id
    me.name = game_id

    # Texture: 1024x1024 max for Roblox, saved next to the exports.
    img = next(n.image for m in me.materials for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
    img.scale(1024, 1024)
    tex_path = os.path.join(OUT, f"{game_id}_texture.png")
    img.filepath_raw = tex_path
    img.file_format = "PNG"
    img.save()
    # The FBX packs its texture inside itself, so editing/reloading that
    # image just brings the packed 2048px original back. Load the prepared
    # file from disk as a brand-new image and point every node at it.
    clean = os.path.join(OUT, f"{game_id}_texture_clean.png")
    fresh = bpy.data.images.load(clean if os.path.exists(clean) else tex_path)
    fresh.name = f"{game_id}_texture"
    for m in me.materials:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                n.image = fresh
    bpy.data.images.remove(img)
    print(f"TEXTURE {game_id}: {fresh.filepath} {tuple(fresh.size)}")
    # Drop the normal map: baked-in shading is already in the colour
    # texture and Roblox would need a separate SurfaceAppearance for it.
    for m in me.materials:
        for n in list(m.node_tree.nodes):
            if n.type == "NORMAL_MAP":
                m.node_tree.nodes.remove(n)

    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"{game_id}.glb"), export_format="GLB", use_selection=True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, f"{game_id}.fbx"), use_selection=True,
                             path_mode="COPY", embed_textures=True, axis_forward="-Z", axis_up="Y",
                             apply_scale_options="FBX_SCALE_ALL")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(W, f"{game_id}.blend"))
    print(f"RESULT {game_id}: {before} -> {after} tris, height {obj.dimensions.z:.2f}, dims {tuple(round(d,2) for d in obj.dimensions)}")
