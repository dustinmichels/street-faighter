# Street fAIGhter

This is a multiplayer fighting game, styled after Street Fighter.

The key feature is that user can bring their own AI coding agent (eg Claude Code) to generate a custom character which they can import into the game.

## Running the game

Requires [Godot](https://godotengine.org/download) 4.7 (standard build, not .NET).

- Editor: open Godot, import `project.godot` from this folder, then press F5 (Run Project).
- Command line, from this folder: `godot --path .`

The game opens on a start menu: choose **Singleplayer** to start a match. **Multiplayer (online)** is shown but disabled until online play is implemented.

In singleplayer you control the red fighter on the left; the blue fighter stands idle. Knock it out by punching it 10 times.

### Controls

| Action     | Keys               |
| ---------- | ------------------ |
| Move left  | A / ←              |
| Move right | D / →              |
| Jump       | W / ↑ / Space      |
| Punch      | J                  |
| Controls   | Esc                |
| Restart    | R (any time)       |

Keys are bound by physical position, so on non-QWERTY layouts use the keys where W/A/D/J/R sit on a QWERTY keyboard.

In game, press Esc or click the **Controls** button (bottom-right) to show or hide this list.

### Rebuilding generated assets

The shipped `.glb` characters and `animations/base.res` are generated; rerun these only after editing their scripts:

- Skeleton template: `blender -b --factory-startup --python characters/template/build_template.py`
- Placeholder characters: `blender -b --factory-startup --python characters/default/source/build_default.py`
- Animation library: `godot --headless --path . -s animations/build_base.gd`

## First Step

No multiplayer. Create very basic fighting game. It looks like 2D pixel art but is driven by real 3D models.

- Find/create a basic character skeleton that can be rigged to do a few basic moves.
  - Walk left/right
  - Jump
  - Punch
  - Fall over

Player will control 1, and the other will do nothing for now.

## Next step

Add multiplayer mode, so two players can control each character, online.

## Final step

Custom character import pipeline.
