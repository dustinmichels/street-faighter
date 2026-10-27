extends SceneTree
## Skeleton drift test: the skeleton is described in four places that must
## agree, because the prompt, the creator kit, the validator, and the
## animations each rely on a different one:
##
## - the rig `creator_kit/build_template.py` actually builds in Blender (dumped
##   by `tests/dump_skeleton.py`: names, parents, head/tail, roll, local axes),
## - the `docs/skeleton.md` tables (copied into every kit as `SKELETON.md`),
## - the rest pose of `characters/default/default.glb` (the validator's reference),
## - `CharacterLoader.REQUIRED_BONES`.
##
## Needs Blender: `blender` on PATH, or set `BLENDER` to its executable.
## Exits 0 when everything agrees, 1 otherwise.
##
##   godot --headless --path . -s tests/skeleton_drift_test.gd

const DOC := "res://docs/skeleton.md"
const DUMP_SCRIPT := "res://tests/dump_skeleton.py"
const DUMP := "user://skeleton_drift_test.json"
const POSITION_TOLERANCE := 0.0005  # meters; the doc gives positions in cm
const AXIS_TOLERANCE := 0.001
## Doc axis names -> Blender directions.
const DIRECTIONS := {
	"+X": Vector3(1, 0, 0), "−X": Vector3(-1, 0, 0),
	"+Y": Vector3(0, 1, 0), "−Y": Vector3(0, -1, 0),
	"+Z": Vector3(0, 0, 1), "−Z": Vector3(0, 0, -1),
}

var _failures := 0


func _initialize() -> void:
	var rig := _dump_rig()
	if not rig.is_empty():
		var doc := _read_doc()
		_compare_doc(rig, doc)
		_compare_glb(rig)
		_check_eq(_sorted(CharacterLoader.REQUIRED_BONES), _sorted(rig.keys()), "REQUIRED_BONES = template bones")
	print("FAIL (%d)" % _failures if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


# --- The rig Blender builds ----------------------------------------------------

## Bone name -> {parent, head, tail, connected, roll, x, y, z} (Blender space), or {}.
func _dump_rig() -> Dictionary:
	var blender := OS.get_environment("BLENDER")
	if blender.is_empty():
		blender = "blender"
	var out := ProjectSettings.globalize_path(DUMP)
	DirAccess.remove_absolute(out)
	var log := []
	var code := OS.execute(blender, [
		"-b", "--factory-startup", "--python", ProjectSettings.globalize_path(DUMP_SCRIPT), "--", out,
	], log, true)
	var dump: Variant = JSON.parse_string(FileAccess.get_file_as_string(out))
	DirAccess.remove_absolute(out)
	if code != 0 or not dump is Dictionary:
		_fail("Blender dump failed (exit %d; is Blender on PATH or in BLENDER?):\n%s" % [code, "".join(log)])
		return {}
	print("Template built by Blender %s" % dump.blender)
	_check_eq(_vec(dump.object.location), Vector3.ZERO, "Armature object location")
	_check_eq(_vec(dump.object.rotation), Vector3.ZERO, "Armature object rotation")
	_check_eq(_vec(dump.object.scale), Vector3.ONE, "Armature object scale")
	var rig := {}
	for bone: Dictionary in dump.bones:
		rig[bone.name] = {
			"parent": bone.parent, "connected": bone.connected, "roll": float(bone.roll),
			"head": _vec(bone.head), "tail": _vec(bone.tail),
			"x": _vec(bone.x), "y": _vec(bone.y), "z": _vec(bone.z),
		}
	return rig


# --- docs/skeleton.md ----------------------------------------------------------

## {bones: name -> {parent, head, tail, connected}, axes: name -> {x, z}, count}
## where axes values are the table text ("+X (left)", "mostly down").
func _read_doc() -> Dictionary:
	var bones := {}
	var axes := {}
	var count := -1
	var section := ""
	for line in FileAccess.get_file_as_string(DOC).split("\n"):
		if line.begins_with("## "):
			section = line.substr(3)
		elif line.begins_with("There are ") and line.contains(" bones."):
			count = line.get_slice(" ", 2).to_int()
		if not line.begins_with("| `"):
			continue
		var cells := Array(line.split("|")).slice(1, -1).map(func(c: String) -> String: return c.strip_edges())
		if section == "Bones":
			bones[cells[0].trim_prefix("`").trim_suffix("`")] = {
				"parent": "" if cells[1] == "(root)" else cells[1].trim_prefix("`").trim_suffix("`"),
				"head": _doc_vec(cells[2]),
				"tail": _doc_vec(cells[3]),
				"connected": cells[4] == "yes",
			}
		elif section == "Bone axes":
			for pattern in cells[0].split(","):
				axes[pattern.strip_edges().trim_prefix("`").trim_suffix("`")] = {"x": cells[1], "z": cells[2]}
	return {"bones": bones, "axes": axes, "count": count}


func _compare_doc(rig: Dictionary, doc: Dictionary) -> void:
	var bones: Dictionary = doc.bones
	_check_eq(_sorted(bones.keys()), _sorted(rig.keys()), "skeleton.md bone table = template bones")
	_check_eq(doc.count, rig.size(), "skeleton.md 'There are N bones'")
	for name: String in rig:
		var actual: Dictionary = rig[name]
		_check(is_zero_approx(actual.roll), "%s: roll 0 (skeleton.md 'Every bone has roll 0')" % name)
		_check_dir(actual.y, (actual.tail - actual.head).normalized(), "%s: local +Y points from head to tail" % name)
		if bones.has(name):
			var row: Dictionary = bones[name]
			_check_eq(actual.parent, row.parent, "skeleton.md %s: parent" % name)
			_check_eq(actual.connected, row.connected, "skeleton.md %s: connected" % name)
			_check_near(actual.head, row.head, "skeleton.md %s: head" % name)
			_check_near(actual.tail, row.tail, "skeleton.md %s: tail" % name)
		var axes := _doc_axes(doc.axes, name)
		if axes.is_empty():
			_fail("skeleton.md Bone axes: no row for %s" % name)
			continue
		_check_axis(actual.x, axes.x, "skeleton.md Bone axes %s: local +X" % name)
		_check_axis(actual.z, axes.z, "skeleton.md Bone axes %s: local +Z" % name)


# Axes row for a bone: exact name or a `<name>.*` pattern.
static func _doc_axes(axes: Dictionary, bone: String) -> Dictionary:
	if axes.has(bone):
		return axes[bone]
	var pattern := bone.get_slice(".", 0) + ".*"
	return axes.get(pattern, {})


func _check_axis(actual: Vector3, text: String, what: String) -> void:
	if text == "mostly down":
		_check(actual.z < 0 and absf(actual.z) > maxf(absf(actual.x), absf(actual.y)), "%s: mostly down, got %s" % [what, actual])
		return
	var key := text.get_slice(" ", 0)
	if not DIRECTIONS.has(key):
		_fail("%s: unknown axis '%s'" % [what, text])
		return
	_check_dir(actual, DIRECTIONS[key], "%s (%s)" % [what, text])


# --- default.glb ---------------------------------------------------------------

## The glTF exporter maps Blender (x, y, z) to Godot (x, z, −y), and each
## bone's global rest basis is its Blender local axes in Godot space.
func _compare_glb(rig: Dictionary) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(CharacterLoader.DEFAULT_CHARACTER, state) != OK:
		_fail("can't read %s" % CharacterLoader.DEFAULT_CHARACTER)
		return
	var root := doc.generate_scene(state)
	var skeleton := CharacterLoader.find_skeleton(root)
	var to_root := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != root:
		to_root = (node as Node3D).transform * to_root
		node = node.get_parent()
	_check(to_root.is_equal_approx(Transform3D.IDENTITY), "default.glb: Armature at the origin, got %s" % to_root)
	var names := []
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	_check_eq(_sorted(names), _sorted(rig.keys()), "default.glb bones = template bones")
	for name: String in rig:
		var i := skeleton.find_bone(name)
		if i == -1:
			continue
		var actual: Dictionary = rig[name]
		var parent := skeleton.get_bone_parent(i)
		_check_eq(skeleton.get_bone_name(parent) if parent != -1 else "", actual.parent, "default.glb %s: parent" % name)
		var rest := to_root * skeleton.get_bone_global_rest(i)
		_check_near(rest.origin, _to_godot(actual.head), "default.glb %s: head" % name)
		_check_dir(rest.basis.x, _to_godot(actual.x), "default.glb %s: local +X" % name)
		_check_dir(rest.basis.y, _to_godot(actual.y), "default.glb %s: local +Y" % name)
		_check_dir(rest.basis.z, _to_godot(actual.z), "default.glb %s: local +Z" % name)
	root.free()


static func _to_godot(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


# --- Helpers -------------------------------------------------------------------

static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## "(−0.10, −0.15, 0.02)" -> Vector3.
static func _doc_vec(text: String) -> Vector3:
	var parts := text.replace("−", "-").trim_prefix("(").trim_suffix(")").split(",")
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())


static func _sorted(items: Variant) -> Array:
	var out := Array(items)
	out.sort()
	return out


func _check_near(actual: Vector3, expected: Vector3, what: String) -> void:
	_check(actual.distance_to(expected) <= POSITION_TOLERANCE, "%s: got %s, expected %s" % [what, actual, expected])


func _check_dir(actual: Vector3, expected: Vector3, what: String) -> void:
	_check(actual.normalized().distance_to(expected) <= AXIS_TOLERANCE, "%s: got %s, expected %s" % [what, actual, expected])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _check_eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_fail("%s: got %s, expected %s" % [what, actual, expected])


func _fail(what: String) -> void:
	_failures += 1
	printerr("FAIL: %s" % what)
