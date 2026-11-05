# Run: blender -b art_src/models/enemy_bat/src/bat_v5.blend --python tools/blender_export_bat.py -- <out.glb> <Bat_Flying|Bat_Die>
import bpy, sys
# Vampire Bat (OpenGameArt, CC0) → GLB for tools/bake_enemy_vat.gd: only the animated bat (Armature_Bat +
# Bat_LP_Anim), one clip per file. The file's actions do not evaluate in Blender 5's depsgraph (pose stays
# put on frame change), so keys are exported straight from the F-curves without sampling.
args = sys.argv[sys.argv.index("--") + 1:]
out, action_name = args[0], args[1]
keep = {"Armature_Bat", "Bat_LP_Anim"}
def walk(lc):
    lc.exclude = False
    lc.hide_viewport = False
    for c in lc.children:
        walk(c)
walk(bpy.context.view_layer.layer_collection)
for o in list(bpy.data.objects):
    if o.name not in keep:
        bpy.data.objects.remove(o, do_unlink=True)
arm = bpy.data.objects["Armature_Bat"]
for o in bpy.data.objects:
    o.hide_viewport = False
    o.hide_set(False)
ad = arm.animation_data
for t in list(ad.nla_tracks):
    ad.nla_tracks.remove(t)
act = bpy.data.actions[action_name]
ad.action = act
ad.action_slot = act.slots[0]
for a in list(bpy.data.actions):
    if a != act:
        bpy.data.actions.remove(a)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True, export_animation_mode="ACTIVE_ACTIONS",
    export_force_sampling=False, export_apply=True)
