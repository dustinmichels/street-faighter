# TODO — Lobby: find other players online

Goal: a player picks "FIND OPPONENT" (or opens a lobby list), waits, and is paired with another player running a compatible build, without anyone typing an IP address.

Builds on step 2 (`multiplayer.md`) and the custom characters (`custom-characters.md`):

- `Session` (`online/session.gd`) is strictly peer to peer: `host(port)` opens an ENet server for exactly one client, and `join(address)` dials a typed address. After the handshake, everything (version check, `CharacterSync`, match start, rematch) is already automatic.
- The project runs no server. Characters ended up travelling peer to peer (`CharacterSync`), so the HTTP service planned in `notes.md` → "Multiplayer distribution" was never built. The lobby server is the first piece of hosted infrastructure.
- Two separate problems:
  1. **Finding** each other: a small rendezvous server plus a menu screen. This part is easy.
  2. **Connecting** once paired: direct IP needs the host to be reachable (UPnP or manual port forwarding, no CGNAT; `docs/guide/online.md` sends CGNAT players to a VPN). Strangers can't share a VPN, so a lobby that only hands out IPs inherits that failure rate.

## 1. Decisions

- [ ] Shape: auto-pairing queue ("FIND OPPONENT") or a room listing waiting players, where you challenge one and they accept. With few players online, the list feels less empty.
- [ ] Connection tier:

  | Tier                          | What you build                                                                    | Connects when                                                  | Client change                                                                         |
  | ----------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
  | 1. Lobby + existing direct IP | WebSocket server that lists/pairs players; paired clients use `Session.host/join` | Either side is reachable (UPnP, manual forward, LAN)           | `Lobby` autoload, menu screen; `Session` unchanged                                    |
  | 2. Tier 1 + UDP hole punching | Server also gets a UDP endpoint to learn each player's public ip:port             | Both NATs are cone type; fails on symmetric NAT and most CGNAT | `create_client(..., local_port)` on the punched port; fiddly, needs real NATs to test |
  | 3. Tier 1 + WebRTC            | Lobby server doubles as signaling; public STUN; TURN relay fallback               | Effectively always (TURN relays the rest)                      | `webrtc-native` GDExtension, swap the peer in `Session`, own RTT measure (§4)         |
  | 4. Steam / EOS lobbies        | GodotSteam or an EOS plugin; their lobbies and relay                              | Always                                                         | Replace the transport; requires shipping on Steam/Epic instead of GitHub releases     |

  Proposal: tier 1 now, with the server speaking WebSocket so the same connection can carry WebRTC signaling later; tier 3 once failed pairings are common. Skip tier 2: WebRTC's ICE does hole punching properly and falls back to TURN.

- [ ] Hosting: where the server runs (Bun on a small VPS / Fly.io, or a Cloudflare Worker with a Durable Object for WebSockets) and who pays for it. The URL is baked into builds, so pick something stable (own domain).
- [ ] IP exposure: in a public lobby, strangers receive your IP. Direct-IP join already does this, but between people who know each other. Only relay-only WebRTC (tier 3) hides it. Mention it in `docs/guide/online.md` either way.
- [ ] After a match: back to the lobby or to the menu. `Session._end()` always loads `MENU_SCENE` today.

## 2. Lobby server (tier 1)

- [ ] One WebSocket per waiting player; the open socket is its presence (no heartbeat bookkeeping beyond WebSocket ping).
- [ ] First message: `hello(game_version, PROTOCOL_VERSION, player_name, upnp_result)`. Players are grouped by `game_version` + `PROTOCOL_VERSION`, so nobody sees an opponent they can't join. `Session._check_hello()` still enforces it.
- [ ] The host's address is the socket's **source IP**, never a client-reported one. Otherwise anyone could list a victim's IP and point other players at it. This also makes the menu's `PUBLIC_IP_URL` lookup unnecessary on this path.
- [ ] Pairing protocol: `matched(role, opponent_name)` → the host runs `Session.host(port)` and replies `listening(port)` → the server sends the guest `join(host_source_ip, port)` → the guest runs `Session.join()`. From here on the existing handshake, `CharacterSync` and match start take over.
- [ ] Choosing the host: `PortMapper.Result` is a **hint only**. A player who forwarded the port by hand (`docs/dev/netcode.md` → "Router configuration") reports `NO_ROUTER` but is reachable, so "neither side reports `OPENED`" must not mean "can't pair". Prefer the side reporting `OPENED`, else pick either, and rely on the role swap below.
- [ ] Reachability: after a failed join (short timeout, §3), the guest reports `join_failed`; the server swaps roles once and retries. If both directions fail, tell both players why ("Neither of you can accept connections: forward UDP 7777 or use a VPN") instead of leaving them waiting.
  - Alternative: the server probes `host_source_ip:port` before handing it to the guest. That needs the server to speak ENet (a headless Godot export as the server, or an ENet binding), because a raw UDP probe gets no answer from an ENet socket. Not worth it for tier 1; the role swap costs one timeout at most.
- [ ] Busy players (in a match) are hidden from the list / skipped by the queue until they come back.
- [ ] Limits: messages per second and connections per IP; reject names `Session.clean_name()` would change (10 printable ASCII chars). A report/blocklist can wait until there are players.
- [ ] Source lives in the repo (e.g. `lobby_server/`, with `.gdignore`), with a `mise` task to run it locally.

## 3. Client

- [ ] `online/lobby.gd`, an autoload next to `Session`, using the built-in `WebSocketPeer` (no extension). Signals for roster, waiting status, matched and errors. Lobby URL is a constant, with a `--lobby=URL` user argument override for development.
- [ ] Short connect timeout for lobby joins: ENet's own can take much longer than a player will wait. Set the client peer's timeout (`ENetPacketPeer.set_timeout()` on `get_peer(1)` after `create_client()`; verify it applies to the connect phase) or have `Lobby` give up after ~5 s and report `join_failed`.
- [ ] Report `PortMapper.finished` results to the server. `Session.host()` already starts UPnP; the lobby flow should start the mapping when the player enters the lobby (`port_mapper.open()`), not only once chosen as host, so the hint exists before pairing.
- [ ] `Screen.LOBBY` in `menu/menu.gd` / `menu.tscn`, reached from the `ONLINE` screen: players online, waiting text, Cancel (closes the lobby socket and any `Session`). Keep direct Host/Join as they are, for LAN and friends.
- [ ] Session end: when a lobby match ends (`Session.ended`), return to the lobby or the menu as decided in §1.
- [ ] `scripts/` / `mise run mp`: a variant that starts the local lobby server and two instances with `--lobby=ws://127.0.0.1:...`.

## 4. Later: WebRTC (tier 3)

`docs/dev/netcode.md` says switching means "changing peer creation in the session code only". Mostly true, with these gaps:

- [ ] `InputSync._measure_rtt()` casts to `ENetMultiplayerPeer` and reads `PEER_ROUND_TRIP_TIME`. Under WebRTC it returns 0, which quietly removes the latency term from tick sync (`advantage`). Needs an own ping, e.g. timestamps echoed in the input packets.
- [ ] Recreate the three channels via `WebRTCMultiplayerPeer` `channels_config`: ch0 reliable (session), ch1 `unreliable_ordered` (inputs), ch2 reliable (`CharacterSync` transfer).
- [ ] `webrtc-native` binaries for each export platform in `export_presets.cfg`.
- [ ] Signaling (offer/answer/ICE candidates) over the lobby WebSocket; public STUN; TURN via coturn on the lobby VPS or a paid provider (bandwidth is small: about 1 byte of input per tick plus overhead).
- [ ] Keep ENet for direct IP/LAN and for `tests/lockstep_test.gd` / `tests/character_sync_test.gd`, which are built on it.

## 5. Tests & docs

- [ ] Server unit tests: version grouping, pairing, host choice, role swap after `join_failed`, busy players skipped, source-IP-only addresses.
- [ ] Headless end-to-end test like `tests/character_sync_test.gd`: local lobby server + two game processes paired by the lobby, reaching a match with equal checksums; one run where the first host is unreachable, so the role swap is exercised.
- [ ] `docs/guide/online.md`: the lobby, what to do when "neither of you can accept connections", IP exposure. `docs/dev/netcode.md`: update "Topology" (the "Revisit when…" note) and "Transport" with the lobby and its protocol.
