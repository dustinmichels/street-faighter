extends SceneTree
## Throwaway: `-s tmp_disc.gd -- host|join [--leave-at=N]`.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var session: Node = root.get_node("Session")
	var leave_at := -1
	var mute_at := -1
	var corrupt_at := -1
	var garbage_at := -1
	for a in args:
		if a.begins_with("--corrupt-at="):
			corrupt_at = int(a.substr(13))
		if a.begins_with("--garbage-at="):
			garbage_at = int(a.substr(13))
	for a in args:
		if a.begins_with("--leave-at="):
			leave_at = int(a.substr(11))
		if a.begins_with("--mute-at="):
			mute_at = int(a.substr(10))
	session.ended.connect(func(t): print("[ended] '%s' frame-ms %d" % [t, Time.get_ticks_msec()]))
	if "host" in args:
		session.host(27781)
	else:
		session.join("127.0.0.1:27781")
	var frozen_tick := -1
	var notice_seen := false
	for frame in 60 * 40:
		await physics_frame
		var scene := current_scene
		if scene == null:
			continue
		if scene.scene_file_path == "res://scenes/menu.tscn" and notice_seen:
			print("back at menu, status='%s' ms %d" % [scene.get_node("%Status").text, Time.get_ticks_msec()])
			quit(0)
			return
		if scene.name != "Main":
			continue
		var world: Match = scene.get_node("GameView/GameViewport/World")
		if mute_at >= 0 and world.tick >= mute_at and world.get_node("InputSync").is_physics_processing():
			print("muting at tick %d ms %d" % [world.tick, Time.get_ticks_msec()])
			world.get_node("InputSync").set_physics_process(false)
		if corrupt_at >= 0 and world.tick >= corrupt_at:
			print("corrupting at tick %d" % world.tick)
			world.fighters[1].health -= 1
			corrupt_at = -1
		var s: InputSync = world.get_node_or_null("InputSync")
		if s != null and world.tick > 0 and world.tick % 60 == 0 and s.is_physics_processing():
			print("tick %d remote_tick %d remote_adv %.2f remote_end %d peer_has %d" % [world.tick, s.remote_tick, s.remote_advantage, s.remote.end_tick(), s._peer_has])
		if garbage_at >= 0 and world.tick >= garbage_at and world.tick < garbage_at + 30 and s.peer_id != 0:
			var p: int = s.peer_id
			var m: int = s.match_id
			var ack: int = s.remote.end_tick()
			var first: int = s._peer_has
			var big := PackedByteArray()
			big.resize(InputSync.MAX_INPUTS + 1)
			big.fill(InputSource.PUNCH)
			s._receive_inputs.rpc_id(p, m, ack, first, big, world.tick, 0.0, -1, 0, s._send_seq)
			s._receive_inputs.rpc_id(p, m, ack, first, PackedByteArray([0xFF, 0xFF, 0xFF]), world.tick, 0.0, -1, 0, s._send_seq)
			s._receive_inputs.rpc_id(p, m, ack, first, PackedByteArray(), 1 << 40, 0.0, -1, 0, s._send_seq)
			s._receive_inputs.rpc_id(p, m, ack, first, PackedByteArray(), world.tick, NAN, -1, 0, s._send_seq)
			s._receive_inputs.rpc_id(p, m, 1 << 40, -5, PackedByteArray([1]), world.tick, 0.0, -1, 0, s._send_seq)
			s._receive_inputs.rpc_id(p, m, ack, first, PackedByteArray(), world.tick, 0.0, 1 << 40, 7, s._send_seq)
			s._receive_inputs.rpc_id(p, m, ack, first, PackedByteArray(), world.tick, 0.0, -1, 0, 1 << 40)
			s._receive_inputs.rpc_id(p, "junk")
			s._receive_inputs.rpc_id(p, m, "a", first, 3, world.tick, 0.0, -1, 0)
			s._receive_desync_state.rpc_id(p, m, maxi(world.tick - 2, 0), PackedInt64Array([1, 2, 3]))
			s._receive_desync_state.rpc_id(p, m, 1 << 40, PackedInt64Array())
		if leave_at >= 0 and world.tick >= leave_at:
			print("leaving at tick ", world.tick)
			session.close()
			for i in 30:
				await physics_frame
			quit(0)
			return
		var hud: Hud = scene.get_node("Hud")
		if hud._notice.visible:
			if not notice_seen:
				notice_seen = true
				frozen_tick = world.tick
				print("notice '%s' at tick %d ms %d, phys=%s" % [hud._notice.text.c_escape(), world.tick, Time.get_ticks_msec(), world.is_physics_processing()])
			elif world.tick != frozen_tick:
				print("FAIL: ticked after notice")
				quit(1)
				return
	print("TIMEOUT")
	quit(1)
