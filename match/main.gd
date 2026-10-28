extends Node
## Match root. Offline, the `restart` action (R) reloads the whole scene,
## resetting fighters, health and camera; it works at any time, not only
## after a KO, and also while the HUD's controls screen pauses the game: this
## node and the HUD process while paused, `GameView` (the fight) doesn't
## (`main.tscn` process modes). After a KO, the `controls` action (Esc)
## returns to the menu, online leaving the session first
## (`Session.close()`); before it, the HUD uses Esc for the controls screen.
##
## Online (`Session.is_online()`), it rewires the scene before anything in it
## is ready: the `Match` is set up from the host's `Session.match_config`
## (stage, characters, seed, start tick), this machine's fighter
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
##
## Offline, the player's fighter uses their saved character
## (`CharacterLibrary.PLAYER_CHOICE`, picked on the menu's character select);
## the computer keeps the scene's default model. A character that can't be
## used at match start (its library entry is gone, or `Fighter.set_character`
## fell back because it no longer validates) shows the default model, and
## the HUD and console say so (`_warn_character_fallbacks()`).
##
## Offline, the `ai_difficulty` debug action (F1) cycles the computer
## opponent's `AIInput.difficulty` (default / easy) mid-match; it carries over
## restarts, and the HUD names it while it isn't the default.
##
## `Music` loops the fight theme (`assets/music/fight.ogg`) from scene load;
## it keeps playing while the controls screen pauses the game and restarts
## with the scene.

## Seconds the reason an online match ended stays up before the menu.
const END_NOTICE_SECONDS := 3.0
## Seconds the connection stays open after a desync, so the peer still gets
## this side's state (`InputSync` reports) before it sees a disconnect.
const DESYNC_LINGER_SECONDS := 0.5

@onready var _world: Match = $GameView/GameViewport/World
var _sync: InputSync
## Offline: the player's saved choice is no longer in the library, so their
## fighter got the default model.
var _missing_choice := false


func _enter_tree() -> void:
	var world: Match = $GameView/GameViewport/World
	if Session.is_online():
		_wire_online(world)
	else:
		var choice := CharacterLibrary.chosen(CharacterLibrary.PLAYER_CHOICE)
		_missing_choice = not CharacterLibrary.BUILTIN.has(choice) and not CharacterLibrary.has(
				choice
			)
		var player_model := CharacterLibrary.model_path(choice)
		for f in world.fighters:
			if not f.input is AIInput:
				f.character_path = player_model
	for f in world.fighters:
		f.specials_enabled = not (f.input is AIInput)
		if f.input is AIInput:
			(f.input as AIInput).apply_difficulty()
	var hud := get_node_or_null("Hud") as Hud
	if hud != null:
		hud.left_name = _fighter_name(world, 0)
		hud.right_name = _fighter_name(world, 1)
		hud.debug_text = _difficulty_text()


## HUD line for the current `AIInput.difficulty`; empty for the default.
static func _difficulty_text() -> String:
	if AIInput.difficulty == AIInput.Difficulty.DEFAULT:
		return ""
	return "CPU difficulty: %s" % str(AIInput.Difficulty.find_key(AIInput.difficulty)).to_lower()


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
	for i in world.fighters.size():
		world.fighters[i].character_path = Session.character_model(i)
	var local := LocalInput.new()
	var remote := NetworkInput.new()
	world.fighters[Session.local_index].input = local
	world.fighters[1 - Session.local_index].input = remote
	_sync = InputSync.new()
	_sync.name = "InputSync"
	_sync.local = local
	_sync.remote_input = remote
	_sync.world = world
	_sync.match_id = Session.match_number
	_sync.apply_sim_args(OS.get_cmdline_user_args())
	_sync.timed_out.connect(_on_sync_timed_out)
	_sync.desynced.connect(_on_sync_desynced)
	world.add_child(_sync)
	($Hud as Hud).net = _sync


## Tells the player (HUD warning and console) about every fighter showing
## the default model instead of its character: a missing library entry
## (`_missing_choice`) or a model that failed to load (`Fighter.model_path`
## differs from `character_path`; the loader already logged why).
func _warn_character_fallbacks() -> void:
	var hud := get_node_or_null("Hud") as Hud
	var lines := PackedStringArray()
	for i in _world.fighters.size():
		var f := _world.fighters[i]
		var who := "Player %d" % (i + 1)
		if hud != null:
			var shown := hud.left_name if i == 0 else hud.right_name
			if not shown.is_empty():
				who = shown
		if f.model_path != f.character_path:
			lines.append("%s's character couldn't be loaded, using the default" % who)
		elif _missing_choice and not f.input is AIInput:
			lines.append("%s's character is no longer in the library, using the default" % who)
	for line in lines:
		push_warning(line)
	if hud != null and not lines.is_empty():
		hud.show_warning("\n".join(lines))


func _ready() -> void:
	_warn_character_fallbacks()
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
func _on_sync_desynced(
	tick: int,
	own_state: PackedInt64Array,
	peer_state: PackedInt64Array,
) -> void:
	printerr(desync_report(tick, own_state, peer_state, Session.match_number, Session.local_index))
	Session.fail("Desync at tick %d: the games went out of sync" % tick, DESYNC_LINGER_SECONDS)


## A table of both sides' `Match.save_state()` values at `tick`, one per
## line, differing ones marked; an empty state is shown as missing.
static func desync_report(
	tick: int,
	own_state: PackedInt64Array,
	peer_state: PackedInt64Array,
	match_number: int,
	local_index: int,
) -> String:
	var names := PackedStringArray(["tick"])
	for i in 2:
		for field in Fighter.SNAPSHOT_FIELDS:
			names.append("fighter%d.%s" % [i + 1, field])
	var lines := PackedStringArray(
		[
			"DESYNC at tick %d (match %d, this side plays fighter %d)"
			% [tick, match_number, local_index + 1],
			"%-26s %12s %12s" % ["value", "this side", "opponent"],
		]
	)
	for i in names.size():
		var own := str(own_state[i]) if i < own_state.size() else "-"
		var peer := str(peer_state[i]) if i < peer_state.size() else "-"
		lines.append("%-26s %12s %12s%s" % [names[i], own, peer, "" if own == peer else "  <--"])
	return "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ai_difficulty") and not event.is_echo() and not Session.is_online():
		get_viewport().set_input_as_handled()
		_cycle_difficulty()
		return
	if event.is_action_pressed(&"controls") and not event.is_echo() and _world.is_over_confirmed():
		get_viewport().set_input_as_handled()
		Session.close()
		_return_to_menu()
		return
	if not event.is_action_pressed(&"restart") or event.is_echo():
		return
	if not Session.is_online():
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
	elif _world.is_over_confirmed():
		get_viewport().set_input_as_handled()
		Session.request_rematch()


func _cycle_difficulty() -> void:
	AIInput.cycle_difficulty()
	for f in _world.fighters:
		if f.input is AIInput:
			(f.input as AIInput).apply_difficulty()
	($Hud as Hud).debug_text = _difficulty_text()
