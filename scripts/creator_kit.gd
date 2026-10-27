class_name CreatorKit
extends RefCounted
## Writes a creator kit: the folder a player's AI agent works in to build one
## custom character in Blender (`docs/todo/custom-characters.md` §1). The kit
## sources are bundled in `res://creator_kit/` (`export_presets.cfg`
## `include_filter`), so a kit always matches the game version and needs no
## internet.
##
## Answers are the questionnaire's raw values, JSON-compatible (strings,
## arrays of strings, and `palette` as a dictionary of `#rrggbb` strings).
## Keys used by `PROMPT_TEMPLATE.md`: `name`, `concept`, `archetype`, `build`,
## `head`, `headwear`, `top`, `bottom`, `footwear`, `palette` (`main`,
## `secondary`, `accent`, `base`), `accessories`, `notes`. `prompt()` and
## `write()` pass them through `sanitize()` first.

const SOURCE_DIR := "res://creator_kit"
## Filled in by `prompt()`; not copied into the kit.
const PROMPT_TEMPLATE := "PROMPT_TEMPLATE.md"
## The single skeleton reference, copied into the kit under its kit name.
const SKELETON_SOURCE := "res://docs/skeleton.md"
const SKELETON_NAME := "SKELETON.md"
const PROMPT_NAME := "PROMPT.md"
const REQUEST_NAME := "character_request.json"
## Folder for kits under the player's Documents folder (`default_dir()`).
const DEFAULT_DIR_NAME := "street-fAIghter characters"
## Shown for a placeholder without an answer.
const UNSPECIFIED := "(not specified)"
## Where the folder the player last picked is remembered.
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "creator_kit"
const SETTINGS_DIR_KEY := "dir"
## The kit folder `write()` last produced (`last_kit_dir()`).
const SETTINGS_LAST_KIT_KEY := "last_kit"
## What the player does after `hand_off()`; the UI shows it with the folder.
const NEXT_STEP := "Open a terminal in this folder, run `claude`, and paste the prompt."
## Text answers, each one line in the prompt's design brief.
const TEXT_KEYS := ["name", "concept", "archetype", "build", "head", "headwear", "top", "bottom",
		"footwear", "notes"]
const PALETTE_KEYS := ["main", "secondary", "accent", "base"]
## Longest kept text answer, in characters (`max_length()`): `MAX_LENGTHS`,
## or `MAX_TEXT` for other keys and each accessory.
const MAX_LENGTHS := {"name": 32, "concept": 160, "notes": 400}
const MAX_TEXT := 80
const MAX_ACCESSORIES := 16
## User argument that makes the game validate a `.glb` and quit instead of
## starting (§4): `<game> --headless -- --validate-character <file.glb>`.
const VALIDATE_ARG := "--validate-character"


## Run after `write()`: copies the kit's `PROMPT.md` to the clipboard and opens
## `folder` in the file manager. Returns the text for the UI to show: the
## folder and `NEXT_STEP`.
static func hand_off(folder: String) -> String:
	var text := FileAccess.get_file_as_string(folder.path_join(PROMPT_NAME))
	if text.is_empty():
		push_error("CreatorKit: can't read '%s': %s" % [folder.path_join(PROMPT_NAME), error_string(FileAccess.get_open_error())])
	else:
		DisplayServer.clipboard_set(text)
	var err := OS.shell_show_in_file_manager(folder)
	if err != OK:
		push_error("CreatorKit: can't open '%s': %s" % [folder, error_string(err)])
	return "Kit saved to %s\n%s" % [folder, NEXT_STEP]


## `~/Documents/street-fAIghter characters` (per platform).
static func default_dir() -> String:
	return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join(DEFAULT_DIR_NAME)


## The folder kits are written to: the one last picked with `choose_dir()`,
## or `default_dir()`.
static func saved_dir() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var dir: String = config.get_value(SETTINGS_SECTION, SETTINGS_DIR_KEY, "")
		if not dir.is_empty():
			return dir
	return default_dir()


## Opens a native folder picker under `parent`, starting at `saved_dir()`.
## On confirm, remembers the folder and calls `on_chosen(dir)`; cancelling
## does nothing. The dialog frees itself when closed.
static func choose_dir(parent: Node, on_chosen: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.title = "Folder for character kits"
	var start := saved_dir()
	# The default folder may not exist yet; a missing start folder makes the
	# dialog fall back to an arbitrary one.
	dialog.current_dir = start if DirAccess.dir_exists_absolute(start) else start.get_base_dir()
	dialog.dir_selected.connect(func(dir: String) -> void:
		dialog.queue_free()
		_save_dir(dir)
		on_chosen.call(dir))
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	dialog.popup_centered()
	return dialog


## The kit folder `write()` last produced, where the agent exports its `.glb`
## (the "Import…" dialog starts there), or `saved_dir()` if there is none or
## it was removed.
static func last_kit_dir() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var dir: String = config.get_value(SETTINGS_SECTION, SETTINGS_LAST_KIT_KEY, "")
		if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
			return dir
	return saved_dir()


static func _save_dir(dir: String) -> void:
	_save_setting(SETTINGS_DIR_KEY, dir)


static func _save_setting(key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # missing file: start empty
	config.set_value(SETTINGS_SECTION, key, value)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_error("CreatorKit: can't save '%s': %s" % [SETTINGS_PATH, error_string(err)])


## File-system-safe name from the character's name: lower-case ASCII letters
## and digits, other runs of characters become one `_`. Also the `.glb` name.
static func slug(name: String) -> String:
	var out := ""
	for c in name.to_lower():
		var code := c.unicode_at(0)
		if (code >= 0x61 and code <= 0x7a) or (code >= 0x30 and code <= 0x39):
			out += c
		elif not out.ends_with("_"):
			out += "_"
	out = out.trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "character"


## Longest kept answer for a text key (see `MAX_LENGTHS`).
static func max_length(key: String) -> int:
	return MAX_LENGTHS.get(key, MAX_TEXT)


## The answers as safe template values: only known keys; text on one line
## (`clean_text()`) and capped at `max_length()`; at most `MAX_ACCESSORIES`
## non-empty accessories; palette colors that aren't `#rrggbb` dropped.
## Missing or dropped answers show as `UNSPECIFIED` in the prompt.
static func sanitize(answers: Dictionary) -> Dictionary:
	var out := {}
	for key: String in TEXT_KEYS:
		if answers.has(key):
			out[key] = clean_text(str(answers[key]), max_length(key))
	var palette: Variant = answers.get("palette")
	if palette is Dictionary:
		var colors := {}
		var hex := RegEx.create_from_string("^#?([0-9a-fA-F]{6})$")
		for key: String in PALETTE_KEYS:
			var m := hex.search(str(palette.get(key, "")).strip_edges())
			if m != null:
				colors[key] = "#" + m.get_string(1).to_lower()
		out["palette"] = colors
	var accessories: Variant = answers.get("accessories")
	if accessories is Array or accessories is PackedStringArray:
		var items: Array[String] = []
		for item: Variant in accessories:
			var text := clean_text(str(item), MAX_TEXT)
			if not text.is_empty() and items.size() < MAX_ACCESSORIES:
				items.append(text)
		out["accessories"] = items
	return out


## One line of player text that can't change the prompt's structure: control,
## line-separator and invisible format characters become spaces, backticks
## (Markdown code spans and fences) become `'`, runs of spaces collapse, and
## the result is trimmed and cut to `limit` characters.
static func clean_text(text: String, limit: int) -> String:
	var out := ""
	for c in text:
		var code := c.unicode_at(0)
		if code < 0x20 or (code >= 0x7f and code <= 0x9f) or (code >= 0x200b and code <= 0x200f) \
				or (code >= 0x2028 and code <= 0x202e) or (code >= 0x2060 and code <= 0x206f) or code == 0xfeff:
			out += " "
		elif c == "`":
			out += "'"
		else:
			out += c
	out = RegEx.create_from_string(" {2,}").sub(out, " ", true).strip_edges()
	return out.left(limit).strip_edges()


## The agent's prompt for a kit in `<dir>/<slug>/`: `PROMPT_TEMPLATE.md` with
## each `{{key}}` replaced by the answer (`{{palette.main}}` for nested keys,
## arrays joined with ", ", `{{slug}}` from the name,
## `{{validator_command}}` from `validator_command()` for the kit's `.glb`),
## after `sanitize()`. Placeholders without an answer get `UNSPECIFIED`.
static func prompt(answers: Dictionary, dir: String = saved_dir()) -> String:
	var template := FileAccess.get_file_as_string(SOURCE_DIR.path_join(PROMPT_TEMPLATE))
	if template.is_empty():
		push_error("CreatorKit: can't read %s: %s" % [PROMPT_TEMPLATE, error_string(FileAccess.get_open_error())])
		return ""
	answers = sanitize(answers)
	var character := slug(str(answers.get("name", "")))
	var values := {
		"slug": character,
		"validator_command": validator_command(dir.path_join(character).path_join(character + ".glb")),
	}
	_flatten(answers, "", values)
	var placeholder := RegEx.create_from_string("\\{\\{\\s*([\\w.]+)\\s*\\}\\}")
	var out := ""
	var last := 0
	for m in placeholder.search_all(template):
		var value: String = values.get(m.get_string(1), "")
		out += template.substr(last, m.get_start() - last)
		out += value if not value.strip_edges().is_empty() else UNSPECIFIED
		last = m.get_end()
	return out + template.substr(last)


static func _flatten(value: Variant, key: String, into: Dictionary) -> void:
	if value is Dictionary:
		for k in value:
			_flatten(value[k], "%s.%s" % [key, k] if not key.is_empty() else str(k), into)
	elif value is Array or value is PackedStringArray:
		into[key] = ", ".join(PackedStringArray(Array(value).map(func(v: Variant) -> String: return str(v))))
	else:
		into[key] = str(value)


## Shell command (POSIX `sh`; Claude Code uses Git Bash on Windows) that runs
## this game binary headless on `glb_path` (absolute, since `--path` changes
## the working directory) and prints the validator's problems or `OK`. Run from
## the editor, the binary is the editor, so the project is added with `--path`.
static func validator_command(glb_path: String) -> String:
	var args := [OS.get_executable_path(), "--headless"]
	if OS.has_feature("editor"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	args += ["--", VALIDATE_ARG, glb_path]
	return " ".join(PackedStringArray(args.map(shell_quote)))


## `arg` as one POSIX shell word: unchanged if it only has safe characters,
## else in single quotes (`'` written as `'\''`).
static func shell_quote(arg: String) -> String:
	if not arg.is_empty() and RegEx.create_from_string("^[\\w@%+=:,./-]+$").search(arg) != null:
		return arg
	return "'%s'" % arg.replace("'", "'\\''")


## Writes the kit into `<dir>/<slug>/`: the kit files, `SKELETON.md`, the
## filled-in `PROMPT.md`, and `character_request.json` (the `sanitize()`d
## answers, so the questionnaire can be reopened). Kit files and those two are
## overwritten if the folder exists; the agent's own files there are kept.
## Returns the kit folder, or "" after pushing an error.
static func write(dir: String, answers: Dictionary) -> String:
	answers = sanitize(answers)
	var folder := dir.path_join(slug(str(answers.get("name", ""))))
	var err := DirAccess.make_dir_recursive_absolute(folder)
	if err != OK:
		push_error("CreatorKit: can't create '%s': %s" % [folder, error_string(err)])
		return ""
	var sources := {SKELETON_NAME: SKELETON_SOURCE}
	for file in DirAccess.get_files_at(SOURCE_DIR):
		if file != PROMPT_TEMPLATE:
			sources[file] = SOURCE_DIR.path_join(file)
	for file: String in sources:
		var bytes := FileAccess.get_file_as_bytes(sources[file])
		if bytes.is_empty():
			push_error("CreatorKit: can't read '%s': %s" % [sources[file], error_string(FileAccess.get_open_error())])
			return ""
		if not _write_file(folder.path_join(file), bytes):
			return ""
	var text := prompt(answers, dir)
	if text.is_empty():
		return ""
	if not _write_file(folder.path_join(PROMPT_NAME), text.to_utf8_buffer()):
		return ""
	if not _write_file(folder.path_join(REQUEST_NAME), (JSON.stringify(answers, "\t", false) + "\n").to_utf8_buffer()):
		return ""
	_save_setting(SETTINGS_LAST_KIT_KEY, folder)
	return folder


static func _write_file(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("CreatorKit: can't write '%s': %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_buffer(bytes)
	return true
