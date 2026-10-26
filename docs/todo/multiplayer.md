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

- [ ] Move all gameplay state (position, velocity, state machine, frame counters, health) into plain variables advanced in one `step(inputs)` per tick, not driven by `_process` or wall-clock time.
- [ ] Avoid Godot physics nondeterminism in gameplay: use custom kinematic movement and shape overlap checks, or confirm that `CharacterBody3D` / `Area3D` results are reproducible.
- [ ] Prefer integer or fixed-point math for positions and velocities, or verify that float results match across platforms.
- [ ] Use a seeded RNG owned by the match, if any randomness exists.
- [ ] Drive animations from the simulation frame counter (seek `AnimationPlayer` to the state's frame) so visuals follow the simulation, not the other way round.
- [ ] Hit detection uses game-defined hitbox/hurtbox shapes evaluated in `step()` on the active frames, not physics signals.
- [ ] Add a state checksum per tick (hash of the gameplay state) for desync detection.
- [ ] Headless determinism test: replay one recorded input log twice (and on two machines) and compare checksums every tick.

## 3. Input pipeline

- [ ] Pack inputs into a compact per-tick bitmask (`move_left`, `move_right`, `jump`, `punch`).
- [ ] `LocalInput`: samples the keyboard each tick and tags it with the tick number.
- [ ] `NetworkInput`: an input source for the remote fighter that serves inputs received from the peer by tick number.
- [ ] Input delay buffer (start at 2–3 ticks) so remote inputs usually arrive before they are needed.
- [ ] Send each packet with the last N inputs (redundancy) over unreliable/unordered UDP to absorb packet loss.
- [ ] Handle missing remote input: stall (lockstep) or predict it as a repeat of the last input (rollback).

## 4. Rollback (optional, after lockstep works)

- [ ] Save/load the full gameplay state per tick (ring buffer of ~8–10 frames).
- [ ] When a late remote input differs from the prediction: restore the snapshot, re-simulate to the current tick, and update visuals.
- [ ] Cap the rollback window; stall if the peer falls further behind.
- [ ] Consider using an existing addon (e.g. Snopek's "Godot Rollback Netcode") instead of a custom implementation.

## 5. Session & lobby

- [ ] Main menu: Local (step 1 behavior), Host, Join (enter IP:port or a room code).
  - Start menu exists: `scenes/menu.tscn` (main scene, `scripts/menu.gd`) with "Singleplayer" (→ `main.tscn`) and a disabled "Multiplayer (online)" button. Enable that button and make it lead to Host/Join.
- [ ] Host: create the peer, wait for one client, assign host = fighter 1, client = fighter 2.
- [ ] Join: connect, handshake with the game version and protocol version, and reject on mismatch.
- [ ] Both peers agree on the match config (stage, character tint, start tick) before the first tick.
- [ ] Synchronized start: a countdown tied to a shared tick, not wall-clock time on each machine.
- [ ] Clock/tick sync: measure RTT and let the faster peer slow down slightly so the peers don't drift apart.
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
