"""Worked example: a box fighter on the template skeleton, exported as example.glb.

Shows the parts of a character script that are easy to get wrong: parenting a mesh to a
bone without it jumping (matrix_parent_inverse), part names that don't clash with bone
names, sRGB -> linear colors, and exporting through export_glb.py.

Run from this folder (after building template.blend with build_template.py):
    blender -b --factory-startup --python example_build_character.py
"""

import os
import sys

import bpy
import bmesh  # after bpy: the PyPI bpy module only provides bmesh once bpy is imported
from mathutils import Matrix

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)  # Blender doesn't put the script's folder on sys.path
sys.dont_write_bytecode = True  # keep __pycache__ out of the kit folder
from export_glb import export_glb  # noqa: E402

TEMPLATE = os.path.join(KIT, "template.blend")
OUT = os.path.join(KIT, "example.glb")

# Display (sRGB) colors, as a color picker shows them. The game shows exactly these.
COLORS = {
    "skin": "#e0a878",
    "shirt": "#c02a20",
    "pants": "#2a2c38",
    "shoes": "#181410",
}

# bone: material, boxes as (min, max) corners in Blender world space (meters, -Y = front).
# .L only; .R is mirrored at -X. Joints stay where SKELETON.md puts them.
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
    """Yield (bone name, (material, boxes)) for every bone, mirroring LEFT to .L and .R."""
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


def material(name, hex_color):
    """Opaque, matte material. Blender and glTF store linear color, so convert from sRGB."""
    color = (*srgb_to_linear(hex_color), 1.0)
    m = bpy.data.materials.new(name)
    if bpy.app.version < (5, 0, 0):
        m.use_nodes = True  # always on (and deprecated) in 5.x
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    m.diffuse_color = color  # what Workbench previews show
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


def parent_to_bone(obj, arm_obj, bone_name):
    """Parent `obj` to a bone (Parent type: Bone) without moving it.

    Bone parenting places the child relative to the bone's tail. Setting
    matrix_parent_inverse to the inverse of that tail matrix cancels it, so a mesh modeled
    in world space stays where it was modeled.
    """
    bone = arm_obj.data.bones[bone_name]
    obj.parent = arm_obj
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    bone_tail = arm_obj.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0))
    obj.matrix_parent_inverse = bone_tail.inverted()


print(f"Blender {bpy.app.version_string}")
bpy.ops.wm.open_mainfile(filepath=TEMPLATE)
scene = bpy.context.scene
arm_obj = bpy.data.objects["Armature"]
mats = {k: material(k, c) for k, c in COLORS.items()}

for bone_name, (mat, boxes) in parts():
    # Never the bare bone name: glTF bones and meshes are both nodes, and Godot renames
    # the bone on a clash (head -> head_2), which breaks animations.
    name = f"{bone_name}_part"
    part = bpy.data.objects.new(name, box_mesh(name, boxes, mats[mat]))
    scene.collection.objects.link(part)
    parent_to_bone(part, arm_obj, bone_name)

export_glb(OUT)
