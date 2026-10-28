# Tests

All tests are headless Godot scripts. Each exits 0 on success and 1 with a list of failures.

| Test                                        | Command                                                          | Needs   |
| ------------------------------------------- | ---------------------------------------------------------------- | ------- |
| [Determinism](#determinism)                 | `godot --headless --path . -s tests/determinism_test.gd`         |         |
| [Lockstep](#lockstep)                       | `godot --headless --path . -s tests/lockstep_test.gd`            |         |
| [Creator kit](#creator-kit)                 | `godot --headless --path . -s tests/creator_kit_test.gd`         |         |
| [Character library](#character-library)     | `godot --headless --path . -s tests/character_library_test.gd`   |         |
| [Character validator](#character-validator) | `godot --headless --path . -s tests/character_validator_test.gd` |         |
| [Character special](#character-special)     | `godot --headless --path . -s tests/character_special_test.gd`   |         |
| [Skeleton drift](#skeleton-drift)           | `godot --headless --path . -s tests/skeleton_drift_test.gd`      | Blender |
| [Character sync](#character-sync)           | `godot --headless --path . -s tests/character_sync_test.gd`      |         |

## Determinism

Online play relies on both machines simulating identically. The test records an AI vs AI match's inputs, replays them twice, and compares the state checksum every tick (exit code 1 and the first differing tick on a desync).

To compare two machines, run `-- --save-log=a.inputs --checksums=a.sums` on one, then `-- --log=a.inputs --expect=a.sums` on the other. Other options are listed at the top of the script.

## Lockstep

Checks the online input exchange without a second machine. It connects a host and a client match over ENet on `127.0.0.1` (UDP port 27777) in one process, both players AI-driven through the online input path, drops 30% of packets, and randomly delays frames. It checks that both sides compute the same checksum every tick, that it matches an offline replay of the same inputs, and that neither side runs ahead further than allowed.

It runs lockstep by default; `--rollback=N` (1–9) tests rollback instead, predicting up to N ticks ahead. Options (`--ticks`, `--loss`, `--stall`, `--delay`, `--rollback`, `--port`, `--seed`) are listed at the top of the script.

## Creator kit

Checks `CreatorKit` (`characters/creator_kit.gd`): slugs can't escape the kit directory, shell quoting and the agent command for POSIX shells and PowerShell, the per-platform `PROMPT.md` (Blender locations, `venv` commands), sanitizing answers so they can't inject lines, fences or placeholders into `creator_kit/PROMPT_TEMPLATE.md`, and writing a kit folder (into `user://creator_kit_test`, removed afterwards), including `kit_config.json` (the `.glb` name and `CreatorKit.validator_args()`) and that saving again keeps the agent's own files.

## Character library

Checks `CharacterLibrary` (`characters/character_library.gd`) in a temporary library under `user://character_library_test`: invalid files are rejected, entries are keyed by SHA-256 and deduplicated, re-importing changed bytes replaces the entry and moves selections to it, a broken source keeps the old entry, and a deleted choice falls back to the default character.

## Character validator

Checks `CharacterValidator` (`characters/character_validator.gd`) and the `--validate-character` command line: `default.glb` and `tests/fixtures/valid.glb` pass, and each broken fixture in `tests/fixtures/` (missing, renamed, or extra bone, a part named like a bone, a moved joint, too many triangles, a transparent material, a rotated or scaled Armature, an oversized texture) fails with exactly its expected errors. The exact command the creator kit gives `kit.py` (`CreatorKit.validator_args()`, in `kit_config.json`) is run on `default.glb` and one broken fixture, checking its exit code and output.

The fixtures are committed. After changing the skeleton, rebuild them with `blender -b --factory-startup --python tests/fixtures/build_bad_characters.py`, then update the expected messages in the test.

## Character special

Checks `CharacterSpecial` (`characters/character_special.gd`), a character's own special throw:

- The standard throw written as a special (`CharacterSpecial.kit_base().standard`, which every creator kit gets) shows the standard throw. The victim's clip matches `thrown` on every tick, its root matches `Fighter.THROW_PATH`, and the thrower's clip matches `throw` on its keys.
- Broken data fails with exactly its expected errors.
- A special injected into `tests/fixtures/valid.glb`'s extras passes the validator and rides along on the loaded model. A broken one fails the file.

## Skeleton drift

Needs Blender (`blender` on `PATH`, or `BLENDER=/path/to/blender`). Builds the template with `creator_kit/build_template.py` (which uses `creator_kit/kit.py`'s bone list, the one build scripts get from `start()`) via `tests/dump_skeleton.py`, dumps the rig Blender actually made (bone names, parents, head/tail, connected, roll, local axes), and checks that it matches:

- the tables in `creator_kit/SKELETON.md` (the [Skeleton](./skeleton) page, copied into every kit),
- the rest pose of `characters/default/default.glb` (the validator's reference),
- `CharacterLoader.REQUIRED_BONES`.

## Character sync

Checks online custom characters with two processes (this one hosts and starts a client copy) over ENet on `127.0.0.1` (UDP port 27812, `-- --port=N`), each with its own library under `user://character_sync_test/`.

The client's custom character is transferred, validated, cached under `remote/`, and shown on the host; a rematch and a second session reuse the cache without a new transfer; a character whose bytes don't match its SHA-256 is rejected and the host shows the default. Both sides must report the same checksum at tick 200 in every match.
