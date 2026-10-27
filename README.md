# Street fAIGhter

This is a multiplayer fighting game, styled after Street Fighter.

The key feature is that user can bring their own AI coding agent (eg Claude Code) to generate a custom character which they can import into the game.

## Running the game

Requires [Godot](https://godotengine.org/download) 4.7 (standard build, not .NET).

- Editor: open Godot, import `project.godot` from this folder, then press F5 (Run Project).
- Command line, from this folder: `godot --path .`

The game opens on a start menu: choose **Singleplayer** to start a match. **Multiplayer (online)** is shown but disabled until online play is implemented.

In singleplayer you control the red fighter on the left against a computer-controlled blue fighter (`scripts/ai_input.gd`): it walks in and jabs, jumps in with air kicks, backs off, and sometimes blocks. Knock it out with 10 hits before it does the same to you. Its difficulty knobs (`reaction_ticks`, `block_chance`, `aggression`, `punch_cooldown_ticks`) are on `Fighter2`'s `input` resource in `scenes/main.tscn`.

### Controls

| Action     | Keyboard            | Gamepad                  |
| ---------- | ------------------- | ------------------------ |
| Move       | A / D or ← / →      | D-pad or left stick      |
| Jump       | W / ↑ / Space (hold to keep jumping; add a direction during the takeoff to jump that way) | D-pad up or stick up |
| Punch      | J or Z (kick while airborne) | X / □ or A / ✕     |
| Block      | K or X (hold)       | RB / R1 or RT / R2 (hold) |
| Controls   | Esc                 | Start                    |
| Restart    | R (any time)        | Back / Select            |

- Hold block to guard in place against hits from the front. You don't move while guarding, and letting go makes you act again immediately. A blocked hit holds your guard for 0.2 s.
- Punches are buffered: a press up to 4 ticks early comes out on the first tick you can act. This covers presses during recovery, hit stun, blockstun and the jump landing. The 5-tick window matches Street Fighter 6.
- WASD is for the left hand with J (punch) and K (block) for the right. With the arrow keys in the right hand, use Z (punch) and X (block) with the left.

Keys are bound by physical position, so on non-QWERTY layouts use the keys where W/A/D/J/K/Z/X/R sit on a QWERTY keyboard.

In game, press Esc or click the **Controls** button (bottom-right) to show or hide this list.

### Rebuilding generated assets

The shipped `.glb` characters and stage and `animations/base.res` are generated; rerun these only after editing their scripts:

- Skeleton template: `blender -b --factory-startup --python characters/template/build_template.py`
- Placeholder characters: `blender -b --factory-startup --python characters/default/source/build_default.py`
- Street stage (backdrop, props, wall pillar): `blender -b --factory-startup --python stages/street/source/build_street.py`
- Animation library: `godot --headless --path . -s animations/build_base.gd`

### Determinism test

Online play relies on both machines simulating identically. Check it with:

```sh
godot --headless --path . -s tests/determinism_test.gd
```

It records an AI vs AI match's inputs, replays them twice and compares the state checksum every tick (exit code 1 and the first differing tick on a desync). To compare two machines, run `-- --save-log=a.inputs --checksums=a.sums` on one, then `-- --log=a.inputs --expect=a.sums` on the other. Other options are listed at the top of the script.

### Lockstep test

Checks the online input exchange without a second machine:

```sh
godot --headless --path . -s tests/lockstep_test.gd
```

It connects a host and a client match over ENet on `127.0.0.1` (UDP port 27777) in one process, both players AI-driven through the online input path, drops 30% of packets and randomly delays frames, and checks that both sides compute the same checksum every tick, that it matches an offline replay of the same inputs, and that neither side runs ahead further than allowed (exit code 1 otherwise). It runs lockstep by default; `--rollback=N` (1–9) tests rollback instead, predicting up to N ticks ahead. Options (`--ticks`, `--loss`, `--stall`, `--delay`, `--rollback`, `--port`, `--seed`) are listed at the top of the script.

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
