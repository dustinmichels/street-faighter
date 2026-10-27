extends SceneTree
## Headless determinism test for the match simulation (`docs/dev/netcode.md`):
## replays one input log twice in fresh matches and compares
## `Match.checksum` every tick. Exits 0 when all runs agree, 1 otherwise.
##
##   godot --headless --path . -s tests/determinism_test.gd [-- options]
##
## Options (after `--`):
##   --log=PATH        replay this input log instead of recording a new one
##   --save-log=PATH   write the (recorded) input log here
##   --checksums=PATH  write the replay's checksums here, one `tick checksum`
##                     line per tick
##   --expect=PATH     also compare with a checksum file from another run
##   --ticks=N         ticks to record (default 3600, one minute)
##   --seed=N          match seed for the recording (default 1)
##
## Without `--log`, the log is recorded from an AI vs AI match (the AI is
## input-side, so its buttons are all the replay needs). Cross-machine check:
## on machine A run with `--save-log=a.inputs --checksums=a.sums`, copy both
## to machine B and run with `--log=a.inputs --expect=a.sums`.
##
## Log format: 2 bytes per tick, the input bitmasks of fighter 1 and 2.

const MAIN_SCENE := "res://match/main.tscn"
const WORLD_PATH := "GameView/GameViewport/World"


func _initialize() -> void:
	# Deferred: during `_initialize` the root isn't in the tree yet, so the
	# scene's `_ready()`s (which set up the match) would not run.
	_run.call_deferred()


func _run() -> void:
	var args := _parse_args()
	var log: PackedByteArray
	var recorded := PackedInt64Array()
	if args.has("log"):
		log = FileAccess.get_file_as_bytes(args["log"])
		if log.is_empty() or log.size() % 2 != 0:
			_fail("bad input log %s" % args["log"])
			return
	else:
		var recording := _record(int(args.get("seed", "1")), int(args.get("ticks", "3600")))
		log = recording[0]
		recorded = recording[1]
	if args.has("save-log"):
		_write_bytes(args["save-log"], log)

	# The first replay also refreshes the visuals every tick, as the game does;
	# display code must not touch the simulation, so the second, without them,
	# has to match it.
	var first := _replay(log, true)
	var second := _replay(log, false)
	var ok := _compare("replay 1", first, "replay 2", second)
	if not recorded.is_empty():
		ok = _compare("recording", recorded, "replay 1", first) and ok
	if args.has("expect"):
		var expected := _read_checksums(args["expect"])
		ok = _compare(args["expect"], expected, "replay 1", first) and ok
	if args.has("checksums"):
		_write_checksums(args["checksums"], first)

	print("%d ticks replayed, final checksum %d" % [log.size() / 2, first[-1]])
	if ok:
		print("PASS: deterministic")
		quit(0)
	else:
		_fail("desync")


## A fresh match from the game's scene, ready and in the tree, its
## `_physics_process` off so only this script steps it. With `ai_vs_ai`,
## fighter 1 is driven by an AI too (fighter 2 already is). Free it with
## `world.owner.free()`.
func _new_match(match_seed: int, ai_vs_ai: bool) -> Match:
	var scene: Node = load(MAIN_SCENE).instantiate()
	# Display only, and it queries keyboard layouts, which the headless
	# display server doesn't support.
	scene.get_node("Hud").free()
	# The intro would hold the match and restart its physics when it ends.
	scene.get_node(WORLD_PATH + "/Camera3D").intro_duration = 0.0
	var world: Match = scene.get_node(WORLD_PATH)
	world.rng_seed = match_seed
	if ai_vs_ai:
		world.fighters[0].input = AIInput.new()
	root.add_child(scene)
	world.set_physics_process(false)
	return world


## Plays AI vs AI for `ticks`, recording each tick's inputs. Returns
## `[log, checksums]`.
func _record(match_seed: int, ticks: int) -> Array:
	var world := _new_match(match_seed, true)
	var log := PackedByteArray()
	var sums := PackedInt64Array([world.checksum])
	for i in ticks:
		var inputs := PackedInt32Array()
		for f in world.fighters:
			inputs.append(f.input.poll(world.tick))
		log.append(inputs[0])
		log.append(inputs[1])
		world.step(inputs)
		sums.append(world.checksum)
	var healths := [world.fighters[0].health, world.fighters[1].health]
	print("recorded %d ticks (seed %d), final health %s" % [ticks, match_seed, healths])
	world.owner.free()
	return [log, sums]


## Steps a fresh match through `log`. Returns the checksum after setup and
## after every tick (`ticks + 1` values).
func _replay(log: PackedByteArray, visuals: bool) -> PackedInt64Array:
	var world := _new_match(1, false)
	var sums := PackedInt64Array([world.checksum])
	for i in range(0, log.size(), 2):
		world.step(PackedInt32Array([log[i], log[i + 1]]))
		if visuals:
			world._sync_visuals()
		sums.append(world.checksum)
	world.owner.free()
	return sums


## Prints the first tick where `a` and `b` differ; true if none.
func _compare(a_name: String, a: PackedInt64Array, b_name: String, b: PackedInt64Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			printerr(
				"%s vs %s: checksums differ at tick %d (%d != %d)" % [a_name, b_name, i, a[i], b[i]]
			)
			return false
	if a.size() != b.size():
		printerr("%s vs %s: %d vs %d ticks" % [a_name, b_name, a.size(), b.size()])
		return false
	return true


func _parse_args() -> Dictionary:
	var args := { }
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.substr(2).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	return args


func _write_bytes(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)


func _write_checksums(path: String, sums: PackedInt64Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	for i in sums.size():
		file.store_line("%d %d" % [i, sums[i]])


func _read_checksums(path: String) -> PackedInt64Array:
	var sums := PackedInt64Array()
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		sums.append(int(line.split(" ")[1]))
	return sums


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)
