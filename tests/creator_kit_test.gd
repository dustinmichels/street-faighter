extends SceneTree
## Headless test for `CreatorKit`: slugs, prompt filling, and writing a kit
## folder (into a temporary directory under `user://`). Exits 0 when all
## checks pass, 1 otherwise.
##
##   godot --headless --path . -s tests/creator_kit_test.gd

var _failures := 0


func _initialize() -> void:
	_test_slug()
	_test_prompt()
	_test_write()
	print("FAIL (%d)" % _failures if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _test_slug() -> void:
	_check_eq(CreatorKit.slug("Big Tony"), "big_tony", "slug: spaces")
	_check_eq(CreatorKit.slug("  --R2-D2!!  "), "r2_d2", "slug: punctuation runs, trimmed")
	_check_eq(CreatorKit.slug("../../etc"), "etc", "slug: no path traversal")
	_check_eq(CreatorKit.slug("☃☃"), "character", "slug: nothing usable")


func _test_prompt() -> void:
	var text := CreatorKit.prompt({
		"name": "Big Tony",
		"palette": {"main": "#c02a20"},
		"accessories": ["belt", "scarf"],
		"concept": "   ",
	})
	_check(text.contains("Name: Big Tony"), "prompt: name filled")
	_check(text.contains("main #c02a20, secondary %s" % CreatorKit.UNSPECIFIED), "prompt: nested key, missing nested key")
	_check(text.contains("Accessories: belt, scarf"), "prompt: array joined")
	_check(text.contains("Concept: %s" % CreatorKit.UNSPECIFIED), "prompt: blank answer")
	_check(text.contains("`big_tony.glb`"), "prompt: slug")
	_check(not text.contains("{{"), "prompt: no placeholder left")


func _test_write() -> void:
	var dir := ProjectSettings.globalize_path("user://creator_kit_test")
	_remove_tree(dir)
	var answers := {"name": "Big Tony", "palette": {"main": "#c02a20"}, "accessories": ["belt"]}
	var folder := CreatorKit.write(dir, answers)
	_check_eq(folder, dir.path_join("big_tony"), "write: returns <dir>/<slug>")
	var expected := ["BPY_NOTES.md", "PROMPT.md", "README.md", "SKELETON.md", "build_template.py",
			"character_request.json", "example_build_character.py", "export_glb.py"]
	_check_eq(Array(DirAccess.get_files_at(folder)), expected, "write: kit files")
	_check_eq(FileAccess.get_file_as_string(folder.path_join("SKELETON.md")),
			FileAccess.get_file_as_string("res://docs/skeleton.md"), "write: SKELETON.md is docs/skeleton.md")
	_check_eq(FileAccess.get_file_as_string(folder.path_join("PROMPT.md")), CreatorKit.prompt(answers), "write: PROMPT.md")
	_check_eq(JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("character_request.json"))),
			answers, "write: request round-trips")

	# Saving again (edited answers) updates the kit and keeps the agent's files.
	var agent_file := folder.path_join("build_character.py")
	FileAccess.open(agent_file, FileAccess.WRITE).store_string("# agent's script\n")
	answers["concept"] = "a retired sumo wrestler"
	_check_eq(CreatorKit.write(dir, answers), folder, "rewrite: same folder")
	_check_eq(FileAccess.get_file_as_string(agent_file), "# agent's script\n", "rewrite: agent's file kept")
	_check(FileAccess.get_file_as_string(folder.path_join("PROMPT.md")).contains("a retired sumo wrestler"),
			"rewrite: PROMPT.md updated")
	_remove_tree(dir)


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
