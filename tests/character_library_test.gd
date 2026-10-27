extends SceneTree
## Headless test for `CharacterLibrary`: importing (valid, invalid, repeated)
## into a temporary library under `user://`. Exits 0 when all checks pass, 1
## otherwise.
##
##   godot --headless --path . -s tests/character_library_test.gd

const WORK := "user://character_library_test"

var _failures := 0


func _initialize() -> void:
	_remove_tree(ProjectSettings.globalize_path(WORK))
	CharacterLibrary.dir = WORK.path_join("library")
	CharacterLibrary.settings_path = WORK.path_join("settings.cfg")
	_test_import()
	_test_reimport()
	_test_choice()
	_remove_tree(ProjectSettings.globalize_path(WORK))
	print("FAIL (%d)" % _failures if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _test_import() -> void:
	var default_bytes := FileAccess.get_file_as_bytes(CharacterLoader.DEFAULT_CHARACTER)
	var glb := ProjectSettings.globalize_path(WORK.path_join("kit/big_tony.glb"))
	_store(glb, default_bytes)

	# Invalid file: errors, nothing stored.
	var junk := ProjectSettings.globalize_path(WORK.path_join("kit/junk.glb"))
	_store(junk, "not a model".to_utf8_buffer())
	var rejected := CharacterLibrary.import_file(junk)
	_check(not rejected.errors.is_empty(), "invalid: errors")
	_check(not rejected.added and rejected.id == "", "invalid: not added")
	_check(CharacterLibrary.entries().is_empty(), "invalid: library empty")

	# No manifest: the name is the file name.
	var result := CharacterLibrary.import_file(glb)
	var id := CharacterLibrary.sha256(default_bytes)
	_check_eq(result.errors, PackedStringArray(), "import: no errors")
	_check_eq(result.id, id, "import: id is the sha256 of the bytes")
	_check(result.added, "import: added")
	_check_eq(FileAccess.get_file_as_bytes(CharacterLibrary.glb_path(id)), default_bytes, "import: bytes copied")
	var info := CharacterLibrary.entry(id)
	_check_eq(info.name, "big_tony", "import: name from file name")
	_check_eq(info.source, glb, "import: source path")
	_check(Time.get_unix_time_from_datetime_string(info.imported) > 0, "import: import time")

	# Same bytes again, now with a manifest: nothing changes.
	_store(glb.get_basename() + ".json", JSON.stringify({"name": "Big ```Tony```\n"}).to_utf8_buffer())
	var again := CharacterLibrary.import_file(glb)
	_check(again.errors.is_empty() and again.id == id and not again.added, "re-import same bytes: no-op")
	_check_eq(CharacterLibrary.entry(id), info, "re-import same bytes: entry unchanged")
	_check_eq(CharacterLibrary.manifest_name(glb), "Big '''Tony'''", "manifest name: cleaned")
	_check_eq(CharacterLibrary.entries().size(), 1, "entries: one")


# Runs after `_test_import`: the library holds `kit/big_tony.glb`.
func _test_reimport() -> void:
	var glb := ProjectSettings.globalize_path(WORK.path_join("kit/big_tony.glb"))
	var old_id := CharacterLibrary.sha256(FileAccess.get_file_as_bytes(glb))
	var settings := ConfigFile.new()
	settings.set_value(CharacterLibrary.SELECTION_SECTION, "p1", old_id)
	settings.set_value(CharacterLibrary.SELECTION_SECTION, "other", "x")
	settings.save(CharacterLibrary.settings_path)

	var same := CharacterLibrary.reimport(old_id)
	_check(same.errors.is_empty() and same.id == old_id and CharacterLibrary.has(old_id), "reimport unchanged: same entry")

	# The agent exports again: different bytes, still valid.
	var changed := _padded(FileAccess.get_file_as_bytes(glb))
	_store(glb, changed)
	var result := CharacterLibrary.reimport(old_id)
	var new_id := CharacterLibrary.sha256(changed)
	_check_eq(result.errors, PackedStringArray(), "reimport changed: no errors")
	_check_eq(result.id, new_id, "reimport changed: new id")
	_check(not CharacterLibrary.has(old_id), "reimport changed: old entry removed")
	_check_eq(CharacterLibrary.entries().map(func(e: Dictionary) -> String: return e.id), [new_id],
			"reimport changed: replaced")
	_check_eq(CharacterLibrary.entry(new_id).name, "Big '''Tony'''", "reimport changed: name from manifest")
	settings.load(CharacterLibrary.settings_path)
	_check_eq(settings.get_value(CharacterLibrary.SELECTION_SECTION, "p1"), new_id, "reimport changed: selection follows")
	_check_eq(settings.get_value(CharacterLibrary.SELECTION_SECTION, "other"), "x", "reimport changed: other choices kept")

	# Source gone or broken: errors, the entry stays.
	_store(glb, "broken".to_utf8_buffer())
	var broken := CharacterLibrary.reimport(new_id)
	_check(not broken.errors.is_empty() and CharacterLibrary.has(new_id), "reimport broken source: entry kept")
	_check(CharacterLibrary.delete(new_id) and CharacterLibrary.entries().is_empty(), "delete: removed")
	_check(not CharacterLibrary.reimport(new_id).errors.is_empty(), "reimport missing entry: error")


func _test_choice() -> void:
	DirAccess.remove_absolute(CharacterLibrary.settings_path)
	var key := CharacterLibrary.PLAYER_CHOICE
	_check_eq(CharacterLibrary.chosen(key), CharacterLibrary.DEFAULT_CHOICE, "choice: default without settings")
	_check_eq(CharacterLibrary.model_path(CharacterLibrary.chosen(key)), CharacterLoader.DEFAULT_CHARACTER,
			"choice: default model")
	var glb := ProjectSettings.globalize_path(WORK.path_join("kit/choice.glb"))
	_store(glb, FileAccess.get_file_as_bytes(CharacterLoader.DEFAULT_CHARACTER))
	var id: String = CharacterLibrary.import_file(glb).id
	CharacterLibrary.choose(key, id)
	_check_eq(CharacterLibrary.chosen(key), id, "choice: saved")
	_check_eq(CharacterLibrary.model_path(id), CharacterLibrary.glb_path(id), "choice: entry model")
	CharacterLibrary.delete(id)
	_check_eq(CharacterLibrary.model_path(id), CharacterLoader.DEFAULT_CHARACTER, "choice: deleted entry → default model")


# The same GLB with its JSON chunk padded by spaces (allowed by the spec):
# different bytes, same model.
func _padded(bytes: PackedByteArray) -> PackedByteArray:
	var json_length := bytes.decode_u32(12)
	var out := bytes.slice(0, 20 + json_length)
	out.append_array(PackedByteArray([32, 32, 32, 32]))
	out.append_array(bytes.slice(20 + json_length))
	out.encode_u32(12, json_length + 4)
	out.encode_u32(8, out.size())
	return out


func _store(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)


func _check_eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s: got %s, expected %s" % [what, actual, expected])
