class_name CharacterLoader
extends RefCounted
## Loads character `.glb` files at runtime with `GLTFDocument` (not editor-imported
## scenes), so characters can be swapped without re-importing. Conventions are in
## `docs/skeleton.md`.

const TOON_SHADER := preload("res://shaders/toon.gdshader")

## Bones every character must have (`docs/skeleton.md`). Animations target these names.
const REQUIRED_BONES: PackedStringArray = [
	"hips", "spine", "chest", "neck", "head",
	"upper_arm.L", "forearm.L", "hand.L",
	"upper_arm.R", "forearm.R", "hand.R",
	"thigh.L", "shin.L", "foot.L",
	"thigh.R", "shin.R", "foot.R",
]


## Loads a character `.glb` and checks it has the required skeleton. Returns the
## scene root, or null after pushing an error naming what's wrong.
static func load_character(path: String) -> Node3D:
	var root := load_glb(path)
	if root == null:
		return null
	if check_skeleton(root, path) == null:
		root.free()
		return null
	return root


## Returns the character's `Skeleton3D` if it has every required bone; otherwise
## pushes an error (prefixed with `source`) and returns null.
static func check_skeleton(root: Node, source: String) -> Skeleton3D:
	var skeleton := find_skeleton(root)
	if skeleton == null:
		push_error("CharacterLoader: '%s' has no Skeleton3D (export the armature from the template, see docs/skeleton.md)" % source)
		return null
	var missing := missing_bones(skeleton)
	if not missing.is_empty():
		push_error("CharacterLoader: '%s' is missing %d required bone(s): %s (bones present: %s)" % [
			source, missing.size(), ", ".join(missing), ", ".join(_bone_names(skeleton))])
		return null
	return skeleton


## First `Skeleton3D` at or under `root`, or null.
static func find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	var found := root.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null


## Names from `REQUIRED_BONES` that `skeleton` lacks (exact, case-sensitive match).
static func missing_bones(skeleton: Skeleton3D) -> PackedStringArray:
	var missing := PackedStringArray()
	for bone in REQUIRED_BONES:
		if skeleton.find_bone(bone) == -1:
			missing.append(bone)
	return missing


static func _bone_names(skeleton: Skeleton3D) -> PackedStringArray:
	var names := PackedStringArray()
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	return names


## Loads the `.glb` at `path` (res://, user://, or absolute) and returns its
## generated scene root, or null after pushing an error. Mesh materials are
## replaced with the toon shader, keeping the original albedo color/texture.
## The caller owns the returned node (add it to the tree or free it).
static func load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("CharacterLoader: can't read '%s': %s" % [path, error_string(err)])
		return null
	var root := doc.generate_scene(state) as Node3D
	if root == null:
		push_error("CharacterLoader: '%s' produced no scene" % path)
		return null
	root.name = path.get_file().get_basename().validate_node_name()
	_apply_toon_materials(root)
	return root


static func _apply_toon_materials(root: Node) -> void:
	var converted := {}  # source Material -> ShaderMaterial, shared between parts
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			if not converted.has(src):
				converted[src] = _toon_from(src)
			mesh.surface_set_material(i, converted[src])


static func _toon_from(src: Material) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	var base := src as BaseMaterial3D
	if base != null:
		mat.set_shader_parameter("albedo", base.albedo_color)
		if base.albedo_texture != null:
			mat.set_shader_parameter("albedo_texture", base.albedo_texture)
	return mat
