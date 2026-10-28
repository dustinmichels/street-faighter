# Custom characters

A player answers a few questions in the game. The game turns the answers into a **creator kit**: a folder with a prompt for the player's own AI agent (Claude Code, Codex, Gemini CLI, Antigravity, Pi, Oh My Pi, or another one), which drives a local Blender to build the character on the game's skeleton and export a `.glb`. The player imports the `.glb`, and it becomes their fighter, in singleplayer and online.

Custom characters are **cosmetic only**. Hitboxes, hurtboxes, and all gameplay numbers are fixed in `Fighter`/`Match` and never come from the mesh, so a model can't change the simulation, the checksums, or the determinism tests. The game never runs Blender or the agent itself.

The skeleton (bone names, rest pose, axes, model conventions) is specified in one place: `creator_kit/SKELETON.md` ([Skeleton](./skeleton)). Every kit gets a copy.

## Pipeline

1. **Questionnaire** (menu → CHARACTERS → CREATE NEW, `character_screen/character_wizard.gd`): three pages — name and concept; archetype, build, and a 4-color palette; free notes (outfit, hair, extras). The prompt tells the agent to design whatever the brief leaves open. Three steps follow on `CharacterScreen`: STEP 1 shows the filled-in prompt with SAVE KIT and FOLDER… (choose where kits go).
2. **Kit** (`CreatorKit.write`, `characters/creator_kit.gd`): writes `<dir>/<slug>/`, where `<dir>` defaults to `~/Documents/street-fAIghter characters/` (the picked folder is saved in `user://settings.cfg`, `[creator_kit] dir`; the kit as `[creator_kit] last_kit`). The kit matches the game version that wrote it and works offline.
3. **Agent** (STEP 2): the AGENT button cycles through `CreatorKit.AGENTS` (saved as `[creator_kit] agent`), and the game copies `CreatorKit.agent_command(folder, agent)` for the player to paste into a terminal: `cd <kit> && <agent> 'Read PROMPT.md and follow it.'`, with `claude`, `codex`, `gemini -i`, `agy -i`, `pi`, or `omp` (each starts an interactive session on that first prompt), or only `cd <kit>` for another agent. The command is written for the player's terminal (`CreatorKit.terminal_shell()`): a POSIX shell on macOS and Linux; PowerShell on Windows, where 5.1 has no `&&`, so it's `cd -LiteralPath '<kit>' -ErrorAction Stop; <agent> '…'`. The STEP 2 page says how to open that terminal (`CharacterScreen.OPEN_TERMINAL`). `PROMPT.md` is tailored the same way (`CreatorKit.PLATFORM_VALUES`: where to look for Blender, the `venv` commands for the `bpy` fallback). COPY PROMPT and OPEN FOLDER are there too. The agent finds Blender (4.2+, or the PyPI `bpy` module as a fallback), writes `build_character.py` on `kit.py`, and reruns it headless (`blender -b --python …`) after every fix. Each run is one command: `kit.py`'s `finish()` prints the stats, renders `previews/sheet.png`, exports `<slug>.glb`, writes `<slug>.json`, and runs the game's validator, until it prints `RESULT: OK`.
4. **Import** (STEP 3, or CHARACTERS → IMPORT… while a kit exists): the page checks every second for the last kit's `<slug>.glb` (`CreatorKit.kit_glb`) and enables IMPORT once it's there; BROWSE… (IMPORT… with no kit) picks any `.glb`, and a `.glb` can be dropped onto the window. The game validates the file again and adds it to the library; on errors, BACK returns to the import page. RE-IMPORT re-reads an entry's source file, so the edit → export → import loop is one click.
5. **Play**: 1 PLAYER VS CPU opens CHOOSE YOUR FIGHTER on the library; online, each side announces its character and the other side downloads it.

## Kit layout

The kit sources are in `creator_kit/`; the export preset bundles them (`include_filter="creator_kit/*"`). `CreatorKit.write` copies every file there except `PROMPT_TEMPLATE.md` and writes `PROMPT.md`, `character_request.json`, and `kit_config.json`. A kit holds:

| File                         | Source                                                                                                                                                                                                   |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `README.md`                  | `creator_kit/README.md`: what the kit is and how to run the agent.                                                                                                                                       |
| `PROMPT.md`                  | `creator_kit/PROMPT_TEMPLATE.md` with the design brief filled in.                                                                                                                                        |
| `SKELETON.md`                | `creator_kit/SKELETON.md`: the skeleton reference ([Skeleton](./skeleton)).                                                                                                                              |
| `BPY_NOTES.md`               | The `kit.py` API, plus the raw `bpy`/`bmesh` calls for other shapes and the ones LLMs invent or that changed between versions.                                                                           |
| `kit.py`                     | The helpers build scripts use: `start()` (the skeleton; the only copy of the bone list), materials, parts parented to bones (`box`, `sphere`, `cylinder`, `capsule`, `part`, `mirror=True`), `finish()`. |
| `build_template.py`          | Saves `kit.py`'s skeleton as `template.blend`, for modeling by hand.                                                                                                                                     |
| `example_build_character.py` | A working fighter on `kit.py`, the agent's starting point.                                                                                                                                               |
| `export_glb.py`              | Export with fixed settings (GLB, rest pose, no animations, shape keys, cameras, or lights); `finish()` calls it.                                                                                         |
| `character_request.json`     | The sanitized questionnaire answers.                                                                                                                                                                     |
| `kit_config.json`            | What `finish()` needs from the game: `glb` (`<slug>.glb`) and `validator` (`CreatorKit.validator_args()`, the program and arguments, the `.glb` path appended).                                          |

`finish()` keeps the build log short: Blender's per-render and per-export log lines are hidden unless that step fails, so a run prints the version, four `stats:` lines, the sheet path, the validator's lines, and `RESULT:`. `previews/sheet.png` is one 776 × 516 image: the T-pose (top row) and a test pose (arms forward, left knee bent; bottom row), from the front, the left side, and the front-left 3/4.

Rewriting a kit keeps the agent's own files (`build_character.py`, `previews/`, `<slug>.glb`, `<slug>.json`). `<slug>.json` is the manifest (`schema_version`, `name`, `model`, `description`); on import, its `name` becomes the library name.

Answers only fill text slots in the prompt. `CreatorKit.sanitize` strips control, bidi, and zero-width characters, turns backticks into `'`, caps lengths (name 32, concept 160, notes 400, other fields 80), and keeps only `#rrggbb` colors.

## Validator

`CharacterValidator` (`characters/character_validator.gd`) is the one set of checks, used by the import, by `CharacterLoader.load_character` at match start, by the online download, and by the agent through the command line:

```sh
<game executable> --headless -- --validate-character /absolute/path/to/character.glb
# from a source checkout:
godot --headless --path . -- --validate-character /absolute/path/to/character.glb
```

It prints `Warning: …` lines for ignored content, then one problem per line (exit code 1) or `OK` (exit code 0). The kit's `kit_config.json` holds the exact command for the game that wrote it (`CreatorKit.validator_args()`), and `kit.py`'s `finish()` runs it after every export. It collects every problem rather than stopping at the first, for example:

```
Bone 'hand.L' missing (found 'hand.L.001')
Part 'head' has the same name as a bone; rename it to 'head_part'
Triangle count 23,410 exceeds 10,000
```

The file is checked before Godot decodes anything, then the decoded scene is checked:

| Check     | Rule                                                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------------------------------------- |
| File      | `.glb` (glTF 2.0 binary), ≤ 4 MB, one embedded buffer, no external URIs.                                                        |
| Safety    | ≤ 1,024 nodes, ≤ 4,096 accessors, ≤ 100,000 elements per accessor and 1,000,000 in total; buffer views and accessors in bounds. |
| Textures  | ≤ 2 images, PNG or JPEG, ≤ 1024×1024 px (read from the image header).                                                           |
| Triangles | ≤ 10,000 in total; no loose points or edges.                                                                                    |
| Parts     | Every mesh is parented to a bone (Parent type _Bone_); no skinning; no part named like a bone.                                  |
| Materials | Opaque only: no alpha blend or clip, base color alpha 1, no transmission.                                                       |
| Skeleton  | Exactly one armature with exactly the 17 template bones and parents; rest pose matches `default.glb` within 2 mm and 0.005 rad. |
| Armature  | The Armature object at the origin, not rotated or scaled.                                                                       |
| Bounds    | At rest, 1.6–2.0 m tall, soles at Z = 0 (±0.05 m), body without the arms within ±0.6 m sideways and front-to-back.              |
| Ignored   | Animations, cameras, lights, and shape keys produce warnings, not errors.                                                       |

The limits are constants at the top of the script; `PROMPT_TEMPLATE.md` states the same budgets to the agent.

## Library

`CharacterLibrary` (`characters/character_library.gd`) stores each import as `user://characters/<sha256>.glb` (the exact validated bytes) plus `<sha256>.json` (`name`, `source`, `imported`). Re-importing identical bytes is a no-op; a re-import with new bytes replaces the entry and moves any saved choice to it. The built-in `DEFAULT` character is listed first and can't be deleted. The library page previews the selected model turning in place with the in-game shaders, with a PUNCH button to check that the parts follow the animation.

The singleplayer choice is saved in `user://settings.cfg` (`[characters] p1`). A choice that's gone from the library, or a file that no longer validates, falls back to the default model with a HUD notice. When both fighters use the same model, fighter 2 is hue-shifted (`toon.gdshader` `tint_hue`).

## Online

The match config carries a descriptor per fighter: `{"builtin": "DEFAULT"}` or `{"sha256", "name", "size"}`. After connecting, each side announces its character (`CharacterSync`, `online/character_sync.gd`); a side that doesn't have the hash requests it, and the owner sends it in chunks of ≤ 64 KB on its own reliable channel. The receiver enforces the size limit before the first chunk, checks the SHA-256, runs the full validator, and caches the file under `user://characters/remote/<sha256>.glb`. The match waits up to 10 s for downloads; on timeout or failure, that fighter is shown with the default model and the match starts anyway, since models don't affect the simulation. The ONLINE panel's OPPONENTS: DEFAULT setting skips downloading and showing other players' models.

## Tests

Described in [Testing](./testing): creator kit, character validator (broken fixtures in `tests/fixtures/`, built by `tests/fixtures/build_bad_characters.py`), skeleton drift (the rig Blender builds vs `creator_kit/SKELETON.md` and `default.glb`), and character sync (two processes).
