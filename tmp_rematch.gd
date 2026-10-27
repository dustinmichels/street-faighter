extends SceneTree
## Throwaway: `-s tmp_rematch.gd -- host|join`. AI vs AI until KO, then a
## rematch (host asks after 30 frames, client after 120), then a second KO.

var session: Node
var matches_done := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	session = root.get_node("Session")
	session.ended.connect(func(t): print("[ended] ", t); quit(2))
	node_added.connect(_on_node_added)
	var is_host := "host" in args
	if is_host:
		session.host(27781)
	else:
		session.join("127.0.0.1:27781")
	var frames := 0
	var ko_frames := 0
	var peer_at_start := 0
	var last_hint := ""
	var last_world: Match = null
	while true:
		await physics_frame
		frames += 1
		if frames > 60 * 120:
			print("TIMEOUT")
			quit(1)
			return
		var scene := current_scene
		if scene == null or scene.name != "Main":
			continue
		var world: Match = scene.get_node("GameView/GameViewport/World")
		if world != last_world:
			last_world = world
			ko_frames = 0
			if peer_at_start == 0:
				peer_at_start = session.peer_id
			print("match %d started: seed %d, peer %d (same connection: %s), tick %d, start_tick %d" % [
				session.match_number, world.rng_seed, session.peer_id, session.peer_id == peer_at_start, world.tick, world.start_tick])
		if not world.is_over():
			continue
		ko_frames += 1
		var hud: Hud = scene.get_node("Hud")
		var hint: String = hud._ko_hint.text
		if hint != last_hint:
			print("  hint: '%s' (match %d, tick %d)" % [hint, session.match_number, world.tick])
			last_hint = hint
		if ko_frames == 1:
			print("KO in match %d at tick %d: checksum_at(%d)=%d health=%d/%d stalled=%d skipped=%d" % [
				session.match_number, world.tick, world.tick - 5, world.checksum_at(world.tick - 5),
				world.fighters[0].health, world.fighters[1].health, world.stalled_frames, world.skipped_frames])
			if session.match_number == 2:
				for i in 120:
					await physics_frame
				quit(0)
				return
		if ko_frames == (30 if is_host else 120):
			# Through the real input path.
			var ev := InputEventAction.new()
			ev.action = &"restart"
			ev.pressed = true
			Input.parse_input_event(ev)


func _on_node_added(node: Node) -> void:
	if node is InputSync:
		var world: Match = node.get_parent()
		var ai := AIInput.new()
		node.local.source = ai
		ai.bind(world.fighters[session.local_index])
