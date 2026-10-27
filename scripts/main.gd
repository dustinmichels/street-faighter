extends Node
## Match root. Offline, the `restart` action (R) reloads the whole scene,
## resetting fighters, health and camera; it works at any time, not only
## after a KO.
##
## Online (`Session.is_online()`), it rewires the scene before anything in it
## is ready: the `Match` is set up from the host's `Session.match_config`
## (stage, tints, seed, start tick), this machine's fighter
## (`Session.local_index`) gets a `LocalInput` (keyboard), the other a
## `NetworkInput`, and an `InputSync` under the `Match` exchanges them with
## `Session.peer_id`. The match stays frozen until `Session` calls `begin()`,
## once both peers have loaded the same effective config. After a KO, R asks
## for a rematch (`Session.request_rematch()`); once both players have, the
## host restarts the match scene on both sides over the same connection.
## When the session ends mid-match (opponent disconnected, ...), `Session`
## calls `end_online()`: the match freezes, the HUD shows why, and after
## `END_NOTICE_SECONDS` the game returns to the menu. Command-line user args
## `--net-latency=MS`, `--net-jitter=MS`, `--net-loss=PERCENT` simulate a
## worse network (`InputSync.apply_sim_args()`).
##
## Offline, the match stays frozen until the camera's intro swing
## (`FollowCamera.intro_finished`) is over.
##
## The HUD labels each health bar with its fighter's name (`_fighter_name()`).
## Only players get the special: a fighter driven by the computer
## (`AIInput`) has `Fighter.specials_enabled` off.

## Seconds the reason an online match ended stays up before the menu.
const END_NOTICE_SECONDS := 3.0
## Seconds the connection stays open after a desync, so the peer still gets
## this side's state (`InputSync` reports) before it sees a disconnect.
const DESYNC_LINGER_SECONDS := 0.5

@onready var _world: Match = $GameView/GameViewport/World
var _sync: InputSync


func _enter_tree() -> void:
	var world: Match = $GameView/GameViewport/World
	if Session.is_online():
		_wire_online(world)
	for f in world.fighters:
		f.specials_enabled = not (f.input is AIInput)
	var hud := get_node_or_null("Hud") as Hud
	if hud != null:
		hud.left_name = _fighter_name(world, 0)
		hud.right_name = _fighter_name(world, 1)


## Name shown on fighter `index`'s health bar: this player's
## `Session.player_name`; online the opponent's, offline a random one for a
## computer opponent (`AIInput.random_name()`).
static func _fighter_name(world: Match, index: int) -> String:
	if Session.is_online():
		return Session.player_name if index == Session.local_index else Session.peer_name
	return AIInput.random_name() if world.fighters[index].input is AIInput else Session.player_name


func _wire_online(world: Match) -> void:
	# Children exist but aren't ready yet, so the `Match` starts the new
	# inputs in its `_ready()`.
	world.apply_config(Session.match_config)
	var local := LocalInput.new()
	var remote := NetworkInput.new()
	world.fighters[Session.local_index].input = local
	world.fighters[1 - Session.local_index].input = remote
	_sync = InputSync.new()
	_sync.name = "InputSync"
	_sync.local = local
	_sync.remote = remote
	_sync.world = world
	_sync.match_id = Session.match_number
	_sync.apply_sim_args(OS.get_cmdline_user_args())
	_sync.timed_out.connect(_on_sync_timed_out)
	_sync.desynced.connect(_on_sync_desynced)
	world.add_child(_sync)
	($Hud as Hud).net = _sync


func _ready() -> void:
	if not Session.is_online():
		# Nobody moves while the camera swings in. Online, the countdown
		# (`Session.COUNTDOWN_TICKS`) already covers the intro.
		var camera: FollowCamera = $GameView/GameViewport/World/Camera3D
		if camera.in_intro():
			_world.set_physics_process(false)
			camera.intro_finished.connect(_world.set_physics_process.bind(true), CONNECT_ONE_SHOT)
		return
	_world.set_physics_process(false)
	_sync.set_physics_process(false)
	Session.match_loaded(self, _world.effective_config())


## Online: both peers have loaded the match; start ticking.
func begin() -> void:
	_sync.peer_id = Session.peer_id
	_sync.reset()
	_world.set_physics_process(true)
	_sync.set_physics_process(true)


## Online: the session ended (already closed) because of `reason`. Freezes
## the match, shows `reason`, and returns to the menu (which shows it again)
## after `END_NOTICE_SECONDS`.
func end_online(reason: String) -> void:
	_world.set_physics_process(false)
	if _sync != null:
		_sync.peer_id = 0
		_sync.set_physics_process(false)
	($Hud as Hud).show_notice("%s\nReturning to the menu..." % reason)
	get_tree().create_timer(END_NOTICE_SECONDS).timeout.connect(_return_to_menu)


func _return_to_menu() -> void:
	get_tree().change_scene_to_file(Session.MENU_SCENE)


func _on_sync_timed_out() -> void:
	Session.fail("Connection lost: no data from the opponent for %d s" % InputSync.TIMEOUT_SECONDS)


## The peers' simulations diverged: logs both states at the first mismatched
## tick confirmed by both (Godot's log, `user://logs/`) and ends the session,
## after `DESYNC_LINGER_SECONDS` so this side's report still reaches the peer.
func _on_sync_desynced(tick: int, own_state: PackedInt64Array, peer_state: PackedInt64Array) -> void:
	printerr(desync_report(tick, own_state, peer_state, Session.match_number, Session.local_index))
	Session.fail("Desync at tick %d: the games went out of sync" % tick, DESYNC_LINGER_SECONDS)


## A table of both sides' `Match.save_state()` values at `tick`, one per
## line, differing ones marked; an empty state is shown as missing.
static func desync_report(tick: int, own_state: PackedInt64Array, peer_state: PackedInt64Array, match_number: int, local_index: int) -> String:
	var names := PackedStringArray(["tick"])
	for i in 2:
		for field in Fighter.SNAPSHOT_FIELDS:
			names.append("fighter%d.%s" % [i + 1, field])
	var lines := PackedStringArray([
		"DESYNC at tick %d (match %d, this side plays fighter %d)" % [tick, match_number, local_index + 1],
		"%-26s %12s %12s" % ["value", "this side", "opponent"],
	])
	for i in names.size():
		var own := str(own_state[i]) if i < own_state.size() else "-"
		var peer := str(peer_state[i]) if i < peer_state.size() else "-"
		lines.append("%-26s %12s %12s%s" % [names[i], own, peer, "" if own == peer else "  <--"])
	return "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"restart") or event.is_echo():
		return
	if not Session.is_online():
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
	elif _world.is_over():
		get_viewport().set_input_as_handled()
		Session.request_rematch()
