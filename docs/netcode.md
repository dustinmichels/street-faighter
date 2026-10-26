# Netcode

Decisions for online play (`docs/todo/multiplayer.md`, step 2). Each one gives the choice, the reasons for it, and when to revisit it.

## Sync model: input sync (lockstep with input delay, rollback later)

Peers exchange only the per-tick input bitmask (`InputSource.LEFT | RIGHT | JUMP | PUNCH`, 4 bits). Both peers run the full simulation from the same start state and the same inputs. The simulation is never sent over the network.

1. **Lockstep first.** Tick `t` simulates only after both peers' inputs for `t` have arrived. Local input is scheduled `D` ticks ahead (input delay, starting at 2–3 ticks) so that remote input usually arrives in time. When it doesn't, the game stalls for a tick instead of guessing.
2. **Rollback later (optional).** This is the same model with a different way of handling missing input. The game predicts the missing input as a repeat of the last one, saves state each tick, and re-simulates when the real input differs. It needs the same determinism as lockstep, plus save/load of state, so building lockstep first loses no work.

Why input sync over state sync (authoritative host):

- **It fits the code.** `Fighter` already advances once per 60 Hz physics tick by a fixed `TICK` and counts time in whole ticks (`scripts/fighter.gd`). It reads controls only through `InputSource.poll()`, which returns a bitmask, so a `NetworkInput` slots in without changing `Fighter`.
- **Fairness.** With state sync, the client's inputs reach the simulation one RTT late unless it predicts locally, and in a fighting game client-side prediction of hits and knockdowns means visible corrections. Input sync gives both players the same input delay.
- **Bandwidth.** About 1 byte per tick plus redundancy (the last N inputs per packet), compared with snapshots of two fighters' full state at 60 Hz.
- **Desync detection.** A per-tick state checksum shows exactly where the peers diverge, which also makes a good regression test (the headless replay in todo §2).
- **Standard practice.** GGPO-style input delay plus rollback is what fighting games ship, and there is a Godot addon for it (Snopek's "Godot Rollback Netcode") if building it ourselves proves too costly.

What this costs (handled in todo §2):

- **The simulation must be bit-identical on both peers.** Current risks are `move_and_slide()` (Jolt) on `CharacterBody3D`, the `Area3D` space query in `hitbox_targets()`, float math across platforms and builds, `PUNCH_LENGTH` and the active window being read from clip times (floats converted to ticks), and the two fighters stepping in separate `_physics_process` calls whose order depends on the scene tree. All of these must become one `step(inputs)` that the match drives in a fixed order.
- **Visuals must follow the simulation.** Animation has to be driven by the tick counter, not by wall-clock time.

Revisit if determinism across platforms can't be achieved at reasonable cost. The fallback is state sync with the host as the authority. The input pipeline (§3) still applies: the client sends inputs and the host sends snapshots.

## Transport: `ENetMultiplayerPeer` (UDP, direct IP)

Use Godot's high-level multiplayer API (`multiplayer.multiplayer_peer`) with `ENetMultiplayerPeer`. The host calls `create_server(port, 1)` and the client calls `create_client(ip, port)`.

- **Input packets** go through an `@rpc("any_peer", "call_remote", "unreliable_ordered", 1)` method that carries `(tick, last N input bytes)`. Unreliable, so a lost packet is never retransmitted and stale inputs never block newer ones (redundancy covers losses). It uses its own channel so that it doesn't share ordering with control traffic.
- **Control messages** (handshake, match config, start tick, rematch, disconnect reason) go through `"reliable"` RPCs on channel 0.
- **Ping** comes from `ENetPacketPeer.get_statistic(PEER_ROUND_TRIP_TIME)` for the HUD and tick sync. A small ping RPC can be added if that isn't precise enough.

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
