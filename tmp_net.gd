extends SceneTree
## Throwaway: `-s tmp_net.gd -- host` / `-- join` (optionally `--ticks=N`).

var ticks := 600


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var session: Node = root.get_node("Session")
	for a in args:
		if a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		if a.begins_with("--version="):
			ProjectSettings.set_setting("application/config/version", a.substr(10))
		if a.begins_with("--time-scale="):
			Engine.time_scale = float(a.substr(13))
	print("check own: '", session._check_hello(session._hello()), "'")
	print("check proto 2: ", session._check_hello(var_to_bytes([session.MAGIC, session.game_version(), 2])))
	print("check junk: ", session._check_hello(PackedByteArray([1, 2, 3])))
	session.status_changed.connect(func(t): print("[status] ", t))
	session.ended.connect(func(t): print("[ended] ", t); quit(2))
	node_added.connect(_on_node_added)
	if "host" in args:
		session.host(27779)
	else:
		session.join("127.0.0.1:27779")
	var frames := 0
	var last_text := "?"
	var first_move := -1
	var start0 := 0
	var start1 := 0
	while true:
		await physics_frame
		frames += 1
		if frames > 60 * 60:
			print("TIMEOUT")
			quit(1)
			return
		var scene := current_scene
		if scene == null or scene.name != "Main":
			if session.take_end_reason() != "":
				pass
			continue
		var world: Match = scene.get_node("GameView/GameViewport/World")
		var hud_text: String = Hud.countdown_text(world.tick, world.start_tick)
		if hud_text != last_text:
			print("hud '%s' from tick %d (frame %d, wall %d ms)" % [hud_text, world.tick, frames, Time.get_ticks_msec()])
			last_text = hud_text
		if start0 == 0:
			start0 = world.fighters[0].pos_x
			start1 = world.fighters[1].pos_x
		if first_move < 0 and (world.fighters[0].pos_x != start0 or world.fighters[1].pos_x != start1):
			first_move = world.tick
			print("first movement at tick ", first_move)
		for a in args:
			if a.begins_with("--tps=") and world.tick == 1:
				Engine.physics_ticks_per_second = int(a.substr(6))
		if world.tick >= ticks:
			print("config=", session.match_config, " effective=", world.effective_config())
			var sync: InputSync = world.get_node("InputSync")
			print("role local_index=%d peer=%d tick=%d checksum_at(%d)=%d health=%d/%d stalled=%d skipped=%d rtt=%d adv=%.2f remote_adv=%.2f lead=%.2f remote_tick=%d" % [
				session.local_index, session.peer_id,
				world.tick, ticks - 10, world.checksum_at(ticks - 10), world.fighters[0].health, world.fighters[1].health, world.stalled_frames,
				world.skipped_frames, sync.rtt_ms, sync.advantage, sync.remote_advantage, sync.lead(), sync.remote_tick])
			# Let the peer finish too.
			for i in 120:
				await physics_frame
			quit(0)
			return


func _on_node_added(node: Node) -> void:
	if node is InputSync:
		var world: Match = node.get_parent()
		var fighter: Fighter = world.fighters[root.get_node("Session").local_index]
		var ai := AIInput.new()
		node.local.source = ai
		ai.bind(fighter)
		if "--no-sync" in OS.get_cmdline_user_args():
			node.world = null
	if node is Stage:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--half-width="):
				node.half_width = float(a.substr(13))
