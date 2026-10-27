"""Regenerate the street stage: a gritty night street with trash cans and steaming pipes.

Writes street.blend (next to this script), ../street.glb (the backdrop, street and props)
and ../wall.glb (the brick pillar shown at each stage wall). Run from the repo root:
    blender -b --factory-startup --python stages/street/source/build_street.py

Everything is modeled in Godot coordinates (x right, y up, +z toward the camera; meters)
and converted to Blender's Z-up / -Y-front on the way in, so the numbers below match what
the game sees. Fighters stand on the road at z = 0, y = 0; the stage walls' inner faces sit
at x = +-6 (Stage.half_width) and the camera never shows past x = +-6.5.

The camera is orthographic and pitched 10 degrees down, so farther things appear higher on
screen and the visible height shrinks with depth: at the facade (z = -3) the top of the
screen is y = 3.75, at z = -13 about y = 2.1. The skyline is sized for that.

Empties named steam_* mark steam emitters: Stage spawns scenes/steam.tscn on each, emitting
along the empty's +Y (Godot) axis; the empty's scale scales the plume.

Textures are generated pixel art (about 64 texels per meter, the game's ~54 px/m), mapped
by world-space box projection, so they line up across separate boxes.
"""

import math
import os
import random

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, ".."))
SEED = 7
MOON_X = 5.5  # clear of the rooftop AC unit


# ---------------------------------------------------------------------------
# Colors and pixel-art textures (sRGB, rows bottom-up like Blender images)
# ---------------------------------------------------------------------------

def rgb(hex_color):
    return np.array([int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)])


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def walk(rng, img, x, y, steps, color):
    """Random-walk crack, wrapping around the tile."""
    h, w, _ = img.shape
    for _ in range(steps):
        img[y % h, x % w] = color
        x += rng.choice((-1, 0, 1))
        y += rng.choice((-1, 0, 1))


def stroke(img, pts, radius, color):
    """Round-brush polyline through `pts` (texel coordinates, x right, y up)."""
    h, w, _ = img.shape
    r = int(math.ceil(radius))
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        n = int(math.hypot(bx - ax, by - ay) * 2) + 1
        for k in range(n + 1):
            cx, cy = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
            for y in range(int(cy) - r, int(cy) + r + 1):
                for x in range(int(cx) - r, int(cx) + r + 1):
                    if 0 <= y < h and 0 <= x < w and (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius:
                        img[y, x] = color


# Graffiti letters as polylines on a unit cell (x right, y up).
TAG_GLYPHS = {
    "K": [[(0, 0), (0.1, 1)], [(0.95, 1), (0.1, 0.45), (0.9, 0)]],
    "R": [[(0, 0), (0.1, 1), (0.8, 1), (0.95, 0.75), (0.75, 0.52), (0.05, 0.5)], [(0.35, 0.5), (1, 0)]],
    "A": [[(0, 0), (0.5, 1), (1, 0)], [(0.22, 0.42), (0.85, 0.42)]],
}


def brick_texture(size, palette, mortar, seed, grime_px=48, paint=None):
    """size x size texels = 4 x 4 m of 16 x 4 texel bricks (25 x 6 cm). Bottom rows are
    grimy, a few drips streak down; `paint` = (color, height_px) paints a chipped band
    along the bottom."""
    rng = random.Random(seed)
    img = np.zeros((size, size, 3))
    pal = [rgb(c) for c in palette]
    mort = rgb(mortar)
    for row in range(size // 4):
        offset = 8 if row % 2 else 0
        for col in range(-1, size // 16 + 1):
            tone = pal[rng.randrange(len(pal))] * rng.uniform(0.9, 1.08)
            if rng.random() < 0.04:
                tone = tone * 0.65  # scorched brick
            x0 = col * 16 + offset
            for y in range(row * 4, row * 4 + 4):
                for x in range(x0, x0 + 16):
                    if 0 <= x < size:
                        edge = y == row * 4 or x == x0
                        img[y, x] = mort if edge else tone * rng.uniform(0.94, 1.04)
    if paint is not None:
        color, height = rgb(paint[0]), paint[1]
        for y in range(height):
            for x in range(size):
                if rng.random() > 0.035:
                    img[y, x] = color * rng.uniform(0.92, 1.05)
        # Bigger chips that show the brick underneath.
        for _ in range(10):
            cx, cy = rng.randrange(size), rng.randrange(height)
            for y in range(cy - 2, cy + 3):
                for x in range(cx - 4, cx + 5):
                    if 0 <= y < height and rng.random() < 0.7:
                        img[y, x % size] = img[y, x % size] * 0 + pal[0] * 0.8
        img[height:height + 1, :] = color * 0.6
    for y in range(grime_px):
        img[y] *= 1.0 - 0.45 * (1.0 - y / grime_px) ** 1.6
    for _ in range(14):  # drips from window sills, pipes
        x = rng.randrange(size)
        top = rng.randrange(grime_px, size)
        for y in range(top - rng.randrange(10, 50), top):
            if 0 <= y < size:
                img[y, x] *= 0.72
    return img


def concrete_texture(seed):
    """64 x 64 = one 1 m sidewalk slab: seams, speckles, cracks, gum."""
    rng = random.Random(seed)
    img = np.zeros((64, 64, 3))
    base = rgb("#77736b")
    for y in range(64):
        for x in range(64):
            img[y, x] = base * rng.uniform(0.9, 1.06)
    img[0, :] = img[:, 0] = base * 0.55
    img[1, :] *= 0.85
    img[:, 1] *= 0.85
    for _ in range(2):
        walk(rng, img, rng.randrange(64), rng.randrange(64), 30, base * 0.6)
    for _ in range(6):
        img[rng.randrange(2, 64), rng.randrange(2, 64)] = base * 0.45
    return img


def asphalt_texture(seed):
    """128 x 128 = 2 x 2 m: speckled tarmac, cracks, oil stains, a patch."""
    rng = random.Random(seed)
    img = np.zeros((128, 128, 3))
    base = rgb("#35353b")
    for y in range(128):
        for x in range(128):
            r = rng.random()
            k = 1.35 if r < 0.04 else 0.8 if r < 0.1 else rng.uniform(0.93, 1.05)
            img[y, x] = base * k
    for _ in range(3):  # oil stains
        cx, cy, rad = rng.randrange(128), rng.randrange(128), rng.randrange(5, 11)
        for y in range(cy - rad, cy + rad):
            for x in range(cx - rad, cx + rad):
                if (x - cx) ** 2 + (y - cy) ** 2 < rad * rad * rng.uniform(0.6, 1.0):
                    img[y % 128, x % 128] *= 0.72
    for y in range(70, 100):  # patched pothole
        for x in range(20, 52):
            img[y, x] = rgb("#2a2a2f") * rng.uniform(0.95, 1.04)
    for _ in range(4):
        walk(rng, img, rng.randrange(128), rng.randrange(128), 60, base * 0.55)
    return img


def shutter_texture(seed):
    """192 x 128 for the 3 x 2 m roll-down shutter: ribbed steel, rust, a tag."""
    rng = random.Random(seed)
    w, h = 192, 128
    img = np.zeros((h, w, 3))
    base = rgb("#69727c")
    for y in range(h):
        k = 0.7 if y % 5 == 0 else 1.12 if y % 5 == 1 else 1.0
        for x in range(w):
            img[y, x] = base * k * rng.uniform(0.96, 1.03)
    for _ in range(18):  # rust streaks
        x = rng.randrange(w)
        top = rng.randrange(h // 3, h)
        for y in range(top - rng.randrange(8, 40), top):
            if 0 <= y:
                img[y, x] = img[y, x] * 0.6 + rgb("#7a4a2a") * 0.4
    # Graffiti tag "KRAK": slanted glyph strokes, dark outline, yellow rim, pink fill, drips.
    x0, y0, gw, gh, slant = 34, 58, 26, 36, 0.3
    layers = ((rgb("#16121c"), 4.2), (rgb("#f0d040"), 3.0), (rgb("#e8409c"), 1.6))
    for color, radius in layers:
        for i, ch in enumerate("KRAK"):
            for line in TAG_GLYPHS[ch]:
                pts = [(x0 + i * (gw + 8) + px * gw + py * gh * slant, y0 + py * gh) for px, py in line]
                stroke(img, pts, radius, color)
    for _ in range(6):
        x = rng.randrange(x0, x0 + 4 * (gw + 8))
        for y in range(y0 - rng.randrange(6, 20), y0 + 2):
            img[max(y, 0), x] = rgb("#e8409c")
    for y in range(24):
        img[y] *= 1.0 - 0.4 * (1.0 - y / 24)
    return img


def poster_texture(seed):
    """48 x 64 = 0.75 x 1 m of layered, torn bill posters."""
    rng = random.Random(seed)
    img = np.zeros((64, 48, 3))
    img[:] = rgb("#5a5048")
    colors = ["#c8b890", "#d04030", "#3060a0", "#e0d8c8", "#e0a020", "#40904a"]
    for _ in range(6):
        x0, y0 = rng.randrange(-8, 36), rng.randrange(-8, 50)
        pw, ph = rng.randrange(14, 26), rng.randrange(18, 30)
        c = rgb(rng.choice(colors))
        ink = rgb("#201c1c")
        for y in range(y0, y0 + ph):
            for x in range(x0, x0 + pw):
                if 0 <= x < 48 and 0 <= y < 64:
                    torn = y < y0 + 3 and rng.random() < 0.4
                    if torn:
                        continue
                    line = (y - y0) % 4 == 0 and y < y0 + ph // 2 and x0 + 2 < x < x0 + pw - 3
                    img[y, x] = ink if line else c * rng.uniform(0.9, 1.03)
        # Big headline block.
        for y in range(y0 + ph - 7, y0 + ph - 3):
            for x in range(x0 + 2, x0 + pw - 2):
                if 0 <= x < 48 and 0 <= y < 64 and rng.random() < 0.8:
                    img[y, x] = ink
    return img


def image(name, pixels):
    h, w, _ = pixels.shape
    im = bpy.data.images.new(name, w, h, alpha=False)
    rgba = np.ones((h, w, 4))
    rgba[..., :3] = np.clip(pixels, 0.0, 1.0)
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.pack()
    return im


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

class Mat:
    """A Blender material plus how its UVs are projected: one texture repeat every
    `tile` meters (u, v), shifted by `origin` (meters)."""

    def __init__(self, name, color="#ffffff", texture=None, tile=(1.0, 1.0), origin=(0.0, 0.0),
                 emission=None, smooth=False):
        self.tile, self.origin, self.smooth = tile, origin, smooth
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nodes = m.node_tree.nodes
        bsdf = nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Metallic"].default_value = 0.0
        lin = (*srgb_to_linear(rgb(color)), 1.0)
        bsdf.inputs["Base Color"].default_value = lin
        m.diffuse_color = lin
        if texture is not None:
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = texture
            tex.interpolation = "Closest"
            m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if emission is not None:
            bsdf.inputs["Emission Color"].default_value = (*srgb_to_linear(rgb(emission)), 1.0)
            bsdf.inputs["Emission Strength"].default_value = 1.0
        self.material = m


# ---------------------------------------------------------------------------
# Geometry, accumulated in Godot coordinates
# ---------------------------------------------------------------------------

class Mesh:
    def __init__(self):
        self.verts = []
        self.faces = []  # (vertex indices, Mat, smooth)

    def add(self, verts, faces, mat, xf=None, smooth=None):
        xf = xf or Matrix.Identity(4)
        base = len(self.verts)
        self.verts.extend(xf @ Vector(v) for v in verts)
        for f in faces:
            self.faces.append(([base + i for i in f], mat, mat.smooth if smooth is None else smooth))

    def build(self, name):
        mats = []
        for _, m, _ in self.faces:
            if m not in mats:
                mats.append(m)
        me = bpy.data.meshes.new(name)
        me.from_pydata([(v.x, -v.z, v.y) for v in self.verts], [], [f for f, _, _ in self.faces])
        for m in mats:
            me.materials.append(m.material)
        uv = me.uv_layers.new(name="UVMap")
        for poly, (idx, m, smooth) in zip(me.polygons, self.faces):
            poly.material_index = mats.index(m)
            poly.use_smooth = smooth
            pts = [self.verts[i] for i in idx]
            n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
            axis = max(range(3), key=lambda a: abs(n[a]))
            for loop_index, p in zip(poly.loop_indices, pts):
                if axis == 2:
                    u, v = (p.x if n.z > 0 else -p.x), p.y
                elif axis == 0:
                    u, v = (-p.z if n.x > 0 else p.z), p.y
                else:
                    u, v = p.x, -p.z
                uv.data[loop_index].uv = ((u - m.origin[0]) / m.tile[0], (v - m.origin[1]) / m.tile[1])
        me.validate()
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# Counter-clockwise seen from outside (glTF front faces).
BOX_FACES = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (2, 6, 7, 3), (1, 5, 6, 2), (0, 3, 7, 4)]


def box(mesh, mat, lo, hi, xf=None):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1),
             (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]
    mesh.add(verts, BOX_FACES, mat, xf)


def lathe(mesh, mat, profile, seg=12, xf=None, smooth=None, phase=0.0):
    """Surface of revolution around local +Y; profile = [(radius, y)], radius 0 = pole."""
    verts, rings = [], []
    for r, y in profile:
        if r == 0:
            rings.append([len(verts)])
            verts.append((0.0, y, 0.0))
        else:
            ring = []
            for i in range(seg):
                a = phase + 2 * math.pi * i / seg
                ring.append(len(verts))
                verts.append((r * math.cos(a), y, -r * math.sin(a)))
            rings.append(ring)
    faces = []
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1:
                faces.append((a[0], b[j], b[i]))
            elif len(b) == 1:
                faces.append((a[i], a[j], b[0]))
            else:
                faces.append((a[i], a[j], b[j], b[i]))
    mesh.add(verts, faces, mat, xf, smooth)


def cylinder(mesh, mat, a, b, radius, seg=10, smooth=None):
    """Capped cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    xf = Matrix.Translation(a) @ rot
    lathe(mesh, mat, [(0, 0), (radius, 0), (radius, d.length), (0, d.length)], seg, xf, smooth)


def pipe(mesh, mat, flange_mat, points, radius, flanges_every=1.4):
    """Pipe through `points` with flanges at the bends, ends and along long runs."""
    pts = [Vector(p) for p in points]
    joints = list(pts)
    for a, b in zip(pts, pts[1:]):
        cylinder(mesh, mat, a, b, radius)
        n = int((b - a).length // flanges_every)
        joints.extend(a.lerp(b, (i + 1) / (n + 1)) for i in range(n))
    for i, p in enumerate(pts):
        if 0 < i < len(pts) - 1:
            lathe(mesh, mat, [(0, -radius), (radius * 0.7, -radius * 0.7), (radius, 0),
                              (radius * 0.7, radius * 0.7), (0, radius)], 10, Matrix.Translation(p))
    for j in joints:
        # Orient the flange along the segment it sits on.
        seg_dir = None
        for a, b in zip(pts, pts[1:]):
            ab = b - a
            t = (j - a).dot(ab) / ab.length_squared
            if -1e-6 <= t <= 1 + 1e-6 and (a + ab * t - j).length < 1e-4:
                seg_dir = ab.normalized()
                break
        h = radius * 0.5
        cylinder(mesh, flange_mat, j - seg_dir * h, j + seg_dir * h, radius * 1.4)


def lump(mesh, mat, center, radii, seed, rings=5, seg=8):
    """Lumpy blob (trash bag): a UV sphere with random radial noise, flattened base."""
    rng = random.Random(seed)
    profile = []
    for i in range(rings + 1):
        t = math.pi * i / rings
        profile.append((math.sin(t), -math.cos(t)))
    verts, faces = [], []
    grid = []
    for i, (r, y) in enumerate(profile):
        row = []
        if r < 1e-6:
            row = [len(verts)] * seg
            verts.append((0.0, max(y, -0.6) * radii[1], 0.0))
        else:
            for k in range(seg):
                a = 2 * math.pi * k / seg
                n = rng.uniform(0.82, 1.12)
                row.append(len(verts))
                verts.append((r * math.cos(a) * radii[0] * n, max(y, -0.6) * radii[1] * n,
                              r * math.sin(a) * radii[2] * n))
        grid.append(row)
    for a, b in zip(grid, grid[1:]):
        for k in range(seg):
            q = (a[k], b[k], b[(k + 1) % seg], a[(k + 1) % seg])
            faces.append(tuple(dict.fromkeys(q)))
    xf = Matrix.Translation(center) @ Matrix.Rotation(rng.uniform(0, 6.28), 4, "Y")
    mesh.add(verts, [f for f in faces if len(f) >= 3], mat, xf, smooth=True)


def quad_z(mesh, mat, x0, y0, x1, y1, z):
    """Camera-facing rectangle at depth z."""
    mesh.add([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], [(0, 1, 2, 3)], mat)


def flat_blob(mesh, mat, cx, cz, rx, rz, y, seed, seg=14):
    """Irregular horizontal patch (puddle) at height y."""
    rng = random.Random(seed)
    verts = [(cx, y, cz)]
    for k in range(seg):
        a = 2 * math.pi * k / seg
        n = rng.uniform(0.7, 1.1)
        verts.append((cx + math.cos(a) * rx * n, y, cz - math.sin(a) * rz * n))
    mesh.add(verts, [(0, k + 1, (k + 1) % seg + 1) for k in range(seg)], mat)


def marker(name, pos, direction=(0, 1, 0), scale=1.0):
    """Empty for a steam emitter: Godot +Y of the empty points along `direction`."""
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "SINGLE_ARROW"
    bpy.context.scene.collection.objects.link(obj)
    d = Vector(direction).normalized()
    b_dir = Vector((d.x, -d.z, d.y))
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(b_dir)
    obj.location = (pos[0], -pos[2], pos[1])
    obj.scale = (scale, scale, scale)
    return obj


# Tiny 3x5 pixel font for neon signs (rows top to bottom).
FONT = {
    "L": ["X..", "X..", "X..", "X..", "XXX"],
    "I": ["XXX", ".X.", ".X.", ".X.", "XXX"],
    "Q": ["XXX", "X.X", "X.X", "XXX", "..X"],
    "U": ["X.X", "X.X", "X.X", "X.X", "XXX"],
    "O": ["XXX", "X.X", "X.X", "X.X", "XXX"],
    "R": ["XX.", "X.X", "XX.", "X.X", "X.X"],
    "H": ["X.X", "X.X", "XXX", "X.X", "X.X"],
    "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
    "E": ["XXX", "X..", "XX.", "X..", "XXX"],
}


def neon_text(mesh, text, mats, x, y, z, px=0.055):
    """Neon lettering, left edge x, top y; `mats` is one Mat per letter (dead tubes)."""
    for i, ch in enumerate(text):
        for row, line in enumerate(FONT[ch]):
            for col, c in enumerate(line):
                if c == "X":
                    x0 = x + (i * 4 + col) * px
                    y0 = y - (row + 1) * px
                    box(mesh, mats[i], (x0, y0, z), (x0 + px, y0 + px, z + 0.03))


# ---------------------------------------------------------------------------
# The street
# ---------------------------------------------------------------------------

def build_street(M):
    mesh = Mesh()
    rng = random.Random(SEED)
    FACADE = -3.0  # building fronts

    # --- ground ---------------------------------------------------------------
    box(mesh, M["asphalt"], (-7.5, -0.3, -1.35), (7.5, 0.0, 6.5))
    box(mesh, M["concrete"], (-7.5, 0.0, -3.0), (7.5, 0.15, -1.5))
    box(mesh, M["curb"], (-7.5, 0.0, -1.5), (7.5, 0.16, -1.35))
    box(mesh, M["dark"], (-3.9, 0.02, -1.351), (-3.2, 0.11, -1.349))  # storm drain mouth
    for i in range(6):
        x = -3.85 + i * 0.12
        box(mesh, M["iron"], (x, 0.02, -1.35), (x + 0.03, 0.11, -1.34))
    # Faded double yellow line, gaps where it has worn off.
    for lane_z in (2.9, 3.1):
        x = -7.5
        while x < 7.5:
            length = rng.uniform(0.6, 2.2)
            if rng.random() < 0.8:
                box(mesh, M["paint_yellow"], (x, 0.0, lane_z), (min(x + length, 7.5), 0.004, lane_z + 0.09))
            x += length + rng.uniform(0.0, 0.25)
    # Manhole (steams).
    lathe(mesh, M["iron"], [(0.37, 0.0), (0.36, 0.012), (0, 0.012)], 16, Matrix.Translation((2.6, 0, -0.75)))
    lathe(mesh, M["iron_dark"], [(0.28, 0.0), (0.28, 0.016), (0.2, 0.016)], 16,
          Matrix.Translation((2.6, 0, -0.75)))
    marker("steam_manhole", (2.6, 0.02, -0.75), scale=1.2)
    # Puddles reflecting the lamp.
    for cx, cz, rx, rz, seed in ((-1.2, 1.0, 0.7, 0.35, 3), (4.3, 2.1, 0.5, 0.3, 4), (-5.0, 3.6, 0.9, 0.4, 5)):
        flat_blob(mesh, M["puddle"], cx, cz, rx, rz, 0.003, seed)
        flat_blob(mesh, M["puddle_shine"], cx + rx * 0.15, cz - rz * 0.1, rx * 0.45, rz * 0.35, 0.005, seed + 50)

    # --- building A (left, brick, tall) ----------------------------------------
    box(mesh, M["brick_red"], (-7.5, 0.0, -10.0), (-0.9, 6.0, FACADE))
    # Concrete base course.
    box(mesh, M["trim"], (-7.5, 0.15, FACADE), (-0.9, 0.35, FACADE + 0.04))
    # Storefront: roll-down shutter, rails, housing.
    box(mesh, M["shutter"], (-5.2, 0.15, FACADE), (-2.4, 2.05, FACADE + 0.03))
    for x in (-5.3, -2.4):
        box(mesh, M["steel_dark"], (x, 0.15, FACADE), (x + 0.1, 2.1, FACADE + 0.07))
    box(mesh, M["steel_dark"], (-5.35, 2.05, FACADE), (-2.25, 2.18, FACADE + 0.14))
    # LIQUOR sign; the Q has died.
    box(mesh, M["sign"], (-5.05, 2.2, FACADE), (-2.55, 2.68, FACADE + 0.12))
    neon = [M["neon_pink"]] * 6
    neon[2] = M["neon_dead"]
    neon_text(mesh, "LIQUOR", neon, -4.58, 2.6, FACADE + 0.12, px=0.065)
    # Barred window.
    box(mesh, M["frame"], (-2.1, 0.95, FACADE), (-1.3, 2.05, FACADE + 0.05))
    box(mesh, M["glass"], (-2.04, 1.01, FACADE), (-1.36, 1.99, FACADE + 0.06))
    box(mesh, M["trim"], (-2.16, 0.9, FACADE), (-1.24, 0.97, FACADE + 0.1))
    for i in range(5):
        x = -2.02 + i * 0.15
        box(mesh, M["steel_dark"], (x, 0.97, FACADE + 0.07), (x + 0.03, 2.05, FACADE + 0.1))
    # Upper floor windows (only their lower halves are on screen).
    for i, x in enumerate((-5.6, -3.9, -2.2)):
        lit = i == 1
        box(mesh, M["trim"], (x - 0.08, 3.2, FACADE), (x + 0.88, 3.28, FACADE + 0.1))
        box(mesh, M["frame"], (x, 3.28, FACADE), (x + 0.8, 4.6, FACADE + 0.04))
        box(mesh, M["window_lit" if lit else "glass"], (x + 0.06, 3.34, FACADE), (x + 0.74, 4.54, FACADE + 0.05))
        if not lit:  # half-drawn blind
            box(mesh, M["blind"], (x + 0.06, 3.6, FACADE), (x + 0.74, 4.54, FACADE + 0.055))
    # Steam main along the facade, down the alley corner; leaks at a flange.
    pipe(mesh, M["pipe"], M["flange"], [(-7.5, 3.05, -2.86), (-1.06, 3.05, -2.86), (-1.06, 0.15, -2.86)], 0.07)
    for x in (-6.2, -4.6, -3.0, -1.7):
        box(mesh, M["steel_dark"], (x, 2.96, FACADE), (x + 0.05, 3.0, -2.84))
    marker("steam_leak", (-3.25, 3.1, -2.8), (0.3, 1, 0.6), 0.8)
    # Valve wheel on the down pipe.
    wheel = Matrix.Translation((-1.06, 1.25, -2.76)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    ring = [(0.13 + 0.022 * math.cos(a), 0.022 * math.sin(a))
            for a in (2 * math.pi * k / 6 for k in range(7))]
    lathe(mesh, M["valve"], ring, 14, wheel)
    for a in (0, math.pi / 2):
        box(mesh, M["valve"], (-0.13, -0.012, -0.012), (0.13, 0.012, 0.012),
            wheel @ Matrix.Rotation(a, 4, "Y"))
    cylinder(mesh, M["flange"], (-1.06, 1.25, -2.86), (-1.06, 1.25, -2.74), 0.025)
    # Gas line with a meter.
    pipe(mesh, M["gas"], M["flange"], [(-5.7, 0.15, -2.93), (-5.7, 4.5, -2.93)], 0.035, 1.6)
    box(mesh, M["meter"], (-5.9, 0.75, FACADE), (-5.5, 1.15, -2.82))
    box(mesh, M["glass"], (-5.82, 0.9, -2.82), (-5.58, 1.07, -2.815))

    # --- alley -----------------------------------------------------------------
    box(mesh, M["asphalt"], (-0.9, 0.0, -10.0), (0.9, 0.13, FACADE))
    box(mesh, M["brick_dark"], (-1.2, 0.0, -10.6), (1.2, 2.0, -10.0))
    quad_z(mesh, M["door_glow"], -0.25, 0.13, 0.25, 1.25, -9.99)
    box(mesh, M["frame"], (-0.32, 1.25, -10.0), (0.32, 1.32, -9.97))
    box(mesh, M["lamp_glow"], (-0.07, 1.42, -10.0), (0.07, 1.52, -9.92))
    # Dumpster.
    box(mesh, M["dumpster"], (-0.75, 0.2, -7.2), (0.55, 1.15, -6.2))
    box(mesh, M["dumpster_lid"], (-0.8, 1.15, -7.25), (0.6, 1.22, -6.15),
        Matrix.Translation((0, 1.15, -6.2)) @ Matrix.Rotation(0.12, 4, "X") @ Matrix.Translation((0, -1.15, 6.2)))
    for x in (-0.6, 0.35):
        box(mesh, M["dark"], (x, 0.13, -6.4), (x + 0.1, 0.2, -6.3))
    box(mesh, M["paint_white"], (-0.5, 0.6, -6.2), (0.25, 0.75, -6.19))
    # Steaming grate in the alley floor.
    box(mesh, M["iron_dark"], (-0.35, 0.13, -4.7), (0.35, 0.14, -4.2))
    marker("steam_grate", (0.0, 0.15, -4.45), scale=1.0)
    lump(mesh, M["bag_black"], (0.55, 0.13, -5.4), (0.25, 0.3, 0.22), 11)

    # --- building B (right, single storey, painted brick) ----------------------
    box(mesh, M["brick_dark"], (0.9, 0.0, -4.5), (7.5, 2.9, FACADE))
    box(mesh, M["roof"], (0.9, 2.9, -4.5), (7.5, 2.95, FACADE))
    box(mesh, M["trim"], (0.85, 2.88, FACADE - 0.05), (7.5, 3.02, FACADE + 0.07))
    # Steel door, step and caged light.
    box(mesh, M["frame"], (1.45, 0.15, FACADE), (2.45, 2.25, FACADE + 0.05))
    box(mesh, M["door"], (1.53, 0.15, FACADE), (2.37, 2.17, FACADE + 0.07))
    box(mesh, M["glass"], (1.8, 1.45, FACADE), (2.1, 1.85, FACADE + 0.075))
    box(mesh, M["steel_dark"], (2.2, 1.0, FACADE + 0.07), (2.3, 1.06, FACADE + 0.12))
    box(mesh, M["concrete"], (1.35, 0.15, FACADE), (2.55, 0.3, FACADE + 0.35))
    box(mesh, M["lamp_glow"], (1.88, 2.34, FACADE), (2.02, 2.48, FACADE + 0.1))
    for x in (1.86, 1.935, 2.01):
        box(mesh, M["steel_dark"], (x, 2.32, FACADE + 0.1), (x + 0.02, 2.5, FACADE + 0.12))
    box(mesh, M["steel_dark"], (1.84, 2.48, FACADE), (2.06, 2.52, FACADE + 0.12))
    # Posters.
    box(mesh, M["posters"], (2.65, 0.85, FACADE), (3.15, 1.65, FACADE + 0.01))
    # Barred window, dark.
    box(mesh, M["frame"], (3.35, 1.0, FACADE), (4.45, 2.1, FACADE + 0.05))
    box(mesh, M["glass"], (3.41, 1.06, FACADE), (4.39, 2.04, FACADE + 0.06))
    box(mesh, M["blind"], (3.41, 1.55, FACADE), (4.39, 2.04, FACADE + 0.065))
    box(mesh, M["trim"], (3.3, 0.95, FACADE), (4.5, 1.02, FACADE + 0.1))
    for i in range(7):
        x = 3.42 + i * 0.155
        box(mesh, M["steel_dark"], (x, 1.02, FACADE + 0.07), (x + 0.03, 2.1, FACADE + 0.1))
    # Drainpipe with a shoe at the bottom.
    pipe(mesh, M["drain"], M["drain"], [(4.85, 2.95, -2.94), (4.85, 0.35, -2.94), (4.85, 0.2, -2.75)], 0.05, 9)
    # Low steam line out of the wall, up into a capped stack.
    pipe(mesh, M["pipe"], M["flange"], [(7.5, 0.55, -2.88), (5.5, 0.55, -2.88), (5.5, 1.3, -2.88)], 0.065)
    lathe(mesh, M["flange"], [(0, 1.3), (0.12, 1.3), (0.12, 1.36), (0, 1.44)], 12,
          Matrix.Translation((5.5, 0.04, -2.88)))
    marker("steam_stack", (5.5, 1.36, -2.88), (0.15, 1, 0.2), 0.9)
    # Electrical box with conduit.
    box(mesh, M["meter"], (5.85, 1.4, FACADE), (6.25, 1.95, FACADE + 0.15))
    cylinder(mesh, M["steel_dark"], (6.0, 1.95, -2.94), (6.0, 2.9, -2.94), 0.025)
    # Rooftop: AC unit and a steaming vent stack.
    box(mesh, M["metal"], (3.9, 2.95, -4.2), (4.75, 3.45, -3.55))
    for i in range(4):
        y = 3.05 + i * 0.1
        box(mesh, M["dark"], (3.98, y, -3.55), (4.67, y + 0.04, -3.54))
    cylinder(mesh, M["pipe"], (2.3, 2.95, -3.7), (2.3, 3.4, -3.7), 0.09)
    lathe(mesh, M["flange"], [(0, 3.4), (0.16, 3.4), (0.16, 3.45), (0, 3.52)], 12, Matrix.Translation((2.3, 0.05, -3.7)))
    marker("steam_roof", (2.3, 3.45, -3.7), scale=1.3)

    # --- skyline (sized for the tilted ortho camera, see module doc) -----------
    x = -1.5
    while x < 7.5:
        w = rng.uniform(0.9, 2.2)
        # Keep the moon in a clear patch of sky.
        top = 1.3 if x < MOON_X + 0.5 and x + w > MOON_X - 0.5 else rng.uniform(1.5, 2.15)
        box(mesh, M["skyline"], (x, 0.0, -13.6), (x + w, top, -13.0))
        for wy in np.arange(0.9, top - 0.1, 0.14):
            for wx in np.arange(x + 0.12, x + w - 0.12, 0.16):
                if rng.random() < 0.18:
                    box(mesh, M["sky_window"], (wx, wy, -13.0), (wx + 0.06, wy + 0.07, -12.99))
        x += w + rng.uniform(-0.2, 0.3)
    x = -2.0
    while x < 8.0:
        w = rng.uniform(1.2, 2.8)
        far_top = 0.3 if x < MOON_X + 0.5 and x + w > MOON_X - 0.5 else rng.uniform(0.5, 0.95)
        box(mesh, M["skyline_far"], (x, 0.0, -18.6), (x + w, far_top, -18.0))
        x += w + rng.uniform(-0.3, 0.1)
    # City glow on the horizon, banded.
    quad_z(mesh, M["haze_low"], -8, -1.2, 8, -0.05, -24.0)
    quad_z(mesh, M["haze_high"], -8, -0.05, 8, 0.6, -24.1)
    # Moon, just below the top of the screen.
    lathe(mesh, M["moon"], [(0, 0), (0.17, 0)], 14,
          Matrix.Translation((MOON_X, -0.11, -22.0)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))

    # --- street furniture ------------------------------------------------------
    # Street lamp (Stage/StreetLamp in main.tscn sits just under its lens).
    lathe(mesh, M["lamp_post"], [(0, 0.15), (0.12, 0.15), (0.12, 0.45), (0.06, 0.55), (0.05, 3.3), (0, 3.3)],
          10, Matrix.Translation((-2.25, 0, -1.75)))
    box(mesh, M["lamp_post"], (-2.45, 3.28, -2.0), (-1.95, 3.4, -1.45))
    box(mesh, M["lamp_glow"], (-2.37, 3.2, -1.9), (-2.03, 3.28, -1.55))
    # Hydrant.
    hx, hz = 3.0, -1.9
    lathe(mesh, M["hydrant"], [(0, 0), (0.13, 0), (0.13, 0.06), (0.09, 0.08), (0.09, 0.48), (0.12, 0.5),
                               (0.12, 0.55), (0.08, 0.62), (0.03, 0.66), (0, 0.66)], 10,
          Matrix.Translation((hx, 0.15, hz)))
    for s in (-1, 1):
        cylinder(mesh, M["hydrant"], (hx, 0.45, hz), (hx + s * 0.17, 0.45, hz), 0.04, 8)
    cylinder(mesh, M["hydrant"], (hx, 0.4, hz), (hx, 0.4, hz + 0.18), 0.055, 8)
    # Trash cans: galvanized, ribbed.
    can = [(0, 0.0), (0.25, 0.0), (0.255, 0.15), (0.27, 0.16), (0.27, 0.19), (0.258, 0.2),
           (0.265, 0.42), (0.28, 0.43), (0.28, 0.46), (0.268, 0.47), (0.278, 0.7), (0.29, 0.71),
           (0.29, 0.76), (0.272, 0.77), (0.272, 0.76), (0, 0.76)]
    lid = [(0, 0.77), (0.305, 0.77), (0.3, 0.795), (0.22, 0.83), (0.08, 0.875), (0, 0.88)]

    def trash_can(x, z, yaw, lid_xf=None, mat="can"):
        xf = Matrix.Translation((x, 0.15, z)) @ Matrix.Rotation(yaw, 4, "Y")
        lathe(mesh, M[mat], can, 12, xf)
        lxf = xf @ (lid_xf or Matrix.Identity(4))
        lathe(mesh, M["can_lid"], lid, 12, lxf)
        box(mesh, M["iron_dark"], (-0.07, 0.88, -0.02), (0.07, 0.92, 0.02), lxf)
        for s in (-1, 1):
            box(mesh, M["iron_dark"], (s * 0.3 - 0.03, 0.58, -0.05), (s * 0.3 + 0.03, 0.62, 0.05), xf)

    trash_can(-4.75, -2.45, 0.2)
    ajar = Matrix.Translation((0.12, 0.05, 0.08)) @ Matrix.Rotation(0.35, 4, "Z")
    trash_can(-4.08, -2.55, 0.9, ajar, mat="can_rusty")
    lump(mesh, M["bag_black"], (-4.08, 0.85, -2.55), (0.2, 0.15, 0.2), 12)
    trash_can(4.35, -2.45, 0.5)
    for i, (x, z, r) in enumerate([(-3.5, -2.4, 0.3), (-3.15, -2.65, 0.26), (-5.3, -2.35, 0.28),
                                   (-3.4, -2.75, 0.22), (4.95, -2.4, 0.27)]):
        lump(mesh, M["bag_green" if i % 2 else "bag_black"], (x, 0.15, z), (r, r * 0.95, r * 0.9), 20 + i)
    # Knocked-over can rolled into the gutter, lid and garbage spilled on the road.
    fallen = (Matrix.Translation((5.05, 0.29, -0.95)) @ Matrix.Rotation(0.5, 4, "Y")
              @ Matrix.Rotation(-math.pi / 2, 4, "Z") @ Matrix.Translation((0, -0.38, 0)))
    lathe(mesh, M["can"], can, 12, fallen)
    lathe(mesh, M["can_lid"], lid, 12, Matrix.Translation((4.15, -0.77, -0.55)) @ Matrix.Rotation(0.15, 4, "X"))
    for k in range(9):
        px = 5.3 + rng.uniform(-0.5, 0.6)
        pz = -0.75 + rng.uniform(-0.3, 0.45)
        s = rng.uniform(0.05, 0.11)
        mat = M[rng.choice(["paper", "paper", "cardboard", "can_red"])]
        box(mesh, mat, (-s, 0.0, -s * 0.7), (s, s * 0.4, s * 0.7),
            Matrix.Translation((px, 0, pz)) @ Matrix.Rotation(rng.uniform(0, 3), 4, "Y"))
    # Cardboard boxes by the window.
    box(mesh, M["cardboard"], (-1.95, 0.15, -2.95), (-1.35, 0.6, -2.45))
    box(mesh, M["cardboard_dark"], (-1.85, 0.6, -2.9), (-1.42, 0.92, -2.55),
        Matrix.Translation((-1.63, 0, -2.72)) @ Matrix.Rotation(0.3, 4, "Y") @ Matrix.Translation((1.63, 0, 2.72)))

    return mesh.build("street")


def build_wall(M):
    """Brick pillar for one stage wall: inner face at x = 0, extending to +x (the right
    wall; Stage mirrors it for the left). Matches Stage.WALL_THICKNESS = 0.5."""
    mesh = Mesh()
    box(mesh, M["brick_pillar"], (0.0, -0.3, -3.0), (0.5, 8.0, 6.5))
    box(mesh, M["trim"], (-0.03, -0.3, 6.5), (0.5, 0.4, 6.56))
    pipe(mesh, M["drain"], M["drain"], [(0.22, 0.0, 6.6), (0.22, 8.0, 6.6)], 0.05, 1.7)
    return mesh.build("wall")


def export(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_animations=False,
        export_morph=False,
        export_lights=False,
        export_cameras=False,
    )
    print(f"wrote {path}")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    T = {
        "brick_red": image("brick_red", brick_texture(
            256, ["#7a3428", "#8a3c2c", "#6c2e26", "#904a34", "#5e2a24"], "#3a2c28", SEED)),
        "brick_dark": image("brick_dark", brick_texture(
            256, ["#5a4a44", "#4e423e", "#66524a", "#584640"], "#2c2624", SEED + 1,
            paint=("#3c5446", 70))),
        "brick_pillar": image("brick_pillar", brick_texture(
            256, ["#4a2a26", "#542e28", "#40262a"], "#221a1a", SEED + 2, grime_px=80)),
        "concrete": image("concrete", concrete_texture(SEED)),
        "asphalt": image("asphalt", asphalt_texture(SEED)),
        "shutter": image("shutter", shutter_texture(SEED)),
        "posters": image("posters", poster_texture(SEED)),
    }
    M = {
        "brick_red": Mat("brick_red", texture=T["brick_red"], tile=(4, 4)),
        "brick_dark": Mat("brick_dark", texture=T["brick_dark"], tile=(4, 4)),
        "brick_pillar": Mat("brick_pillar", texture=T["brick_pillar"], tile=(4, 4)),
        "concrete": Mat("concrete", texture=T["concrete"], tile=(1, 1)),
        "asphalt": Mat("asphalt", texture=T["asphalt"], tile=(2, 2)),
        "shutter": Mat("shutter", texture=T["shutter"], tile=(3.0, 2.0), origin=(-5.3, 0.1)),
        "posters": Mat("posters", texture=T["posters"], tile=(0.5, 0.8), origin=(2.65, 0.85)),
        "curb": Mat("curb", "#8c877c"),
        "trim": Mat("trim", "#6e685e"),
        "dark": Mat("dark", "#141416"),
        "iron": Mat("iron", "#3e3a36"),
        "iron_dark": Mat("iron_dark", "#2a2725"),
        "paint_yellow": Mat("paint_yellow", "#a88c34"),
        "paint_white": Mat("paint_white", "#b8b4a8"),
        "puddle": Mat("puddle", "#323c54"),
        "puddle_shine": Mat("puddle_shine", "#56668c"),
        "steel_dark": Mat("steel_dark", "#2e3236"),
        "metal": Mat("metal", "#7c8288"),
        "sign": Mat("sign", "#1c1a24"),
        "neon_pink": Mat("neon_pink", "#ff4aa8", emission="#ff3a9c"),
        "neon_dead": Mat("neon_dead", "#4a2a3a"),
        "frame": Mat("frame", "#2a2420"),
        "glass": Mat("glass", "#1c2a34"),
        "blind": Mat("blind", "#8a8070"),
        "window_lit": Mat("window_lit", "#402c10", emission="#e8b048"),
        "door_glow": Mat("door_glow", "#402c10", emission="#f0b850"),
        "lamp_glow": Mat("lamp_glow", "#403010", emission="#ffc870"),
        "pipe": Mat("pipe", "#8a5a3a"),
        "flange": Mat("flange", "#4a3c34"),
        "gas": Mat("gas", "#c0a030"),
        "valve": Mat("valve", "#b02a22"),
        "meter": Mat("meter", "#6a6e66"),
        "drain": Mat("drain", "#585c60"),
        "roof": Mat("roof", "#2a2628"),
        "door": Mat("door", "#3c4a52"),
        "dumpster": Mat("dumpster", "#2f5a3c"),
        "dumpster_lid": Mat("dumpster_lid", "#244830"),
        "bag_black": Mat("bag_black", "#24252a", smooth=True),
        "bag_green": Mat("bag_green", "#2c3c2c", smooth=True),
        "can": Mat("can", "#808c8e"),
        "can_rusty": Mat("can_rusty", "#7a705e"),
        "can_lid": Mat("can_lid", "#9aa4a6"),
        "can_red": Mat("can_red", "#c03020"),
        "paper": Mat("paper", "#d8d4c4"),
        "cardboard": Mat("cardboard", "#9a7448"),
        "cardboard_dark": Mat("cardboard_dark", "#7a5a38"),
        "hydrant": Mat("hydrant", "#b02c22"),
        "lamp_post": Mat("lamp_post", "#2c3034"),
        "skyline": Mat("skyline", "#1e1c30"),
        "skyline_far": Mat("skyline_far", "#2a2440"),
        "sky_window": Mat("sky_window", "#302810", emission="#d8b060"),
        "haze_low": Mat("haze_low", "#000000", emission="#4a2c4a"),
        "haze_high": Mat("haze_high", "#000000", emission="#2c2040"),
        "moon": Mat("moon", "#000000", emission="#e8e0c8"),
    }
    street = build_street(M)
    markers = [o for o in bpy.data.objects if o.type == "EMPTY"]
    wall = build_wall(M)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "street.blend"), compress=True)
    export(os.path.join(OUT_DIR, "street.glb"), [street, *markers])
    export(os.path.join(OUT_DIR, "wall.glb"), [wall])
    print(f"street: {len(street.data.polygons)} faces, {len(markers)} steam markers")


main()
