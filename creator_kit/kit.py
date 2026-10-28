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
previews/sheet.png, exports, and runs the game's validator. special() adds a special throw
(SPECIAL.md). build_template.py saves the same skeleton as template.blend, for modeling by
hand.
"""

import contextlib
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile

import bpy
import bmesh  # after bpy: the PyPI bpy module only provides bmesh once bpy is imported
from mathutils import Euler, Matrix, Quaternion, Vector

KIT = os.path.dirname(os.path.abspath(__file__))
if KIT not in sys.path:
    sys.path.insert(0, KIT)
from export_glb import export_glb, reset_pose  # noqa: E402

__all__ = [
    "start", "material", "part", "box", "sphere", "cylinder", "capsule", "head", "tail",
    "stats", "previews", "finish", "special", "pose", "mirror", "STANCE", "GRAB",
    "STANDARD_THROW", "math", "Matrix", "Quaternion", "Vector",
]

# Written by the game into each kit: {"glb": "<slug>.glb", "validator": [program, args...]}.
CONFIG = os.path.join(KIT, "kit_config.json")
# Also written by the game into each kit: what a special throw needs (SPECIAL.md).
SPECIAL_BASE = os.path.join(KIT, "special_base.json")

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
            flip = lambda v: (v[0] * sx, v[1], v[2])  # noqa: E731
            yield f"{name}.{side}", parent, flip(head_), flip(tail_), connected


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

# previews/special.png: the throw ticks shown, left to right, top row first: the lift and
# flight, the slam (26), the bounce, and the thrower's last tick before its stance (43).
SPECIAL_TICKS = (0, 6, 12, 18, 22, 26, 34, 43)
SPECIAL_COLUMNS = 4

_materials = {}
_special = {}  # what special() stored for finish()


def _load_special_base():
    """special_base.json (the game writes it into every kit), or None outside a kit."""
    if not os.path.exists(SPECIAL_BASE):
        return None
    with open(SPECIAL_BASE, encoding="utf-8") as f:
        return json.load(f)


_BASE = _load_special_base()
# The game's fighting stance and grab poses ({} outside a kit), and the standard throw as
# special() arguments: special(**STANDARD_THROW).
STANCE = _BASE["poses"]["stance"] if _BASE else {}
GRAB = _BASE["poses"]["grab"] if _BASE else {}
STANDARD_THROW = {
    "attacker": [(k["tick"], k["pose"]) for k in _BASE["standard"]["attacker"]],
    "victim": [(k["tick"], k["pose"], tuple(k["root"])) for k in _BASE["standard"]["victim"]],
} if _BASE else {"attacker": [], "victim": []}


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
    _special.clear()
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


def pose(base, over):
    """A copy of pose `base` with the bones (and "hips_pos") in `over` set on top."""
    out = {name: list(v) for name, v in base.items()}
    out.update({name: list(v) for name, v in over.items()})
    return out


def mirror(v):
    """The .R value of a .L rotation (x, y, z): the same motion on the other side."""
    return (v[0], -v[1], -v[2])


def special(attacker, victim):
    """Give the character its own special throw (SPECIAL.md); finish() saves it in the .glb
    and renders previews/special.png.

    `attacker`: (tick, pose) keys for the thrower. `victim`: (tick, pose, (forward, up))
    keys for the thrown fighter, its body origin relative to the thrower's. A pose maps
    bone names to (x, y, z) degrees and "hips_pos" to (x, y, z) meters. The game's
    validator checks the rules when finish() runs it.
    """
    if _BASE is None:
        raise RuntimeError(f"special(): no {SPECIAL_BASE}. The game writes it into every "
                           "creator kit: build the special in a kit folder the game wrote.")
    data = {
        "version": _BASE["version"],
        "attacker": [_special_key(k, f"attacker[{i}]", False) for i, k in enumerate(attacker)],
        "victim": [_special_key(k, f"victim[{i}]", True) for i, k in enumerate(victim)],
    }
    _special.clear()
    _special.update(data)



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
    target = Vector((0.0, 0.0, 1.0))
    with _preview_scene() as (scene, cam, tmp):
        scene.render.resolution_x = scene.render.resolution_y = TILE
        cam.data.ortho_scale = 2.3  # meters visible: Z -0.15..2.15, past the 2.0 m limit
        rows = []
        for test in (None, TEST_POSE):
            _set_pose(test)
            row = []
            for view, (x, y) in VIEWS.items():
                cam.location = Vector((x, y, target.z))
                cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
                row.append(_render(scene, os.path.join(tmp, f"{len(rows)}_{view}.png")))
            rows.append(row)
        _stitch(rows, path)
    print(f"previews: {path}")
    return path


def finish(name, description, glb=None):
    """Print stats(), render previews(), export the .glb with export_glb(), save the
    special() in it and render previews/special.png, write its manifest (<slug>.json), and
    run the game's validator on it.

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
    special_png = os.path.join(KIT, "previews", "special.png")
    if _special:
        _inject_special(glb, _special)
        print(f"special: {len(_special['attacker'])} attacker keys, "
              f"{len(_special['victim'])} victim keys, saved in {os.path.basename(glb)}")
        _special_previews(_special, special_png)
        print(f"special: previews: {special_png} (ticks {', '.join(map(str, SPECIAL_TICKS))})")
    elif os.path.exists(special_png):
        os.remove(special_png)  # from an earlier build with a special: it would mislead
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


def _stitch(rows, path, size=(TILE, TILE)):
    """Tile the rendered views (rows of PNG paths, top row first, each `size` px) into one
    PNG."""
    import numpy as np  # ships with Blender and the bpy module

    w, h = size
    n_rows, n_cols = len(rows), max(len(row) for row in rows)
    width = n_cols * w + (n_cols - 1) * GAP
    height = n_rows * h + (n_rows - 1) * GAP
    sheet = np.zeros((height, width, 4), np.float32)
    sheet[..., 3] = 1.0
    for r, row in enumerate(rows):
        y = (n_rows - 1 - r) * (h + GAP)  # image rows run bottom-up
        for c, file in enumerate(row):
            img = bpy.data.images.load(file)
            px = np.empty(w * h * 4, np.float32)
            img.pixels.foreach_get(px)
            bpy.data.images.remove(img)
            x = c * (w + GAP)
            sheet[y:y + h, x:x + w] = px.reshape(h, w, 4)
    out = bpy.data.images.new("preview_sheet", width, height, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)


@contextlib.contextmanager
def _preview_scene():
    """Set up Workbench rendering, a gray world, and an ortho camera; yield (scene, camera,
    temp folder) and remove them again, so none of it reaches the export."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"  # shows material.diffuse_color
    scene.display.shading.show_object_outline = True
    scene.view_settings.view_transform = "Standard"  # palette colors as picked
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("preview_world")
    world.color = (0.45, 0.45, 0.45)
    old_world, scene.world = scene.world, world
    cam_data = bpy.data.cameras.new("preview_cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("preview_cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    tmp = tempfile.mkdtemp()
    try:
        yield scene, cam, tmp
    finally:
        reset_pose()
        bpy.data.objects.remove(cam)
        bpy.data.cameras.remove(cam_data)
        scene.world = old_world
        bpy.data.worlds.remove(world)
        shutil.rmtree(tmp, ignore_errors=True)


def _render(scene, file):
    scene.render.filepath = file
    with _quiet():
        bpy.ops.render.render(write_still=True)
    return file


def _numbers(value, n, label):
    try:
        out = [float(c) for c in value]
    except (TypeError, ValueError):
        out = []
    if len(out) != n or not all(math.isfinite(c) for c in out):
        raise TypeError(f"{label} must be {n} numbers, not {value!r}")
    return out


def _special_key(key, label, with_root):
    """One special() key as the .glb stores it: {"tick", "pose"[, "root"]}."""
    label = f"special(): {label}"
    shape = "(tick, pose, (forward, up))" if with_root else "(tick, pose)"
    if not isinstance(key, (list, tuple)) or len(key) != (3 if with_root else 2):
        raise TypeError(f"{label} must be {shape}, not {key!r}")
    tick = _numbers([key[0]], 1, f"{label} tick")[0]
    if not isinstance(key[1], dict):
        raise TypeError(f"{label} pose must be a dict of bone name -> (x, y, z)")
    out = {
        "tick": int(tick) if tick.is_integer() else tick,
        "pose": {str(b): _numbers(v, 3, f"{label} pose['{b}']") for b, v in key[1].items()},
    }
    if with_root:
        out["root"] = _numbers(key[2], 2, f"{label} root (forward, up)")
    return out


def _inject_special(glb, data):
    """Put `data` in the .glb's top-level glTF extras ("street_faighter" -> "special"):
    rewrite the JSON chunk, keep the BIN chunk as it is."""
    with open(glb, "rb") as f:
        blob = f.read()
    magic, version, length = struct.unpack_from("<4sII", blob, 0)
    json_length, json_type = struct.unpack_from("<II", blob, 12)
    if magic != b"glTF" or json_type != 0x4E4F534A:  # "JSON"
        raise ValueError(f"{glb} is not a glTF binary")
    gltf = json.loads(blob[20:20 + json_length])
    extras = gltf.get("extras") if isinstance(gltf.get("extras"), dict) else {}
    game = extras.get("street_faighter") if isinstance(extras.get("street_faighter"), dict) else {}
    game["special"] = data
    extras["street_faighter"] = game
    gltf["extras"] = extras
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)  # chunks are 4-byte aligned; JSON pads with spaces
    rest = blob[20 + json_length:length]
    with open(glb, "wb") as f:
        f.write(struct.pack("<4sII", magic, version, 20 + len(text) + len(rest)))
        f.write(struct.pack("<II", len(text), json_type))
        f.write(text)
        f.write(rest)


def _special_tracks(data):
    """The keys the game plays, as (tick, pose) lists for the attacker and the victim and
    (tick, (forward, up)) for the victim's root: `data`'s keys plus the game's own."""
    b = _BASE
    attacker = [(k["tick"], k["pose"]) for k in data["attacker"]]
    attacker.append((b["throw_ticks"], b["poses"]["stance"]))
    victim = [(k["tick"], k["pose"]) for k in data["victim"]]
    victim += [(k["tick"], k["pose"]) for k in b["after_slam"]]
    root = [(k["tick"], k["root"]) for k in data["victim"]]
    root.append((b["slam_tick"], b["landing"]))
    return attacker, victim, root


def _between(keys, tick):
    """The keys around `tick` and the blend weight: (a, b, w). Before the first key the
    first holds, after the last the last holds."""
    if tick <= keys[0][0]:
        return keys[0][1], keys[0][1], 0.0
    for (ta, a), (tb, b) in zip(keys, keys[1:]):
        if tick <= tb:
            return a, b, (tick - ta) / (tb - ta) if tb > ta else 1.0
    return keys[-1][1], keys[-1][1], 0.0


def _rotation(degrees):
    """A pose value as the game builds it: Godot's Quaternion.from_euler (YXZ order)."""
    if degrees is None:
        return Quaternion()
    return Euler([math.radians(c) for c in degrees], "ZXY").to_quaternion()


def _pose_at(arm_obj, keys, tick):
    """Pose `arm_obj` at `tick` like the game: rotations slerped the short way round,
    hips_pos lerped, unlisted bones at rest."""
    a, b, w = _between(keys, tick)
    for pb in arm_obj.pose.bones:
        qa, qb = _rotation(a.get(pb.name)), _rotation(b.get(pb.name))
        if qa.dot(qb) < 0:
            qb.negate()
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = qa.slerp(qb, w)
    hips_a, hips_b = Vector(a.get("hips_pos", (0, 0, 0))), Vector(b.get("hips_pos", (0, 0, 0)))
    arm_obj.pose.bones["hips"].location = hips_a.lerp(hips_b, w)


def _special_previews(data, path):
    """Render previews/special.png: the character's left side at SPECIAL_TICKS, the
    thrower in its colors at the origin, the victim as a gray copy at its root."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    attacker, victim, root = _special_tracks(data)
    ticks = [t for t in SPECIAL_TICKS if t < _BASE["throw_ticks"]]
    arm = bpy.data.objects["Armature"]
    scene = bpy.context.scene
    parts = [o for o in scene.objects if o.type == "MESH" and o.parent == arm]
    made = []  # preview objects, removed at the end
    gray, dark = bpy.data.materials.new("preview_victim"), bpy.data.materials.new("preview_floor")
    gray.diffuse_color = (0.6, 0.6, 0.6, 1.0)  # what Workbench shows
    dark.diffuse_color = (0.02, 0.02, 0.02, 1.0)
    try:
        twin = arm.copy()
        twin.data = arm.data.copy()
        twin.rotation_euler = (0.0, 0.0, math.pi)  # faces the thrower (+Y)
        scene.collection.objects.link(twin)
        made.append(twin)
        for o in parts:
            c = o.copy()  # shares the mesh; same bone
            c.parent = twin
            c.matrix_parent_inverse = o.matrix_parent_inverse  # setting parent resets it
            scene.collection.objects.link(c)
            made.append(c)
            for slot in c.material_slots:
                slot.link = "OBJECT"  # gray on this copy only
                slot.material = gray

        def pose_at(tick):
            _pose_at(arm, attacker, tick)
            _pose_at(twin, victim, tick)
            a, b, w = _between(root, tick)
            forward, up = (a[i] + (b[i] - a[i]) * w for i in (0, 1))
            twin.location = (0.0, -forward, up)
            bpy.context.view_layer.update()

        # Fit the camera to both bodies over all ticks, the floor included.
        inf = float("inf")
        y0, y1, z0, z1 = inf, -inf, 0.0, -inf
        for tick in ticks:
            pose_at(tick)
            dg = bpy.context.evaluated_depsgraph_get()
            for o in made[1:] + parts:
                ev = o.evaluated_get(dg)
                for corner in ev.bound_box:
                    p = ev.matrix_world @ Vector(corner)
                    y0, y1, z0, z1 = min(y0, p.y), max(y1, p.y), min(z0, p.z), max(z1, p.z)
        margin = 0.15
        y0, y1, z0, z1 = y0 - margin, y1 + margin, z0 - margin, z1 + margin
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(
            (0, (y0 + y1) / 2, -0.015)) @ Matrix.Diagonal((0.8, y1 - y0, 0.03, 1.0)))
        floor_mesh = bpy.data.meshes.new("preview_floor")
        bm.to_mesh(floor_mesh)
        bm.free()
        floor_mesh.materials.append(dark)
        floor = bpy.data.objects.new("preview_floor", floor_mesh)
        scene.collection.objects.link(floor)
        made.append(floor)

        with _preview_scene() as (scene, cam, tmp):
            width, height = y1 - y0, z1 - z0
            res_x = min(max(round(TILE * width / height), TILE), 2 * TILE)
            scene.render.resolution_x, scene.render.resolution_y = res_x, TILE
            cam.data.ortho_scale = max(width, height * res_x / TILE)  # spans the image width
            target = Vector((0.0, (y0 + y1) / 2, (z0 + z1) / 2))
            cam.location = target + Vector((10.0, 0.0, 0.0))  # the thrower's left side
            cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
            r = scene.render
            for prop in r.bl_rna.properties:  # stamp only the note: "tick N"
                if prop.identifier.startswith("use_stamp_") and not prop.is_readonly:
                    setattr(r, prop.identifier, False)
            r.use_stamp = r.use_stamp_note = True
            r.stamp_font_size = 20
            files = []
            try:
                for tick in ticks:
                    pose_at(tick)
                    r.stamp_note_text = f"tick {tick}"
                    files.append(_render(scene, os.path.join(tmp, f"{tick}.png")))
            finally:
                r.use_stamp = False
            rows = [files[i:i + SPECIAL_COLUMNS] for i in range(0, len(files), SPECIAL_COLUMNS)]
            _stitch(rows, path, (res_x, TILE))
    finally:
        for o in reversed(made):
            data_block = o.data
            bpy.data.objects.remove(o)
            if data_block is not None and data_block.users == 0:
                if isinstance(data_block, bpy.types.Armature):
                    bpy.data.armatures.remove(data_block)
                elif isinstance(data_block, bpy.types.Mesh):
                    bpy.data.meshes.remove(data_block)
        for m in (gray, dark):
            bpy.data.materials.remove(m)
        reset_pose()
    return path
