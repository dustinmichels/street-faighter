"""Build the template skeleton with creator_kit/build_template.py and dump it as JSON.

Used by tests/skeleton_drift_test.gd, which compares the dump with creator_kit/SKELETON.md and
default.glb. The dump comes from the rig Blender actually builds, not from the script's
tables: bone name, parent, head, tail, connected, roll, and the local X/Y/Z axes at rest,
all in Blender armature space (meters, Z up, -Y forward).

    blender -b --factory-startup --python tests/dump_skeleton.py -- <out.json>
"""

import json
import os
import runpy
import sys
import tempfile

import bpy

KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "creator_kit")
out = sys.argv[sys.argv.index("--") + 1]
template = os.path.join(tempfile.mkdtemp(), "template.blend")

argv = sys.argv
sys.argv = [argv[0], "--", template]
runpy.run_path(os.path.join(KIT, "build_template.py"), run_name="__main__")
sys.argv = argv

bpy.ops.wm.open_mainfile(filepath=template)
arm_obj = bpy.data.objects["Armature"]
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode="EDIT")
rolls = {b.name: b.roll for b in arm_obj.data.edit_bones}
bpy.ops.object.mode_set(mode="OBJECT")


def vec(v):
    return [round(c, 6) for c in v]


bones = []
for bone in arm_obj.data.bones:
    axes = bone.matrix_local.to_3x3()
    bones.append({
        "name": bone.name,
        "parent": bone.parent.name if bone.parent else "",
        "head": vec(bone.head_local),
        "tail": vec(bone.tail_local),
        "connected": bone.use_connect,
        "roll": round(rolls[bone.name], 6),
        "x": vec(axes.col[0]),
        "y": vec(axes.col[1]),
        "z": vec(axes.col[2]),
    })
dump = {
    "blender": bpy.app.version_string,
    "object": {
        "location": vec(arm_obj.location),
        "rotation": vec(arm_obj.rotation_euler),
        "scale": vec(arm_obj.scale),
    },
    "bones": bones,
}
with open(out, "w") as f:
    json.dump(dump, f, indent=1)
os.remove(template)
print(f"dumped {len(bones)} bones to {out}")
