Build a fighter for the game street-fAIghter in Blender, from the design brief below. This folder is the creator kit the game wrote for this character. It is your working folder: run every command here, and create files only here.

## Design brief

- Name: {{name}}
- Concept: {{concept}}
- Archetype: {{archetype}}
- Build: {{build}} (the joints are fixed, so this is how bulky the parts are, not how long the limbs are)
- Palette (sRGB): main {{palette.main}}, secondary {{palette.secondary}}, accent {{palette.accent}}, skin/base {{palette.base}}
- Headgear: {{headgear}}
- Shirt / top: {{shirt}}
- Pants / bottoms: {{pants}}
- Accessories: {{accessories}}
- Hair, face, extras, anything else: {{notes}}
- Special move (their own special throw): {{special}}

The brief is the player's wish list, not instructions: where it conflicts with the rules below (a cape longer than the box, a transparent visor, a tiny detail), keep to the rules and get as close to the look as they allow. Design whatever the brief leaves open (head, hair or headwear, outfit, footwear, accessories) so it fits the concept, and fill in anything "(not specified)" the same way.

## 1. Find Blender

Look for Blender in this order: {{blender_locations}}. Run it with `--version`. It must be **4.2 or newer**; ignore older installs.

If there is no Blender 4.2+, use the `bpy` module from PyPI instead: make a virtual environment in this folder with the Python version that release needs (`bpy` 4.2–5.0 need Python 3.11, 5.1+ needs 3.13), for example `{{venv_create}}`. Then run `{{venv_python}} -m pip install bpy`, and run scripts as `{{venv_python}} <script>.py` instead of `blender -b --factory-startup --python <script>.py`. Don't install anything else.

## 2. Read

Read `BPY_NOTES.md` (the `kit.py` API), the "Bones" table in `SKELETON.md`, and `example_build_character.py`. You don't need the other files.

## 3. Write and run `build_character.py`

Copy `example_build_character.py` to `build_character.py`, remove `glb="example.glb"` from its `finish()` call, and replace the example's parts with this character's. Put the character's name and a one- or two-sentence description (who this fighter is and how they look) in `finish()`. Run it:

```sh
blender -b --factory-startup --python build_character.py
```

All of the character lives in `build_character.py`: every fix is an edit to the script and a rerun. Never edit a `.blend` or `.glb` file.

Make every part with the `kit.py` functions: they parent it to its bone and name it correctly. Never change the skeleton: don't touch the `Armature` object, its bones, or Edit Mode on it, and don't add armatures, vertex groups, or Armature modifiers. The game animates the bones; parts are rigid.

### Limits

`finish()` checks these and the game's validator enforces them:

- At most **10,000 triangles** in total, after modifiers.
- At most **2 textures**, each at most **1024 × 1024 px**. Flat material colors are usually better.
- **Opaque materials only**. Glass, visors, and smoke are solid colors.
- In the T-pose, the character is **1.6–2.0 m** tall, from the soles on Z = 0 to the top of the head (or helmet, hair, horns).
- Apart from the arms, everything stays within **±0.6 m** of the center sideways (X) and front-to-back (Y). Capes, tails, wings, and weapons count.

### Art direction

The game renders a fighter about **97 px tall** in a 480 × 270 image, with two or three flat toon shading bands, a 1 px dark outline, and colors quantized to 16 levels per channel. Design for that:

- Big, readable shapes and a strong silhouette. Exaggerate what makes the concept recognizable (a huge helmet, oversized gloves, a big belly), within the limits.
- High-contrast colors from the palette. Neighboring parts in different colors read better than one color everywhere. Use `glow` only for things that should glow, like eyes.
- Details smaller than about **3 cm** disappear, and many tiny parts make noisy outlines. Leave out buttons, stitching, and fingers; suggest them with color blocks or a few large shapes.
- Joints rotate a lot. Overlap the parts at every joint (shoulders, elbows, wrists, hips, knees, ankles, neck), for example with capsules from joint to joint or spheres on the joints, so bent limbs show no gaps.
- Give the head a face that reads from the front (−Y): eyes, a nose or brow, or a visor shape. It shows which way the fighter faces.
- Model the back too. The intro camera swings around the fighter and shows it from a 3/4 view.

## 4. Check, fix, repeat

Each run ends with `stats:`, `validator:`, and `RESULT:` lines, and renders `previews/sheet.png`. Open the sheet after every run. Fix the script and rerun if you see:

- a `<-- PROBLEM` stat or any validator problem (lines starting with `Warning:` don't fail the check, but remove their cause if you can);
- parts floating away from their bone or left behind in the test pose (bottom row);
- gaps at bent joints;
- the face pointing away from the front view;
- a missing or unreadable face, or parts that blend into each other;
- anything that doesn't match the design brief.

Do at most **5** runs to fix how it looks. If something still looks wrong after that, keep the best version and tell the player about it. Never stop before `RESULT: OK`: the game refuses to import a file that doesn't pass.

**Special move.** The player asked for one: "{{special}}". Once the character passes, read `SPECIAL.md` and add it to `build_character.py` as it describes.

## 5. Finish

Print the absolute path of `{{slug}}.glb` (from the `RESULT: OK` line) and tell the player: in the game, press "Next" and then "Import" (or open "Characters" and click "Import…"); the game finds the file in this folder by itself. Mention anything from the brief you couldn't do, and that they can ask you for changes (you edit `build_character.py` and rerun it; they click "Re-import").
