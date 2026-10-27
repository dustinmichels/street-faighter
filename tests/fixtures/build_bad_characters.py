"""Build the validator test fixtures: one valid and several broken character .glbs.

Each fixture is the same simple fighter (one box per bone) with exactly one thing broken,
so `tests/character_validator_test.gd` can check that the validator reports it. They are
built in Blender because Godot's glTF exporter drops unskinned skeletons.

Run from the repo root, then commit the .glb files (this folder has a .gdignore, so Godot
doesn't import them):
    blender -b --factory-startup --python tests/fixtures/build_bad_characters.py
"""

import math
import os
import runpy
import sys
import tempfile

import bpy
import bmesh  # after bpy: the PyPI bpy module only provides bmesh once bpy is imported
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.join(HERE, "..", "..", "creator_kit")
sys.path.insert(0, KIT)
sys.dont_write_bytecode = True
from export_glb import export_glb  # noqa: E402

TEMPLATE = os.path.join(tempfile.mkdtemp(), "template.blend")
HALF = 0.04  # half-thickness of each bone's box: soles at about -0.02 m, top at 1.75 m


def build_template():
    argv = sys.argv
    sys.argv = [argv[0], "--", TEMPLATE]
    try:
        runpy.run_path(os.path.join(KIT, "build_template.py"), run_name="__main__")
    finally:
        sys.argv = argv


def open_template():
    bpy.ops.wm.open_mainfile(filepath=TEMPLATE)
    arm_obj = bpy.data.objects["Armature"]
    bpy.context.view_layer.objects.active = arm_obj
    return arm_obj


def edit_bones(arm_obj, edit):
    """Run `edit(edit_bones)` in Edit Mode on the armature."""
    bpy.ops.object.mode_set(mode="EDIT")
    edit(arm_obj.data.edit_bones)
    bpy.ops.object.mode_set(mode="OBJECT")


def material(name, alpha=1.0):
    m = bpy.data.materials.new(name)
    if bpy.app.version < (5, 0, 0):
        m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.5, 0.2, 0.1, 1.0)
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        m.surface_render_method = "BLENDED"
    return m


def bone_box(name, arm_obj, bone, mat):
    """A box from the bone's head to its tail, in world space."""
    bm = bmesh.new()
    bm.loops.layers.uv.new()  # textures need UVs
    scale = Matrix.Diagonal((2 * HALF, bone.length, 2 * HALF, 1.0))
    local = Matrix.Translation((0, bone.length / 2, 0)) @ scale
    bmesh.ops.create_cube(bm, size=1.0, matrix=arm_obj.matrix_world @ bone.matrix_local @ local, calc_uvs=True)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    return me


def add_part(name, mesh, arm_obj, bone_name):
    """Link a mesh modeled in world space and parent it to a bone without moving it."""
    part = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(part)
    bone = arm_obj.data.bones[bone_name]
    part.parent = arm_obj
    part.parent_type = "BONE"
    part.parent_bone = bone_name
    tail = arm_obj.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0))
    part.matrix_parent_inverse = tail.inverted()
    return part


def add_body(arm_obj, mat=None, names=None):
    """One box per bone, named '<bone>_part' unless `names` maps a bone to another name."""
    mat = mat or material("body")
    names = names or {}
    for bone in arm_obj.data.bones:
        name = names.get(bone.name, f"{bone.name}_part")
        add_part(name, bone_box(name, arm_obj, bone, mat), arm_obj, bone.name)


def export(name):
    export_glb(os.path.join(HERE, f"{name}.glb"))


# --- Fixtures -----------------------------------------------------------------

def valid():
    add_body(open_template())
    export("valid")


def missing_bone():
    arm_obj = open_template()
    edit_bones(arm_obj, lambda eb: eb.remove(eb["hand.L"]))
    add_body(arm_obj)
    export("missing_bone")


def renamed_bone():
    arm_obj = open_template()
    arm_obj.data.bones["hand.L"].name = "hand.L.001"
    add_body(arm_obj)
    export("renamed_bone")


def part_named_like_bone():
    arm_obj = open_template()
    add_body(arm_obj, names={"head": "head"})
    export("part_named_like_bone")


def extra_bone():
    arm_obj = open_template()

    def add_tail(eb):
        b = eb.new("tail")
        b.head, b.tail, b.roll = (0, 0.1, 0.95), (0, 0.4, 0.8), 0.0
        b.parent = eb["hips"]
    edit_bones(arm_obj, add_tail)
    add_body(arm_obj)
    export("extra_bone")


def moved_joint():
    arm_obj = open_template()

    def move_elbow(eb):
        eb["upper_arm.L"].tail = (0.50, 0, 1.42)  # forearm.L is connected, so its head moves too
    edit_bones(arm_obj, move_elbow)
    add_body(arm_obj)
    export("moved_joint")


def too_many_triangles():
    arm_obj = open_template()
    add_body(arm_obj)
    bm = bmesh.new()
    # A dense 0.3 m plate in front of the chest: 75 x 75 quads = 11,250 triangles.
    plate = Matrix.Translation((0, -0.12, 1.35)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    bmesh.ops.create_grid(bm, x_segments=75, y_segments=75, size=0.15, matrix=plate)
    me = bpy.data.meshes.new("chest_plate")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bpy.data.materials["body"])
    add_part("chest_plate", me, arm_obj, "chest")
    export("too_many_triangles")


def transparent_material():
    arm_obj = open_template()
    add_body(arm_obj, mat=material("ghost", alpha=0.5))
    export("transparent_material")


def wrong_facing():
    arm_obj = open_template()
    arm_obj.rotation_euler = (0, 0, math.pi)  # turned to face +Y
    add_body(arm_obj)
    export("wrong_facing")


def wrong_scale():
    arm_obj = open_template()
    arm_obj.scale = (1.25, 1.25, 1.25)  # 2.3 m tall
    bpy.context.view_layer.update()
    add_body(arm_obj)
    export("wrong_scale")


def oversized_texture():
    arm_obj = open_template()
    mat = material("printed")
    image = bpy.data.images.new("print_2048", 2048, 2048)
    image.generated_color = (0.8, 0.3, 0.1, 1.0)
    image.pack()
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    add_body(arm_obj, mat=mat)
    export("oversized_texture")


FIXTURES = [
    valid, missing_bone, renamed_bone, part_named_like_bone, extra_bone, moved_joint,
    too_many_triangles, transparent_material, wrong_facing, wrong_scale, oversized_texture,
]

print(f"Blender {bpy.app.version_string}")
build_template()
for fixture in FIXTURES:
    fixture()
os.remove(TEMPLATE)
