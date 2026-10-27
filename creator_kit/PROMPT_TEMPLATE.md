Build a fighter for the game street-fAIghter in Blender, from the design brief below. This folder is the creator kit the game wrote for this character; work only in this folder.

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

## Steps

1. Find Blender 4.2 or newer (`blender` on PATH, or `/Applications/Blender.app/Contents/MacOS/Blender` on macOS) and print its version. Regenerate the skeleton with `blender -b --factory-startup --python build_template.py`.
2. Read `SKELETON.md` and `BPY_NOTES.md` before writing any code. Follow `SKELETON.md` exactly: never edit the skeleton, parent rigid parts to bones, name parts `<bone>_<what>`, origin at the feet, facing −Y.
3. Write `build_character.py`, based on `example_build_character.py`, and run it headless. Every fix is an edit to the script and a rerun; never edit a `.blend` by hand.
4. Export `{{slug}}.glb` with `export_glb.py`, and write `{{slug}}.json` with `schema_version` 1, `name`, `model` (`{{slug}}.glb`), and `description`.
5. Print the path of `{{slug}}.glb` and tell the player to click "Import…" in the game.
