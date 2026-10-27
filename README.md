# Street fAIghter

A multiplayer fighting game in the style of Street Fighter: pixel art driven by real 3D models. Bring your own AI coding agent (Claude Code, Codex, Gemini CLI, …) to build a custom fighter in Blender, import it, and take it online.

**Documentation:** [`docs/`](docs/) is a VitePress site with the player guide and the developer docs. Preview it with `mise run docs`, or `cd docs && npm install && npm run dev`.

| Players                                                         | Developers                                              |
| --------------------------------------------------------------- | ------------------------------------------------------- |
| [Download & install](docs/guide/download.md)                    | [Run from source](docs/dev/index.md)                    |
| [How to play](docs/guide/playing.md)                            | [Tests](docs/dev/testing.md)                            |
| [Online multiplayer](docs/guide/online.md)                      | [Netcode](docs/dev/netcode.md)                          |
| [Make your own fighter](docs/guide/custom-characters.md)        | [Custom character pipeline](docs/dev/custom-characters.md) |
| [Troubleshooting](docs/guide/troubleshooting.md)                | [Skeleton](creator_kit/SKELETON.md)                     |

## Quick start from source

Requires [Godot](https://godotengine.org/download) 4.7 (standard build, not .NET).

```sh
godot --path .            # play
mise run mp               # two connected instances side by side
godot --headless --path . -s tests/determinism_test.gd   # one of the tests in tests/
```

Plans and progress logs are in [`docs-todo/`](docs-todo/).
