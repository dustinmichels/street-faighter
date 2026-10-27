extends SceneTree
## Headless netcode test (`docs/dev/netcode.md`): a host and a client match in
## one process, each in its own `SceneMultiplayer` branch, connected over ENet
## on 127.0.0.1. Each side's player is a `LocalInput` driven by an AI, the
## other a `NetworkInput` fed by `InputSync`. Every loop iteration runs one
## physics frame per side (`Match` then `InputSync`), except that a side
## sometimes skips its frame (a slow machine) and its packet is sometimes
## dropped (loss). Checks that both sides end up with identical checksums for
## every tick (once confirmed, `Match.confirmed_tick`) and that neither runs
## further ahead than allowed: the other side's input delay in lockstep, plus
## `Match.max_rollback` with rollback. Exits 0 on success, 1 otherwise.
##
##   godot --headless --path . -s tests/lockstep_test.gd [-- options]
##
## Options (after `--`):
##   --ticks=N    ticks to simulate (default 1200)
##   --loss=P     chance a frame's packet is dropped (default 0.3)
##   --stall=P    chance a side skips a frame (default 0.2)
##   --delay=N    input delay of both sides (default `LocalInput.DEFAULT_DELAY`)
##   --rollback=N `Match.max_rollback` of both sides (default 0: lockstep)
##   --port=N     UDP port on 127.0.0.1 (default 27777)
##   --seed=N     match seed and seed of the loss/skip pattern (default 1)

const MAIN_SCENE := "res://scenes/main.tscn"
const WORLD_PATH := "GameView/GameViewport/World"
## Loop iterations before giving up (a deadlock).
const MAX_FRAMES := 200000


class Peer:
	var world: Match
	var sync: InputSync
	var multiplayer: SceneMultiplayer
	var checksums := PackedInt64Array()


func _initialize() -> void:
	# Deferred: the root isn't in the tree yet during `_initialize`.
	_run.call_deferred()


func _run() -> void:
	var args := _parse_args()
	var ticks := int(args.get("ticks", "1200"))
	var loss := float(args.get("loss", "0.3"))
	var stall := float(args.get("stall", "0.2"))
	var delay := int(args.get("delay", str(LocalInput.DEFAULT_DELAY)))
	var rollback := int(args.get("rollback", "0"))
	var port := int(args.get("port", "27777"))
	var match_seed := int(args.get("seed", "1"))
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed

	# Multiplayer is polled below, together with the frames.
	multiplayer_poll = false
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	if server.create_server(port, 1) != OK or client.create_client("127.0.0.1", port) != OK:
		_fail("cannot open ENet peers on port %d" % port)
		return
	var host := _side("Host", 0, server, match_seed, delay, rollback)
	var guest := _side("Client", 1, client, match_seed, delay, rollback)
	var sides: Array[Peer] = [host, guest]
	var frames := 0
	while client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or host.multiplayer.get_peers().is_empty():
		for s in sides:
			s.multiplayer.poll()
		frames += 1
		if frames > MAX_FRAMES:
			_fail("no connection")
			return
		await process_frame
	host.sync.peer_id = host.multiplayer.get_peers()[0]
	guest.sync.peer_id = 1

	var dropped := 0
	var max_lead := 0
	frames = 0
	while host.checksums.size() < ticks or guest.checksums.size() < ticks:
		for s in sides:
			s.multiplayer.poll()
		for s in sides:
			if rng.randf() < stall:
				continue
			# A side done with its ticks keeps sending, so the other gets its
			# last inputs and acks.
			if s.checksums.size() < ticks:
				s.world._physics_process(0.0)
				while s.checksums.size() < mini(s.world.confirmed_tick, ticks):
					s.checksums.append(s.world.checksum_at(s.checksums.size() + 1))
			if rng.randf() < loss:
				dropped += 1
			else:
				s.sync._physics_process(0.0)
		max_lead = maxi(max_lead, absi(host.world.tick - guest.world.tick))
		if max_lead > delay + rollback:
			_fail("one side ran %d ticks ahead (delay %d, rollback %d)" % [max_lead, delay, rollback])
			return
		frames += 1
		if frames > MAX_FRAMES:
			_fail("stuck at ticks %d / %d" % [host.world.tick, guest.world.tick])
			return
		await process_frame

	print("%d ticks in %d frames: %d/%d stalled frames, %d packets dropped, max lead %d" % [
		ticks, frames, host.world.stalled_frames, guest.world.stalled_frames, dropped, max_lead])
	print("rollbacks %d/%d, re-simulated ticks %d/%d" % [host.world.rollbacks, guest.world.rollbacks,
		host.world.resimulated_ticks, guest.world.resimulated_ticks])
	if rollback > 0 and loss > 0.0 and host.world.rollbacks + guest.world.rollbacks == 0:
		_fail("rollback enabled but no prediction was ever corrected")
		return
	for i in ticks:
		if host.checksums[i] != guest.checksums[i]:
			_fail("desync at tick %d (%d != %d)" % [i + 1, host.checksums[i], guest.checksums[i]])
			return
	# The same inputs replayed in an offline match must give the same ticks.
	var replay := _replay(host.sync.local, host.sync.remote, match_seed)
	for i in ticks:
		if replay[i] != host.checksums[i]:
			_fail("tick %d differs from an offline replay of the inputs (%d != %d)" % [i + 1, host.checksums[i], replay[i]])
			return
	print("final checksum %d, health %d/%d" % [host.checksums[-1], host.world.fighters[0].health, host.world.fighters[1].health])
	print("PASS: in sync")
	quit(0)


## Checksums after each tick of a fresh offline match whose fighters replay
## the inputs that `first` and `second` hold.
func _replay(first: TickInput, second: TickInput, match_seed: int) -> PackedInt64Array:
	var scene: Node = load(MAIN_SCENE).instantiate()
	scene.name = "Replay"
	scene.get_node("Hud").free()
	# The intro would hold the match and restart its physics when it ends.
	scene.get_node(WORLD_PATH + "/Camera3D").intro_duration = 0.0
	var world: Match = scene.get_node(WORLD_PATH)
	world.rng_seed = match_seed
	var inputs: Array[NetworkInput] = [NetworkInput.new(), NetworkInput.new()]
	for i in 2:
		world.fighters[i].input = inputs[i]
	world.set_physics_process(false)
	root.add_child(scene)
	# After `_ready()`, which `start()`s (clears) the inputs.
	inputs[0].receive(0, first.inputs_from(0, first.end_tick()))
	inputs[1].receive(0, second.inputs_from(0, second.end_tick()))
	var sums := PackedInt64Array()
	while world.fighters[0].input.has_input(world.tick) and world.fighters[1].input.has_input(world.tick):
		world._physics_process(0.0)
		sums.append(world.checksum)
	return sums


## A match from the game's scene where fighter `local_index` is this side's
## (AI-driven) player, with an `InputSync` and its own multiplayer branch on
## `peer`. Frames are run by `_run()`, not by the engine.
func _side(scene_name: String, local_index: int, peer: ENetMultiplayerPeer, match_seed: int, delay: int, rollback: int) -> Peer:
	var scene: Node = load(MAIN_SCENE).instantiate()
	scene.name = scene_name
	# Display only, and it queries keyboard layouts, which the headless
	# display server doesn't support.
	scene.get_node("Hud").free()
	scene.get_node(WORLD_PATH + "/Camera3D").intro_duration = 0.0
	var side := Peer.new()
	side.world = scene.get_node(WORLD_PATH)
	side.world.rng_seed = match_seed
	side.world.max_rollback = rollback
	var local := LocalInput.new()
	local.source = AIInput.new()
	local.delay = delay
	var remote := NetworkInput.new()
	side.world.fighters[local_index].input = local
	side.world.fighters[1 - local_index].input = remote
	side.sync = InputSync.new()
	side.sync.name = "InputSync"
	side.sync.local = local
	side.sync.remote = remote
	side.sync.world = side.world
	side.world.add_child(side.sync)
	root.add_child(scene)
	side.multiplayer = SceneMultiplayer.new()
	set_multiplayer(side.multiplayer, scene.get_path())
	side.multiplayer.multiplayer_peer = peer
	side.world.set_physics_process(false)
	side.sync.set_physics_process(false)
	return side


func _parse_args() -> Dictionary:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.substr(2).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	return args


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)
