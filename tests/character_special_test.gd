extends SceneTree
## Headless test for `CharacterSpecial`, a character's own special throw:
## the standard throw written as a special (`kit_base().standard`, what every
## creator kit gets) shows the standard throw; broken data fails with
## exactly its expected errors; and the special is read from a `.glb`'s
## extras through `CharacterValidator` and `CharacterLoader`. Exits 0 when
## all checks pass, 1 otherwise.
##
##   godot --headless --path . -s tests/character_special_test.gd

const VALID_GLB := "res://tests/fixtures/valid.glb"
const TMP_DIR := "user://character_special_test"
## Largest difference allowed between sampled poses (quaternion components,
## meters): the kit's values are rounded to 0.0001.
const TOLERANCE := 0.001

## A pose that passes, for the error cases.
const OK_POSE := { "spine": [10, 0, 0] }

var _failures := 0


func _initialize() -> void:
	_test_standard()
	_test_errors()
	_test_glb()
	print("FAIL (%d)" % _failures if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


## The standard throw as a special, after a trip through JSON as in a `.glb`:
## the victim's clip and path match the standard `thrown` clip and
## `Fighter.THROW_PATH` on every tick, and the thrower's clip matches the
## standard `throw` on its keys (that clip is cubic, a special is linear) and
## ends in the stance like it.
func _test_standard() -> void:
	var data: Variant = JSON.parse_string(JSON.stringify(CharacterSpecial.kit_base().standard))
	var special := CharacterSpecial.parse(data)
	_check_eq(special.errors, PackedStringArray(), "standard: no errors")
	if not special.errors.is_empty():
		return
	var library := special.library()
	var thrown := Fighter.ANIMATIONS.get_animation(&"thrown")
	var ticks := range(Fighter.THROWN_LENGTH + 1)
	_check_clip(library.get_animation(&"thrown"), thrown, ticks, "standard: thrown")
	var throw_ticks := []
	for key: Dictionary in data.attacker:
		throw_ticks.append(int(key.tick))
	throw_ticks.append(Fighter.THROW_LENGTH)
	var throw := Fighter.ANIMATIONS.get_animation(&"throw")
	_check_clip(library.get_animation(&"throw"), throw, throw_ticks, "standard: throw")
	for tick in Fighter.THROW_SLAM + 1:
		var want := Vector2(Fighter.throw_offset(tick)) / Fighter.SCALE
		var got := special.victim_root(tick)
		_check(
			got.distance_to(want) < TOLERANCE,
			"standard: victim root on tick %d: got %s, expected %s" % [tick, got, want],
		)


## Each case: data → the complete list of errors it must produce, in order.
func _test_errors() -> void:
	var attacker := [{ "tick": 0, "pose": OK_POSE }]
	var victim := [{ "tick": 0, "pose": OK_POSE, "root": [0.6, 0] }]
	var cases := [
		[[], ["Special: must be an object with 'version', 'attacker' and 'victim'"]],
		[
			{ "version": 2, "attacker": attacker, "victim": victim },
			["Special: 'version' is 2; this game reads version 1"],
		],
		[
			{ "version": 1, "attacker": [], "victim": victim },
			["Special: 'attacker' must be a list of 1–64 keys {'tick', 'pose'}"],
		],
		[
			{
				"version": 1,
				"attacker": [
					{ "tick": 10, "pose": OK_POSE },
					{ "tick": 10, "pose": OK_POSE },
					{ "tick": 44.0, "pose": OK_POSE }, # JSON numbers parse as floats
					{ "tick": 2.5, "pose": OK_POSE },
				],
				"victim": victim,
			},
			[
				"Special: attacker[1]: tick 10 must come after the previous key's (10)",
				"Special: attacker[2]: tick 44 is outside 0–43",
				"Special: attacker[3]: 'tick' must be a whole number 0–43, not 2.5",
			],
		],
		[
			{
				"version": 1,
				"attacker": [
					{ "tick": 0, "pose": { "hand": [0, 0, 0], "spine": [0, 0], "neck": [0, 400, 0] } },
					{ "tick": 1, "pose": { "hips_pos": [0, -2.5, 0] } },
				],
				"victim": [
					{ "tick": 26, "pose": OK_POSE, "root": [0, 0] },
					{ "tick": 0, "pose": OK_POSE, "root": [3.5, -2] },
					{ "tick": 1, "pose": OK_POSE },
				],
			},
			[
				"Special: attacker[0]: unknown bone 'hand'; bones: %s, and hips_pos"
				% ", ".join(CharacterLoader.REQUIRED_BONES),
				"Special: attacker[0]: 'spine' must be 3 numbers (degrees)",
				"Special: attacker[0]: 'neck' (0.0, 400.0, 0.0) is past ±360°",
				"Special: attacker[1]: 'hips_pos' (0.0, -2.5, 0.0) moves the hips more than 2 m",
				"Special: victim[0]: tick 26 is outside 0–25",
				"Special: victim[1]: root forward 3.50 m is past ±3 m",
				"Special: victim[1]: root up -2.00 m is outside -1–3 m",
				"Special: victim[2]: 'root' must be [forward, up] in meters",
			],
		],
	]
	for i in cases.size():
		var special := CharacterSpecial.parse(cases[i][0])
		_check_eq(special.errors, PackedStringArray(cases[i][1]), "errors: case %d" % i)


## `valid.glb` with a special in its extras loads with it; with a broken one
## it fails validation with the special's errors.
func _test_glb() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var bytes := FileAccess.get_file_as_bytes(VALID_GLB)
	var standard: Dictionary = CharacterSpecial.kit_base().standard
	var good := TMP_DIR.path_join("with_special.glb")
	_write(good, _with_special(bytes, standard))
	var model := CharacterLoader.load_character(good)
	_check(model != null, "glb: valid with a special")
	if model != null:
		_check(CharacterSpecial.of(model) != null, "glb: the model carries its special")
		model.free()
	var plain := CharacterLoader.load_character(VALID_GLB)
	_check(CharacterSpecial.of(plain) == null, "glb: no special without one")
	plain.free()

	var broken := standard.duplicate(true)
	broken.victim[0].root = [5, 0]
	var bad := TMP_DIR.path_join("broken_special.glb")
	_write(bad, _with_special(bytes, broken))
	var validator := CharacterValidator.new()
	_check_eq(
		validator.validate(bad),
		PackedStringArray(["Special: victim[0]: root forward 5.00 m is past ±3 m"]),
		"glb: broken special",
	)
	_check(validator.scene == null and validator.special == null, "glb: nothing kept when broken")
	for file in DirAccess.get_files_at(TMP_DIR):
		DirAccess.remove_absolute(TMP_DIR.path_join(file))
	DirAccess.remove_absolute(TMP_DIR)


## Compares two clips' tracks (by path) on each tick in `ticks`.
func _check_clip(got: Animation, want: Animation, ticks: Array, what: String) -> void:
	for track in want.get_track_count():
		var path := want.track_get_path(track)
		var type := want.track_get_type(track)
		var other := got.find_track(path, type)
		if other == -1:
			_check(false, "%s: no track %s" % [what, path])
			continue
		for tick: int in ticks:
			var t := tick * Fighter.TICK
			var diff := 0.0
			if type == Animation.TYPE_ROTATION_3D:
				# Components, not `angle_to()`: its acos is noisy near 0.
				var a := got.rotation_track_interpolate(other, t)
				var b := want.rotation_track_interpolate(track, t)
				diff = minf((a - b).length(), (a + b).length())
			else:
				diff = got.position_track_interpolate(other, t).distance_to(
					want.position_track_interpolate(track, t)
				)
			if diff > TOLERANCE:
				_check(false, "%s: %s differs by %.4f on tick %d" % [what, path, diff, tick])
				break


## `glb` with `special` in its top-level extras, as `kit.py` writes it.
static func _with_special(glb: PackedByteArray, special: Dictionary) -> PackedByteArray:
	var json_length := glb.decode_u32(12)
	var json: Dictionary = JSON.parse_string(glb.slice(20, 20 + json_length).get_string_from_utf8())
	json.extras = { CharacterSpecial.EXTRAS_KEY: { CharacterSpecial.SPECIAL_KEY: special } }
	var text := JSON.stringify(json).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var out := glb.slice(0, 20)
	out.encode_u32(12, text.size())
	out.append_array(text)
	out.append_array(glb.slice(20 + json_length))
	out.encode_u32(8, out.size())
	return out


static func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: %s" % what)


func _check_eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s: got %s, expected %s" % [what, actual, expected])
