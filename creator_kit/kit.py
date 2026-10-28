"""Helpers for a street-fAIghter character build script. API reference: BPY_NOTES.md.

    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # Blender doesn't add it
    sys.dont_write_bytecode = True  # no __pycache__ in the kit folder
    from kit import *

    start()
    material("skin", "#d9a07a")
    sphere("head", "skull", "skin", (0, 0, 1.66), 0.13)
    finish("Big Tony", "A retired sumo wrestler turned subway busker.")

start() builds the template skeleton (SKELETON.md) in an empty scene, the part functions
model in world space and parent each part to its bone, and finish() checks, renders
previews/sheet.png, exports, and runs the game's validator. build_template.py saves the
same skeleton as template.blend, for modeling by hand.
"""

import contextlib
import json
import math
import os
import subprocess
import sys
import tempfile

import bpy
import bmesh  # after bpy: the PyPI bpy module only provides bmesh once bpy is imported
from mathutils import Matrix, Quaternion, Vector

KIT = os.path.dirname(os.path.abspath(__file__))
if KIT not in sys.path:
    sys.path.insert(0, KIT)
from export_glb import export_glb, reset_pose  # noqa: E402

__all__ = [
    "start", "material", "part", "box", "sphere", "cylinder", "capsule", "head", "tail",
    "stats", "previews", "finish", "math", "Matrix", "Quaternion", "Vector",
]

# Written by the game into each kit: {"glb": "<slug>.glb", "validator": [program, args...]}.
CONFIG = os.path.join(KIT, "kit_config.json")

# The skeleton (SKELETON.md): name, parent, head, tail, connected. .L only; .R mirrors at -X.
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
SIDED = {name for name, *_ in LEFT}


def skeleton():
    """Yield (name, parent, head, tail, connected) for all 17 bones, parents first."""
    yield from CENTER
    for side, sx in (("L", 1), ("R", -1)):
        for name, parent, head_, tail_, connected in LEFT:
            if parent in SIDED:
                parent = f"{parent}.{side}"
            mirror = lambda v: (v[0] * sx, v[1], v[2])  # noqa: E731
            yield f"{name}.{side}", parent, mirror(head_), mirror(tail_), connected


BONES = {name: (Vector(h), Vector(t)) for name, _, h, t, _ in skeleton()}
ARM_BONES = {f"{n}.{s}" for n in ("upper_arm", "forearm", "hand") for s in "LR"}

# The limits the game's validator enforces (characters/character_validator.gd).
MAX_TRIANGLES = 10000
MIN_HEIGHT, MAX_HEIGHT = 1.6, 2.0
FLOOR_TOLERANCE = 0.05
MAX_HALF_EXTENT = 0.6

# Edges between faces bent more than this are shaded sharp (box edges), the rest smooth
# (spheres, cylinder sides).
SHARP_ANGLE = math.radians(45)

TILE = 256  # px per preview view
GAP = 4  # px between views on the sheet
# Camera (x, y) for each sheet column. The character faces -Y; the side view is its left.
VIEWS = {"front": (0.0, -6.0), "side": (6.0, 0.0), "three_quarter": (4.2, -4.2)}
# Sheet bottom row: arms swung forward, left knee bent (SKELETON.md, "Bone axes").
TEST_POSE = {
    "upper_arm.L": ((0, 0, 1), -70),
    "upper_arm.R": ((0, 0, 1), 70),
    "thigh.L": ((1, 0, 0), -60),
    "shin.L": ((1, 0, 0), 90),
}

_materials = {}


def build_skeleton():
    """Add the template Armature to the current scene (meters) and return it."""
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
    for name, parent, head_, tail_, connected in skeleton():
        b = arm.edit_bones.new(name)
        b.head, b.tail, b.roll = head_, tail_, 0.0
        if parent:
            b.parent = arm.edit_bones[parent]
            b.use_connect = connected
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def start():
    """Print the Blender version, empty the scene, and add the template skeleton."""
    print(f"Blender {bpy.app.version_string}")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()
    return build_skeleton()


def head(bone):
    """The bone's head (joint at its start) in world space, as a Vector."""
    return BONES[_check_bone(bone)][0].copy()


def tail(bone):
    """The bone's tail (joint at its end) in world space, as a Vector."""
    return BONES[_check_bone(bone)][1].copy()


def srgb_to_linear(hex_color):
    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(lin(int(hex_color[i:i + 2], 16) / 255) for i in (1, 3, 5))


def material(name, color, glow=0.0):
    """An opaque, matte material named `name` from an sRGB "#rrggbb" color.

    `glow` > 0 makes it emissive in its own color with that strength (eyes, lights).
    Parts take the material or its name.
    """
    linear = (*srgb_to_linear(color), 1.0)
    m = bpy.data.materials.new(name)
    if bpy.app.version < (5, 0, 0):
        m.use_nodes = True  # always on (and deprecated) in 5.x
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = linear
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    if glow > 0:
        bsdf.inputs["Emission Color"].default_value = linear
        bsdf.inputs["Emission Strength"].default_value = glow
    m.diffuse_color = linear  # what the Workbench previews show
    _materials[name] = m
    return m


def part(bone, what, mat, bm, mirror=False):
    """Make bmesh `bm` (world space, T-pose) a part named `<bone>_<what>` on `bone`.

    Frees `bm`. With `mirror`, also adds the copy mirrored at -X: on the other side's bone
    for a .L/.R bone, else as `<bone>_<what>_L` and `_R`. Returns the new objects.
    """
    _check_bone(bone)
    mat = _material(mat)
    if not mirror:
        objs = [_link(f"{bone}_{what}", bone, mat, bm)]
        bm.free()
        return objs
    copy = bm.copy()
    bmesh.ops.transform(copy, matrix=Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0)), verts=copy.verts)
    bmesh.ops.reverse_faces(copy, faces=copy.faces)  # mirroring turns the faces inside out
    if bone[-2:] in (".L", ".R"):
        other = bone[:-1] + ("R" if bone.endswith("L") else "L")
        names = [(f"{bone}_{what}", bone), (f"{other}_{what}", other)]
    else:
        left = sum(v.co.x for v in bm.verts) >= 0  # which side the given geometry is on
        names = [(f"{bone}_{what}_{s}", bone) for s in (("L", "R") if left else ("R", "L"))]
    objs = [_link(n, b, mat, m) for (n, b), m in zip(names, (bm, copy))]
    bm.free()
    copy.free()
    return objs


def box(bone, what, mat, lo, hi, mirror=False):
    """A box between corners `lo` and `hi` (any two opposite corners)."""
    lo, hi = Vector(map(min, lo, hi)), Vector(map(max, lo, hi))
    bm = bmesh.new()
    m = Matrix.Translation((lo + hi) / 2) @ Matrix.Diagonal((*(hi - lo), 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    return part(bone, what, mat, bm, mirror)


def sphere(bone, what, mat, center, radius, mirror=False, segments=12):
    """A sphere, or an ellipsoid when `radius` is (rx, ry, rz)."""
    r = radius if isinstance(radius, (tuple, list, Vector)) else (radius,) * 3
    bm = bmesh.new()
    _add_sphere(bm, Vector(center), r, segments)
    return part(bone, what, mat, bm, mirror)


def cylinder(bone, what, mat, a, b, radius, radius_b=None, mirror=False, segments=12):
    """A closed cylinder from point `a` to point `b`; a cone if `radius_b` (at `b`) differs."""
    bm = bmesh.new()
    _add_cylinder(bm, Vector(a), Vector(b), radius, radius if radius_b is None else radius_b,
                  segments)
    return part(bone, what, mat, bm, mirror)


def capsule(bone, what, mat, a, b, radius, mirror=False, segments=12):
    """A cylinder from `a` to `b` with a sphere on each end. On a limb from its head to its
    tail, the end spheres cover the joints, so bent limbs show no gaps (~380 triangles)."""
    a, b = Vector(a), Vector(b)
    bm = bmesh.new()
    _add_cylinder(bm, a, b, radius, radius, segments)
    for p in (a, b):
        _add_sphere(bm, p, (radius,) * 3, segments)
    return part(bone, what, mat, bm, mirror)


def stats():
    """Print triangles, height, floor, and body extents against the game's limits.

    Measures the rest pose after modifiers. Returns the list of problems.
    """
    reset_pose()
    dg = bpy.context.evaluated_depsgraph_get()
    tris = 0
    inf = float("inf")
    low, high = Vector((inf,) * 3), Vector((-inf,) * 3)
    body = [inf, -inf, inf, -inf]  # min x, max x, min y, max y without the arm parts
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        m.calc_loop_triangles()
        tris += len(m.loop_triangles)
        mw = o.matrix_world
        arm = o.parent_type == "BONE" and o.parent_bone in ARM_BONES
        for v in m.vertices:
            w = mw @ v.co
            low = Vector(map(min, low, w))
            high = Vector(map(max, high, w))
            if not arm:
                body = [min(body[0], w.x), max(body[1], w.x), min(body[2], w.y),
                        max(body[3], w.y)]
        ev.to_mesh_clear()
    if tris == 0:
        print("stats: no parts")
        return ["no parts"]
    problems = []
    half = max(abs(c) for c in body)
    checks = [
        (f"triangles {tris:,}", tris <= MAX_TRIANGLES, f"max {MAX_TRIANGLES:,}"),
        (f"height {high.z:.2f} m", MIN_HEIGHT <= high.z <= MAX_HEIGHT,
         f"{MIN_HEIGHT}-{MAX_HEIGHT} m"),
        (f"soles at {low.z:+.2f} m", abs(low.z) <= FLOOR_TOLERANCE, "Z = 0"),
        (f"body X {body[0]:+.2f}..{body[1]:+.2f}, Y {body[2]:+.2f}..{body[3]:+.2f} m",
         half <= MAX_HALF_EXTENT, f"within ±{MAX_HALF_EXTENT} m without arms"),
    ]
    for text, ok, limit in checks:
        print(f"stats: {text}" + ("" if ok else f"  <-- PROBLEM: {limit}"))
        if not ok:
            problems.append(f"{text} ({limit})")
    return problems


def previews(path=None):
    """Render previews/sheet.png: T-pose (top row) and the test pose (bottom row), seen
    from the front, the character's left side, and the front-left 3/4 (columns)."""
    path = path or os.path.join(KIT, "previews", "sheet.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"  # shows material.diffuse_color
    scene.display.shading.show_object_outline = True
    scene.view_settings.view_transform = "Standard"  # palette colors as picked
    scene.render.resolution_x = scene.render.resolution_y = TILE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("preview_world")
    world.color = (0.45, 0.45, 0.45)
    old_world, scene.world = scene.world, world
    cam_data = bpy.data.cameras.new("preview_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.3  # meters visible: Z -0.15..2.15, past the 2.0 m limit
    cam = bpy.data.objects.new("preview_cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0.0, 0.0, 1.0))
    tmp = tempfile.mkdtemp()
    rows = []
    try:
        for pose in (None, TEST_POSE):
            _set_pose(pose)
            row = []
            for view, (x, y) in VIEWS.items():
                cam.location = Vector((x, y, target.z))
                cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
                scene.render.filepath = os.path.join(tmp, f"{len(rows)}_{view}.png")
                with _quiet():
                    bpy.ops.render.render(write_still=True)
                row.append(scene.render.filepath)
            rows.append(row)
        _stitch(rows, path)
    finally:
        reset_pose()
        bpy.data.objects.remove(cam)  # keep the camera out of the export
        bpy.data.cameras.remove(cam_data)
        scene.world = old_world
        bpy.data.worlds.remove(world)
        for row in rows:
            for f in row:
                os.remove(f)
        os.rmdir(tmp)
    print(f"previews: {path}")
    return path


def finish(name, description, glb=None):
    """Print stats(), render previews(), export the .glb with export_glb(), write its
    manifest (<slug>.json), and run the game's validator on it.

    `glb` defaults to the kit's "<slug>.glb" (kit_config.json). Returns True if the
    validator printed OK.
    """
    config = {}
    if os.path.exists(CONFIG):
        with open(CONFIG, encoding="utf-8") as f:
            config = json.load(f)
    glb = glb or config.get("glb")
    if not glb:
        raise ValueError("no kit_config.json: pass glb='<name>.glb'")
    glb = os.path.join(KIT, glb)
    stats()
    previews()
    with _quiet():
        export_glb(glb)
    manifest = {
        "schema_version": 1,
        "name": name,
        "model": os.path.basename(glb),
        "description": description,
    }
    with open(os.path.splitext(glb)[0] + ".json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    validator = config.get("validator")
    if not validator:
        print("validator: skipped (no kit_config.json)")
        return False
    try:
        run = subprocess.run([*validator, glb], capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=300)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"validator: couldn't run {validator[0]}: {e}")
        return False
    lines = [line for line in run.stdout.splitlines()
             if line.strip() and not line.startswith("Godot Engine")]
    if not lines:  # no verdict on stdout: show why
        lines = run.stderr.strip().splitlines()[-10:]
    for line in lines:
        print(f"validator: {line}")
    ok = run.returncode == 0
    print(f"RESULT: {'OK' if ok else 'FIX THE VALIDATOR PROBLEMS'} {glb}")
    return ok


def _check_bone(bone):
    if bone not in BONES:
        raise ValueError(f"no bone '{bone}'; bones: {', '.join(BONES)}")
    return bone


def _material(mat):
    if isinstance(mat, bpy.types.Material):
        return mat
    if mat not in _materials:
        raise ValueError(f"no material '{mat}'; make it with material() first")
    return _materials[mat]


def _link(name, bone, mat, bm):
    if name in bpy.data.objects:
        raise ValueError(f"part '{name}' exists; give each part on a bone its own name")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    me.set_sharp_from_angle(angle=SHARP_ANGLE)
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    _parent_to_bone(obj, bone)
    return obj


def _parent_to_bone(obj, bone_name):
    """Parent type Bone, without moving `obj`: bone parenting places the child relative to
    the bone's tail, so matrix_parent_inverse cancels that."""
    arm_obj = bpy.data.objects["Armature"]
    bone = arm_obj.data.bones[bone_name]
    obj.parent = arm_obj
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    bone_tail = arm_obj.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0))
    obj.matrix_parent_inverse = bone_tail.inverted()


def _add_sphere(bm, center, radii, segments):
    m = Matrix.Translation(center) @ Matrix.Diagonal((*radii, 1.0))
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=max(4, segments * 2 // 3),
                              radius=1.0, matrix=m)


def _add_cylinder(bm, a, b, radius_a, radius_b, segments):
    d = b - a
    if d.length < 1e-6:
        raise ValueError("cylinder ends a and b are the same point")
    # create_cone builds along Z with radius1 at -Z: turn +Z onto a -> b.
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    m = Matrix.Translation((a + b) / 2) @ rot
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius_a, radius2=radius_b, depth=d.length, matrix=m)


def _set_pose(pose):
    reset_pose()
    if not pose:
        return
    arm_obj = bpy.data.objects["Armature"]
    for bone, (axis, degrees) in pose.items():
        pb = arm_obj.pose.bones[bone]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion(axis, math.radians(degrees))
    bpy.context.view_layer.update()


@contextlib.contextmanager
def _quiet():
    """Keep the per-file lines Blender logs (renders, glTF export) out of the build log;
    print them if the block fails."""
    sys.stdout.flush()
    sys.stderr.flush()
    saved = [os.dup(1), os.dup(2)]
    ok = False
    with tempfile.TemporaryFile() as log:
        os.dup2(log.fileno(), 1)
        os.dup2(log.fileno(), 2)
        try:
            yield
            ok = True
        finally:
            sys.stdout.flush()
            sys.stderr.flush()
            for fd, copy in zip((1, 2), saved):
                os.dup2(copy, fd)
                os.close(copy)
            if not ok:
                log.seek(0)
                print(log.read().decode("utf-8", "replace"))


def _stitch(rows, path):
    """Tile the rendered views (rows of PNG paths, top row first) into one PNG."""
    import numpy as np  # ships with Blender and the bpy module

    n_rows, n_cols = len(rows), len(rows[0])
    width = n_cols * TILE + (n_cols - 1) * GAP
    height = n_rows * TILE + (n_rows - 1) * GAP
    sheet = np.zeros((height, width, 4), np.float32)
    sheet[..., 3] = 1.0
    for r, row in enumerate(rows):
        y = (n_rows - 1 - r) * (TILE + GAP)  # image rows run bottom-up
        for c, file in enumerate(row):
            img = bpy.data.images.load(file)
            px = np.empty(TILE * TILE * 4, np.float32)
            img.pixels.foreach_get(px)
            bpy.data.images.remove(img)
            x = c * (TILE + GAP)
            sheet[y:y + TILE, x:x + TILE] = px.reshape(TILE, TILE, 4)
    out = bpy.data.images.new("preview_sheet", width, height, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
