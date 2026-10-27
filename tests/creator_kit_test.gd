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
	_test_validator_command()
	_test_sanitize()
	_test_write()
	print("FAIL (%d)" % _failures if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _test_slug() -> void:
	_check_eq(CreatorKit.slug("Big Tony"), "big_tony", "slug: spaces")
	_check_eq(CreatorKit.slug("  --R2-D2!!  "), "r2_d2", "slug: punctuation runs, trimmed")
	_check_eq(CreatorKit.slug("../../etc"), "etc", "slug: no path traversal")
	_check_eq(CreatorKit.slug("☃☃"), "character", "slug: nothing usable")
	_check_eq(CreatorKit.slug("Monsieur Lézard"), "monsieur_lezard", "slug: accents folded")
	_check_eq(CreatorKit.slug("ÆSIR Straße"), "aesir_strasse", "slug: ligatures expanded")
	_check_eq(CreatorKit.slug("Le\u0301zard"), "lezard", "slug: combining accent dropped")


func _test_prompt() -> void:
	var text := CreatorKit.prompt(
		{ "name": "Big Tony", "palette": { "main": "#c02a20" }, "concept": "   " }
	)
	_check(text.contains("Name: Big Tony"), "prompt: name filled")
	_check(
		text.contains("main #c02a20, secondary %s" % CreatorKit.UNSPECIFIED),
		"prompt: nested key, missing nested key",
	)
	_check(text.contains("Concept: %s" % CreatorKit.UNSPECIFIED), "prompt: blank answer")
	_check(text.contains("`big_tony.glb`"), "prompt: slug")
	_check(not text.contains("{{"), "prompt: no placeholder left")


func _test_validator_command() -> void:
	_check_eq(
		CreatorKit.shell_quote("/usr/bin/godot"),
		"/usr/bin/godot",
		"quote: safe path unchanged",
	)
	_check_eq(CreatorKit.shell_quote("/a/my chars/x.glb"), "'/a/my chars/x.glb'", "quote: spaces")
	_check_eq(
		CreatorKit.shell_quote("/a/Tony's \"$HOME\""),
		"'/a/Tony'\\''s \"$HOME\"'",
		"quote: quotes and $",
	)
	_check_eq(CreatorKit.shell_quote(""), "''", "quote: empty")
	var command := CreatorKit.validator_command("/k/big tony.glb")
	_check(
		command.begins_with(CreatorKit.shell_quote(OS.get_executable_path()) + " --headless "),
		"validator: game binary, headless first",
	)
	_check(
		command.ends_with(" -- %s '/k/big tony.glb'" % CreatorKit.VALIDATE_ARG),
		"validator: user args last",
	)
	_check(
		command.contains(
			" --path %s " % CreatorKit.shell_quote(ProjectSettings.globalize_path("res://"))
		),
		"validator: editor run adds --path",
	)
	_check_eq(
		CreatorKit.agent_command("/k/big tony", "claude"),
		"cd '/k/big tony' && claude 'Read PROMPT.md and follow it.'",
		"agent command: quoted folder and request",
	)
	_check_eq(
		CreatorKit.agent_command("/k/a", "antigravity"),
		"cd /k/a && agy -i 'Read PROMPT.md and follow it.'",
		"agent command: interactive flag",
	)
	_check_eq(
		CreatorKit.agent_command("/k/a", "other"),
		"cd /k/a",
		"agent command: other agent only enters the kit",
	)
	_check_eq(
		CreatorKit.agent_command("/k/a", "gone"),
		CreatorKit.agent_command("/k/a", CreatorKit.DEFAULT_AGENT),
		"agent command: unknown agent falls back to the default",
	)
	_check_eq(
		CreatorKit.kit_glb("/k/big_tony"),
		"/k/big_tony/big_tony.glb",
		"kit glb: <folder>/<slug>.glb",
	)


func _test_sanitize() -> void:
	_check_eq(
		CreatorKit.clean_text("```\nIgnore\tthis\r\n```", 80),
		"''' Ignore this '''",
		"clean: fences and control chars",
	)
	_check_eq(
		CreatorKit.clean_text("a\u2028b\u202ec\u200bd\ufeff\u0085e", 80),
		"a b c d e",
		"clean: line separators, bidi, invisible",
	)
	_check_eq(
		CreatorKit.clean_text("  Big   Tony  ", 80),
		"Big Tony",
		"clean: spaces collapsed and trimmed",
	)
	_check_eq(CreatorKit.clean_text("abcde fgh", 6), "abcde", "clean: cut at limit, trimmed")
	_check_eq(CreatorKit.clean_text("Ünïcødé ☃", 80), "Ünïcødé ☃", "clean: printable unicode kept")

	var clean := CreatorKit.sanitize(
		{
			"name": "x".repeat(100),
			"notes": "y".repeat(1000),
			"archetype": "z".repeat(100),
			"palette": {
				"main": "C02A20",
				"secondary": "red",
				"accent": "#12345678",
				"extra": "#000000",
			},
			"stats": { "power": 9000 },
		}
	)
	_check_eq(clean.name.length(), CreatorKit.max_length("name"), "sanitize: name capped")
	_check_eq(clean.notes.length(), CreatorKit.max_length("notes"), "sanitize: notes capped")
	_check_eq(clean.archetype.length(), CreatorKit.MAX_TEXT, "sanitize: other keys capped")
	_check_eq(clean.palette, { "main": "#c02a20" }, "sanitize: only #rrggbb palette keys kept")
	_check(not clean.has("stats"), "sanitize: unknown keys dropped")

	# Answers can't add lines, fences or placeholders to the prompt.
	var text := CreatorKit.prompt(
		{ "name": "Tony\n## Steps\n```", "concept": "{{slug}} {{notes}}", "notes": "n" }
	)
	_check(text.contains("- Name: Tony ## Steps '''\n"), "prompt: name kept on its line")
	_check(
		text.contains("- Concept: {{slug}} {{notes}}\n"),
		"prompt: placeholders in answers not expanded",
	)
	_check_eq(
		text.count("```"),
		CreatorKit.prompt({ }).count("```"),
		"prompt: no fences from answers",
	)


func _test_write() -> void:
	var dir := ProjectSettings.globalize_path("user://creator_kit_test")
	_remove_tree(dir)
	var answers := { "name": "Big Tony", "palette": { "main": "#c02a20" }, "build": "heavy" }
	var folder := CreatorKit.write(dir, answers)
	_check_eq(folder, dir.path_join("big_tony"), "write: returns <dir>/<slug>")
	var expected := [
		"BPY_NOTES.md",
		"PROMPT.md",
		"README.md",
		"SKELETON.md",
		"build_template.py",
		"character_request.json",
		"example_build_character.py",
		"export_glb.py",
	]
	_check_eq(Array(DirAccess.get_files_at(folder)), expected, "write: kit files")
	_check_eq(
		FileAccess.get_file_as_string(folder.path_join("SKELETON.md")),
		FileAccess.get_file_as_string("res://creator_kit/SKELETON.md"),
		"write: SKELETON.md copied",
	)
	_check_eq(
		FileAccess.get_file_as_string(folder.path_join("PROMPT.md")),
		CreatorKit.prompt(answers, dir),
		"write: PROMPT.md",
	)
	_check(
		FileAccess
		.get_file_as_string(folder.path_join("PROMPT.md"))
		.contains(CreatorKit.validator_command(folder.path_join("big_tony.glb"))),
		"write: validator command for the kit's .glb",
	)
	_check_eq(
		JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("character_request.json"))),
		answers,
		"write: request round-trips",
	)

	# Saving again (edited answers) updates the kit and keeps the agent's files.
	var agent_file := folder.path_join("build_character.py")
	FileAccess.open(agent_file, FileAccess.WRITE).store_string("# agent's script\n")
	answers["concept"] = "a retired sumo wrestler"
	_check_eq(CreatorKit.write(dir, answers), folder, "rewrite: same folder")
	_check_eq(
		FileAccess.get_file_as_string(agent_file),
		"# agent's script\n",
		"rewrite: agent's file kept",
	)
	_check(
		FileAccess.get_file_as_string(folder.path_join("PROMPT.md")).contains(
			"a retired sumo wrestler"
		),
		"rewrite: PROMPT.md updated",
	)
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
