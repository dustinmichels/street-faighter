# Run from source

The game is a [Godot](https://godotengine.org) 4.7 project. Running it from source works on macOS, Windows, and Linux.

## Requirements

| Tool                                                                     | For                                                           |
| ------------------------------------------------------------------------ | ------------------------------------------------------------- |
| [Godot 4.7](https://godotengine.org/download) (standard build, not .NET) | Running, editing, testing, and exporting the game.            |
| [Blender](https://www.blender.org/download/) 4.2+                        | Rebuilding the generated models, and the skeleton drift test. |
| [mise](https://mise.jdx.dev) (optional)                                  | The task shortcuts in `mise.toml`.                            |
| [Node.js](https://nodejs.org) (optional)                                 | This documentation site.                                      |

## Get the code and run it

```sh
git clone https://github.com/dustinmichels/street-faighter.git
cd street-faighter
godot --path .
```

Or in the editor: open Godot, **Import** the `project.godot` from the folder, then press <kbd>F5</kbd> (Run Project).

## Command-line options

Game options go after `--`:

| Option                               | Effect                                                                                  |
| ------------------------------------ | --------------------------------------------------------------------------------------- |
| `--host`                             | Host on port 7777 right away.                                                           |
| `--host --port=8888`                 | Host on another port.                                                                   |
| `--join=127.0.0.1:7777`              | Join a host right away.                                                                 |
| `--name=RYU`                         | Set the player name and skip the name screen.                                           |
| `--no-upnp`                          | When hosting, don't ask the router to forward the port (UPnP); for local testing.       |
| `--net-latency=MS`                   | Simulate one-way delay on this instance's input packets, in both directions.            |
| `--net-jitter=MS`                    | Add a random 0–MS delay per packet.                                                     |
| `--net-loss=PERCENT`                 | Drop that share of input packets.                                                       |
| `--validate-character /abs/path.glb` | Check a character model, print every problem or `OK`, and exit (use with `--headless`). |

For example: `godot --path . -- --host --name=RYU --net-latency=50 --net-jitter=20 --net-loss=5`.

The host and join shortcuts act on the first menu only: once a session ends, the instance stays in the menu and shows why. Set the network simulation on one instance only; its ping (and the <kbd>F3</kbd> overlay) includes the simulated delay, the other side's doesn't.

## Two instances on one machine

**Terminal:** `mise run mp` (alias of `mise run multiplayer`) starts a host and a joiner side by side, already connected; <kbd>Ctrl</kbd>+<kbd>C</kbd> closes both. Without mise:

```sh
godot --path . --resolution 960x540 --position 0,40 -- --host --no-upnp &
godot --path . --resolution 960x540 --position 960,40 -- --join=127.0.0.1:7777
```

**Editor:** Debug → Customize Run Instances… → check **Enable Multiple Instances**, set 2 instances, and give them these **Launch Arguments** (engine arguments first, then `--` and the game's own):

- Instance 1: `--resolution 960x540 --position 0,40 -- --host --no-upnp`
- Instance 2: `--resolution 960x540 --position 960,40 -- --join=127.0.0.1:7777`

<kbd>F5</kbd> then starts both, already connected. The setting is stored in `.godot/` (not versioned), so each checkout sets it once. If the editor embeds the running game (Game tab), turn that off (Game tab → "Embed Game on Next Play") so both windows appear.

Keyboard input goes to the focused window only; click the other window to play its fighter. A gamepad drives both instances at once.

## Debug keys

| Key           | Effect                                                                                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| <kbd>F3</kbd> | Network overlay under the left health bar: current and confirmed tick, the opponent's tick and your lead, rollbacks, stalled/skipped frames, packets received/lost. |
| <kbd>F1</kbd> | CPU difficulty: default / easy (`AIInput.EASY_KNOBS`).                                                                                                              |

The CPU's difficulty knobs (`reaction_ticks`, `block_chance`, `duck_chance`, `sweep_chance`, `aggression`, `punch_cooldown_ticks`) are on `Fighter2`'s `input` resource in `match/main.tscn`.

## Export a build

You need the Godot 4.7 export templates (Editor → Manage Export Templates). The repo has presets for macOS (universal binary, ad-hoc signed, not notarized), Windows (x86_64, unsigned), and Linux (x86_64). `mise run export` builds all three and zips them into `build/release/`:

```sh
godot --headless --path . --export-release macOS build/macos/street-fAIghter.zip
godot --headless --path . --export-release Windows build/windows/street-fAIghter.exe
godot --headless --path . --export-release Linux build/linux/street-fAIghter.x86_64
```

The version players see and the online handshake checks is `application/config/version` in `project.godot`; bump it for every release.

Every preset sets **Resources → Filters to export non-resource files** to `creator_kit/*`. The creator kits are written from those files, so a build without them can't make kits. Set the same filter on any preset you add.

## Publish a release

`mise run release` (or `mise run release minor`, `major`, `v1.2.3`) runs from a clean, up-to-date `main`. It exports all platforms, tags the next version, publishes a GitHub release with the zips, and pushes the builds to [itch.io](https://dustinmichels.itch.io/street-faighter) on the channels `mac`, `windows`, and `linux`. `mise run itch v1.2.3` pushes the current `build/` to itch.io again, if that step failed.

itch.io uploads go through [butler](https://itch.io/docs/butler/), which mise installs. Log in once with `butler login`, or run `mise run setup` to paste an [API key](https://itch.io/user/settings/api-keys) into the git-ignored `mise.local.toml`. The release stops before tagging if butler can't reach the project (`ITCH_TARGET` in `mise.toml`).

## Rebuilding generated assets

The shipped `.glb` characters and stage, `animations/base.res` and the sound effects in `match/sounds/` are generated. Rerun these only after editing their scripts:

| Asset                                | Command                                                                                                     |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Skeleton template                    | `blender -b --factory-startup --python creator_kit/build_template.py -- characters/template/template.blend` |
| Placeholder character                | `blender -b --factory-startup --python characters/default/source/build_default.py`                          |
| Street stage (backdrop, props, wall) | `blender -b --factory-startup --python stages/street/source/build_street.py`                                |
| Animation library                    | `godot --headless --path . -s animations/build_base.gd`                                                     |
| Sound effects                        | `godot --headless --path . -s match/sounds/build_sounds.gd`                                                 |

## Project layout

Code is grouped by entity: each folder holds a thing's scenes, scripts, and shaders together.

| Path                | What                                                                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `menu/`             | Start menu (the main scene), its theme, focus cursor, and title background shaders.                                                   |
| `character_screen/` | The CHARACTERS screen: library, creation wizard, model preview.                                                                       |
| `match/`            | The fight scene (`main.tscn`): simulation loop (`match.gd`), HUD, cameras, sound effects, outline and color quantization shaders.     |
| `fighter/`          | The fighter scene and its simulation (`fighter.gd`).                                                                                  |
| `input/`            | Input sources: keyboard, CPU, idle, and the per-tick buffers used online.                                                             |
| `online/`           | Netcode: the `Session` autoload, input and character exchange, UPnP port mapping.                                                     |
| `characters/`       | Loading, validating, and storing characters, the creator kit writer, the toon shader, the built-in fighter and the skeleton template. |
| `stages/`           | The stage script, steam effect, and the street stage.                                                                                 |
| `animations/`       | The animation library and the script that builds it.                                                                                  |
| `assets/`           | Shared assets: the pixel font (OFL), the logo, and the CC0 background music by Juhani Junkala (`assets/music/INFO.txt`).              |
| `creator_kit/`      | Files copied into every creator kit, including the skeleton reference `SKELETON.md`.                                                  |
| `tests/`            | Headless tests; see [Tests](./testing).                                                                                               |
| `docs/`             | This site (VitePress). Ignored by Godot (`docs/.gdignore`).                                                                           |
| `docs-todo/`        | Implementation plans and progress logs.                                                                                               |

## This documentation

The site lives in `docs/` and is built with [VitePress](https://vitepress.dev):

```sh
cd docs
npm install
npm run dev      # local preview with hot reload
npm run build    # static site in docs/.vitepress/dist
```

Or `mise run docs` / `mise run docs-build` from the project root.
