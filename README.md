# Street fAIGhter

This is a multiplayer fighting game, styled after Street Fighter.

The key feature is that user can bring their own AI coding agent (eg Claude Code) to generate a custom character which they can import into the game.

## Running the game

Requires [Godot](https://godotengine.org/download) 4.7 (standard build, not .NET).

- Editor: open Godot, import `project.godot` from this folder, then press F5 (Run Project).
- Command line, from this folder: `godot --path .`

The game opens on a start menu: choose **Singleplayer** to start a match against AI, or **Multiplayer (online)** to host or join an online peer-to-peer match.
In singleplayer you control the red fighter on the left against a computer-controlled blue fighter (`scripts/ai_input.gd`): it walks in and jabs or sweeps, jumps in with air kicks, backs off, and sometimes blocks or ducks your punches, answering a ducked punch with a sweep. Knock it out with 10 hits before it does the same to you. Its difficulty knobs (`reaction_ticks`, `block_chance`, `duck_chance`, `sweep_chance`, `aggression`, `punch_cooldown_ticks`) are on `Fighter2`'s `input` resource in `scenes/main.tscn`.

### Online Multiplayer & Hosting

Online play connects two players peer-to-peer using Godot's ENet transport (UDP). One player acts as the host (red fighter, player 1) and the other joins (blue fighter, player 2).

#### Hosting & Joining

1. **Host:** Click **Multiplayer (online)**, optionally enter a UDP port (default `7777`), and click **Host**.
2. **Join:** Click **Multiplayer (online)**, enter the host's IP address (and port if not 7777, e.g. `192.168.1.50`, `203.0.113.19:8000` or `[2001:db8::5]:7777` for IPv6), and click **Join**.
3. **Match start:** Once both games have loaded the match, a shared "3, 2, 1, FIGHT!" countdown starts it on both machines at the same tick.
4. **Rematch:** When a fighter is knocked out (KO), both players can press **R** (Restart) to agree to a rematch on the same connection. Online, R does nothing before the KO.

Both players need the same build: the joiner sends its game version (`application/config/version` in `project.godot`) and network protocol version, and the host refuses a mismatch; both menus show the reason. If the opponent quits, nothing arrives from them for 5 s, or the two games go out of sync (desync), the match freezes, shows why, and returns to the menu after 3 s.

The game runs in lockstep with an input delay of 3 ticks (50 ms): each side waits for the opponent's input for a tick before simulating it, so it only plays at full speed while inputs arrive within that delay. Measured: full speed on a LAN (~15 ms ping); about 20% of frames spent waiting at ~70 ms ping with some jitter and 2–7% packet loss; about half speed at ~150 ms ping. The bottom-left HUD shows the ping and input delay during a match, and F3 shows the stalled frames.

#### Port Forwarding for Internet Hosting

When hosting over the public internet with direct IP:

- **Protocol:** **UDP** (ENet uses UDP packets; TCP forwarding will not work).
- **Port:** **7777** UDP (or your custom configured port).
- **Who forwards:** Only the **host** needs to forward a port on their router. The joining client does not need to forward any ports.
- **Router Setup:**
  1. Look up your host computer's local IP address (e.g. `192.168.1.X`).
  2. In your router settings, create a port forwarding rule directing incoming **UDP** traffic on port `7777` to your computer's local IP.
  3. Ensure your local firewall (Windows Defender, macOS Firewall, etc.) allows incoming UDP traffic for Godot.
  4. Give your public IP address to the other player.
- **No Port Forwarding needed:**
  - **Local LAN:** If both machines are on the same local Wi-Fi/Ethernet network, the joiner connects directly to the host's local IP (e.g. `192.168.1.X`).
  - **Mesh VPN:** Using a free mesh VPN like [Tailscale](https://tailscale.com/) or [ZeroTier](https://www.zerotier.com/), players can connect directly using their virtual VPN IP without touching router NAT settings.
  - **Local testing:** Connect two instances on the same machine via `127.0.0.1:7777`.

#### Command Line Shortcuts

- Host on port 7777: `godot --path . -- --host`
- Host on a custom port: `godot --path . -- --host --port=8888`
- Join a host: `godot --path . -- --join=127.0.0.1:7777`
- Simulate a worse network on this instance: add `--net-latency=MS` (one-way delay added to each direction), `--net-jitter=MS` (extra random 0–MS delay per packet) and/or `--net-loss=PERCENT`, e.g. `godot --path . -- --host --net-latency=50 --net-jitter=20 --net-loss=5`. It shapes the input packets this instance sends and receives, so set it on one instance only; that side's ping (and the F3 overlay) includes it, the other side's ping doesn't.

These shortcuts act on the first menu only: once a session ends, the instance stays in the menu and shows why.

#### Two Instances on One Machine

- **Editor:** Debug → Customize Run Instances… → check **Enable Multiple Instances**, set 2 instances, and give them these **Launch Arguments** (engine arguments first, then `--` and a space before the game's own):
  - Instance 1: `--resolution 960x540 --position 0,40 -- --host`
  - Instance 2: `--resolution 960x540 --position 960,40 -- --join=127.0.0.1:7777`

  Then Run Project (F5) starts both, side by side, already connected. Add the `--net-…` options to one of them to test a worse network. The setting is stored in `.godot/` (not versioned), so each checkout sets it once. If the editor embeds the running game (Game tab), turn that off (Game tab → "Embed Game on Next Play") so both windows appear.
- **Terminal:** `godot --path . --resolution 960x540 --position 0,40 -- --host & godot --path . --resolution 960x540 --position 960,40 -- --join=127.0.0.1:7777`

Keyboard input goes to the focused window only; click the other window to play its fighter. A gamepad drives both instances at once.

### Controls

| Action   | Keyboard                                                                                  | Gamepad                   |
| -------- | ----------------------------------------------------------------------------------------- | ------------------------- |
| Move     | A / D or ← / →                                                                            | D-pad or left stick       |
| Jump     | W / ↑ / Space (hold to keep jumping; add a direction during the takeoff to jump that way) | D-pad up or stick up      |
| Punch    | J or Z (kick while airborne, sweep while crouching)                                       | X / □ or A / ✕            |
| Block    | K or X (hold)                                                                             | RB / R1 or RT / R2 (hold) |
| Crouch   | S or ↓ (hold)                                                                             | D-pad down or stick down (hold) |
| Controls | Esc                                                                                       | Start                     |
| Restart  | R (any time)                                                                              | Back / Select             |
| Network debug overlay | F3                                                                             | —                         |

- Hold block to guard in place against hits from the front. You don't move while guarding, and letting go makes you act again immediately. A blocked hit holds your guard for 0.2 s.
- Hold crouch to duck in place: punches pass over you, but air kicks still hit. You don't move while crouching, and a held block takes priority.
- Punch while crouching to sweep: a low spinning kick (one full turn, the back leg swinging around along the floor) that knocks the opponent off their feet (10 damage). When you sweep, the camera also orbits all the way around the fighters during the kick, with the street dimmed and the fighters lit up so they stay easy to follow; your opponent's sweeps don't move your camera. They stay down about 1.15 s, can't be hit while down, then get back up. Blocking and crouching don't stop a sweep; only jumping does. The jump has to start before the sweep's active frames (6 ticks after the press), and its takeoff already counts.
- Punches are buffered: a press up to 4 ticks early comes out on the first tick you can act. This covers presses during recovery, hit stun, blockstun and the jump landing. The 5-tick window matches Street Fighter 6.
- WASD is for the left hand with J (punch) and K (block) for the right. With the arrow keys in the right hand, use Z (punch) and X (block) with the left.

Keys are bound by physical position, so on non-QWERTY layouts use the keys where W/A/S/D/J/K/Z/X/R sit on a QWERTY keyboard.

In game, press Esc or click the **Controls** button (bottom-right) to show or hide this list. F3 toggles a network debug overlay under the left health bar: current and confirmed tick, the opponent's tick and your lead, rollbacks, stalled/skipped frames, and packets received/lost with the loss over the last second.

### Rebuilding generated assets

The shipped `.glb` characters and stage and `animations/base.res` are generated; rerun these only after editing their scripts:

- Skeleton template: `blender -b --factory-startup --python creator_kit/build_template.py -- characters/template/template.blend`
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
