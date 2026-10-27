# Prompt-Driven Animation

Open-source options for turning a player's prompt into animation on the shared skeleton (see `skeleton.md`). The rig suits this well: it has 17 bones and rigid parts, and every bone axis is documented. `animations/build_base.gd` already builds an `AnimationLibrary` from pose tables.

The game is non-commercial, so research-only model licenses aren't a blocker. See [Licensing](#licensing) for the terms that still apply.

## 1. Text-to-motion models (prompt → full-body motion)

These models take text such as "a spinning back kick" and output a motion clip for the 22-joint HumanML3D/SMPL skeleton.

| Project                                     | Notes                                                                                                                        |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **MoMask** (`EricGuo5513/momask-codes`)     | Among the best-quality open models. Supports filling in motion between keyframes you supply.                                 |
| **MDM** (`GuyTevet/motion-diffusion-model`) | The standard baseline. Diffusion-based and easy to constrain, for example by fixing the root path or chosen joints. Slow.    |
| **MotionLCM**                               | A fast version of the diffusion approach, around tens of ms per clip. The only one realistic to run at request time.         |
| **T2M-GPT**, **MotionGPT** (OpenMotionLab)  | Treat motion as tokens. MotionGPT can also describe a motion back in text, which helps check that a clip matches its prompt. |
| **HY-Motion** (Tencent Hunyuan)             | Newer and larger. License and quality not yet checked.                                                                       |

### Converting to our skeleton

- **Bone mapping.** HumanML3D joints map onto our bones as follows. The collar and toe joints have no match and are dropped.

  | Our bone      | HumanML3D joint |
  | ------------- | --------------- |
  | `hips`        | pelvis          |
  | `spine`       | spine1          |
  | `chest`       | spine3          |
  | `neck`        | neck            |
  | `head`        | head            |
  | `upper_arm.*` | shoulder        |
  | `forearm.*`   | elbow           |
  | `hand.*`      | wrist           |
  | `thigh.*`     | hip             |
  | `shin.*`      | knee            |
  | `foot.*`      | ankle           |

- **Positions to rotations.** The models output joint positions, not rotations. For each bone, take the direction from its joint to its child's joint. Then compute the rotation that swings the bone's rest direction onto it (`Quaternion(rest_dir, target_dir)`, in the parent's space). No IK is needed.
- **Twist is lost.** Rotation around a bone's own axis can't be recovered from positions. With rigid parts this is mostly invisible, although wrists may look odd.
- **Facing.** HumanML3D is Y-up and faces +Z, which matches the skeleton in Godot after glTF import.
- **Root motion.** The pelvis translation becomes the `hips` position track. Scale it to match our 0.95 m hip height.

## 2. The LLM writes keyframes directly (no ML model)

`skeleton.md` gives an LLM everything it needs to write poses: bone names, local axes, and which axis bends which joint. Claude outputs pose-table entries (bone rotations per key, timing, and markers such as hit frames). The same `build()` in `animations/build_base.gd` then turns them into clips.

- **Quality:** stiffer than models trained on motion capture, but it fits the snappy, PS1-style fighting look.
- **Hosting:** no ML hosting, and no model licenses to track.
- **Validation:** results can be checked deterministically. Checks can include joint ranges, startup, active, and recovery frame counts, and limits on root movement.
- **Building blocks:** this matches the approach in `notes.md`. A prompt composes moves from archetypes (jab, sweep, uppercut, and so on) with parameters, instead of producing arbitrary motion.

## 3. Supporting tools

- **Godot built-ins.**
  - `AnimationTree` blends and layers generated clips.
  - `SkeletonModifier3D` subclasses add procedural touches such as look-at and IK.
  - Godot 4.6 added IK modifiers (`TwoBoneIK3D`, FABRIK, CCD). These are useful for keeping feet planted on generated motion.
- **Blender.**
  - The official Blender MCP server (see `notes.md`) lets Claude keyframe in Blender, check its work with screenshots, and export.
  - The free Rokoko retargeting add-on maps BVH or FBX motion onto a rig.
  - Animations made in Blender must be rebuilt as game-side clips, because `skeleton.md` says uploaded files contain no animations.
- **Format converters.** The MDM and MoMask repos include HumanML3D→BVH scripts. `SMPL-to-FBX` and `joints2smpl` convert model output into standard formats.
- **Motion cleanup.** Text-to-motion output tends to slide. A simple foot-contact detector, plus a pass that locks contacting feet to the floor, fixes most of it.

## Licensing

Most text-to-motion code is MIT-licensed. The weights are a different matter: they are trained on AMASS/HumanML3D, and AMASS and SMPL are licensed for non-commercial research only. Because this game is non-commercial, using them is generally acceptable, with these conditions:

- **No redistribution.** SMPL and AMASS require registration and forbid sharing their model files and data. Run the models on a server, or require players to download the weights themselves. Never bundle the weights with the game.
- **Check each project.** Some projects add their own terms on top, for example HY-Motion. Read each license before adopting it.
- **Commercial use changes this.** If the game ever becomes commercial, tier 1 needs to be re-checked. Tier 2 has no such dependency.

## Recommendation

1. **Start with tier 2.** Claude writes a JSON pose table, the server validates it, and `build_base.gd`'s `build()` turns it into clips. This fits the existing rig and pipeline and keeps animation fairness enforceable.
2. **Add tier 1 later.** MoMask or MotionLCM can provide an optional "realistic motion" path. Retarget its output with the mapping above, and run it through the same validator.
