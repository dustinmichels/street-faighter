extends SceneTree
## Headless online character test (`docs/todo/custom-characters.md` §7) with
## two processes: this one hosts and starts a second one as the client (same
## script, `--role=client`). Both run the real `Session` and match scene over
## ENet on 127.0.0.1, each with its own character library under
## `user://character_sync_test/<role>/`. Three sessions:
##   1. The client plays custom character A: the host downloads it
##      (`CharacterSync`), validates and caches it, and shows it. A rematch
##      on the same connection shows it again without a new download.
##   2. A new session with A: the host shows its cached copy, no download.
##   3. The client plays B, whose stored file it corrupted after importing
##      (one byte, same size): the host rejects the transfer (SHA-256),
##      caches nothing and shows the default, and the match still runs.
## In every match both sides must report the same checksum at tick
## `CHECK_TICK` (exchanged as files in the shared folder). Exits 0 on
## success, 1 otherwise.
##
##   godot --headless --path . -s tests/character_sync_test.gd [-- --port=N]

const BASE := "user://character_sync_test"
const CHECK_TICK := 200
## Seconds any single step may take.
const STEP_TIMEOUT := 60.0
const MENU_SCENE := "res://scenes/menu.tscn"
const WORLD_PATH := "GameView/GameViewport/World"
## JSON chunk padding of A and B (different bytes, so different ids); A
## needs several `CharacterSync.CHUNK_BYTES` chunks.
const PAD_A := 200000
const PAD_B := 100000
## Matches per session (1 = no rematch).
const MATCHES := [2, 1, 1]

var _role := "host"
var _port := 27812
var _client_pid := 0
var _session: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr(7)
		elif arg.begins_with("--port="):
			_port = int(arg.substr(7))
	_session = root.get_node("Session")
	CharacterLibrary.dir = BASE.path_join(_role).path_join("characters")
	CharacterLibrary.settings_path = BASE.path_join(_role).path_join("settings.cfg")
	var problem := ""
	if _role == "host":
		problem = await _host()
	else:
		problem = await _client()
	if _client_pid != 0 and OS.is_process_running(_client_pid):
		OS.kill(_client_pid)
	if not problem.is_empty():
		printerr("FAIL (%s): %s" % [_role, problem])
		quit(1)
		return
	print("PASS (%s)" % _role)
	quit(0)


# --- Host ---

func _host() -> String:
	_remove_tree(ProjectSettings.globalize_path(BASE))
	DirAccess.make_dir_recursive_absolute(BASE.path_join("host"))
	_client_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/character_sync_test.gd",
		"--", "--role=client", "--port=%d" % _port])
	if _client_pid <= 0:
		return "can't start the client process"
	var ids := await _read_ids()
	if ids.is_empty():
		return "the client didn't import its characters"
	var a: String = ids[0]
	var b: String = ids[1]
	var remote := CharacterLibrary.remote_path(a)
	for s in MATCHES.size():
		if not _session.host(_port):
			return "can't host on port %d" % _port
		_write_text(_marker(s), "")
		for m in MATCHES[s]:
			var world := await _match_world(s, m)
			if world == null:
				return "session %d match %d didn't start: %s" % [s + 1, m + 1, _session.take_end_reason()]
			var downloads: Dictionary = _session.characters._downloads
			var expected := remote
			match s:
				0:
					if downloads.keys() != [a] or downloads[a].state != "ready" or not FileAccess.file_exists(remote):
						return "A wasn't downloaded and cached (downloads %s)" % [downloads]
				1:
					if not downloads.is_empty():
						return "cached A was downloaded again (downloads %s)" % [downloads]
				2:
					if downloads.keys() != [b] or downloads[b].state != "failed":
						return "corrupted B wasn't rejected (downloads %s)" % [downloads]
					expected = CharacterLoader.DEFAULT_CHARACTER
			var cached := Array(DirAccess.get_files_at(remote.get_base_dir()))
			if cached != [remote.get_file()]:
				return "remote cache holds %s, expected only A" % [cached]
			if world.fighters[1].model_path != expected or world.fighters[0].model_path != CharacterLoader.DEFAULT_CHARACTER:
				return "session %d match %d shows %s, expected [default, %s]" % [s + 1, m + 1,
					[world.fighters[0].model_path, world.fighters[1].model_path], expected]
			var sum := await _checksum(world)
			if sum < 0:
				return "session %d match %d didn't reach tick %d: %s" % [s + 1, m + 1, CHECK_TICK, _session.take_end_reason()]
			var reply: Variant = await _wait_text(_result("client", s, m))
			if reply != str(sum):
				return "session %d match %d: host checksum %d, client reported \"%s\"" % [s + 1, m + 1, sum, reply]
			print("session %d match %d: checksum %d, opponent shown as %s" % [s + 1, m + 1, sum, expected.get_file()])
			if m + 1 < MATCHES[s]:
				_session.request_rematch()
		_session.close()
		change_scene_to_file(MENU_SCENE)
	return "" if (await _wait_text(_result("client", MATCHES.size(), 0))) == "done" else "the client didn't finish"


func _read_ids() -> PackedStringArray:
	var text: Variant = await _wait_text(BASE.path_join("ids.txt"))
	var ids := str(text).split(" ") if text != null else PackedStringArray()
	return ids if ids.size() == 2 else PackedStringArray()


# --- Client ---

func _client() -> String:
	DirAccess.make_dir_recursive_absolute(BASE.path_join("client"))
	var a := _import_padded(PAD_A)
	var b := _import_padded(PAD_B)
	if a.is_empty() or b.is_empty():
		return "can't import the test characters"
	# Corrupt B's stored copy: its id and size stay, its bytes don't match.
	var bytes := FileAccess.get_file_as_bytes(CharacterLibrary.glb_path(b))
	var at := 20 + bytes.decode_u32(12) - 1  # The JSON chunk's last padding space.
	bytes[at] = 0x09  # A tab: still valid JSON whitespace, so the client's own copy loads.
	_write_bytes(CharacterLibrary.glb_path(b), bytes)
	_write_text(BASE.path_join("ids.txt"), "%s %s" % [a, b])
	for s in MATCHES.size():
		var own := a if s < 2 else b
		CharacterLibrary.choose(CharacterLibrary.PLAYER_CHOICE, own)
		if (await _wait_text(_marker(s))) == null:
			return "the host didn't open session %d" % [s + 1]
		if not _session.join("127.0.0.1:%d" % _port):
			return "can't join"
		for m in MATCHES[s]:
			var world := await _match_world(s, m)
			if world == null:
				return "session %d match %d didn't start: %s" % [s + 1, m + 1, _session.take_end_reason()]
			if world.fighters[1].model_path != CharacterLibrary.glb_path(own) \
					or world.fighters[0].model_path != CharacterLoader.DEFAULT_CHARACTER:
				return "session %d match %d shows %s" % [s + 1, m + 1, [world.fighters[0].model_path, world.fighters[1].model_path]]
			var sum := await _checksum(world)
			if sum < 0:
				return "session %d match %d didn't reach tick %d: %s" % [s + 1, m + 1, CHECK_TICK, _session.take_end_reason()]
			_write_text(_result("client", s, m), str(sum))
			if m + 1 < MATCHES[s]:
				_session.request_rematch()
		# The host closes the session once it has checked this one.
		if not await _until(func() -> bool: return not _session.is_online()):
			return "the host didn't close session %d" % [s + 1]
		_session.take_end_reason()
	_write_text(_result("client", MATCHES.size(), 0), "done")
	return ""


## Imports the default character with `pad` spaces added to its JSON chunk
## (`CharacterLibrary.import_file()`), returning its id ("" on errors).
func _import_padded(pad: int) -> String:
	var bytes := FileAccess.get_file_as_bytes(CharacterLoader.DEFAULT_CHARACTER)
	var json_length := bytes.decode_u32(12)
	var out := bytes.slice(0, 20 + json_length)
	var spaces := PackedByteArray()
	spaces.resize(pad)
	spaces.fill(32)
	out.append_array(spaces)
	out.append_array(bytes.slice(20 + json_length))
	out.encode_u32(12, json_length + pad)
	out.encode_u32(8, out.size())
	var path := BASE.path_join(_role).path_join("pad_%d.glb" % pad)
	_write_bytes(path, out)
	var result := CharacterLibrary.import_file(ProjectSettings.globalize_path(path))
	if not result.errors.is_empty():
		printerr(result.errors)
	return result.id


# --- Shared ---

## The `Match` of session `s`'s match `m` once it is running, or null.
func _match_world(s: int, m: int) -> Match:
	var number := m + 1
	var ok := await _until(func() -> bool:
		return _session.match_number == number and current_scene != null \
			and current_scene.has_method("begin") and current_scene.has_node(WORLD_PATH) \
			and (current_scene.get_node(WORLD_PATH) as Match).is_physics_processing() \
			and (current_scene.get_node(WORLD_PATH) as Match).tick < CHECK_TICK)  # Not the previous match's.
	if not ok:
		print("%s: session %d match %d not running" % [_role, s + 1, number])
		return null
	return current_scene.get_node(WORLD_PATH)


## `world`'s confirmed checksum at `CHECK_TICK`, or -1 if it isn't reached.
func _checksum(world: Match) -> int:
	var ok := await _until(func() -> bool:
		return is_instance_valid(world) and world.confirmed_tick >= CHECK_TICK)
	if not ok or not world.has_tick(CHECK_TICK):
		return -1
	return world.checksum_at(CHECK_TICK)


## Waits (physics frames) until `condition` holds; false after `STEP_TIMEOUT`.
func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await physics_frame
	return true


## The text of file `path` once it exists, or null after `STEP_TIMEOUT`.
func _wait_text(path: String) -> Variant:
	if not await _until(func() -> bool: return FileAccess.file_exists(path)):
		return null
	return FileAccess.get_file_as_string(path)


func _marker(s: int) -> String:
	return BASE.path_join("host_ready_%d" % s)


func _result(role: String, s: int, m: int) -> String:
	return BASE.path_join("%s_%d_%d.txt" % [role, s, m])


## Written under a temporary name and renamed, so the other process never
## reads a partial file.
func _write_text(path: String, text: String) -> void:
	_write_bytes(path, text.to_utf8_buffer())


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	DirAccess.rename_absolute(temp, path)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
