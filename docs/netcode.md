# Netcode

Decisions for online play (`docs/todo/multiplayer.md`, step 2). Each one gives the choice, the reasons for it, and when to revisit it.

## Sync model: input sync (lockstep with input delay, optional rollback)

Peers exchange only the per-tick input bitmask (`InputSource.LEFT | RIGHT | JUMP | PUNCH | BLOCK`, 5 bits in one byte, `InputSource.BUTTONS`). Both peers run the full simulation from the same start state and the same inputs. The simulation is never sent over the network. Everything the inputs feed into, including `Fighter.attack_buffer` (buffered presses) and `block_stun`, is simulation state in `Fighter.snapshot()`, so it is checksummed and saved and restored by rollback.

1. **Lockstep first.** Tick `t` simulates only after both peers' inputs for `t` have arrived. Local input is scheduled `D` ticks ahead (input delay, starting at 2–3 ticks) so that remote input usually arrives in time. When it doesn't, the game stalls for a tick instead of guessing.
2. **Rollback (optional, `Match.max_rollback` > 0).** This is the same model with a different way of handling missing input. The game predicts the missing input as a repeat of the last one, saves state each tick, and re-simulates when the real input differs. It needs the same determinism as lockstep, plus save/load of state, so building lockstep first lost no work.

Implementation (input pipeline): `InputSource.poll(tick)`/`has_input(tick)`; `LocalInput` (live source + input delay, `delay` ≥ 1), `NetworkInput` (inputs received by tick), both `TickInput`s keeping one byte per tick; `InputSync` sends every unacknowledged local input plus an ack each physics frame; in lockstep `Match._physics_process` stalls (counting `stalled_frames`) until every input for the tick is known. Tested by `tests/lockstep_test.gd`.

Implementation (rollback): `Match.step()` saves `save_state()` (`tick` + both `Fighter.snapshot()`s, restored by `Fighter.restore()`) and the checksum at the start of each tick in a ring buffer of `Match.HISTORY` = 10 ticks (`load_tick()`). Missing inputs are `InputSource.predict()`ed (`TickInput`: repeat the last known one) and the inputs each tick used are kept. Each frame the match first confirms the ticks whose real inputs have arrived, from `confirmed_tick` on; at the first mispredicted one it rewinds there and re-simulates to the current tick, then simulates one new tick. It predicts at most `max_rollback` (≤ 9) ticks past `confirmed_tick` and stalls beyond that, so a peer leads by at most the other's input delay + `max_rollback`. Only checksums of confirmed ticks (`checksum_at(t)`, `t ≤ confirmed_tick`) are final and comparable between peers. Visuals are derived from the state each frame (`Fighter.sync_visual()`), so a rewind needs nothing extra. Local input sources are sampled once per tick and stored (`LocalInput`), so re-simulation never re-polls the keyboard or the AI. Tested by `tests/lockstep_test.gd --rollback=N`.

Why custom rollback and not Snopek's "Godot Rollback Netcode" addon (gitlab.com/snopek-games/godot-rollback-netcode; Godot 4 on its `main` branch): the addon is built around its own `SyncManager` singleton that drives every networked node through `_network_process(input)` / `_save_state()` / `_load_state()` with `Dictionary` state, its own network adaptor and message serializer, input delay, ping and hashing. Adopting it would mean replacing `Match`'s single ordered `step(inputs)`, the integer snapshot and checksum and `InputSync`, all of which already exist and are tested, for features this game doesn't use (spawning, rollback-aware timers, sound, RNG helpers). Our core is about 60 lines in `Match` on top of state that was already one integer array. Revisit if rollback grows features the addon already has; its Log Inspector (replaying recorded matches, stepping to a mismatch) and its time sync (pinging and skipping frames so peers stay level, todo §5) are worth borrowing ideas from.

Why input sync over state sync (authoritative host):

- **It fits the code.** `Fighter` already advances once per 60 Hz physics tick by a fixed `TICK` and counts time in whole ticks (`scripts/fighter.gd`). It reads controls only through `InputSource.poll()`, which returns a bitmask, so a `NetworkInput` slots in without changing `Fighter`.
- **Fairness.** With state sync, the client's inputs reach the simulation one RTT late unless it predicts locally, and in a fighting game client-side prediction of hits and knockdowns means visible corrections. Input sync gives both players the same input delay.
- **Bandwidth.** About 1 byte per tick plus redundancy (every input the peer hasn't acknowledged, a few per packet), compared with snapshots of two fighters' full state at 60 Hz.
- **Desync detection.** A per-tick state checksum (`Match.checksum`) shows exactly where the peers diverge, which also makes a good regression test (`tests/determinism_test.gd`, see `README.md`).
- **Standard practice.** GGPO-style input delay plus rollback is what fighting games ship, and there is a Godot addon for it (Snopek's "Godot Rollback Netcode") if building it ourselves proves too costly.

What this costs (handled in todo §2):

- **The simulation must be bit-identical on both peers.** Current risks are `move_and_slide()` (Jolt) on `CharacterBody3D`, the `Area3D` space query in `hitbox_targets()`, float math across platforms and builds, `PUNCH_LENGTH` and the active window being read from clip times (floats converted to ticks), and the two fighters stepping in separate `_physics_process` calls whose order depends on the scene tree. All of these must become one `step(inputs)` that the match drives in a fixed order.
- **Visuals must follow the simulation.** Animation has to be driven by the tick counter, not by wall-clock time.

Revisit if determinism across platforms can't be achieved at reasonable cost. The fallback is state sync with the host as the authority. The input pipeline (§3) still applies: the client sends inputs and the host sends snapshots.

## Transport: `ENetMultiplayerPeer` (UDP, direct IP)

Use Godot's high-level multiplayer API (`multiplayer.multiplayer_peer`) with `ENetMultiplayerPeer`. The host calls `create_server(port, 1)` and the client calls `create_client(ip, port)`.

- **Input packets** go through `InputSync._receive_inputs`, an `@rpc("any_peer", "call_remote", "unreliable_ordered", 1)` method carrying `(ack, first tick, input bytes, match tick, advantage)`: every local input from the first tick the peer hasn't acknowledged, the first remote tick this side still lacks, and the tick sync values (see "Session" → tick sync). One goes out every physics frame. Unreliable, so a lost packet is never retransmitted and stale inputs never block newer ones (the next packet repeats unacknowledged inputs). It uses its own channel so that it doesn't share ordering with control traffic.
- **Control messages** (handshake, match config, start tick, rematch, disconnect reason) go through `"reliable"` RPCs on channel 0.
- **Ping** comes from `ENetPacketPeer.get_statistic(PEER_ROUND_TRIP_TIME)` (`InputSync.rtt_ms`) for the HUD and tick sync.

Why ENet:

- It ships with every desktop export and needs no extension and no extra service. Two instances on one machine (`127.0.0.1`) or over a LAN work right away, which makes testing fast.
- It provides UDP with unreliable and reliable channels on one socket, which covers both kinds of traffic above.

Why not WebRTC (yet):

- On desktop, `WebRTCMultiplayerPeer` needs the `webrtc-native` GDExtension. It also needs a signaling server and STUN (plus TURN as a fallback) before two peers can connect at all. Its benefits, NAT traversal and web export, aren't goals for this step.
- Gameplay code talks only to `multiplayer` and RPCs, never to ENet directly. Switching to `WebRTCMultiplayerPeer` later means changing peer creation in the session code only.

Cost: internet play needs the host to forward the UDP port (default `7777`, configurable; see todo §6), or both players need a VPN such as Tailscale or ZeroTier. Revisit (WebRTC, or a relay) if port forwarding turns out to be too much friction for players.

## Topology: peer-to-peer host/join (one player hosts)

One player picks Host and becomes ENet peer `1` and fighter 1. The other picks Join and becomes fighter 2. There is no server process. The host differs from the client only in session duties: it accepts the connection, checks the version handshake, and picks the match config, the start tick, and the rematch. Gameplay is symmetric. Each peer simulates both fighters from both input streams, and neither one is authoritative over the simulation.

Why not a dedicated server:

- With input sync, a server would only forward input bytes. It adds a hop of latency and has hosting costs, and it buys nothing for a 1v1 match except NAT traversal and protection against a host who cheats.
- Cheating is limited anyway. A peer can only send its own inputs, and any state tampering shows up as a checksum mismatch (todo §7).
- No hosting, deployment, or headless export is needed to play.

Revisit when the final step adds custom characters. That step already needs an HTTP upload/validation service (`notes.md` → "Multiplayer distribution"), and the same service could host room codes, WebRTC signaling, or a relay. Matches would stay peer-to-peer. A relay would only forward packets, so this design keeps working.

## Session

`Session` (autoload, `scripts/session.gd`) owns the connection across scene changes. After the version handshake the host picks the match config (`_new_match_config()`: stage scenery, each fighter's character `.glb` = tint, `seed`, `max_rollback`, `start_tick`) and sends it with the reliable `_start_match(config)` RPC, so both peers load `main.tscn` with the same choices; `main.gd` applies it with `Match.apply_config()` before the scene is ready. Once loaded, each side sends its `Match.effective_config()` (the applied config plus scene-file values: stage `half_width`, start positions, tick rate) with `_peer_loaded_rpc`, and `begin()` runs only when both are equal (`Session.config_mismatch()`); otherwise both sides end the session naming the first differing key, before the first tick.

Start: `start_tick` is `Session.COUNTDOWN_TICKS` (180 = 3 s). `Match.step()` simulates the ticks before it with all inputs 0, and the HUD shows "3", "2", "1", then "FIGHT!" from `Hud.countdown_text(Match.tick, start_tick)`. Both are functions of the simulation tick, not of each machine's clock, so in lockstep both peers see each number and the first controllable tick (`start_tick`) at the same tick, even if one started its scene later. Inputs still flow during the countdown, so the input pipeline is warm when the fight starts. Offline matches keep `start_tick` 0 (no countdown).

Tick sync: each input packet also carries the sender's `Match.tick` and its smoothed `InputSync.advantage` = own tick − (peer's last reported tick + RTT/2 in ticks). `InputSync.lead()` = (own advantage − peer's advantage) / 2 is how far this side leads; the latency terms cancel, so asymmetric or imprecise RTT barely matters. When it is ≥ `SKIP_THRESHOLD` (1 tick), the side calls `Match.skip_frame()`: the next physics frame simulates nothing (`Match.skipped_frames`), at most once every `SKIP_INTERVAL` (20) frames, i.e. ≤ 5% slower. Without it, a peer whose clock runs fast runs ahead until it hits the input delay and then stalls in bursts, and its lead eats the delay budget that should absorb latency. Measured (two processes, host forced to 63 Hz after the start): without tick sync the host stalls 73 frames in 1500 ticks at a lead of 3 (the input delay); with it, 74 spread-out skipped frames, 1 stall, lead ≈ 1. Timing only: skipping never changes the simulation or checksums.
