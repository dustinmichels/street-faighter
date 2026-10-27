# Skeleton

Every character uses this one skeleton. The game owns all animations and plays them on the skeleton by bone name, so a model only needs the right bone names and rest pose to work. `build_template.py` builds `template.blend`, a file with this skeleton and nothing else. Build new characters on it. (In the game's repo, the script is `creator_kit/build_template.py`, the file is `characters/template/template.blend`, and this document is `creator_kit/SKELETON.md`, which the game copies into every creator kit.)

## Model conventions

- Blender units are meters. The character is about **1.8 m** tall.
- **Origin at the feet**: the soles rest on Z = 0, centered on X = 0, Y = 0.
- **Faces −Y** in Blender (front view, numpad 1, shows the character's face). The character's left side is +X.
- **Transforms applied** (Ctrl+A → All Transforms) on every object. The armature object stays at the origin with no rotation and scale 1.
- **Rigid parts, no skinning.** Each body part is its own mesh object, parented to one bone (Parent type: *Bone*, Ctrl+P → *Bone*). Don't use an Armature modifier, vertex groups, or weight painting.
- **Don't give a part the same name as a bone** (e.g. call it `head_part`, not `head`). glTF stores bones and meshes as nodes, and Godot fixes a name clash by renaming the bone (`head` → `head_2`), which breaks animations.
- **Don't edit the skeleton.** Don't rename, add, delete, move, or re-roll bones, and don't change the rest pose. Parts can be any shape or size, but the joints stay where they are.
- **No animations, constraints, or shape keys in the file.** The game ignores them.
- Export as glTF 2.0 binary (`.glb`).

## Bones

There are 17 bones. Names are lowercase snake_case, and sides use Blender's `.L` / `.R` suffixes so the mirror tools work. `.L` is the character's left (+X).

Rest pose is a T-pose. The table gives positions in Blender space in meters, with X = left, −Y = forward, Z = up. `.R` bones mirror their `.L` bones at −X. "Connected" means the head sits on the parent's tail.

| Bone          | Parent        | Head               | Tail                | Connected |
| ------------- | ------------- | ------------------ | ------------------- | --------- |
| `hips`        | (root)        | (0, 0, 0.95)       | (0, 0, 1.05)        | n/a       |
| `spine`       | `hips`        | (0, 0, 1.05)       | (0, 0, 1.25)        | yes       |
| `chest`       | `spine`       | (0, 0, 1.25)       | (0, 0, 1.45)        | yes       |
| `neck`        | `chest`       | (0, 0, 1.45)       | (0, 0, 1.55)        | yes       |
| `head`        | `neck`        | (0, 0, 1.55)       | (0, 0, 1.75)        | yes       |
| `upper_arm.L` | `chest`       | (0.18, 0, 1.42)    | (0.45, 0, 1.42)     | no        |
| `forearm.L`   | `upper_arm.L` | (0.45, 0, 1.42)    | (0.70, 0, 1.42)     | yes       |
| `hand.L`      | `forearm.L`   | (0.70, 0, 1.42)    | (0.80, 0, 1.42)     | yes       |
| `thigh.L`     | `hips`        | (0.10, 0, 0.95)    | (0.10, 0, 0.50)     | no        |
| `shin.L`      | `thigh.L`     | (0.10, 0, 0.50)    | (0.10, 0, 0.08)     | yes       |
| `foot.L`      | `shin.L`      | (0.10, 0, 0.08)    | (0.10, −0.15, 0.02) | yes       |
| `upper_arm.R` | `chest`       | (−0.18, 0, 1.42)   | (−0.45, 0, 1.42)    | no        |
| `forearm.R`   | `upper_arm.R` | (−0.45, 0, 1.42)   | (−0.70, 0, 1.42)    | yes       |
| `hand.R`      | `forearm.R`   | (−0.70, 0, 1.42)   | (−0.80, 0, 1.42)    | yes       |
| `thigh.R`     | `hips`        | (−0.10, 0, 0.95)   | (−0.10, 0, 0.50)    | no        |
| `shin.R`      | `thigh.R`     | (−0.10, 0, 0.50)   | (−0.10, 0, 0.08)    | yes       |
| `foot.R`      | `shin.R`      | (−0.10, 0, 0.08)   | (−0.10, −0.15, 0.02)| yes       |

`hips` is the only root bone. Animations move the whole body by translating it, for example to crouch or bob. There are no IK, twist, finger, or control bones.

## Bone axes

Every bone has roll 0. As in Blender, each bone's local +Y points from its head to its tail. The other two local axes at rest are:

| Bones                                       | Local +X       | Local +Z           |
| ------------------------------------------- | -------------- | ------------------ |
| `hips`, `spine`, `chest`, `neck`, `head`    | +X (left)      | −Y (forward)       |
| `thigh.*`, `shin.*`                         | +X (left)      | +Y (backward)      |
| `foot.*`                                    | +X (left)      | mostly down        |
| `upper_arm.L`, `forearm.L`, `hand.L`        | −Y (forward)   | +Z (up)            |
| `upper_arm.R`, `forearm.R`, `hand.R`        | +Y (backward)  | +Z (up)            |

For animators, this means:

- **Torso, neck, head, legs, and feet** bend forward and back by rotating around local X.
- **Arms** swing forward and back (in the horizontal plane) by rotating around local Z. They raise and lower by rotating around local X.

## In Godot

The glTF exporter converts Blender's Z-up axes to Y-up axes, mapping (x, y, z) to (x, z, −y). After import, the character faces **+Z** (Godot's `Vector3.MODEL_FRONT`), its left is +X, and up is +Y. The torso bones' rest basis is the identity. `GLTFDocument.generate_scene` produces `<root>/Armature/Skeleton3D`, and the bone names stay exactly as above, dots included. Each rigid part ends up under a `BoneAttachment3D` child of the skeleton. These are node names, which can't contain dots, so they're sanitized (for example `hand_L`); look parts up by `bone_name`, not by node name. Animation tracks target `Skeleton3D:<bone>`, for example `Skeleton3D:upper_arm.L`.
