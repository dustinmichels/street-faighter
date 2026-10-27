extends Node
## The online session (autoload `Session`): hosting or joining over ENet, the
## version handshake, and which fighter this machine plays. Lives across scene
## changes, so the connection outlasts each match scene. Local play doesn't
## use it (`mode` stays `LOCAL`), except for `player_name`, entered in the
## menu. Design in `docs/dev/netcode.md` → "Session".
##
## The host listens for exactly one client; once its handshake passes, both
## machines load the match scene (`main.gd` wires it from this session) and
## report back, and the match runs once both have loaded, so no input packet
## is sent to a scene that doesn't exist yet on the other side.
##
## Handshake: `SceneMultiplayer` authentication, before the peers count as
## connected (no RPCs, no `peer_connected` until both sides complete it). The
## client sends `[MAGIC, game version, PROTOCOL_VERSION, player name]`; the
## host answers with its own four values plus a rejection reason ("" =
## accepted). Each side checks the other's versions and keeps its name as
## `peer_name`. Raw `var_to_bytes` arrays, not RPCs: RPCs are
## matched by method index, which differs between game versions, while this
## format is stable, so even an incompatible build gets a readable reason.

## A line for the menu's status label (connecting, waiting, ...).
signal status_changed(text: String)
## The session closed: by `close()`, a failed connection, a rejected
## handshake or the other side leaving. `reason` is "" when closed on purpose.
signal ended(reason: String)

enum Mode {
	LOCAL,
	HOST,
	CLIENT,
}

## UDP port the host listens on and `parse_address()` assumes when none is given.
const DEFAULT_PORT := 7777
## Bump whenever the network messages or the simulation change in a way older
## builds can't follow; peers with different values refuse each other.
const PROTOCOL_VERSION := 9
## First handshake value, so a packet from something that isn't this game is
## rejected as such.
const MAGIC := "street-faighter"
## Seconds a connecting peer has to complete the handshake.
const AUTH_TIMEOUT := 5.0
const MATCH_SCENE := "res://match/main.tscn"
const MENU_SCENE := "res://menu/menu.tscn"
## The host's stage choice (`_new_match_config()`).
const STAGE := "res://stages/street/street.glb"
## Length of the pre-fight countdown (`Match.start_tick`): 3 s at 60 Hz. It
## counts simulation ticks, so in lockstep both peers reach "FIGHT!" on the
## same tick, however their wall clocks differ.
const COUNTDOWN_TICKS := 180
## `Match.max_rollback` of online matches: how many ticks a side predicts the
## opponent's late input before it stalls. With `LocalInput.DEFAULT_DELAY`
## (3), one-way latency up to 3 + 5 ticks (133 ms) plays without stalls.
const MAX_ROLLBACK := 5
## Seconds a match waits for a character download before showing the default
## model instead (`_load_when_characters_ready()`).
const CHARACTER_TIMEOUT := 10.0
## Player names (`clean_name()`): at most this many characters, and the one
## used when none was entered.
const MAX_NAME_LENGTH := 10
const DEFAULT_NAME := "PLAYER"

var mode := Mode.LOCAL
## The other player's multiplayer peer id once the handshake passed, else 0.
var peer_id := 0
## The fighter this machine controls (`Match.fighters` index): host 0,
## client 1. The other one is driven by the peer's inputs.
var local_index := 0
## This machine's player, entered in the menu (`clean_name()` form). Kept
## across sessions; sent to the opponent in the handshake.
var player_name := DEFAULT_NAME
## The opponent's `player_name` once the handshake passed, else "".
var peer_name := ""
## Why the last session ended, for the menu after returning to it ("" = no
## error). Cleared when read by `take_end_reason()`.
var _end_reason := ""
## The current match's config, picked by the host and sent with the start
## (`Match.apply_config()` keys); {} when no match is running.
var match_config := { }
## Matches started in this session (the current one's number, from 1),
## counted the same on both sides; input packets carry it, so a late packet
## from the previous match is never fed into a rematch.
var match_number := 0
## After a KO: whether this player / the opponent asked for a rematch.
var rematch_requested := false
var peer_rematch_requested := false
## Whether this machine's / the peer's match scene has loaded.
var _loaded := false
var _peer_loaded := false
## Effective match configs (`Match.effective_config()`) of this machine's
## loaded match and the peer's, compared before `begin()`.
var _loaded_config := { }
var _peer_config := { }
## Character announcements and downloads (a child, so its RPCs share the
## session's connection).
var characters := CharacterSync.new()
## Forwards the hosted port on the router (UPnP) until the session closes.
var port_mapper := PortMapper.new()
## The loaded match scene, waiting for both sides (`main.gd`).
var _match: Node
## A `fail()` is pending.
var _failing := false


func _ready() -> void:
	var mp := multiplayer as SceneMultiplayer
	mp.auth_callback = _on_auth
	mp.auth_timeout = AUTH_TIMEOUT
	mp.peer_authenticating.connect(_on_peer_authenticating)
	mp.peer_authentication_failed.connect(_on_peer_authentication_failed)
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected_to_server)
	mp.connection_failed.connect(_on_connection_failed)
	mp.server_disconnected.connect(_on_server_disconnected)
	characters.name = "CharacterSync"
	characters.peer_announced.connect(_on_peer_announced)
	add_child(characters)
	port_mapper.name = "PortMapper"
	add_child(port_mapper)


func is_online() -> bool:
	return mode != Mode.LOCAL


## `application/config/version` from `project.godot`.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Splits "host", "host:port" or "[ipv6]:port" into `[host, port]`; `[]` if
## it isn't a usable address. The port defaults to `DEFAULT_PORT`.
static func parse_address(text: String) -> Array:
	var host := text.strip_edges()
	var port := DEFAULT_PORT
	if host.begins_with("["):
		var close_at := host.find("]")
		if close_at < 0:
			return []
		var rest := host.substr(close_at + 1)
		host = host.substr(1, close_at - 1)
		if not rest.is_empty():
			if not rest.begins_with(":"):
				return []
			port = parse_port(rest.substr(1))
	elif host.count(":") == 1:
		var parts := host.split(":")
		host = parts[0]
		port = parse_port(parts[1])
	if host.is_empty() or port < 0 or host.contains(" "):
		return []
	return [host, port]


## The port number in `text`, or -1 if it isn't one.
static func parse_port(text: String) -> int:
	if not text.is_valid_int():
		return -1
	var port := text.to_int()
	return port if port >= 1 and port <= 65535 else -1


## `text` as a player name: printable ASCII only (what the arcade font can
## draw), upper case, trimmed to `MAX_NAME_LENGTH`; `DEFAULT_NAME` if
## nothing is left. Also applied to the peer's name from the handshake.
static func clean_name(text: String) -> String:
	var kept := ""
	for c in text.to_upper():
		if c.unicode_at(0) >= 0x20 and c.unicode_at(0) <= 0x7E:
			kept += c
	kept = kept.strip_edges().left(MAX_NAME_LENGTH).strip_edges()
	return kept if not kept.is_empty() else DEFAULT_NAME


## Starts listening on `port` for one opponent; this machine plays fighter 1.
## Returns false (and emits `ended`) if the port can't be opened.
func host(port: int = DEFAULT_PORT) -> bool:
	close()
	if port < 1 or port > 65535:
		_end("Invalid port %d: use 1-65535" % port)
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		_end("Cannot host on UDP port %d (%s)" % [port, error_string(err)])
		return false
	mode = Mode.HOST
	local_index = 0
	multiplayer.multiplayer_peer = peer
	port_mapper.open(port)
	status_changed.emit("Hosting on port %d, waiting for an opponent..." % port)
	return true


## Connects to a host at `address` (`parse_address()` format); this machine
## plays fighter 2. Returns false (and emits `ended`) if the address is
## invalid or the connection can't be started.
func join(address: String) -> bool:
	close()
	var parsed := parse_address(address)
	if parsed.is_empty():
		_end("Invalid address \"%s\": use IP or IP:port" % address)
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(parsed[0], parsed[1])
	if err != OK:
		_end("Cannot connect to %s:%d (%s)" % [parsed[0], parsed[1], error_string(err)])
		return false
	mode = Mode.CLIENT
	local_index = 1
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Connecting to %s:%d..." % parsed)
	return true


## Leaves the session (closing the connection) without an error.
func close() -> void:
	_reset()


## Returns and clears why the last session ended ("" = no error).
func take_end_reason() -> String:
	var reason := _end_reason
	_end_reason = ""
	return reason


## Called by the match scene once loaded and wired (`main.gd`), with itself
## and its `Match.effective_config()`, which is sent to the peer. Its
## `begin()` is called once the peer's scene has loaded too, with the same
## effective config; a different one ends the session before the first tick.
func match_loaded(match_scene: Node, config: Dictionary) -> void:
	_match = match_scene
	_loaded_config = config
	_loaded = true
	_peer_loaded_rpc.rpc_id(peer_id, config)
	_begin_if_ready()


func _begin_if_ready() -> void:
	if not (_loaded and _peer_loaded and is_instance_valid(_match)):
		return
	var problem := config_mismatch(_loaded_config, _peer_config)
	if not problem.is_empty():
		_end("Match setup differs from the opponent's: %s" % problem)
		return
	_match.begin()


## The first key on which the two effective match configs differ, described,
## or "" if they are equal.
static func config_mismatch(own: Dictionary, other: Dictionary) -> String:
	for key: String in own:
		if not other.has(key):
			return "%s missing on the other side" % key
		if typeof(other[key]) != typeof(own[key]) or other[key] != own[key]:
			return "%s (this game: %s, other: %s)" % [key, own[key], other[key]]
	for key: String in other:
		if not own.has(key):
			return "%s missing on this side" % key
	return ""


## After a KO: this player wants a rematch. Tells the opponent; once both
## want one, the host starts a new match on the same connection
## (`_start_match()`, both sides reload the match scene).
func request_rematch() -> void:
	if not is_online() or rematch_requested or peer_id == 0:
		return
	rematch_requested = true
	_rematch_rpc.rpc_id(peer_id)
	_start_rematch_if_agreed()


@rpc("any_peer", "call_remote", "reliable")
func _rematch_rpc() -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	peer_rematch_requested = true
	_start_rematch_if_agreed()


## Host: starts the rematch once both players asked for it. Requests and the
## start share the reliable channel, so a request always arrives before the
## match it asked for.
func _start_rematch_if_agreed() -> void:
	if mode == Mode.HOST and rematch_requested and peer_rematch_requested:
		_start_match.rpc(_new_match_config())


@rpc("any_peer", "call_remote", "reliable")
func _peer_loaded_rpc(config: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_peer_config = config
	_peer_loaded = true
	_begin_if_ready()


## Host: a new match config: a random seed, the default stage, each fighter's
## character (the announced `CharacterLibrary.descriptor()`s, by fighter
## index: this player's, then the peer's), `MAX_ROLLBACK` and a
## `COUNTDOWN_TICKS` countdown.
func _new_match_config() -> Dictionary:
	return {
		"stage": STAGE,
		"characters": [characters.own_character, characters.peer_character],
		"seed": randi() & 0x7FFFFFFF,
		"max_rollback": MAX_ROLLBACK,
		"start_tick": COUNTDOWN_TICKS,
	}


## The model fighter `index` shows in the current match: its
## `match_config` character (`CharacterLibrary.descriptor_model()`), or the
## default model if this machine doesn't have it, or if it is the opponent's
## and `CharacterLibrary.opponents_default()` is on.
func character_model(index: int) -> String:
	var characters: Variant = match_config.get("characters")
	if not characters is Array or index >= characters.size() \
			or (index != local_index and CharacterLibrary.opponents_default()):
		return CharacterLoader.DEFAULT_CHARACTER
	var model := CharacterLibrary.descriptor_model(characters[index])
	return model if not model.is_empty() else CharacterLoader.DEFAULT_CHARACTER


## Host: both peers load the match scene, set up from `config`, once their
## characters are ready (`_load_when_characters_ready()`).
@rpc("authority", "call_local", "reliable")
func _start_match(config: Dictionary) -> void:
	match_config = config
	match_number += 1
	rematch_requested = false
	peer_rematch_requested = false
	_loaded = false
	_peer_loaded = false
	_loaded_config = { }
	_peer_config = { }
	_match = null
	_load_when_characters_ready(match_number)


## Loads match `number`'s scene once every `match_config` character is
## ready here (`CharacterSync.status()` isn't "receiving"), or after
## `CHARACTER_TIMEOUT` seconds. A character still missing then, or rejected,
## is shown as the default model (`character_model()`). Each side waits on
## its own; `match_loaded()` already holds `begin()` until both have loaded,
## and the models are visual only, so the sides needn't agree on them.
func _load_when_characters_ready(number: int) -> void:
	var deadline := Time.get_ticks_msec() + int(CHARACTER_TIMEOUT * 1000.0)
	if _characters_receiving():
		status_changed.emit("Receiving %s's character..." % peer_name)
	while _characters_receiving() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if match_number != number: # Session closed or another match started.
			return
	get_tree().change_scene_to_file(MATCH_SCENE)


func _characters_receiving() -> bool:
	var list: Variant = match_config.get("characters")
	if not list is Array:
		return false
	for desc: Variant in list:
		if characters.status(desc) == "receiving":
			return true
	return false

# --- Handshake ---


func _hello() -> PackedByteArray:
	return var_to_bytes([MAGIC, game_version(), PROTOCOL_VERSION, player_name])


## Why `data` (the peer's handshake) is incompatible with this build, or ""
## if it isn't.
static func _check_hello(data: PackedByteArray) -> String:
	var hello: Variant = bytes_to_var(data) if data.size() >= 4 else null
	if not hello is Array or hello.size() < 3 or not hello[0] is String or hello[0] != MAGIC:
		return "Not a street-faighter peer"
	if not hello[1] is String or not hello[2] is int:
		return "Malformed handshake"
	if hello[2] != PROTOCOL_VERSION:
		return "Protocol version mismatch (this game: %d, other: %d)" % [PROTOCOL_VERSION, hello[2]]
	if hello[1] != game_version():
		return "Game version mismatch (this game: %s, other: %s)" % [game_version(), hello[1]]
	if hello.size() < 4 or not hello[3] is String:
		return "Malformed handshake"
	return ""


func _on_peer_authenticating(id: int) -> void:
	if mode == Mode.CLIENT:
		(multiplayer as SceneMultiplayer).send_auth(id, _hello())


func _on_auth(id: int, data: PackedByteArray) -> void:
	var mp := multiplayer as SceneMultiplayer
	var problem := _check_hello(data)
	if mode == Mode.HOST:
		var reply: Array = bytes_to_var(_hello())
		reply.append(problem)
		mp.send_auth(id, var_to_bytes(reply))
		# A rejected client disconnects itself on the reply; if it doesn't,
		# the auth timeout drops it.
		if problem.is_empty():
			peer_name = clean_name(bytes_to_var(data)[3])
			mp.complete_auth(id)
		else:
			status_changed.emit("Refused a player: %s. Still waiting..." % problem)
		return
	# Client: the host's reply, with its verdict on us.
	var reply: Array = bytes_to_var(data) if problem.is_empty() else []
	if reply.size() >= 5 and reply[4] is String:
		problem = reply[4]
	if not problem.is_empty():
		fail("Rejected by the host: %s" % problem)
		return
	peer_name = clean_name(reply[3])
	mp.complete_auth(id)


func _on_peer_authentication_failed(_id: int) -> void:
	if mode == Mode.CLIENT:
		fail("Handshake with the host failed (timed out)")

# --- Connection events ---


## After the handshake both sides announce their character (this player's
## saved choice, `CharacterLibrary.PLAYER_CHOICE`); the host starts the first
## match once the client's announcement arrived (`_on_peer_announced()`).
func _on_peer_connected(id: int) -> void:
	if mode == Mode.HOST:
		peer_id = id
		status_changed.emit("%s joined, starting..." % peer_name)
		_announce_character()


func _on_connected_to_server() -> void:
	peer_id = 1
	status_changed.emit("Connected, waiting for the host...")
	_announce_character()


func _announce_character() -> void:
	characters.peer_id = peer_id
	characters.announce(
		CharacterLibrary.descriptor(CharacterLibrary.chosen(CharacterLibrary.PLAYER_CHOICE))
	)


func _on_peer_announced() -> void:
	if mode == Mode.HOST and match_number == 0:
		_start_match.rpc(_new_match_config())


func _on_peer_disconnected(id: int) -> void:
	if mode == Mode.HOST and id == peer_id:
		fail("Opponent disconnected")


func _on_connection_failed() -> void:
	fail("Could not connect to the host")


func _on_server_disconnected() -> void:
	fail("Opponent disconnected" if is_instance_valid(_match) else "Host disconnected")


## Ends the session with the error `reason` once the current multiplayer
## poll / physics step is over (multiplayer signals arrive while the peer is
## being polled), or after `linger` seconds, keeping the connection open so
## messages just sent still reach the peer. Only the first reason counts
## (closing can raise more signals). Mid-match, the match scene shows it
## before the menu (`_end()`).
func fail(reason: String, linger := 0.0) -> void:
	if _failing:
		return
	_failing = true
	if linger > 0.0:
		get_tree().create_timer(linger).timeout.connect(
			func() -> void:
				if _failing: # Not closed meanwhile.
					_end(reason),
		)
	else:
		_end.call_deferred(reason)


## Closes the session with an error `reason` and returns to the menu, which
## shows it. During a match, the match scene pauses and shows `reason` first
## (`main.gd` `end_online()`), then goes back to the menu itself.
func _end(reason: String) -> void:
	var match_scene := _match if is_instance_valid(_match) else null
	_reset()
	_end_reason = reason
	ended.emit(reason)
	if match_scene != null:
		match_scene.end_online(reason)
	elif get_tree().current_scene == null or get_tree().current_scene.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _reset() -> void:
	if (
		multiplayer.multiplayer_peer != null
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.LOCAL
	peer_id = 0
	peer_name = ""
	local_index = 0
	_loaded = false
	_peer_loaded = false
	_failing = false
	_match = null
	match_config = { }
	match_number = 0
	rematch_requested = false
	peer_rematch_requested = false
	_loaded_config = { }
	_peer_config = { }
	characters.reset()
	port_mapper.close()
