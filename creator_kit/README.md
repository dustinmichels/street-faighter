# street-fAIghter creator kit

This folder is everything an AI coding agent needs to build a custom fighter for street-fAIghter in Blender. The game wrote it for one character, from your answers to its questionnaire, and it matches the game version that wrote it. Nothing in it needs the internet.

The agent writes a Python script that builds the character on the game's skeleton, runs it in Blender without opening a window, looks at preview renders, and exports a `.glb` file. You then import that file in the game ("Characters" → "Import…").

## What you need

- [Blender](https://www.blender.org/download/) 4.2 or newer. Without Blender, the agent can use the `bpy` Python module from PyPI instead.
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (or another agent that can run shell commands).

## How to run it

1. Open a terminal in this folder.
2. Run `claude`.
3. Paste the prompt (the game copied it to the clipboard; it's also in `PROMPT.md`), or type: "Read PROMPT.md and follow it."
4. When the agent prints the path of the `.glb`, click "Import…" in the game and pick that file.

To change the design later, edit `build_character.py` (or ask the agent to), rerun it, and click "Re-import" in the game.

## Files

| File                          | What it is                                                                                   |
| ----------------------------- | -------------------------------------------------------------------------------------------- |
| `PROMPT.md`                   | The instructions for the agent, with your design brief filled in.                            |
| [`SKELETON.md`](SKELETON.md)  | The skeleton every character uses: bone names, rest pose, axes, and model conventions. A copy of the game's `docs/skeleton.md`, the one skeleton reference. |
| `BPY_NOTES.md`                | Correct Blender Python calls for this task, and the ones that don't exist.                   |
| `build_template.py`           | Builds `template.blend` (the bare skeleton) next to itself.                                  |
| `example_build_character.py`  | A complete, working example: a box fighter, built and exported.                              |
| `export_glb.py`               | Exports the scene with the settings the game expects. Every build script calls it.           |
| `character_request.json`      | Your questionnaire answers, so the game can reopen them.                                     |

The agent adds `template.blend`, `build_character.py`, `previews/` (render images), `<name>.glb` (the character), and `<name>.json` (its name and description).

## Running the scripts yourself

```sh
blender -b --factory-startup --python build_template.py            # writes template.blend
blender -b --factory-startup --python example_build_character.py   # writes example.glb
```

On macOS, `blender` is `/Applications/Blender.app/Contents/MacOS/Blender` if it isn't on your PATH.
