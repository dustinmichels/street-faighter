class_name CharacterLoader
extends RefCounted
## Loads character `.glb` files at runtime with `GLTFDocument` (not editor-imported
## scenes), so characters can be swapped without re-importing. Conventions are in
## `creator_kit/SKELETON.md`.

const TOON_SHADER := preload("res://characters/toon.gdshader")

## Built-in character, also the reference skeleton and rest pose for
## `CharacterValidator` and the fallback when a character can't be loaded.
const DEFAULT_CHARACTER := "res://characters/default/default.glb"
## Hue rotation (turns, `toon.gdshader` `tint_hue`) for fighter 2 in a mirror
## match, so both fighters are told apart: red turns blue.
const MIRROR_TINT := 0.6

## Bones every character must have (`creator_kit/SKELETON.md`). Animations target these names.
const REQUIRED_BONES: PackedStringArray = [
	"hips",
	"spine",
	"chest",
	"neck",
	"head",
	"upper_arm.L",
	"forearm.L",
	"hand.L",
	"upper_arm.R",
	"forearm.R",
	"hand.R",
	"thigh.L",
	"shin.L",
	"foot.L",
	"thigh.R",
	"shin.R",
	"foot.R",
]


## Loads a character `.glb` after `CharacterValidator` accepts it. Returns the
## scene root, or null after pushing an error that lists every problem. A
## custom special throw rides along on the root (`CharacterSpecial.of()`).
static func load_character(path: String) -> Node3D:
	var validator := CharacterValidator.new()
	var errors := validator.validate(path)
	if not errors.is_empty():
		push_error(
			"CharacterLoader: '%s' is not a valid character:\n  %s" % [path, "\n  ".join(errors)]
		)
		return null
	for warning in validator.warnings:
		push_warning("CharacterLoader: '%s': %s" % [path, warning])
	_apply_toon_materials(validator.scene)
	if validator.special != null:
		validator.scene.set_meta(CharacterSpecial.META, validator.special)
	return validator.scene


## First `Skeleton3D` at or under `root`, or null.
static func find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	var found := root.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null


## Sets the toon shader's `tint_hue` (turns, 0 = none) on every material of a
## `load_character()`/`load_glb()` model. Each load converts its own
## materials, so this only changes `root`.
static func set_tint(root: Node, hue: float) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter("tint_hue", hue)


## Loads the `.glb` at `path` (res://, user://, or absolute) and returns its
## generated scene root, or null after pushing an error. Mesh materials are
## replaced with the toon shader, keeping the original albedo color/texture
## and emission color. Also used for stage scenery (`Stage`).
## The caller owns the returned node (add it to the tree or free it).
static func load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	# Keep embedded textures in memory; the default extracts them as PNG files
	# next to the .glb (into the project when run from the editor).
	state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("CharacterLoader: can't read '%s': %s" % [path, error_string(err)])
		return null
	var root := doc.generate_scene(state) as Node3D
	if root == null:
		push_error("CharacterLoader: '%s' produced no scene" % path)
		return null
	root.name = path.get_file().get_basename().validate_node_name()
	bake_importer_meshes(root)
	_apply_toon_materials(root)
	return root


## In the editor (tool scripts such as `Stage`), `generate_scene()` leaves
## `ImporterMeshInstance3D`s, which don't render; swap them for real
## `MeshInstance3D`s. A no-op in the running game.
static func bake_importer_meshes(root: Node) -> void:
	for node in root.find_children("*", "ImporterMeshInstance3D", true, false):
		var src := node as ImporterMeshInstance3D
		var mi := MeshInstance3D.new()
		mi.name = src.name
		mi.transform = src.transform
		if src.mesh != null:
			mi.mesh = src.mesh.get_mesh()
		mi.skin = src.skin
		mi.skeleton = src.skeleton_path
		src.replace_by(mi, true)
		src.free()


static func _apply_toon_materials(root: Node) -> void:
	var converted := { } # source Material -> ShaderMaterial, shared between parts
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
		if base.emission_enabled:
			mat.set_shader_parameter("emission", base.emission * base.emission_energy_multiplier)
	return mat
