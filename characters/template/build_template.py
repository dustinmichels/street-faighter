"""Regenerate template.blend: the shared character skeleton (spec: docs/skeleton.md).

Run from the repo root:
    blender -b --factory-startup --python characters/template/build_template.py
"""

import os

import bpy

# name, parent, head, tail, connected. .L only; .R is mirrored at -X.
CENTER = [
    ("hips", None, (0, 0, 0.95), (0, 0, 1.05), False),
    ("spine", "hips", (0, 0, 1.05), (0, 0, 1.25), True),
    ("chest", "spine", (0, 0, 1.25), (0, 0, 1.45), True),
    ("neck", "chest", (0, 0, 1.45), (0, 0, 1.55), True),
    ("head", "neck", (0, 0, 1.55), (0, 0, 1.75), True),
]
LEFT = [
    ("upper_arm", "chest", (0.18, 0, 1.42), (0.45, 0, 1.42), False),
    ("forearm", "upper_arm", (0.45, 0, 1.42), (0.70, 0, 1.42), True),
    ("hand", "forearm", (0.70, 0, 1.42), (0.80, 0, 1.42), True),
    ("thigh", "hips", (0.10, 0, 0.95), (0.10, 0, 0.50), False),
    ("shin", "thigh", (0.10, 0, 0.50), (0.10, 0, 0.08), True),
    ("foot", "shin", (0.10, 0, 0.08), (0.10, -0.15, 0.02), True),
]
SIDED_PARENTS = {name for name, *_ in LEFT}


def bones():
    yield from CENTER
    for side, sx in (("L", 1), ("R", -1)):
        for name, parent, head, tail, connected in LEFT:
            if parent in SIDED_PARENTS:
                parent = f"{parent}.{side}"
            mirror = lambda v: (v[0] * sx, v[1], v[2])
            yield f"{name}.{side}", parent, mirror(head), mirror(tail), connected


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

arm = bpy.data.armatures.new("Armature")
arm.display_type = "STICK"
obj = bpy.data.objects.new("Armature", arm)
obj.show_in_front = True
scene.collection.objects.link(obj)
bpy.context.view_layer.objects.active = obj

bpy.ops.object.mode_set(mode="EDIT")
for name, parent, head, tail, connected in bones():
    b = arm.edit_bones.new(name)
    b.head, b.tail, b.roll = head, tail, 0.0
    if parent:
        b.parent = arm.edit_bones[parent]
        b.use_connect = connected
bpy.ops.object.mode_set(mode="OBJECT")

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "template.blend")
bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
print(f"wrote {out} ({len(arm.bones)} bones)")
