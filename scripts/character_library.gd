class_name CharacterLibrary
extends RefCounted
## The player's imported characters.
##
## Each entry is a validated copy `<dir>/<sha256>.glb` (the hash of its bytes
## is its id) plus `<sha256>.json`: `name`, `source` (the path it was imported
## from, for "Re-import") and `imported` (UTC, ISO 8601).
##
## Character choices are saved in `settings_path` section `SELECTION_SECTION`,
## valued by entry id (or a `BUILTIN` name), so `reimport()` can retarget them.

## File filter of the "Import…" dialog.
const GLB_FILTER := "*.glb ; glTF binary"
## Settings section holding character choices (any key, entry id as value).
const SELECTION_SECTION := "characters"
## Key of the singleplayer player's choice in `SELECTION_SECTION`.
const PLAYER_CHOICE := "p1"
## Characters that ship with the game: display name (also their choice
## value) → model.
const BUILTIN := { "DEFAULT": CharacterLoader.DEFAULT_CHARACTER }
## Choice used when none was saved.
const DEFAULT_CHOICE := "DEFAULT"
## Settings key (section `ONLINE_SECTION`) of "Show opponents as default
## character" (`opponents_default()`).
const ONLINE_SECTION := "online"
const OPPONENTS_DEFAULT_KEY := "opponents_default"

## Where entries are stored; tests point it elsewhere.
static var dir := "user://characters"
static var settings_path := CreatorKit.SETTINGS_PATH


## The saved choice `key` (an entry id or a `BUILTIN` name), or
## `DEFAULT_CHOICE` if there is none.
static func chosen(key: String) -> String:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return DEFAULT_CHOICE
	var choice := str(config.get_value(SELECTION_SECTION, key, DEFAULT_CHOICE))
	return choice if not choice.is_empty() else DEFAULT_CHOICE


## Saves `choice` (an entry id or a `BUILTIN` name) as choice `key`.
static func choose(key: String, choice: String) -> void:
	var config := ConfigFile.new()
	config.load(settings_path) # missing file: start empty
	config.set_value(SELECTION_SECTION, key, choice)
	var err := config.save(settings_path)
	if err != OK:
		push_error("CharacterLibrary: can't save '%s': %s" % [settings_path, error_string(err)])


## "Show opponents as default character": online, the opponent's custom
## character is neither downloaded (`CharacterSync.fetch()`) nor shown
## (`Session.character_model()`). Off unless saved.
static func opponents_default() -> bool:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return false
	return config.get_value(ONLINE_SECTION, OPPONENTS_DEFAULT_KEY, false) == true


static func set_opponents_default(on: bool) -> void:
	var config := ConfigFile.new()
	config.load(settings_path) # missing file: start empty
	config.set_value(ONLINE_SECTION, OPPONENTS_DEFAULT_KEY, on)
	var err := config.save(settings_path)
	if err != OK:
		push_error("CharacterLibrary: can't save '%s': %s" % [settings_path, error_string(err)])


## Model of `choice`: a built-in's `res://` path or the entry's stored `.glb`.
## A choice that is neither (an entry deleted since) gives the default model.
static func model_path(choice: String) -> String:
	if BUILTIN.has(choice):
		return BUILTIN[choice]
	if has(choice):
		return glb_path(choice)
	return CharacterLoader.DEFAULT_CHARACTER


## How `choice` is named in an online match config (`Session`): a built-in
## as `{"builtin": <BUILTIN name>}`, a library entry by its content as
## `{"sha256": <id>, "name": <entry name>, "size": <bytes>}`. A choice that is
## neither gives the default built-in.
static func descriptor(choice: String) -> Dictionary:
	if has(choice):
		var info := entry(choice)
		var file := FileAccess.open(glb_path(choice), FileAccess.READ)
		if not info.is_empty() and file != null:
			return { "sha256": choice, "name": info.name, "size": file.get_length() }
	return { "builtin": choice if BUILTIN.has(choice) else DEFAULT_CHOICE }


## The sha256 of a `descriptor()` naming a custom character, or "" if it is
## a built-in or malformed (it comes from the other player). A custom
## descriptor also needs a `size` within `CharacterValidator.MAX_FILE_BYTES`.
static func descriptor_sha256(desc: Variant) -> String:
	if not desc is Dictionary or not desc.has("sha256"):
		return ""
	var id: Variant = desc["sha256"]
	var size: Variant = desc.get("size")
	if (
			not id is String or not is_sha256(id) or not size is int \
				or size <= 0
		or size > CharacterValidator.MAX_FILE_BYTES
	):
		return ""
	return id


## The model this machine has for `desc` (a `descriptor()`, possibly the
## other player's): a built-in's `res://` path, a library entry or a cached
## download (`remote_path()`); "" for a custom character not on this machine.
## Malformed descriptors and unknown built-ins give the default model.
static func descriptor_model(desc: Variant) -> String:
	var id := descriptor_sha256(desc)
	if id.is_empty():
		var name: Variant = desc.get("builtin") if desc is Dictionary else null
		return BUILTIN.get(name, CharacterLoader.DEFAULT_CHARACTER) if name is String else CharacterLoader.DEFAULT_CHARACTER
	if has(id):
		return glb_path(id)
	if FileAccess.file_exists(remote_path(id)):
		return remote_path(id)
	return ""


## `desc` (the other player's `descriptor()`) with only the known keys:
## a valid custom descriptor keeps `sha256`, `size` and its `name` (cleaned
## like a questionnaire answer); anything else becomes a built-in, the default
## one unless it names a `BUILTIN`.
static func clean_descriptor(desc: Variant) -> Dictionary:
	var id := descriptor_sha256(desc)
	if not id.is_empty():
		return {
			"sha256": id,
			"name": CreatorKit.clean_text(str(desc.get("name", "")), CreatorKit.max_length("name")),
			"size": desc.size,
		}
	var name: Variant = desc.get("builtin") if desc is Dictionary else null
	return { "builtin": name if name is String and BUILTIN.has(name) else DEFAULT_CHOICE }


## Where a character downloaded from another player is cached, by its
## sha256 (`dir/remote/`, not listed in the library).
static func remote_path(id: String) -> String:
	return dir.path_join("remote").path_join(id + ".glb")


## True if `text` is a lower-case hex SHA-256 (an entry id).
static func is_sha256(text: String) -> bool:
	return text.length() == 64 and RegEx.create_from_string("^[0-9a-f]{64}$").search(text) != null


## Validates the `.glb` at `path` and, if it is a usable character, adds it to
## the library. The name comes from the agent's manifest next to it
## (`<file>.json`, key `name`), else the file name. Importing bytes that are
## already in the library changes nothing. Returns:
##   `errors`: the validator's problems (empty on success),
##   `warnings`: the validator's warnings,
##   `id`: the entry's sha256 ("" on errors),
##   `added`: false if it was invalid or already in the library.
static func import_file(path: String) -> Dictionary:
	var result := {
		"errors": PackedStringArray(),
		"warnings": PackedStringArray(),
		"id": "",
		"added": false,
	}
	var validator := CharacterValidator.new()
	result.errors = validator.validate(path)
	result.warnings = validator.warnings
	if validator.scene != null:
		validator.scene.free()
	if not result.errors.is_empty():
		return result
	var id := sha256(validator.file_bytes)
	result.id = id
	if has(id):
		return result
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		result.errors.append(
			"Can't create the library folder '%s': %s"
			% [ProjectSettings.globalize_path(dir), error_string(err)]
		)
		return result
	var info := {
		"name": manifest_name(path),
		"source": path,
		"imported": Time.get_datetime_string_from_system(true) + "Z",
	}
	# The .json goes last: an entry without it isn't listed.
	if not _write(glb_path(id), validator.file_bytes) \
			or not _write(_info_path(id), (JSON.stringify(info, "\t") + "\n").to_utf8_buffer()):
		DirAccess.remove_absolute(glb_path(id))
		result.errors.append(
			"Can't save the character to '%s'" % ProjectSettings.globalize_path(dir)
		)
		return result
	result.added = true
	return result


## Imports entry `id` again from its `source` path (the edit → export →
## import loop). If the file changed, the new entry replaces `id`, and saved
## choices of `id` (`SELECTION_SECTION`) move to it. Returns as
## `import_file()`; on errors the old entry stays.
static func reimport(id: String) -> Dictionary:
	var info := entry(id)
	if info.is_empty():
		return {
			"errors": PackedStringArray(["Character %s is not in the library" % id]),
			"warnings": PackedStringArray(),
			"id": "",
			"added": false,
		}
	var result := import_file(info.source)
	if result.errors.is_empty() and result.id != id:
		delete(id)
		_retarget_selections(id, result.id)
	return result


## Removes entry `id` (both files). Returns false if it wasn't there.
static func delete(id: String) -> bool:
	if not has(id):
		return false
	DirAccess.remove_absolute(_info_path(id))
	DirAccess.remove_absolute(glb_path(id))
	return true


## True if an entry with this id is in the library.
static func has(id: String) -> bool:
	return FileAccess.file_exists(glb_path(id)) and FileAccess.file_exists(_info_path(id))


## The stored model of entry `id`.
static func glb_path(id: String) -> String:
	return dir.path_join(id + ".glb")


## The entry's info (`name`, `source`, `imported`, plus `id`), or {} if missing.
static func entry(id: String) -> Dictionary:
	if not has(id):
		return { }
	var info: Variant = _parse_json(_info_path(id))
	if not info is Dictionary:
		return { }
	info.id = id
	info.name = str(info.get("name", id))
	info.source = str(info.get("source", ""))
	return info


## Every entry, sorted by name (then import time).
static func entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return found
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "json":
			var info := entry(file.get_basename())
			if not info.is_empty():
				found.append(info)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.name.naturalnocasecmp_to(b.name) != 0:
				return a.name.naturalnocasecmp_to(b.name) < 0
			return str(a.get("imported", "")) < str(b.get("imported", "")),
	)
	return found


## Display name for the `.glb` at `path`: `name` from the agent's manifest
## `<same name>.json` next to it, cleaned like a questionnaire answer, or the
## file name without extension.
static func manifest_name(path: String) -> String:
	var manifest: Variant = _parse_json(path.get_basename() + ".json")
	if manifest is Dictionary:
		var name := CreatorKit.clean_text(
			str(manifest.get("name", "")),
			CreatorKit.max_length("name"),
		)
		if not name.is_empty():
			return name
	return CreatorKit.clean_text(path.get_file().get_basename(), CreatorKit.max_length("name"))


## Lower-case hex SHA-256 of `bytes`.
static func sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Opens a native file picker for one `.glb` under `parent`, starting in the
## last kit folder (`CreatorKit.last_kit_dir()`). On confirm, calls
## `on_chosen(path)`; cancelling does nothing. The dialog frees itself when
## closed.
static func choose_glb(parent: Node, on_chosen: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray([GLB_FILTER])
	dialog.title = "Import a character (.glb)"
	var start := CreatorKit.last_kit_dir()
	dialog.current_dir = start if DirAccess.dir_exists_absolute(start) else start.get_base_dir()
	dialog.file_selected.connect(
		func(path: String) -> void:
			dialog.queue_free()
			on_chosen.call(path),
	)
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	dialog.popup_centered()
	return dialog


## The first `.glb` among dropped `files`, or "".
static func first_glb(files: PackedStringArray) -> String:
	for file in files:
		if file.get_extension().to_lower() == "glb":
			return file
	return ""


# The parsed JSON file at `path`, or null if it is missing or invalid (quietly:
# a broken manifest only means falling back to the file name).
static func _parse_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	return json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null


# Points every saved choice of entry `old` at `new`.
static func _retarget_selections(old: String, new: String) -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK or not config.has_section(SELECTION_SECTION):
		return
	var changed := false
	for key in config.get_section_keys(SELECTION_SECTION):
		if str(config.get_value(SELECTION_SECTION, key)) == old:
			config.set_value(SELECTION_SECTION, key, new)
			changed = true
	if changed:
		var err := config.save(settings_path)
		if err != OK:
			push_error("CharacterLibrary: can't save '%s': %s" % [settings_path, error_string(err)])


static func _info_path(id: String) -> String:
	return dir.path_join(id + ".json")


static func _write(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error(
			"CharacterLibrary: can't write '%s': %s"
			% [path, error_string(FileAccess.get_open_error())]
		)
		return false
	file.store_buffer(bytes)
	return true
