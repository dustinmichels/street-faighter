# TODO — Step 2: Online multiplayer

Goal: two players, each on their own machine, control one fighter each in the same match over the internet.

Builds on step 1 (`todo.md`):

- `Fighter` reads input through an input source abstraction (`PlayerInput` / `IdleInput`); add a `NetworkInput` without changing `Fighter`.
- All gameplay logic runs on a fixed 60 Hz physics tick, which is what makes input-based netcode possible.
- Custom character upload/distribution (`notes.md` → "Multiplayer distribution") belongs to the final step. Here both players use the default character with different tints.

## 1. Netcode model

- [x] Choose the sync model and record the decision in `docs/netcode.md`:
  - Input sync (lockstep with input delay, optionally rollback later): send only inputs per tick; both peers simulate. Small bandwidth, the usual approach for fighting games, but the simulation must be deterministic.
  - State sync (authoritative host): the host simulates and sends snapshots, and the client predicts. More tolerant of non-determinism but adds input lag on the client.
- [x] Choose the transport: Godot high-level multiplayer with `ENetMultiplayerPeer` (UDP, direct IP / port forward), or `WebRTCMultiplayerPeer` if NAT traversal or a web build is needed.
- [x] Choose the topology: peer-to-peer host/join (one player hosts) vs. a dedicated server.
  - Decisions in `docs/netcode.md`: input sync (lockstep → rollback), ENet, P2P host/join. §2 must remove the `move_and_slide`/`Area3D` query/per-node `_physics_process` order dependencies.

## 2. Deterministic simulation

Required for input sync; also useful for state sync with prediction.

- [x] Move all gameplay state (position, velocity, state machine, frame counters, health) into plain variables advanced in one `step(inputs)` per tick, not driven by `_process` or wall-clock time.
  - `Match` (`scripts/match.gd`, on `main.tscn` `World`) polls both `Fighter.input`s in order and calls `step(inputs: PackedInt32Array)`; it calls `Fighter.step(buttons, opponent_x, threatened)` for both (opponent x and proximity-guard threat from tick start), then push-apart, screen-edge limit, and hits (both detected before either applies, so trades happen). Fighters have no `_physics_process`; `sync_visual()` only displays the state.
- [x] Avoid Godot physics nondeterminism in gameplay: use custom kinematic movement and shape overlap checks, or confirm that `CharacterBody3D` / `Area3D` results are reproducible.
  - `Fighter` is a plain `Node3D`: `_move()` clamps to the floor (y = 0) and `wall_limit` (from `Stage.half_width` minus `BODY_RADIUS`, set by `Match`), `shove()` for push-apart. Hurtbox/hitbox/body shapes and the stage's static bodies/physics layers are gone.
- [x] Prefer integer or fixed-point math for positions and velocities, or verify that float results match across platforms.
  - All simulation math is `int`: positions in `Fighter.SCALE` units (1/10000 m), speeds per tick, accelerations per tick², durations in ticks (constants rounded, e.g. `WALK_SPEED` 333 ≈ 2 m/s, `GRAVITY` 69). Floats only at setup (scene positions, `Stage.half_width`, clip marker times → ticks, all from identical files) and in display (`sync_visual()`). `AIInput` ranges are in units too.
- [x] Use a seeded RNG owned by the match, if any randomness exists.
  - The simulation has no randomness. `Match.rng_seed` seeds the only random source, the AI: `Match._ready()` calls `InputSource.start(rng_seed + i)` per fighter, and `AIInput.start()` seeds its RNG and resets its plan state. Verified headless: AI vs AI for 1500 ticks, same seed gives identical per-tick state, a different seed diverges.
- [x] Drive animations from the simulation frame counter (seek `AnimationPlayer` to the state's frame) so visuals follow the simulation, not the other way round.
  - The simulation no longer touches the `AnimationPlayer` (`change_state`/`_set_jump_phase`/`face` only set state). `Fighter.sync_visual()` → `_pose()` picks the clip with `_state_clip()` (state + `jump_phase`; `HIT` = `knockdown` up to `HIT_RECOIL_END`) and seeks it to `state_ticks * TICK`, wrapped for looping clips and held at the end otherwise (walk mirrored to `length - t` when retreating). The player uses `ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`, so the pose depends only on the state, and is correct after a rollback restore too. Verified headless (AI vs AI, 1500 ticks, 2 seeds): sim trace hash unchanged, the clip matches the state every tick, and the same (clip, state, tick, direction) always gives the same bone pose and clip time. A windowed render shows a mid-punch pose.
- [x] Hit detection uses game-defined hitbox/hurtbox shapes evaluated in `step()` on the active frames, not physics signals.
  - Already in place from the earlier items: `Match.step()` calls `Fighter.attack_connects()` for both fighters before applying either. That checks `is_hitbox_active()` (clip-marker windows in ticks), `attack_landed`, and an integer overlap test of the square hitbox (`hitbox_center()`, `HITBOX_HALF`) against the capsule hurtbox (`hurtbox_overlaps()`). No `Area3D`/collision shapes/signals remain in `scripts/` or `scenes/`. Verified headless via `Match.step()`: a punch in range lands on active tick 5 exactly once, out of range misses, simultaneous punches trade, holding back blocks (no damage, block push), and the air kick lands once in its window.
- [x] Add a state checksum per tick (hash of the gameplay state) for desync detection.
  - `Fighter.snapshot()` returns every simulation variable as a `PackedInt64Array` (fixed order); `Match.state_checksum()` hashes `tick` + both snapshots (32-bit FNV-1a over 32-bit words, integer-only) and `Match.step()` stores it in `Match.checksum` (also set in `_ready()` for tick 0). Verified headless: same seed → identical 601 checksums, all distinct; changing one fighter's health at tick 300 changes the checksum from that tick on.
- [x] Headless determinism test: replay one recorded input log twice (and on two machines) and compare checksums every tick.
  - `tests/determinism_test.gd` (`godot --headless --path . -s tests/determinism_test.gd`, usage in `README.md`): records an AI vs AI input log (2 bytes/tick), replays it twice in fresh `main.tscn` matches (first with `_sync_visuals()` every tick, second without), compares per-tick `Match.checksum` with each other and with the recording; `--save-log`/`--checksums`/`--log`/`--expect` for cross-machine runs; exit 1 on desync. Verified: 3600 ticks pass (seeds 1 and 7); a separate process replaying the saved log matches the saved checksums; a tampered checksum file fails at the right tick; the x86_64 build (Rosetta, `arch -x86_64 godot`) reproduces the arm64 checksums exactly. Harness note: in `-s` scripts the root isn't in the tree during `_initialize()`, so set up deferred.

## 3. Input pipeline

- [x] Pack inputs into a compact per-tick bitmask (`move_left`, `move_right`, `jump`, `punch`, `block`). Rollback snapshots must include `Fighter.attack_buffer` and `block_stun`.
  - Already the format: `InputSource` bits `LEFT | RIGHT | JUMP | PUNCH | BLOCK` (5 bits, one byte per tick); added `InputSource.BUTTONS` (all defined bits) for validating received bytes. `attack_buffer` and `block_stun` are in `Fighter.snapshot()` (checksummed). `docs/netcode.md` updated.
- [x] `LocalInput`: samples the keyboard each tick and tags it with the tick number.
  - `InputSource.poll(tick)` now takes the simulation tick (live sources ignore it). `TickInput` (`scripts/tick_input.gd`) keeps one byte per tick from tick 0 (`end_tick()`, `inputs_from()`); `LocalInput` (`scripts/local_input.gd`) extends it, samples its `source` (`PlayerInput` by default; any live source works, e.g. `AIInput` in tests) once per tick on first `poll(tick)` and stores it under that tick. Verified headless with `Input.action_press`: stored bytes match the pressed keys per tick, re-polling returns the stored sample.
- [x] `NetworkInput`: an input source for the remote fighter that serves inputs received from the peer by tick number.
  - `scripts/network_input.gd` (extends `TickInput`): `receive(first, inputs)` appends the not-yet-known part of a run (skips repeats, ignores runs that would leave a gap or start below 0, masks with `BUTTONS`), returns the count added. New `InputSource.has_input(tick)` (default true; `TickInput`: tick < `end_tick()`; `LocalInput`: always). Verified headless: overlapping/gapped runs, and a match fed fighter 2's inputs through `NetworkInput` in overlapping chunks matches the reference checksums for 600 ticks.
- [x] Input delay buffer (start at 2–3 ticks) so remote inputs usually arrive before they are needed.
  - `LocalInput.delay` (default `DEFAULT_DELAY` = 3 ticks, 1–15, asserted ≥ 1: with 0, lockstep deadlocks since neither side samples a tick before simulating it): `start()` prefills ticks `0 .. delay - 1` with 0, and `poll(t)` samples the source for tick `t + delay`, so each local sample exists `delay` ticks before it is simulated (on both peers). Peers may use different delays. Verified headless: a press at tick 10 is polled at tick 13 with delay 3; `start()` resets the buffer.
- [x] Send each packet with the last N inputs (redundancy) over unreliable/unordered UDP to absorb packet loss.
  - `InputSync` node (`scripts/input_sync.gd`, `local`/`remote` exports, `peer_id`, `reset()`): every physics frame (priority 1, after `Match`) sends `_receive_inputs(ack, first, inputs)` via `@rpc("any_peer", "call_remote", "unreliable_ordered", 1)`: all local inputs from the first tick the peer hasn't acknowledged (≤ `MAX_INPUTS` = 60) plus an ack of the remote ticks received. Sends even while stalled, so acks flow and a lost packet can't deadlock. Ignores senders other than `peer_id`. Must sit at the same node path on both peers; §5 must create it, set `peer_id`, and call `reset()` on (re)start. Verified headless: host and client matches in one process (separate `SceneMultiplayer` branches, ENet loopback), AI-driven `LocalInput`s, 30% of sends dropped: 1200 ticks (through a KO) with identical per-tick checksums.
- [x] Handle missing remote input: stall (lockstep) or predict it as a repeat of the last input (rollback).
  - Lockstep stall: `Match._physics_process` simulates a tick only when every fighter's `input.has_input(tick)`, else counts `Match.stalled_frames` and waits (offline sources always have input, so local play is unchanged). Permanent test `tests/lockstep_test.gd` (usage in `README.md`): host + client over ENet loopback, AI-driven `LocalInput`s, random packet loss and skipped frames; fails on any checksum mismatch, a lead beyond the input delay, or a deadlock. Verified: default (30% loss, 20% skipped frames), delay 1 with 50% loss, delay 2 with 50% skipped frames over 2400 ticks, and no loss — all in sync, max lead ≤ delay. Determinism test and the windowed game still run clean.

## 4. Rollback (optional, after lockstep works)

- [x] Save/load the full gameplay state per tick (ring buffer of ~8–10 frames).
  - `Fighter.restore(values, offset)` is the inverse of `snapshot()` (`SNAPSHOT_SIZE` values). `Match.save_state()` = `tick` + both snapshots (exactly what `state_checksum()` hashes, so checksums are unchanged), `load_state()` restores it (and `checksum`). `Match.step()` first saves the state and checksum of the tick it starts into a ring buffer of `Match.HISTORY` = 10 slots; `has_tick(t)`/`load_tick(t)` rewind to any of the last 10 ticks (slots checked by their stored tick, so stale ones after a rewind aren't used), `checksum_at(t)`. Verified headless: AI vs AI 1500 ticks through a KO, rewinding 0–10 ticks at many points and re-stepping the same inputs reproduces every checksum; out-of-window ticks are refused; determinism test passes.
- [x] When a late remote input differs from the prediction: restore the snapshot, re-simulate to the current tick, and update visuals.
  - `InputSource.predict(tick)` (default 0; `TickInput`: the last known input, i.e. repeat). `Match.max_rollback` (0 = lockstep, default) enables it: `_physics_process` first runs `_correct_predictions()` — from `confirmed_tick` on, compares each now-known tick's inputs with the ones it was simulated with (`_used_inputs` ring); equal → confirm, different → `load_tick()` there and `_advance()` back up to the current tick (`rollbacks`, `resimulated_ticks` counters) — then `_advance()`s one tick on real-or-predicted inputs; `_sync_visuals()` afterwards shows the corrected state. `confirmed_tick`: ticks before it used only real inputs, so `checksum_at(t)` for `t ≤ confirmed_tick` is final (what peers must compare, §7). `tests/lockstep_test.gd --rollback=N` (README): collects confirmed checksums, compares both sides and an offline replay of the recorded inputs. Verified: rollback 7 (30% loss), 7 with delay 1 and 50% loss, 3 with delay 2 and 50% skipped frames over 2400 ticks, 9 with delay 1 and no loss — all in sync with dozens of rollbacks; rollback 7 gives the same final checksum as lockstep for the same seed; lockstep runs unchanged.
- [x] Cap the rollback window; stall if the peer falls further behind.
  - `Match.max_rollback` (0–9, below `HISTORY` so every rewind target is kept) is the cap: `_physics_process` stalls (`stalled_frames`) while `tick - confirmed_tick >= max_rollback` and the tick's inputs aren't known, so a side leads by at most its peer's input delay + `max_rollback` (asserted by `tests/lockstep_test.gd`). Session code (§5) must pick the value (default 0 = lockstep). Verified headless: a peer that goes silent after 20 ticks leaves the match at tick 20 + `max_rollback` with `confirmed_tick` 20 for `max_rollback` 0/1/5/9, stalling every further frame; once the inputs arrive it catches up and tick 300 matches the offline checksum.
- [x] Consider using an existing addon (e.g. Snopek's "Godot Rollback Netcode") instead of a custom implementation.
  - Decided: keep the custom rollback; reasons in `docs/netcode.md` → "Why custom rollback". The addon (Godot 4 on `main`) would replace `Match.step()`, the integer snapshot/checksum and `InputSync` with its `SyncManager` and per-node `Dictionary` state. Its time sync and Log Inspector are worth borrowing ideas from for §5 clock sync and §7/§8 debugging.

## 5. Session & lobby

- [x] Main menu: Local (step 1 behavior), Host, Join (enter IP:port or a room code).
  - Start menu exists: `scenes/menu.tscn` (main scene, `scripts/menu.gd`) with "Singleplayer" (→ `main.tscn`) and a disabled "Multiplayer (online)" button. Enable that button and make it lead to Host/Join.
  - Done: "Multiplayer (online)" opens the `%Online` panel (Host, address field + Join, Back/Cancel, `%Status` label). Networking lives in the new `Session` autoload (`scripts/session.gd`, registered in `project.godot`): `host(port)`, `join(address)` (`parse_address()`: IP, IP:port, `[ipv6]:port`; default port `Session.DEFAULT_PORT` 7777), `close()`, signals `status_changed`/`ended`; an ended session returns to the menu, which shows `take_end_reason()`. IP:port only; room codes need a relay/server (§6).
- [x] Host: create the peer, wait for one client, assign host = fighter 1, client = fighter 2.
  - `Session.host()`: `ENetMultiplayerPeer.create_server(port, 1)` (one client). On `peer_connected` (after the handshake) it sets `peer_id` and RPCs `_start_match` (call_local) → both load `main.tscn`. `main.gd` `_enter_tree()` (before the `Match` is ready) gives fighter `Session.local_index` (host 0, client 1) a `LocalInput`, the other a `NetworkInput`, and adds `World/InputSync`; `_ready()` freezes `Match`/`InputSync` and calls `Session.match_loaded()`, which tells the peer; once both loaded, `Session` calls `main.begin()` (sets `InputSync.peer_id`, `reset()`, unfreezes), so no input packet reaches a scene the peer hasn't loaded. R (restart) is ignored online. Verified with two headless processes (AI-driven `LocalInput`s): roles/inputs as above, identical `checksum_at(590)`.
- [x] Join: connect, handshake with the game version and protocol version, and reject on mismatch.
  - `Session.join()` → `create_client()`. Handshake via `SceneMultiplayer` auth (`auth_callback`, `send_auth`/`complete_auth`, `AUTH_TIMEOUT` 5 s), before any RPC: client sends `var_to_bytes([MAGIC, game version, PROTOCOL_VERSION])` (game version = new `application/config/version` "0.1.0"; `Session.PROTOCOL_VERSION` 1, bump on wire/simulation changes); host replies with its own plus a rejection reason; each side checks the other (`_check_hello()`). Raw bytes, not RPCs, so a different build still gets a readable reason. Rejected client closes and the menu shows "Rejected by the host: …"; host shows "Refused a player…" and keeps waiting. Verified (3 processes): a client with version 9.9 is rejected on both sides, then a matching client connects and plays in sync; protocol mismatch and junk data give their reasons.
- [x] Both peers agree on the match config (stage, character tint, start tick) before the first tick.
  - Host picks it (`Session._new_match_config()`: `stage`, `characters` (tints), `seed`, `max_rollback`, `start_tick`) and sends it in `_start_match(config)` → `Session.match_config`; `main.gd` `_enter_tree()` calls `Match.apply_config()`. Each side then sends `Match.effective_config()` (adds `half_width`, `start_x`, `tick_rate`) in `_peer_loaded_rpc(config)`; `begin()` only if equal, else both end with "Match setup differs from the opponent's: <key> (…)". New `Match.start_tick` (default 0): `step()` zeroes inputs while `tick < start_tick` — the next item should set it and show the countdown. Verified (2 headless processes, `tmp_net.gd`): same config/checksums; a client with `half_width` 7 is refused on both sides before tick 0; determinism + lockstep tests pass. `docs/netcode.md` → "Session".
- [x] Synchronized start: a countdown tied to a shared tick, not wall-clock time on each machine.
  - Host config `start_tick` = `Session.COUNTDOWN_TICKS` (180). `Match.step()` zeroes inputs before it; `Hud.fight` (new export, wired in `main.tscn`) + static `Hud.countdown_text(tick, start_tick)` show "3"/"2"/"1"/"FIGHT!" (`Hud.FIGHT_TICKS` 45) from the simulation tick only. Offline: 0 = no countdown. Verified (2 headless processes, `tmp_net.gd`): both show each number at ticks 0/60/120/180, first movement at tick 181 on both despite ~2 s different wall-clock start, identical `checksum_at(590)`; windowed screenshot shows the centered "3".
- [x] Clock/tick sync: measure RTT and let the faster peer slow down slightly so the peers don't drift apart.
  - `InputSync` (new `world: Match` export, set by `main.gd` and `tests/lockstep_test.gd`) sends `Match.tick` + smoothed `advantage` in each input packet; `rtt_ms` from ENet `PEER_ROUND_TRIP_TIME`; `lead()` = (advantage − remote_advantage)/2 (latency cancels); lead ≥ 1 tick → `Match.skip_frame()` (≤ 1 per 20 frames, `Match.skipped_frames`). `PROTOCOL_VERSION` → 2. `reset()` clears the estimates (rematch must call it). Verified (`tmp_net.gd --tps=63` on host): no sync → 73 stall frames at lead 3; sync → 74 skipped, 1 stall, lead ≈ 1, checksums equal; lockstep (+ `--rollback=5`) and determinism tests pass. `docs/netcode.md` → "Session" → tick sync.
- [ ] Rematch flow after KO without reconnecting.

## 6. Connectivity

- [ ] Configurable port; document the port forwarding needed for direct-IP hosting.
- [ ] If WebRTC: a signaling server (small WebSocket service) plus STUN (and TURN as a fallback).
- [ ] If a dedicated server/relay: headless export, hosting choice, and room codes.

## 7. Error handling

- [ ] Handle disconnects mid-match: pause, show "opponent disconnected", return to the menu.
- [ ] Timeout when no packets arrive for N seconds.
- [ ] On a checksum mismatch, log the desync (tick, both states) and end the match cleanly.
- [ ] Ignore malformed or out-of-range packets (wrong size, ticks far in the past or future).

## 8. HUD & debug

- [ ] Show ping and input delay in the HUD.
- [ ] Network debug overlay: current tick, remote tick, rollback count, packet loss.
- [ ] Simulated network conditions (artificial latency, jitter, loss) for local testing.
- [ ] Run two instances on one machine (Godot "Run Multiple Instances") for quick testing.

## 9. Wrap-up

- [ ] Playtest over LAN, then over the internet with real latency (~50–150 ms).
- [ ] Verify that a full match (walk, jump, punch, KO, rematch) stays in sync, with no checksum mismatches.
- [ ] Update `README.md` with how to host/join and any port requirements.
