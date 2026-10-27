extends SceneTree
## Headless test for `CharacterValidator` and the `--validate-character` CLI:
## `default.glb` and the valid fixture pass, and each broken fixture from
## `tests/fixtures/build_bad_characters.py` fails with exactly its expected
## errors. The CLI (exit code, printed errors) is checked on one passing and
## one failing file. Exits 0 when all checks pass, 1 otherwise.
##
##   godot --headless --path . -s tests/character_validator_test.gd

const FIXTURES := "res://tests/fixtures"
const _EDIT := "don't edit bones, rebuild from template.blend"
const _ARMATURE := "The Armature object is moved, rotated, or scaled; keep it at the origin with no rotation and scale 1"
const _OPAQUE := "(fighters must be fully opaque)"

## Fixture name -> the complete list of errors it must produce, in order.
const EXPECTED := {
	"missing_bone": ["Bone 'hand.L' missing"],
	"renamed_bone": ["Bone 'hand.L' missing (found 'hand.L.001')"],
	"part_named_like_bone": ["Part 'head' has the same name as a bone; rename it to 'head_part'"],
	"extra_bone": [
		"Extra bone 'tail'; delete it (the skeleton must have exactly the 17 template bones)"
	],
	"moved_joint": [
		"Bone 'forearm.L' rest pose differs from the template (moved 0.050 m, rotated 0.0°); "
		+ _EDIT,
		"Bone 'hand.L' rest pose differs from the template (moved 0.050 m, rotated 0.0°); " + _EDIT,
	],
	"too_many_triangles": ["Triangle count 11,454 exceeds 10,000"],
	"transparent_material": [
		"Material 'ghost' uses alpha blending; set Blend Mode to Opaque " + _OPAQUE,
		"Material 'ghost' has alpha 0.50; set Alpha to 1.0",
	],
	"wrong_facing": [_ARMATURE],
	"wrong_scale": [_ARMATURE, "Height 2.21 m is outside 1.6–2.0 m (Blender Z)"],
	"oversized_texture": ["Texture 'print_2048' is 2048×2048 px; the limit is 1024×1024"],
}

## Fixture whose errors are also checked through the CLI.
const CLI_FIXTURE := "transparent_material"
## Longest a CLI run may take.
const CLI_TIMEOUT_MSEC := 30000

var _failures := 0


func _initialize() -> void:
	_check_file(CharacterLoader.DEFAULT_CHARACTER, [])
	_check_file(FIXTURES.path_join("valid.glb"), [])
	for fixture: String in EXPECTED:
		_check_file(FIXTURES.path_join(fixture + ".glb"), EXPECTED[fixture])
	_check_cli(CharacterLoader.DEFAULT_CHARACTER, [])
	_check_cli(FIXTURES.path_join(CLI_FIXTURE + ".glb"), EXPECTED[CLI_FIXTURE])
	print("FAIL (%d)" % _failures if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _check_file(path: String, expected: Array) -> void:
	var name := path.get_file()
	var validator := CharacterValidator.new()
	var errors := validator.validate(path)
	_check_eq(errors, PackedStringArray(expected), "%s: errors" % name)
	_check_eq(validator.scene != null, expected.is_empty(), "%s: scene only when valid" % name)
	if validator.scene != null:
		validator.scene.free()


## The CLI through the exact command the creator kit's prompt gives the agent.
## Killed after `CLI_TIMEOUT_MSEC` (a broken command starts the game instead).
func _check_cli(path: String, expected: Array) -> void:
	var name := path.get_file()
	var command := CreatorKit.validator_command(ProjectSettings.globalize_path(path))
	var proc := OS.execute_with_pipe("sh", ["-c", "exec " + command], false)
	var pid: int = proc.pid
	var deadline := Time.get_ticks_msec() + CLI_TIMEOUT_MSEC
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(20)
	if OS.is_process_running(pid):
		OS.kill(pid)
		_check(false, "%s: CLI didn't exit within %d ms: %s" % [name, CLI_TIMEOUT_MSEC, command])
		return
	var code := OS.get_process_exit_code(pid)
	var lines := PackedStringArray()
	for line in (proc.stdio as FileAccess).get_as_text().split("\n", false):
		if (
			not line.begins_with("Godot Engine") and not line.begins_with("Warning: ")
			and not line.strip_edges().is_empty()
		):
			lines.append(line)
	_check_eq(code, 0 if expected.is_empty() else 1, "%s: CLI exit code" % name)
	_check_eq(
		lines,
		PackedStringArray(["OK"]) if expected.is_empty() else PackedStringArray(expected),
		"%s: CLI output" % name,
	)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)


func _check_eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s: got %s, expected %s" % [what, actual, expected])
