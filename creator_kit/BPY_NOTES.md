# bpy notes for building a character

Use only the calls shown here, in these forms. Every snippet was run on Blender 4.2, 4.4, 4.5, 5.0, 5.1, and 5.2 (the app and the PyPI `bpy` module). Where versions differ, both forms are given. Print `bpy.app.version_string` at the start of every script so the log shows which rules apply.

## Running scripts

- Headless: `blender -b --factory-startup --python build_character.py`. Arguments for your script go after `--` (`... --python build_character.py -- out.glb`) and are read from `sys.argv[sys.argv.index("--") + 1:]`.
- Without Blender, the PyPI module works the same way: `python build_character.py`. Each `bpy` release supports one Python version: `bpy` 4.2–5.0 needs Python 3.11, and 5.1+ needs 3.13. With `bpy` 4.4, `numpy.core.multiarray failed to import` is printed at startup; it's harmless (or `pip install "numpy<2"`).
- **Import `bpy` before `bmesh`.** In the PyPI module, `import bmesh` fails with `No module named 'bmesh'` until `bpy` is imported.
- Blender doesn't put the script's folder on `sys.path`. To import `export_glb.py`:

  ```python
  KIT = os.path.dirname(os.path.abspath(__file__))
  sys.path.insert(0, KIT)
  sys.dont_write_bytecode = True  # no __pycache__ in the kit folder
  from export_glb import export_glb
  ```

- `bpy.ops.wm.open_mainfile(filepath=...)` replaces all data and the context. Look objects up again afterwards (`bpy.data.objects["Armature"]`); references from before are invalid.
- Never save over `template.blend`. If you want a `.blend` to inspect, save it under another name with `bpy.ops.wm.save_as_mainfile(filepath=...)`.

## Imports

```python
import math
import os
import sys

import bpy
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector
```

`Matrix`, `Vector`, `Euler`, and `Quaternion` live in `mathutils`. `from bpy import Matrix` raises `ImportError`.

## mathutils

```python
Quaternion((0, 0, 1), math.radians(90))          # axis-angle: TWO arguments (axis, radians)
Quaternion(Vector((0, 0, 1)), math.radians(90))  # same, with a Vector axis
Quaternion((1, 0, 0, 0))                         # raw w, x, y, z: ONE 4-sequence (identity)
Matrix.Translation((x, y, z))
Matrix.Rotation(math.radians(30), 4, "X")        # angle, size, axis
Matrix.Diagonal((sx, sy, sz, 1.0))               # 4x4 scale
Matrix.LocRotScale(Vector(loc), Quaternion(...), Vector(scale))
(target - cam.location).to_track_quat("-Z", "Y").to_euler()  # aim a camera at a point
```

`Quaternion(((0, 0, 1), angle))` (one tuple) raises `sequence length is 2, expected [3 - 4]`.

## Objects and meshes

Create meshes with `bmesh` and the data API. The parameters are `radius`, never `diameter` (that keyword was removed and raises `TypeError`):

```python
bm = bmesh.new()
m = Matrix.Translation(center) @ Matrix.Diagonal((*size, 1.0))
bmesh.ops.create_cube(bm, size=1.0, matrix=m)
bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.1, matrix=m)
bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.1, matrix=m)
bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=12,
                      radius1=0.1, radius2=0.05, depth=0.3, matrix=m)  # cylinder: radius1 == radius2
bmesh.ops.create_circle(bm, cap_ends=True, segments=12, radius=0.1, matrix=m)
me = bpy.data.meshes.new("chest_armor")
bm.to_mesh(me)
bm.free()
me.materials.append(mat)
obj = bpy.data.objects.new("chest_armor", me)
bpy.context.scene.collection.objects.link(obj)  # an unlinked object is not in the scene or the export
```

- `mesh.from_pydata(verts, edges, faces)` builds a mesh from lists. Call `mesh.update()` afterwards.
- Operators also work (`bpy.ops.mesh.primitive_cube_add(size=0.2, location=(0, 0, 1))`, `primitive_uv_sphere_add(radius=, segments=, ring_count=)`, `primitive_cylinder_add(vertices=, radius=, depth=)`). The new object is `bpy.context.active_object`, linked to the active collection.
- Smooth shading: `me.shade_smooth()` / `me.shade_flat()`. `mesh.use_auto_smooth` was removed in 4.1.
- Vertex colors: `mesh.color_attributes`. `mesh.vertex_colors` is the old API; don't use it.
- Modifiers: `obj.modifiers.new("bevel", type="BEVEL")` (`.width`, `.segments`), `"SUBSURF"` (`.levels`), `"MIRROR"`. The export applies them, so count triangles after modifiers:

  ```python
  dg = bpy.context.evaluated_depsgraph_get()
  tris = 0
  for o in bpy.context.scene.objects:
      if o.type == "MESH":
          m = o.evaluated_get(dg).to_mesh()
          m.calc_loop_triangles()
          tris += len(m.loop_triangles)
          o.evaluated_get(dg).to_mesh_clear()
  ```

- Names are unique per data type. Creating a second `"chest_armor"` gives `"chest_armor.001"`; check `obj.name` if you rely on it.
- Object selection is `obj.select_set(True)`. `obj.select = True` doesn't exist.
- Linking is `scene.collection.objects.link(obj)`. `scene.objects.link` doesn't exist.
- Updating is `bpy.context.view_layer.update()`. `scene.update()` doesn't exist.

## Parenting a part to a bone

Use the data API. `bpy.ops.object.parent_set(type="BONE")` depends on the active bone in the UI, which a headless script doesn't control.

```python
def parent_to_bone(obj, arm_obj, bone_name):
    bone = arm_obj.data.bones[bone_name]
    obj.parent = arm_obj
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    # Bone parenting places the child relative to the bone's TAIL. Cancel that so a mesh
    # modeled in world space stays where it was modeled.
    bone_tail = arm_obj.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0))
    obj.matrix_parent_inverse = bone_tail.inverted()
```

- Model each part's vertices in world space (meters, character at rest in T-pose) and leave the object's own location, rotation, and scale at identity. Then `parent_to_bone`. This is what `example_build_character.py` does.
- Without `matrix_parent_inverse`, every part jumps by its bone's tail position.
- Don't use `parent_type = "ARMATURE"`, an Armature modifier, or vertex groups. Parts are rigid.
- Part names: `<bone>_<what>`, e.g. `head_helmet`, `hand.L_glove`. Never the bare bone name (`head`).

## The armature is read-only

- `arm_obj.data.bones[name]` gives rest data (`head_local`, `tail_local`, `matrix_local`, `length`); it's read-only.
- `arm_obj.data.edit_bones` is empty outside Edit Mode. Never enter Edit Mode on the armature; never change `edit_bones` head, tail, roll, or parent.
- Never call `bpy.ops.pose.armature_apply()`. It bakes the current pose into the rest pose.
- Never move, rotate, or scale the `Armature` object.
- `pose_bone.rotate(...)`, `bone.rotate(...)`, and `bpy.types.Bone.Matrix` don't exist.

## Posing for previews

Pose bones rotate in their local axes on top of the rest pose (SKELETON.md, "Bone axes"). `rotation_mode` is `"QUATERNION"` by default. `export_glb()` resets every bone to rest and removes actions before exporting, so a test pose can't end up in the file.

```python
pb = arm_obj.pose.bones["upper_arm.L"]
pb.rotation_mode = "QUATERNION"
pb.rotation_quaternion = Quaternion((0, 0, 1), math.radians(-70))  # left arm swings forward
bpy.context.view_layer.update()
```

Signs, in Blender: torso, neck, and head bend forward around local +X. Thighs swing forward around −X, shins bend the knee around +X. The left arm swings forward around −Z and the right arm around +Z; both lower around −X.

## Materials

```python
m = bpy.data.materials.new("armor")
if bpy.app.version < (5, 0, 0):
    m.use_nodes = True  # 5.x: always on; setting it prints a DeprecationWarning
bsdf = m.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)  # LINEAR, not sRGB
bsdf.inputs["Roughness"].default_value = 1.0
bsdf.inputs["Metallic"].default_value = 0.0
m.diffuse_color = (r, g, b, 1.0)  # the color Workbench previews show
```

- Colors in Blender and glTF are linear. Convert a picked sRGB hex color with `c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4` per channel (see `srgb_to_linear` in the example).
- Principled BSDF input names since 4.0: `Base Color`, `Metallic`, `Roughness`, `Alpha`, `Emission Color`, `Emission Strength`, `Specular IOR Level`, `Coat Weight`, `Subsurface Weight`, `Transmission Weight`, `Sheen Weight`. The 3.x names `Emission`, `Specular`, `Clearcoat`, `Subsurface`, `Subsurface Color`, `Transmission`, and `Sheen` raise `KeyError`.
- Keep materials opaque: don't touch `Alpha`, `Transmission Weight`, `blend_method`, or `surface_render_method`. The game replaces materials with its toon shader and keeps only the base color (or base color texture) and the emission (`Emission Color` × `Emission Strength`, e.g. for glowing eyes). Metallic, roughness, and the rest are ignored.
- Textures: `img = bpy.data.images.load(path)` or `bpy.data.images.new(name, 512, 512)`, a `ShaderNodeTexImage` node with `.image = img`, linked with `m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])`. At most 2 textures, ≤ 1024 px.

## Preview renders

Workbench renders in about a second and works headless. Render engine names differ: EEVEE is `"BLENDER_EEVEE_NEXT"` in 4.2–4.5 and `"BLENDER_EEVEE"` in 5.x; `"BLENDER_WORKBENCH"` is the same everywhere, so use that.

```python
def render_previews(out_dir, tag):
    """Render front, side and 3/4 views to out_dir/<tag>_<view>.png."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"  # shows material.diffuse_color
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.image_settings.file_format = "PNG"
    cam_data = bpy.data.cameras.new("preview_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.2  # meters visible; the fighter is ~1.8 m tall
    cam = bpy.data.objects.new("preview_cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0.0, 0.0, 0.9))
    # The character faces -Y, so the front camera sits at -Y. Side = its left (+X).
    views = {"front": (0.0, -6.0), "side": (6.0, 0.0), "three_quarter": (4.2, -4.2)}
    for view, (x, y) in views.items():
        cam.location = Vector((x, y, 0.9))
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{tag}_{view}.png")
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)  # keep the camera out of the export


def test_pose(arm_obj):
    """Arms swung forward, left knee bent. export_glb() resets it before exporting."""
    pose = {
        "upper_arm.L": ((0, 0, 1), -70),  # -Z swings the left arm forward
        "upper_arm.R": ((0, 0, 1), 70),  # +Z the right one (mirrored)
        "thigh.L": ((1, 0, 0), -60),  # legs bend around local X
        "shin.L": ((1, 0, 0), 90),
    }
    for bone, (axis, degrees) in pose.items():
        pb = arm_obj.pose.bones[bone]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion(axis, math.radians(degrees))
    bpy.context.view_layer.update()
```

In the front view the character's left (+X) is on the image's right, and in the side view its front is on the image's left.

## Export

Call `export_glb(path)` from `export_glb.py`; don't call the exporter yourself. For reference, its settings are `bpy.ops.export_scene.gltf(filepath=..., export_format="GLB", export_yup=True, export_apply=True, export_animations=False, export_morph=False, export_cameras=False, export_lights=False)`.

Parameter names LLMs commonly invent, none of which exist: `export_selected` (it's `use_selection`), `export_colors` (it's `export_vertex_color`), `export_apply_transforms`, `export_y_up`, `export_animation`, `export_shape_keys` (it's `export_morph`). `export_apply` applies modifiers, not object transforms.
