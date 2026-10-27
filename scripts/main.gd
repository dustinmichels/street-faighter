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
##
## Offline, the match stays frozen until the camera's intro swing
## (`FollowCamera.intro_finished`) is over.

@onready var _world: Match = $GameView/GameViewport/World
var _sync: InputSync


func _enter_tree() -> void:
	if not Session.is_online():
		return
	# Children exist but aren't ready yet, so the `Match` starts the new
	# inputs in its `_ready()`.
	var world: Match = $GameView/GameViewport/World
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
	world.add_child(_sync)


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


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"restart") or event.is_echo():
		return
	if not Session.is_online():
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
	elif _world.is_over():
		get_viewport().set_input_as_handled()
		Session.request_rematch()
