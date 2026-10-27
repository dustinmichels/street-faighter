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
## `secondary`, `accent`, `base`), `accessories`, `notes`.

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
## What the player does after `hand_off()`; the UI shows it with the folder.
const NEXT_STEP := "Open a terminal in this folder, run `claude`, and paste the prompt."


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


static func _save_dir(dir: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # missing file: start empty
	config.set_value(SETTINGS_SECTION, SETTINGS_DIR_KEY, dir)
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


## The agent's prompt: `PROMPT_TEMPLATE.md` with each `{{key}}` replaced by
## the answer (`{{palette.main}}` for nested keys, arrays joined with ", ",
## `{{slug}}` from the name). Placeholders without an answer get `UNSPECIFIED`.
static func prompt(answers: Dictionary) -> String:
	var template := FileAccess.get_file_as_string(SOURCE_DIR.path_join(PROMPT_TEMPLATE))
	if template.is_empty():
		push_error("CreatorKit: can't read %s: %s" % [PROMPT_TEMPLATE, error_string(FileAccess.get_open_error())])
		return ""
	var values := {"slug": slug(str(answers.get("name", "")))}
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


## Writes the kit into `<dir>/<slug>/`: the kit files, `SKELETON.md`, the
## filled-in `PROMPT.md`, and `character_request.json` (the raw `answers`, so
## the questionnaire can be reopened). Kit files and those two are overwritten
## if the folder exists; the agent's own files there are kept. Returns the
## kit folder, or "" after pushing an error.
static func write(dir: String, answers: Dictionary) -> String:
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
	var text := prompt(answers)
	if text.is_empty():
		return ""
	if not _write_file(folder.path_join(PROMPT_NAME), text.to_utf8_buffer()):
		return ""
	if not _write_file(folder.path_join(REQUEST_NAME), (JSON.stringify(answers, "\t", false) + "\n").to_utf8_buffer()):
		return ""
	return folder


static func _write_file(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("CreatorKit: can't write '%s': %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_buffer(bytes)
	return true
