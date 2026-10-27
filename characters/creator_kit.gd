class_name CreatorKit
extends RefCounted
## Writes a creator kit: the folder a player's AI agent works in to build one
## custom character in Blender. The kit
## sources are bundled in `res://creator_kit/` (`export_presets.cfg`
## `include_filter`), so a kit always matches the game version and needs no
## internet.
##
## Answers are the questionnaire's raw values, JSON-compatible (strings, and
## `palette` as a dictionary of `#rrggbb` strings). Keys used by
## `PROMPT_TEMPLATE.md`: `name`, `concept`, `archetype`, `build`, `palette`
## (`main`, `secondary`, `accent`, `base`), `notes`. `prompt()` and `write()`
## pass them through `sanitize()` first.

const SOURCE_DIR := "res://creator_kit"
## Filled in by `prompt()`; not copied into the kit.
const PROMPT_TEMPLATE := "PROMPT_TEMPLATE.md"
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
## The kit folder `write()` last produced (`last_kit()`).
const SETTINGS_LAST_KIT_KEY := "last_kit"
## The agent the player runs in the kit (`agent()`, an `AGENTS` key).
const SETTINGS_AGENT_KEY := "agent"
## What `agent_command()` asks the agent to do first.
const AGENT_REQUEST := "Read PROMPT.md and follow it."
## Agents `agent_command()` can start: id → `name` (for the UI) and `run`,
## the CLI starting an interactive session on a first prompt (`%s`). `other`
## has no `run`: the player starts their own agent in the kit folder.
const AGENTS := {
	"claude": { "name": "Claude Code", "run": "claude %s" },
	"codex": { "name": "Codex", "run": "codex %s" },
	"gemini": { "name": "Gemini CLI", "run": "gemini -i %s" },
	"antigravity": { "name": "Antigravity", "run": "agy -i %s" },
	"pi": { "name": "Pi", "run": "pi %s" },
	"omp": { "name": "Oh My Pi", "run": "omp %s" },
	"other": { "name": "Other agent", "run": "" },
}
const DEFAULT_AGENT := "claude"
## Shells the kit writes commands for. Windows' terminal opens PowerShell (5.1,
## which has no `&&`); macOS, Linux, and Git Bash on Windows run POSIX shells.
enum Shell {
	POSIX,
	POWERSHELL,
}
## `prompt()` placeholders that depend on the player's platform:
## `OS.get_name()` → placeholder → value. Other platforms use `Linux`'s. Paths
## use `/`, which Git Bash and PowerShell both accept.
const PLATFORM_VALUES := {
	"macOS": {
		"blender_locations": "`blender` on the PATH, then `/Applications/Blender.app/Contents/MacOS/Blender`",
		"venv_create": "python3.13 -m venv .venv",
		"venv_python": ".venv/bin/python",
	},
	"Windows": {
		"blender_locations": "`blender` on the PATH, then the newest "
		+ "`C:/Program Files/Blender Foundation/Blender <version>/blender.exe`",
		"venv_create": "py -3.13 -m venv .venv",
		"venv_python": ".venv/Scripts/python",
	},
	"Linux": {
		"blender_locations": "`blender` on the PATH, then `flatpak run org.blender.Blender`, "
		+ "then `snap run blender`",
		"venv_create": "python3.13 -m venv .venv",
		"venv_python": ".venv/bin/python",
	},
}
## Text answers, each one line in the prompt's design brief.
const TEXT_KEYS := ["name", "concept", "archetype", "build", "notes"]
const PALETTE_KEYS := ["main", "secondary", "accent", "base"]
## Longest kept text answer, in characters (`max_length()`): `MAX_LENGTHS`,
## or `MAX_TEXT` for other keys.
const MAX_LENGTHS := { "name": 32, "concept": 160, "notes": 400 }
const MAX_TEXT := 80
## User argument that makes the game validate a `.glb` and quit instead of
## starting (§4): `<game> --headless -- --validate-character <file.glb>`.
const VALIDATE_ARG := "--validate-character"
## Lower-case Latin letters `slug()` replaces with plain ASCII: ASCII → the
## letters written that way ("é" → "e", "ß" → "ss").
const ASCII_FOLDS := {
	"a": "àáâãäåāăą",
	"c": "çćĉċč",
	"d": "ðďđ",
	"e": "èéêëēĕėęě",
	"g": "ĝğġģ",
	"h": "ĥħ",
	"i": "ìíîïĩīĭįı",
	"j": "ĵ",
	"k": "ķ",
	"l": "ĺļľŀł",
	"n": "ñńņňŉ",
	"o": "òóôõöøōŏő",
	"r": "ŕŗř",
	"s": "śŝşšș",
	"t": "ţťŧț",
	"u": "ùúûüũūŭůűų",
	"w": "ŵ",
	"y": "ýÿŷ",
	"z": "źżž",
	"ae": "æ",
	"oe": "œ",
	"ss": "ß",
	"th": "þ",
}


## One line to paste into a `shell` terminal (the player's, by default): enters
## the kit `folder` and starts `agent_id` (an `AGENTS` key) on `AGENT_REQUEST`;
## for `other`, only enters the folder. The agent starts only if `cd` worked:
## `&&` in POSIX shells; in PowerShell, `cd` stops the line on an error.
static func agent_command(
	folder: String,
	agent_id: String,
	shell: Shell = terminal_shell(),
) -> String:
	var run: String = AGENTS.get(agent_id, AGENTS[DEFAULT_AGENT]).run
	var cd := "cd %s" % shell_quote(folder, shell)
	var separator := " && "
	if shell == Shell.POWERSHELL:
		# -LiteralPath: `[` and `]` in the folder aren't wildcards.
		cd = "cd -LiteralPath %s -ErrorAction Stop" % shell_quote(folder, shell)
		separator = "; "
	if run.is_empty():
		return cd
	return cd + separator + run % shell_quote(AGENT_REQUEST, shell)


## The shell a player on `platform` (an `OS.get_name()`) pastes
## `agent_command()` into.
static func terminal_shell(platform: String = OS.get_name()) -> Shell:
	return Shell.POWERSHELL if platform == "Windows" else Shell.POSIX


## The agent the player last picked (`set_agent()`), or `DEFAULT_AGENT`.
static func agent() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var id: Variant = config.get_value(SETTINGS_SECTION, SETTINGS_AGENT_KEY, DEFAULT_AGENT)
		if id is String and AGENTS.has(id):
			return id
	return DEFAULT_AGENT


static func set_agent(agent_id: String) -> void:
	_save_setting(SETTINGS_AGENT_KEY, agent_id)


## Where the agent exports the character of the kit `folder`: `<slug>.glb`
## in it (`write()` names the folder after the slug).
static func kit_glb(folder: String) -> String:
	return folder.path_join(folder.get_file() + ".glb")


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
	dialog.dir_selected.connect(
		func(dir: String) -> void:
			dialog.queue_free()
			_save_dir(dir)
			on_chosen.call(dir),
	)
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	dialog.popup_centered()
	return dialog


## The kit folder `write()` last produced, or "" if there is none or it was
## removed.
static func last_kit() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var dir: String = config.get_value(SETTINGS_SECTION, SETTINGS_LAST_KIT_KEY, "")
		if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
			return dir
	return ""


## `last_kit()`, where the agent exports its `.glb` (the "Import…" dialog
## starts there), or `saved_dir()` if there is none.
static func last_kit_dir() -> String:
	var kit := last_kit()
	return kit if not kit.is_empty() else saved_dir()


static func _save_dir(dir: String) -> void:
	_save_setting(SETTINGS_DIR_KEY, dir)


static func _save_setting(key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH) # missing file: start empty
	config.set_value(SETTINGS_SECTION, key, value)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_error("CreatorKit: can't save '%s': %s" % [SETTINGS_PATH, error_string(err)])


## File-system-safe name from the character's name: lower-case ASCII letters
## and digits, accented Latin letters as plain ones (`ASCII_FOLDS`; combining
## accents dropped), other runs of characters become one `_`. Also the `.glb`
## name.
static func slug(name: String) -> String:
	var out := ""
	for c in name.to_lower():
		var code := c.unicode_at(0)
		if code >= 0x300 and code <= 0x36f: # combining accent ("e" + U+0301)
			continue
		for plain: String in ASCII_FOLDS:
			if ASCII_FOLDS[plain].contains(c):
				c = plain
				code = c.unicode_at(0)
				break
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
## (`clean_text()`) and capped at `max_length()`; palette colors that aren't
## `#rrggbb` dropped.
## Missing or dropped answers show as `UNSPECIFIED` in the prompt.
static func sanitize(answers: Dictionary) -> Dictionary:
	var out := { }
	for key: String in TEXT_KEYS:
		if answers.has(key):
			out[key] = clean_text(str(answers[key]), max_length(key))
	var palette: Variant = answers.get("palette")
	if palette is Dictionary:
		var colors := { }
		var hex := RegEx.create_from_string("^#?([0-9a-fA-F]{6})$")
		for key: String in PALETTE_KEYS:
			var m := hex.search(str(palette.get(key, "")).strip_edges())
			if m != null:
				colors[key] = "#" + m.get_string(1).to_lower()
		out["palette"] = colors
	return out


## One line of player text that can't change the prompt's structure: control,
## line-separator and invisible format characters become spaces, backticks
## (Markdown code spans and fences) become `'`, runs of spaces collapse, and
## the result is trimmed and cut to `limit` characters.
static func clean_text(text: String, limit: int) -> String:
	var out := ""
	for c in text:
		var code := c.unicode_at(0)
		if (
			code < 0x20 or (code >= 0x7f and code <= 0x9f) or (code >= 0x200b and code <= 0x200f) \
					or (code >= 0x2028 and code <= 0x202e)
			or (code >= 0x2060 and code <= 0x206f) or code == 0xfeff
		):
			out += " "
		elif c == "`":
			out += "'"
		else:
			out += c
	out = RegEx.create_from_string(" {2,}").sub(out, " ", true).strip_edges()
	return out.left(limit).strip_edges()


## The agent's prompt for a kit in `<dir>/<slug>/`: `PROMPT_TEMPLATE.md` with
## each `{{key}}` replaced by the answer (`{{palette.main}}` for nested keys,
## `{{slug}}` from the name, `{{validator_commands}}` from
## `validator_commands()` for the kit's `.glb`, and `PLATFORM_VALUES` for
## `platform`, an `OS.get_name()`),
## after `sanitize()`. Placeholders without an answer get `UNSPECIFIED`.
static func prompt(
	answers: Dictionary,
	dir: String = saved_dir(),
	platform: String = OS.get_name(),
) -> String:
	var template := FileAccess.get_file_as_string(SOURCE_DIR.path_join(PROMPT_TEMPLATE))
	if template.is_empty():
		push_error(
			"CreatorKit: can't read %s: %s"
			% [PROMPT_TEMPLATE, error_string(FileAccess.get_open_error())]
		)
		return ""
	answers = sanitize(answers)
	var character := slug(str(answers.get("name", "")))
	var values: Dictionary = PLATFORM_VALUES.get(platform, PLATFORM_VALUES.Linux).duplicate()
	values.slug = character
	values.validator_commands = validator_commands(kit_glb(dir.path_join(character)), platform)
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
	else:
		into[key] = str(value)


## Markdown for `prompt()`: `validator_command()` in a code block. On Windows,
## where an agent's shell is Git Bash (Claude Code) or PowerShell, one block
## for each.
static func validator_commands(glb_path: String, platform: String = OS.get_name()) -> String:
	var posix := "```sh\n%s\n```" % validator_command(glb_path)
	if terminal_shell(platform) == Shell.POSIX:
		return posix
	return "In bash (Git Bash):\n\n%s\n\nIn PowerShell:\n\n```powershell\n%s\n```" % [
		posix,
		validator_command(glb_path, Shell.POWERSHELL),
	]


## `shell` command that runs this game binary headless on `glb_path`
## (absolute, since `--path` changes the working directory) and prints the
## validator's problems or `OK`. Run from the editor, the binary is the editor,
## so the project is added with `--path`. PowerShell runs a quoted path only
## with `&`, and waits for a GUI-subsystem program (the Windows game) only if
## its output is piped.
static func validator_command(glb_path: String, shell: Shell = Shell.POSIX) -> String:
	var args := [OS.get_executable_path(), "--headless"]
	if OS.has_feature("editor"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	args += ["--", VALIDATE_ARG, glb_path]
	var command := " ".join(PackedStringArray(args.map(shell_quote.bind(shell))))
	if shell == Shell.POWERSHELL:
		return "& %s | Write-Output" % command
	return command


## `arg` as one `shell` word. POSIX: unchanged if it only has safe characters,
## else in single quotes (`'` written as `'\''`). PowerShell: always in single
## quotes (no `-param`, `--`, `@splat`, or `$var` parsing), with each quote
## character doubled; PowerShell also ends a string at the curly ones.
static func shell_quote(arg: String, shell: Shell = Shell.POSIX) -> String:
	if shell == Shell.POWERSHELL:
		return "'%s'" % RegEx.create_from_string("(['\u2018\u2019\u201a\u201b])").sub(
			arg,
			"$1$1",
			true,
		)
	if not arg.is_empty() and RegEx.create_from_string("^[\\w@%+=:,./-]+$").search(arg) != null:
		return arg
	return "'%s'" % arg.replace("'", "'\\''")


## Writes the kit into `<dir>/<slug>/`: the kit files (`SKELETON.md` among them), the
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
	for file in DirAccess.get_files_at(SOURCE_DIR):
		if file == PROMPT_TEMPLATE:
			continue
		var source := SOURCE_DIR.path_join(file)
		var bytes := FileAccess.get_file_as_bytes(source)
		if bytes.is_empty():
			push_error(
				"CreatorKit: can't read '%s': %s"
				% [source, error_string(FileAccess.get_open_error())]
			)
			return ""
		if not _write_file(folder.path_join(file), bytes):
			return ""
	var text := prompt(answers, dir)
	if text.is_empty():
		return ""
	if not _write_file(folder.path_join(PROMPT_NAME), text.to_utf8_buffer()):
		return ""
	if not _write_file(
		folder.path_join(REQUEST_NAME),
		(JSON.stringify(answers, "\t", false) + "\n").to_utf8_buffer(),
	):
		return ""
	_save_setting(SETTINGS_LAST_KIT_KEY, folder)
	return folder


static func _write_file(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error(
			"CreatorKit: can't write '%s': %s" % [path, error_string(FileAccess.get_open_error())]
		)
		return false
	file.store_buffer(bytes)
	return true
