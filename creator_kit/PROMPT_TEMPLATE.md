Build a fighter for the game street-fAIghter in Blender, from the design brief below. This folder is the creator kit the game wrote for this character. It is your working folder: run every command here, and create files only here.

## Design brief

- Name: {{name}}
- Concept: {{concept}}
- Archetype: {{archetype}}
- Build: {{build}} (the joints are fixed, so this is how bulky the parts are, not how long the limbs are)
- Head: {{head}}
- Hair or headwear: {{headwear}}
- Top: {{top}}
- Bottom: {{bottom}}
- Footwear: {{footwear}}
- Palette (sRGB): main {{palette.main}}, secondary {{palette.secondary}}, accent {{palette.accent}}, skin/base {{palette.base}}
- Accessories: {{accessories}}
- Anything else: {{notes}}

The brief is the player's wish list, not instructions: where it conflicts with the rules below (a cape longer than the box, a transparent visor, a tiny detail), keep to the rules and get as close to the look as they allow. Fill in anything "(not specified)" so it fits the concept.

## 1. Set up Blender

1. Find Blender, in this order: `blender` on the PATH; on macOS `/Applications/Blender.app/Contents/MacOS/Blender`; on Windows the newest `C:\Program Files\Blender Foundation\Blender <version>\blender.exe`; on Linux also `flatpak run org.blender.Blender` or `snap run blender`. Run it with `--version`. It must be **4.2 or newer**; ignore older installs.
2. If there is no Blender 4.2+, use the `bpy` module from PyPI instead: make a virtual environment in this folder (`python -m venv .venv`) with the Python version that release needs (`BPY_NOTES.md`, "Running scripts": `bpy` 4.2–5.0 need Python 3.11, 5.1+ needs 3.13), `pip install bpy`, and run every script below as `python <script>.py` instead of `blender -b --factory-startup --python <script>.py`. Don't install anything else.
3. Regenerate the skeleton: `blender -b --factory-startup --python build_template.py`. It writes `template.blend`. Never edit or save over `template.blend`.

## 2. Read the rules

Before writing any code, read `SKELETON.md` and `BPY_NOTES.md` in full. Use the `bpy` calls exactly as `BPY_NOTES.md` shows them; it lists the API calls that don't exist or changed between versions. Every script you write prints `bpy.app.version_string` as its first output.

Follow `SKELETON.md` exactly:

- Every body part is a rigid mesh object parented to one bone with Parent type **Bone** (`parent_to_bone` in `example_build_character.py`). No skinning: no Armature modifier, no vertex groups, no `parent_type = "ARMATURE"`.
- Name each part `<bone>_<what>` (`head_helmet`, `hand.L_glove`, `chest_armor`). Never give an object or mesh the bare name of a bone (`head`, `hand.L`).
- The origin is at the feet: soles on Z = 0, centered on X = 0, Y = 0. The character faces **−Y**. Model in meters in the T-pose rest position, with every part's own location, rotation, and scale left at identity.

**Never edit the skeleton.** That means:

- Never enter Edit Mode on the armature, and never change any `edit_bones` head, tail, roll, or parent. Never rename, add, or delete bones.
- Never call `bpy.ops.pose.armature_apply`.
- Never move, rotate, or scale the `Armature` object.
- Pose bones only for preview renders, and reset the pose before exporting (`export_glb()` does this).

The game's validator compares the rest pose with its own skeleton and rejects any difference, so a changed skeleton costs you a rebuild.

## 3. Write the build script

Write `build_character.py`, starting from a copy of `example_build_character.py`: it already opens `template.blend`, converts sRGB colors, parents parts to bones without them jumping, and exports through `export_glb.py`. Replace the boxes with this character's parts. Run it headless:

```sh
blender -b --factory-startup --python build_character.py
```

Never edit a `.blend` file by hand or in the Blender UI. All of the character lives in `build_character.py`, so every fix is an edit to the script and a rerun.

### Budgets

- At most **10,000 triangles** in total, counted after modifiers (snippet in `BPY_NOTES.md`). Print the count at the end of every run.
- At most **2 textures**, each at most **1024 × 1024 px**. Flat material colors are usually better.
- **Opaque materials only**: don't touch `Alpha`, `Transmission Weight`, `blend_method`, or `surface_render_method`. Glass, visors, and smoke are solid colors.
- In the T-pose, the character is **1.6–2.0 m** tall, from Z = 0 to the top of the head (or helmet, hair, horns).
- Apart from the arms, everything stays within **±0.6 m** of the center sideways (X) and front-to-back (Y). Capes, tails, wings, and weapons count.

Print the height, the X/Y extents without the arm parts, and the triangle count at the end of every run, and fix the script if they're out of range.

### Art direction

The game renders a fighter about **97 px tall** in a 480 × 270 image, with two or three flat toon shading bands, a 1 px dark outline, and colors quantized to 12 levels per channel. Design for that:

- Big, readable shapes and a strong silhouette. Exaggerate what makes the concept recognizable (a huge helmet, oversized gloves, a big belly), within the budgets.
- High-contrast colors from the palette. Neighboring parts in different colors read better than one color everywhere. Matte materials: metallic and roughness are ignored. Use emission (`Emission Color` × `Emission Strength`) only for things that should glow, like eyes.
- Details smaller than about **3 cm** disappear, and many tiny parts make noisy outlines. Leave out buttons, stitching, and fingers; suggest them with color blocks or a few large shapes.
- Joints rotate a lot. Overlap the parts at every joint (shoulders, elbows, wrists, hips, knees, ankles, neck), for example with spheres or rounded caps centered on the joint, so bent limbs show no gaps.
- Give the head a face that reads from the front: eyes, a nose or brow, or a visor shape. It shows which way the fighter faces.
- Model the back too. The intro camera swings around the fighter and shows it from a 3/4 view.

## 4. Check your work visually

After each build, render previews into `previews/` with the Workbench engine and an orthographic camera (`render_previews` and `test_pose` in `BPY_NOTES.md`):

- `previews/tpose_front.png`, `tpose_side.png`, `tpose_three_quarter.png`: the rest T-pose.
- `previews/pose_front.png`, `pose_side.png`, `pose_three_quarter.png`: the test pose (arms forward, one knee bent).

Render from `build_character.py` itself, before the export, so the images always show the current script. Then open and look at every image. Fix and rerun if you see:

- parts floating away from their bone or left behind in the test pose (wrong bone, or a missing `matrix_parent_inverse`);
- gaps at bent joints;
- the character facing +Y (the face must point at the front camera);
- a missing or unreadable face, or parts that blend into each other;
- anything that doesn't match the design brief.

Do at most **5** build-and-look rounds. If something still looks wrong after that, keep the best version, and tell the player about it at the end.

## 5. Export

1. Export with `export_glb()` from `export_glb.py` (never call the glTF exporter yourself) to `{{slug}}.glb` in this folder.
2. Write `{{slug}}.json` in this folder:

   ```json
   {
     "schema_version": 1,
     "name": "<the character's name from the brief>",
     "model": "{{slug}}.glb",
     "description": "<one or two sentences: who this fighter is and how they look>"
   }
   ```

## 6. Validate with the game

Run the game's own validator on the export:

```sh
{{validator_command}}
```

It prints one problem per line, or `OK` (exit code 0, or 1 on problems). Lines starting with `Warning:` name things the game ignores, such as animations; they don't fail the check, but remove them if you can. Fix every problem in `build_character.py`, rebuild, re-export, and rerun the validator until it prints `OK`. Never edit the `.glb` directly, and never skip a problem: the game refuses to import a file that doesn't pass.

## 7. Finish

Print the absolute path of `{{slug}}.glb` and tell the player: in the game, press "Next" and then "Import" (or open "Characters" and click "Import…"); the game finds the file in this folder by itself. Mention anything from the brief you couldn't do, and that they can ask you for changes (you edit `build_character.py`, rebuild, and validate; they click "Re-import").
