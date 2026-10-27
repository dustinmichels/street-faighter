# Netcode

Decisions for online play (`docs-todo/multiplayer.md`, step 2). Each one gives the choice, the reasons for it, and when to revisit it.

## Sync model: input sync (lockstep with input delay, optional rollback)

Peers exchange only the per-tick input bitmask (`InputSource.LEFT | RIGHT | JUMP | PUNCH | BLOCK | CROUCH | SPECIAL`, 7 bits in one byte, `InputSource.BUTTONS`). Both peers run the full simulation from the same start state and the same inputs. The simulation is never sent over the network. Everything the inputs feed into, including `Fighter.attack_buffer` / `special_buffer` (buffered presses), `hit_streak` (the special meter) and `block_stun`, is simulation state in `Fighter.snapshot()`, so it is checksummed and saved and restored by rollback.

1. **Lockstep first.** Tick `t` simulates only after both peers' inputs for `t` have arrived. Local input is scheduled `D` ticks ahead (input delay, starting at 2–3 ticks) so that remote input usually arrives in time. When it doesn't, the game stalls for a tick instead of guessing.
2. **Rollback (optional, `Match.max_rollback` > 0).** This is the same model with a different way of handling missing input. The game predicts the missing input as a repeat of the last one, saves state each tick, and re-simulates when the real input differs. It needs the same determinism as lockstep, plus save/load of state, so building lockstep first lost no work.

Implementation (input pipeline): `InputSource.poll(tick)`/`has_input(tick)`; `LocalInput` (live source + input delay, `delay` ≥ 1), `NetworkInput` (inputs received by tick), both `TickInput`s keeping one byte per tick; `InputSync` sends every unacknowledged local input plus an ack each physics frame; in lockstep `Match._physics_process` stalls (counting `stalled_frames`) until every input for the tick is known. Tested by `tests/lockstep_test.gd`.

Implementation (rollback): `Match.step()` saves `save_state()` (`tick` + both `Fighter.snapshot()`s, restored by `Fighter.restore()`) and the checksum at the start of each tick in a ring buffer of `Match.HISTORY` = 10 ticks (`load_tick()`). Missing inputs are `InputSource.predict()`ed (`TickInput`: repeat the last known one) and the inputs each tick used are kept. Each frame the match first confirms the ticks whose real inputs have arrived, from `confirmed_tick` on; at the first mispredicted one it rewinds there and re-simulates to the current tick, then simulates one new tick. It predicts at most `max_rollback` (≤ 9) ticks past `confirmed_tick` and stalls beyond that, so a peer leads by at most the other's input delay + `max_rollback`. Only checksums of confirmed ticks (`checksum_at(t)`, `t ≤ confirmed_tick`) are final and comparable between peers. Visuals are derived from the state each frame (`Fighter.sync_visual()`), so a rewind needs nothing extra. Local input sources are sampled once per tick and stored (`LocalInput`), so re-simulation never re-polls the keyboard or the AI. Tested by `tests/lockstep_test.gd --rollback=N`.

Why custom rollback and not Snopek's "Godot Rollback Netcode" addon (gitlab.com/snopek-games/godot-rollback-netcode; Godot 4 on its `main` branch): the addon is built around its own `SyncManager` singleton that drives every networked node through `_network_process(input)` / `_save_state()` / `_load_state()` with `Dictionary` state, its own network adaptor and message serializer, input delay, ping and hashing. Adopting it would mean replacing `Match`'s single ordered `step(inputs)`, the integer snapshot and checksum and `InputSync`, all of which already exist and are tested, for features this game doesn't use (spawning, rollback-aware timers, sound, RNG helpers). Our core is about 60 lines in `Match` on top of state that was already one integer array. Revisit if rollback grows features the addon already has; its Log Inspector (replaying recorded matches, stepping to a mismatch) and its time sync (pinging and skipping frames so peers stay level, todo §5) are worth borrowing ideas from.

Why input sync over state sync (authoritative host):

- **It fits the code.** `Fighter` already advances once per 60 Hz physics tick by a fixed `TICK` and counts time in whole ticks (`scripts/fighter.gd`). It reads controls only through `InputSource.poll()`, which returns a bitmask, so a `NetworkInput` slots in without changing `Fighter`.
- **Fairness.** With state sync, the client's inputs reach the simulation one RTT late unless it predicts locally, and in a fighting game client-side prediction of hits and knockdowns means visible corrections. Input sync gives both players the same input delay.
- **Bandwidth.** About 1 byte per tick plus redundancy (every input the peer hasn't acknowledged, a few per packet), compared with snapshots of two fighters' full state at 60 Hz.
- **Desync detection.** A per-tick state checksum (`Match.checksum`) shows exactly where the peers diverge, which also makes a good regression test (`tests/determinism_test.gd`, see [Tests](./testing#determinism)).
- **Standard practice.** GGPO-style input delay plus rollback is what fighting games ship, and there is a Godot addon for it (Snopek's "Godot Rollback Netcode") if building it ourselves proves too costly.

What this costs (handled in todo §2):

- **The simulation must be bit-identical on both peers.** Current risks are `move_and_slide()` (Jolt) on `CharacterBody3D`, the `Area3D` space query in `hitbox_targets()`, float math across platforms and builds, `PUNCH_LENGTH` and the active window being read from clip times (floats converted to ticks), and the two fighters stepping in separate `_physics_process` calls whose order depends on the scene tree. All of these must become one `step(inputs)` that the match drives in a fixed order.
- **Visuals must follow the simulation.** Animation has to be driven by the tick counter, not by wall-clock time.

Revisit if determinism across platforms can't be achieved at reasonable cost. The fallback is state sync with the host as the authority. The input pipeline (§3) still applies: the client sends inputs and the host sends snapshots.

## Transport: `ENetMultiplayerPeer` (UDP, direct IP)

Use Godot's high-level multiplayer API (`multiplayer.multiplayer_peer`) with `ENetMultiplayerPeer`. The host calls `create_server(port, 1)` and the client calls `create_client(ip, port)`.

- **Input packets** go through `InputSync._receive_inputs`, an `@rpc("any_peer", "call_remote", "unreliable_ordered", 1)` method carrying `(match_number, ack, first tick, input bytes, match tick, advantage, check tick, checksum, seq)`: every local input from the first tick the peer hasn't acknowledged, the first remote tick this side still lacks, the tick sync values (see "Session" → tick sync), the checksum of the sender's latest confirmed tick (see "Session" → desync), and a sequence number for loss statistics. One goes out every physics frame. Unreliable, so a lost packet is never retransmitted and stale inputs never block newer ones (the next packet repeats unacknowledged inputs). It uses its own channel so that it doesn't share ordering with control traffic.
- **Control messages** (handshake, match config, start tick, rematch, disconnect reason) go through `"reliable"` RPCs on channel 0.
- **Ping** comes from `ENetPacketPeer.get_statistic(PEER_ROUND_TRIP_TIME)` (`InputSync.rtt_ms`) for the HUD and tick sync.
- **Simulated network** (local testing): `--net-latency=MS`, `--net-jitter=MS`, `--net-loss=PERCENT` (`InputSync.apply_sim_args()`) drop or delay the input packets one instance sends and receives, inside `InputSync` (queues released each physics frame, so ~16 ms granularity). ENet can't see the delay, so `rtt_ms` and tick sync ignore it (an error common to both sides cancels in `lead()`); the HUD's `ping_ms()` adds it. Reliable RPCs are unaffected.

Why ENet:

- It ships with every desktop export and needs no extension and no extra service. Two instances on one machine (`127.0.0.1`) or over a LAN work right away, which makes testing fast.
- It provides UDP with unreliable and reliable channels on one socket, which covers both kinds of traffic above.

Why not WebRTC (yet):

- On desktop, `WebRTCMultiplayerPeer` needs the `webrtc-native` GDExtension. It also needs a signaling server and STUN (plus TURN as a fallback) before two peers can connect at all. Its benefits, NAT traversal and web export, aren't goals for this step.
- Gameplay code talks only to `multiplayer` and RPCs, never to ENet directly. Switching to `WebRTCMultiplayerPeer` later means changing peer creation in the session code only.

### Direct-IP hosting & port forwarding

Internet play uses direct IP: the host listens on a UDP port (default `7777`, configurable in the menu or via `--port=N`), and the joining client connects to the host's public IP address.

- **Protocol:** UDP (ENet is UDP-based; forwarding TCP will not work).
- **Port:** UDP 7777 by default, or 1–65535 if configured.
- **Who needs port forwarding:** Only the host (Player 1). The client (Player 2) initiates an outbound connection, so the client does not need to forward any ports.
- **Router configuration (for the host):**
  1. Find the host machine's local IPv4 address on the LAN (e.g. `ipconfig` on Windows, `ip route` on Linux, `ipconfig getifaddr en0` on macOS).
  2. Open the router's admin portal (commonly `192.168.1.1` or `192.168.0.1`).
  3. Navigate to **Port Forwarding** / **Virtual Server**.
  4. Add a forwarding rule:
     - **Protocol:** UDP
     - **External Port:** 7777 (or your custom port)
     - **Internal / Target Port:** 7777 (or matching custom port)
     - **Internal IP:** Host machine's local LAN IP
  5. Save and apply settings.
- **Firewall:** Ensure the host OS firewall (Windows Defender Firewall, macOS Application Firewall, Linux `ufw`/`iptables`) allows incoming UDP traffic on the specified port.
- **Connecting over the Internet:**
  - The host finds their public IP (e.g. via `curl -4 ifconfig.me` or searching "what is my ip").
  - The joining player enters `public_ip` (or `public_ip:port` if using a custom port) in the Join address box.
- **Local LAN & VPN alternatives:**
  - On the same local network, port forwarding is not needed; the client connects directly to the host's local LAN IP (e.g. `192.168.1.X:7777`).
  - Peer-to-peer VPNs like Tailscale or ZeroTier provide encrypted mesh connections without router port forwarding; client connects to the host's VPN IP.
  - On the same machine, connect via `127.0.0.1:7777`.

## Topology: peer-to-peer host/join (one player hosts)

One player picks Host and becomes ENet peer `1` and fighter 1. The other picks Join and becomes fighter 2. There is no server process. The host differs from the client only in session duties: it accepts the connection, checks the version handshake, and picks the match config, the start tick, and the rematch. Gameplay is symmetric. Each peer simulates both fighters from both input streams, and neither one is authoritative over the simulation.

Why not a dedicated server:

- With input sync, a server would only forward input bytes. It adds a hop of latency and has hosting costs, and it buys nothing for a 1v1 match except NAT traversal and protection against a host who cheats.
- Cheating is limited anyway. A peer can only send its own inputs, and any state tampering shows up as a checksum mismatch (todo §7).
- No hosting, deployment, or headless export is needed to play.

Revisit when the final step adds custom characters. That step already needs an HTTP upload/validation service (`notes.md` → "Multiplayer distribution"), and the same service could host room codes, WebRTC signaling, or a relay. Matches would stay peer-to-peer. A relay would only forward packets, so this design keeps working.

## Session

`Session` (autoload, `scripts/session.gd`) owns the connection across scene changes. After the version handshake the host picks the match config (`_new_match_config()`: stage scenery, each fighter's character, `seed`, `max_rollback`, `start_tick`) and sends it with the reliable `_start_match(config)` RPC, so both peers load `main.tscn` with the same choices; `main.gd` applies it with `Match.apply_config()` before the scene is ready. Characters are named by content (`CharacterLibrary.descriptor()`: `{"builtin": "DEFAULT"}` or `{"sha256": …, "name": …, "size": …}`), and each side shows the model it has for them (`Session.character_model()`: built-in, library entry, cached download, else the default). `Match` hue-shifts fighter 2 when both show the same model (`CharacterLoader.MIRROR_TINT`, display only). Once loaded, each side sends its `Match.effective_config()` (the applied config plus scene-file values: stage `half_width`, start positions, tick rate; not the characters, which are visual only and may differ between the sides) with `_peer_loaded_rpc`, and `begin()` runs only when both are equal (`Session.config_mismatch()`); otherwise both sides end the session naming the first differing key, before the first tick.

Characters: after the handshake both sides announce their character (`CharacterSync`, a child of `Session`: the saved `CharacterLibrary.PLAYER_CHOICE` as a descriptor), and the host starts the first match once the client's announcement is in. A side that lacks the other's custom character requests it; the owner sends only its own announced `.glb`, once per session, in chunks of ≤ 64 KB (`CharacterSync.CHUNK_BYTES`) on reliable transfer channel 2, so it doesn't hold up the session's messages (channel 0) or inputs (channel 1). The receiver knows the size from the descriptor (≤ `CharacterValidator.MAX_FILE_BYTES`, checked before the request) and drops the download on any chunk out of order or past it. A complete file must match its SHA-256 and pass the full `CharacterValidator`, and is then cached as `user://characters/remote/<sha256>.glb` (`CharacterLibrary.remote_path()`), which later sessions reuse.

Names: the handshake (`Session._hello()`: `[MAGIC, game version, PROTOCOL_VERSION, player_name]`, the host's reply adding its verdict) also carries each player's `Session.player_name`, so both sides know the other's (`Session.peer_name`, sanitized by `Session.clean_name()`) before the match loads. They're display-only (HUD labels via `main.gd`), never part of the match config or the simulation.

Start: `start_tick` is `Session.COUNTDOWN_TICKS` (180 = 3 s). `Match.step()` simulates the ticks before it with all inputs 0, and the HUD shows "3", "2", "1", then "FIGHT!" from `Hud.countdown_text(Match.tick, start_tick)`. Both are functions of the simulation tick, not of each machine's clock, so in lockstep both peers see each number and the first controllable tick (`start_tick`) at the same tick, even if one started its scene later. Inputs still flow during the countdown, so the input pipeline is warm when the fight starts. Offline matches keep `start_tick` 0 (no countdown).

Tick sync: each input packet also carries the sender's `Match.tick` and its smoothed `InputSync.advantage` = own tick − (peer's last reported tick + RTT/2 in ticks). `InputSync.lead()` = (own advantage − peer's advantage) / 2 is how far this side leads; the latency terms cancel, so asymmetric or imprecise RTT barely matters. When it is ≥ `SKIP_THRESHOLD` (1 tick), the side calls `Match.skip_frame()`: the next physics frame simulates nothing (`Match.skipped_frames`), at most once every `SKIP_INTERVAL` (20) frames, i.e. ≤ 5% slower. Without it, a peer whose clock runs fast runs ahead until it hits the input delay and then stalls in bursts, and its lead eats the delay budget that should absorb latency. Measured (two processes, host forced to 63 Hz after the start): without tick sync the host stalls 73 frames in 1500 ticks at a lead of 3 (the input delay); with it, 74 spread-out skipped frames, 1 stall, lead ≈ 1. Timing only: skipping never changes the simulation or checksums.

Rematch: after a knockdown (`Match.is_over()`), pressing R (`restart` action) calls `Session.request_rematch()`, sending a reliable `_rematch_rpc` to the peer. The HUD's KO hint (`Hud.ko_hint()`) updates to reflect whether this machine is waiting for the opponent or the opponent has already requested. Once both have requested, the host generates a new match config and broadcasts `_start_match.rpc(config)`, reloading `main.tscn` on both sides across the existing ENet connection. `Session.match_number` increments on each match; input packets include `match_number` (`InputSync.match_id`), ensuring any late packets from a prior match are rejected.

Leaving after a knockdown: the `controls` action (Esc) calls `Session.close()` and switches to the menu (`main.gd`), with no error shown on this side. The peer gets a regular disconnect (`peer_disconnected` / `server_disconnected`) and goes through the session-end path below. Before the knockdown, Esc only toggles the HUD's controls panel.

Session end mid-match: when the session closes with an error while a match scene is loaded (the opponent disconnected — host: `peer_disconnected`, client: `server_disconnected` — or any later `fail()` reason), `Session._end()` closes the connection and calls `main.gd` `end_online(reason)` instead of switching scenes: the `Match` and `InputSync` stop processing, the HUD shows the reason centered (`Hud.show_notice()`), and after `END_NOTICE_SECONDS` (3 s) the game returns to the menu, which shows the reason in its status line. Before the match scene has loaded, `_end()` goes straight to the menu.

Timeout: input packets arrive every frame, so silence means the link is gone even if ENet hasn't noticed yet (its peer timeout can take up to 30 s). `InputSync` records the wall-clock time of each packet from the peer (reset by `reset()`); after `InputSync.TIMEOUT_SECONDS` (5 s) without one it stops and emits `timed_out`, and `main.gd` calls `Session.fail("Connection lost: ...")`. Closing the connection then makes the silent side see "Opponent disconnected".

Desync: each input packet carries `Match.checksum_at(confirmed_tick)` (final on both sides). `InputSync` keeps its own confirmed checksums and states and the peer's checksums for the last `CHECK_HISTORY` (128) ticks and compares them wherever both exist. On a mismatch it freezes the `Match`, stops sending inputs and sends its `Match.state_at(tick)` in a reliable `_receive_desync_state(match_number, tick, state)`; the peer, told or finding it itself, answers with its own (the earliest reported tick wins). With both states (or after `DESYNC_WAIT_SECONDS`, 2 s) it emits `desynced`; `main.gd` prints a field-by-field table of both states (`Fighter.SNAPSHOT_FIELDS`, differing values marked `<--`) to stderr / Godot's log (`user://logs/godot.log`) and calls `Session.fail("Desync at tick N: ...", DESYNC_LINGER_SECONDS)`, which keeps the connection open 0.5 s so the peer gets the report before it sees a disconnect, then ends like any other error.

Malformed packets: Godot's RPC layer already drops calls with the wrong argument count or types (logging an error). `InputSync._valid_packet()` drops a whole input packet whose values no well-behaved peer could send: more than `MAX_INPUTS` inputs, bits outside `InputSource.BUTTONS`, a first tick below 0 or past the next unknown one (a gap), an ack beyond the inputs sent, a match tick below 0 or more than `Match.HISTORY` past our inputs, a confirmed tick past either, a checksum outside 32 bits, or a non-finite advantage beyond `TIMEOUT_SECONDS` worth of ticks. A desync report is ignored if its tick is outside the checksum window or past our inputs, its state has the wrong size or tick, or it equals our own state.
