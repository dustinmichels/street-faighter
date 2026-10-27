"""Regenerate the placeholder fighter: one box per bone on the template skeleton.

Writes default.blend (next to this script) and ../default.glb. Fighter 2 in a mirror
match is told apart by a runtime tint (`CharacterLoader.MIRROR_TINT`), not a variant.
Run from the repo root:
    blender -b --factory-startup --python characters/default/source/build_default.py
"""

import os

import bmesh
import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "..", "..", "template", "template.blend")

# Display (sRGB) colors; this is what Godot shows as albedo_color.
COLORS = {
    "skin": "#e0a878",
    "shirt": "#c02a20",
    "pants": "#2a2c38",
    "shoes": "#181410",
}


# bone: material, boxes as (min, max) corners in Blender world space (meters, -Y = front).
# .L only; .R is mirrored at -X. Joints stay on the skeleton from creator_kit/SKELETON.md.
CENTER = {
    "hips": ("pants", [((-0.16, -0.10, 0.88), (0.16, 0.10, 1.05))]),
    "spine": ("shirt", [((-0.14, -0.09, 1.05), (0.14, 0.09, 1.25))]),
    "chest": ("shirt", [((-0.20, -0.11, 1.25), (0.20, 0.11, 1.48))]),
    "neck": ("skin", [((-0.05, -0.05, 1.45), (0.05, 0.05, 1.56))]),
    # Head plus a nose so the facing direction reads at low resolution.
    "head": ("skin", [((-0.10, -0.11, 1.55), (0.10, 0.10, 1.80)),
                      ((-0.02, -0.15, 1.63), (0.02, -0.11, 1.68))]),
}
LEFT = {
    "upper_arm": ("shirt", [((0.18, -0.06, 1.36), (0.45, 0.06, 1.48))]),
    "forearm": ("skin", [((0.45, -0.05, 1.37), (0.70, 0.05, 1.47))]),
    "hand": ("skin", [((0.70, -0.055, 1.365), (0.82, 0.055, 1.475))]),
    "thigh": ("pants", [((0.03, -0.08, 0.50), (0.17, 0.08, 0.95))]),
    "shin": ("pants", [((0.04, -0.065, 0.08), (0.16, 0.065, 0.50))]),
    "foot": ("shoes", [((0.04, -0.20, 0.0), (0.16, 0.06, 0.10))]),
}


def parts():
    yield from CENTER.items()
    for side, sx in (("L", 1), ("R", -1)):
        for name, (mat, boxes) in LEFT.items():
            mirrored = []
            for lo, hi in boxes:
                xs = sorted((lo[0] * sx, hi[0] * sx))
                mirrored.append(((xs[0], lo[1], lo[2]), (xs[1], hi[1], hi[2])))
            yield f"{name}.{side}", (mat, mirrored)


def srgb_to_linear(hex_color):
    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(lin(int(hex_color[i:i + 2], 16) / 255) for i in (1, 3, 5))


def set_color(m, hex_color):
    color = (*srgb_to_linear(hex_color), 1.0)  # Blender and glTF store linear color.
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = color
    m.diffuse_color = color


def material(name, hex_color):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    set_color(m, hex_color)
    return m


def box_mesh(name, boxes, mat):
    bm = bmesh.new()
    for lo, hi in boxes:
        size = [h - l for l, h in zip(lo, hi)]
        center = [(l + h) / 2 for l, h in zip(lo, hi)]
        m = Matrix.Translation(center) @ Matrix.Diagonal((*size, 1.0))
        bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    return me


bpy.ops.wm.open_mainfile(filepath=TEMPLATE)
scene = bpy.context.scene
arm_obj = bpy.data.objects["Armature"]
mats = {k: material(k, c) for k, c in COLORS.items()}

for bone_name, (mat, boxes) in parts():
    bone = arm_obj.data.bones[bone_name]
    # Must not share the bone's name: glTF bones and meshes are both nodes, and Godot
    # de-duplicates clashing node names by renaming the bone (head -> head_2).
    name = f"{bone_name}_part"
    part = bpy.data.objects.new(name, box_mesh(name, boxes, mats[mat]))
    scene.collection.objects.link(part)
    part.parent = arm_obj
    part.parent_type = "BONE"
    part.parent_bone = bone_name
    # Bone parenting attaches at the bone's tail; cancel it so the mesh stays where it was modeled.
    bone_tail = arm_obj.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0))
    part.matrix_parent_inverse = bone_tail.inverted()

out = os.path.join(HERE, "default.blend")
bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
print(f"wrote {out} ({len(arm_obj.children)} parts)")
glb = os.path.normpath(os.path.join(HERE, "..", "default.glb"))
bpy.ops.export_scene.gltf(
    filepath=glb,
    export_format="GLB",
    export_yup=True,
    export_apply=True,
    export_animations=False,
    export_morph=False,
    export_lights=False,
    export_cameras=False,
)
print(f"wrote {glb}")
