# Building a character with kit.py

`kit.py` does the parts that are easy to get wrong: the skeleton, bone parenting, part names, colors, previews, export, and validation. You don't need to read it. It was run on the Blender 5.2.3 app and the PyPI `bpy` module 4.2.0, 4.4.0, 4.5.4, 5.0.0, and 5.1.0.

## Running scripts

- Headless: `blender -b --factory-startup --python build_character.py`. With the PyPI module: `python build_character.py`. Each `bpy` release supports one Python version: `bpy` 4.2–5.0 need Python 3.11, 5.1+ needs 3.13. With `bpy` 4.4 and NumPy 2, importing `bpy` prints a long `numpy.core.multiarray failed to import` traceback, but the build still finishes, previews included; `pip install "numpy<2"` removes the message.
- Start the script with the lines from `example_build_character.py`: Blender doesn't put the script's folder on `sys.path`.

## API

Coordinates are Blender world space in meters, the character in its T-pose: X = the character's left, −Y = forward (its face), Z = up, soles on Z = 0. Every part is a rigid mesh on one bone, named `<bone>_<what>`. Part functions return the new objects.

| Call                                                | Does                                                                                                                                                           |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `start()`                                           | Prints the Blender version, empties the scene, adds the template skeleton. Call it first.                                                                      |
| `material(name, "#rrggbb", glow=0)`                 | Opaque, matte material from an sRGB color. `glow` > 0 makes it emissive in its own color (eyes, lights). Parts take the material's name.                       |
| `head(bone)`, `tail(bone)`                          | The joint at the bone's start or end, as a `Vector` (SKELETON.md, "Bones").                                                                                    |
| `box(bone, what, mat, lo, hi)`                      | Box between two opposite corners.                                                                                                                              |
| `sphere(bone, what, mat, center, r)`                | Sphere; an ellipsoid if `r` is `(rx, ry, rz)`. About 170 triangles.                                                                                            |
| `cylinder(bone, what, mat, a, b, r, radius_b=None)` | Closed cylinder from point `a` to `b`; a cone if `radius_b` (the radius at `b`) differs.                                                                       |
| `capsule(bone, what, mat, a, b, r)`                 | Cylinder with a sphere on each end, about 380 triangles. From a limb's `head()` to its `tail()`, the end spheres cover the joints, so bent limbs show no gaps. |
| `part(bone, what, mat, bm)`                         | Any other shape: a `bmesh` you built in world space (below). Frees `bm`.                                                                                       |
| `finish(name, description)`                         | Prints the stats, renders `previews/sheet.png`, exports `<slug>.glb`, writes `<slug>.json`, and runs the game's validator. Call it last.                       |

- Every part function takes `mirror=True`: it adds the copy mirrored at −X, on the `.R` bone for a `.L` bone (or the other way round), else as `<bone>_<what>_L` and `_R` (eyes, ears, shoulder pads). Model the `.L` side (+X).
- Sphere, cylinder, and capsule take `segments=12`. Fewer segments mean fewer triangles.
- Each `what` must be unique on its bone (a repeat raises an error), and never use a bare bone name as a part name.
- Edges sharper than 45° shade flat, the rest smooth: boxes look crisp, spheres round.
- Errors name the problem: an unknown bone lists the bone names, an unknown material says to call `material()` first.

`finish()` output, in order:

- `stats:` lines (triangles, height, soles, body X/Y extents without the arms), each marked `<-- PROBLEM` when outside the limits in `PROMPT.md`.
- `previews: …/sheet.png`: a 3 × 2 grid. Top row: the T-pose. Bottom row: the test pose (arms swung forward, left knee bent). Columns: front, the character's left side (its front faces the image's left), and the front-left 3/4 view.
- `validator:` lines from the game's validator, then `RESULT: OK <path>` or `RESULT: FIX THE VALIDATOR PROBLEMS <path>`.

## Other shapes with bmesh

Build in world space, then hand the bmesh to `part()`. The parameters are `radius`, never `diameter` (that keyword was removed):

```python
import bmesh  # `from kit import *` gives math, Matrix, Quaternion, and Vector

bm = bmesh.new()
m = Matrix.Translation((0, 0.1, 1.3)) @ Matrix.Diagonal((0.3, 0.05, 0.4, 1.0))  # move @ scale
bmesh.ops.create_cube(bm, size=1.0, matrix=m)
bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.1, matrix=m)
bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=12,
                      radius1=0.1, radius2=0.0, depth=0.3, matrix=m)  # along Z, radius1 at -Z
verts = [bm.verts.new(p) for p in ((0, 0, 1.8), (0.1, 0, 1.9), (0, 0.1, 1.9))]
bm.faces.new(verts)  # custom faces: list vertices counter-clockwise seen from outside
part("chest", "cape", "cape", bm)
```

## mathutils

```python
Quaternion((0, 0, 1), math.radians(90))      # axis-angle: TWO arguments (axis, radians)
Matrix.Rotation(math.radians(30), 4, "X")    # angle, size, axis
Vector((0, 0, 1)).rotation_difference(d)     # Quaternion turning +Z onto direction d
```

`Matrix`, `Vector`, and `Quaternion` live in `mathutils`; `from bpy import Matrix` raises `ImportError`. `Quaternion(((0, 0, 1), angle))` (one tuple) raises `sequence length is 2, expected [3 - 4]`.

## Modifiers and textures

- Modifiers work on the returned objects: `obj = box(...)[0]; mod = obj.modifiers.new("bevel", type="BEVEL"); mod.width = 0.02; mod.segments = 2`. The export applies them and the stats count them, so watch the triangles. `"SUBSURF"` (`.levels`) multiplies triangles by 4 per level.
- A texture is rarely worth it at 97 px. If you need one: `img = bpy.data.images.load(path)`, a `ShaderNodeTexImage` node in `mat.node_tree` (`mat = material(...)`) with `.image = img`, linked with `mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])`, where `bsdf = mat.node_tree.nodes["Principled BSDF"]`.
- Don't touch `Alpha`, `Transmission Weight`, `blend_method`, or `surface_render_method`: the game needs opaque materials. It keeps only the base color (or texture) and the emission.
- Vertex colors: `mesh.color_attributes`, not `mesh.vertex_colors`. `mesh.use_auto_smooth` was removed in 4.1.
