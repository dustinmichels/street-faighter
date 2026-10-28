class_name CharacterValidator
extends RefCounted
## Checks a character `.glb` against the contract in `creator_kit/SKELETON.md` and
## collects every problem, worded so a player can paste the list to the agent
## that built the model. `CharacterLoader.load_character` and the
## `--validate-character` CLI both use it.
##
## The file is checked in two stages. First the raw GLB container and its JSON
## chunk are parsed by hand (size, header, external URIs, accessor and image
## bounds), so nothing oversized reaches `GLTFDocument`. Only if that passes is
## the file decoded and the generated scene checked (skeleton, rest pose, bounds).
##
##   var v := CharacterValidator.new()
##   var errors := v.validate(path)  # empty = valid; `v.scene` holds the model

const MAX_FILE_BYTES := 4 * 1024 * 1024
const MAX_TRIANGLES := 10000
const MAX_TEXTURES := 2
const MAX_TEXTURE_SIZE := 1024
## Safety limits for the JSON chunk, far above what a valid character needs
## (`default.glb`: 35 nodes, 37 accessors of at most a few hundred elements).
const MAX_NODES := 1024
const MAX_ACCESSORS := 4096
const MAX_ACCESSOR_ELEMENTS := 100000
const MAX_TOTAL_ELEMENTS := 1000000
## Height range in meters, and how far the soles may be from the floor.
const MIN_HEIGHT := 1.6
const MAX_HEIGHT := 2.0
const FLOOR_TOLERANCE := 0.05
## Half-width of the box the body (arms excluded) must fit in, sideways and front-to-back.
const MAX_HALF_EXTENT := 0.6
## Rest pose tolerances against `REFERENCE`.
const REST_POSITION_TOLERANCE := 0.002 # meters
const REST_ANGLE_TOLERANCE := 0.005 # radians
const REST_SCALE_TOLERANCE := 0.002
const REFERENCE := CharacterLoader.DEFAULT_CHARACTER
const ARM_BONES: PackedStringArray = [
	"upper_arm.L",
	"forearm.L",
	"hand.L",
	"upper_arm.R",
	"forearm.R",
	"hand.R",
]

const _CHUNK_JSON := 0x4E4F534A
const _CHUNK_BIN := 0x004E4942
const _COMPONENT_BYTES := { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 }
const _TYPE_COMPONENTS := {
	"SCALAR": 1,
	"VEC2": 2,
	"VEC3": 3,
	"VEC4": 4,
	"MAT2": 4,
	"MAT3": 9,
	"MAT4": 16,
}

## Problems found by the last `validate` call (same as its return value).
var errors := PackedStringArray()
## Things the game ignores (animations, cameras, lights, shape keys); not failures.
var warnings := PackedStringArray()
## The generated scene of a valid file (raw `GLTFDocument` output, before
## `CharacterLoader`'s material pass), or null. The caller owns it.
var scene: Node3D
## The contents of a valid file, exactly as checked (the library stores
## these, not a second read of the path), or empty.
var file_bytes := PackedByteArray()

# Bone name -> {"parent": String, "rest": Transform3D}, plus the skeleton's
# transform relative to the scene root, from `REFERENCE` (loaded once).
static var _reference_bones: Dictionary
static var _reference_skeleton_transform: Transform3D


## Validates the `.glb` at `path` and returns every problem found, or an empty
## array if the character is usable. Warnings go to `warnings`. On success
## `scene` holds the decoded model; otherwise it is null.
func validate(path: String) -> PackedStringArray:
	errors = PackedStringArray()
	warnings = PackedStringArray()
	scene = null
	file_bytes = PackedByteArray()
	var data := _read_file(path)
	if data.is_empty():
		return errors
	var json := _parse_glb(data)
	if json.is_empty():
		return errors
	_check_safety(json, data)
	if not errors.is_empty():
		return errors # never hand unsafe data to GLTFDocument
	_check_content(json, data)
	var root := _decode(data, path)
	if root == null:
		return errors
	_check_scene(root)
	if errors.is_empty():
		scene = root
		file_bytes = data
	else:
		root.free()
	return errors


func _fail(message: String) -> void:
	errors.append(message)

# --- File and container -----------------------------------------------------


func _read_file(path: String) -> PackedByteArray:
	if path.get_extension().to_lower() != "glb":
		_fail("File '%s' is not a .glb; export as glTF Binary (.glb)" % path.get_file())
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Can't open '%s': %s" % [path, error_string(FileAccess.get_open_error())])
		return PackedByteArray()
	var size := file.get_length()
	if size > MAX_FILE_BYTES:
		_fail("File size %s exceeds %s (4 MB)" % [_bytes(size), _bytes(MAX_FILE_BYTES)])
		return PackedByteArray()
	var bytes := file.get_buffer(size)
	if bytes.is_empty():
		_fail("File '%s' is empty" % path.get_file())
	return bytes


## Checks the GLB header and chunk layout; returns the parsed JSON chunk, or {}
## after recording why the file can't be read.
func _parse_glb(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 20 or bytes.slice(0, 4).get_string_from_ascii() != "glTF":
		_fail("Not a binary glTF file (missing 'glTF' header); export as glTF Binary (.glb)")
		return { }
	var version := bytes.decode_u32(4)
	if version != 2:
		_fail("glTF version %d is not supported; export glTF 2.0" % version)
		return { }
	if bytes.decode_u32(8) != bytes.size():
		_fail(
			"File is truncated or padded: header says %s, file is %s"
			% [_bytes(bytes.decode_u32(8)), _bytes(bytes.size())]
		)
		return { }
	var json_length := bytes.decode_u32(12)
	if bytes.decode_u32(16) != _CHUNK_JSON or 20 + json_length > bytes.size():
		_fail("GLB JSON chunk is missing or truncated")
		return { }
	var parsed: Variant = JSON.parse_string(
		bytes.slice(20, 20 + json_length).get_string_from_utf8()
	)
	if not parsed is Dictionary:
		_fail("GLB JSON chunk is not valid JSON")
		return { }
	return parsed


# Returns the BIN chunk's [offset, length] in `bytes`, or [0, 0] if absent.
func _bin_chunk(bytes: PackedByteArray) -> Vector2i:
	var at := 20 + ((bytes.decode_u32(12) + 3) & ~3)
	if at + 8 > bytes.size() or bytes.decode_u32(at + 4) != _CHUNK_BIN:
		return Vector2i.ZERO
	var length := bytes.decode_u32(at)
	if at + 8 + length > bytes.size():
		return Vector2i.ZERO
	return Vector2i(at + 8, length)

# --- Stage 1: JSON safety (before GLTFDocument decodes anything) -------------


func _check_safety(json: Dictionary, bytes: PackedByteArray) -> void:
	var bin := _bin_chunk(bytes)
	var buffers := _array(json, "buffers")
	if buffers.size() > 1:
		_fail("File has %d buffers; a .glb export has one" % buffers.size())
	for i in buffers.size():
		var buffer := _dict(buffers[i])
		if buffer.has("uri"):
			_fail(
				"Buffer %d refers to an external file '%s'; export as glTF Binary (.glb) so everything is embedded"
				% [i, _short(buffer.uri)]
			)
		elif _int(buffer.get("byteLength")) < 0 or _int(buffer.get("byteLength")) > bin.y:
			_fail("Buffer %d is larger than the file's binary chunk" % i)
	var buffer_length := _int(_dict(buffers[0]).get("byteLength")) if buffers.size() == 1 else 0
	var views := _array(json, "bufferViews")
	var view_ok := []
	for i in views.size():
		var view := _dict(views[i])
		var offset := _int(view.get("byteOffset", 0))
		var length := _int(view.get("byteLength"))
		var ok := (
			_int(view.get("buffer")) == 0 and offset >= 0
			and length >= 0 and offset + length <= buffer_length
		)
		if not ok:
			_fail("Buffer view %d points outside the binary data" % i)
		view_ok.append(ok)
	var nodes := _array(json, "nodes")
	if nodes.size() > MAX_NODES:
		_fail("Node count %s exceeds %s" % [_thousands(nodes.size()), _thousands(MAX_NODES)])
	var accessors := _array(json, "accessors")
	if accessors.size() > MAX_ACCESSORS:
		_fail(
			"Accessor count %s exceeds %s"
			% [_thousands(accessors.size()), _thousands(MAX_ACCESSORS)]
		)
		return
	var total := 0
	for i in accessors.size():
		var accessor := _dict(accessors[i])
		var count := _int(accessor.get("count"))
		var element := int(_COMPONENT_BYTES.get(_int(accessor.get("componentType")), 0)) * int(
			_TYPE_COMPONENTS.get(accessor.get("type"), 0)
		)
		if count < 1 or element == 0:
			_fail("Accessor %d is malformed (count or type)" % i)
			continue
		if count > MAX_ACCESSOR_ELEMENTS:
			_fail(
				"Accessor %d has %s elements, more than %s"
				% [i, _thousands(count), _thousands(MAX_ACCESSOR_ELEMENTS)]
			)
			continue
		total += count
		if (
			accessor.has("bufferView")
			and not _fits(
				views,
				view_ok,
				accessor.bufferView,
				_int(accessor.get("byteOffset", 0)),
				count,
				element,
			)
		):
			_fail("Accessor %d reads past the end of its buffer view" % i)
		if accessor.has("sparse"):
			var sparse := _dict(accessor.sparse)
			var sparse_count := _int(sparse.get("count"))
			var index_bytes := int(
				_COMPONENT_BYTES.get(_int(_dict(sparse.get("indices")).get("componentType")), 0)
			)
			if sparse_count < 1 or sparse_count > count or index_bytes == 0 \
					or not _fits(
				views,
				view_ok,
				_dict(sparse.get("indices")).get("bufferView"),
				_int(_dict(sparse.get("indices")).get("byteOffset", 0)),
				sparse_count,
				index_bytes,
			) \
					or not _fits(
				views,
				view_ok,
				_dict(sparse.get("values")).get("bufferView"),
				_int(_dict(sparse.get("values")).get("byteOffset", 0)),
				sparse_count,
				element,
			):
				_fail("Accessor %d has malformed sparse data" % i)
	if total > MAX_TOTAL_ELEMENTS:
		_fail(
			"Accessors hold %s elements in total, more than %s"
			% [_thousands(total), _thousands(MAX_TOTAL_ELEMENTS)]
		)
	var images := _array(json, "images")
	if images.size() > MAX_TEXTURES:
		_fail("Texture count %d exceeds %d" % [images.size(), MAX_TEXTURES])
	for i in images.size():
		var image := _dict(images[i])
		var label := "Texture '%s'" % image.name if image.get("name") is String else "Texture %d" % i
		if image.has("uri"):
			_fail(
				"%s refers to an external file '%s'; pack the image into the .glb"
				% [label, _short(image.uri)]
			)
			continue
		var view_index := _int(image.get("bufferView"))
		if view_index < 0 or view_index >= views.size() or not view_ok[view_index]:
			_fail("%s has no embedded image data" % label)
			continue
		var view := _dict(views[view_index])
		var start := bin.x + _int(view.get("byteOffset", 0))
		var data := bytes.slice(start, start + _int(view.byteLength))
		var size := _image_size(data)
		if size == Vector2i.ZERO:
			_fail("%s is not a PNG or JPEG image" % label)
		elif size.x > MAX_TEXTURE_SIZE or size.y > MAX_TEXTURE_SIZE:
			_fail(
				"%s is %d×%d px; the limit is %d×%d"
				% [label, size.x, size.y, MAX_TEXTURE_SIZE, MAX_TEXTURE_SIZE]
			)


func _fits(
	views: Array,
	view_ok: Array,
	view_index: Variant,
	offset: int,
	count: int,
	element: int,
) -> bool:
	var index := _int(view_index)
	if index < 0 or index >= views.size() or not view_ok[index] or offset < 0:
		return false
	var view := _dict(views[index])
	var stride := maxi(_int(view.get("byteStride", element)), element)
	return offset + stride * (count - 1) + element <= _int(view.byteLength)


## Width and height of a PNG or JPEG from its header, or zero if neither.
static func _image_size(data: PackedByteArray) -> Vector2i:
	if data.size() >= 24 and data.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return Vector2i(_u32_be(data, 16), _u32_be(data, 20))
	if data.size() < 4 or data[0] != 0xFF or data[1] != 0xD8:
		return Vector2i.ZERO
	var at := 2
	while at + 9 < data.size():
		if data[at] != 0xFF:
			return Vector2i.ZERO
		var marker := data[at + 1]
		if marker == 0xFF:
			at += 1
			continue
		var length := (data[at + 2] << 8) | data[at + 3]
		# SOF0–SOF15, except DHT (C4), JPG (C8), and DAC (CC).
		if marker >= 0xC0 and marker <= 0xCF and marker not in [0xC4, 0xC8, 0xCC]:
			return Vector2i((data[at + 7] << 8) | data[at + 8], (data[at + 5] << 8) | data[at + 6])
		at += 2 + length
	return Vector2i.ZERO


static func _u32_be(data: PackedByteArray, at: int) -> int:
	return (data[at] << 24) | (data[at + 1] << 16) | (data[at + 2] << 8) | data[at + 3]

# --- Stage 1b: JSON content (parts, triangles, materials, ignored data) -------


func _check_content(json: Dictionary, bytes: PackedByteArray) -> void:
	var nodes := _array(json, "nodes")
	var joints := { }
	for skin in _array(json, "skins"):
		for joint in _array(_dict(skin), "joints"):
			joints[_int(joint)] = true
	var parent_of := { }
	for i in nodes.size():
		for child in _array(_dict(nodes[i]), "children"):
			parent_of[_int(child)] = i
	var meshes := _array(json, "meshes")
	var accessors := _array(json, "accessors")
	var triangles := 0
	var shape_keys := false
	for i in nodes.size():
		var node := _dict(nodes[i])
		var name := _node_name(node, i)
		if not joints.has(i) and name in CharacterLoader.REQUIRED_BONES:
			_fail("Part '%s' has the same name as a bone; rename it to '%s_part'" % [name, name])
		if not node.has("mesh"):
			continue
		if node.has("skin"):
			_fail(
				"Part '%s' is skinned (Armature modifier or vertex groups); remove that and parent it to one bone (Ctrl+P → Bone)"
				% name
			)
		elif not _under_joint(i, joints, parent_of):
			_fail("Part '%s' isn't parented to a bone; parent it with Ctrl+P → Bone" % name)
		var mesh_index := _int(node.mesh)
		if mesh_index < 0 or mesh_index >= meshes.size():
			_fail("Part '%s' refers to a missing mesh" % name)
			continue
		for primitive in _array(_dict(meshes[mesh_index]), "primitives"):
			primitive = _dict(primitive)
			if not _array(primitive, "targets").is_empty():
				shape_keys = true
			var mode := _int(primitive.get("mode", 4))
			var indices := _accessor_count(accessors, primitive.get("indices"))
			var vertices := _accessor_count(
				accessors,
				_dict(primitive.get("attributes")).get("POSITION"),
			)
			var count := indices if indices > 0 else vertices
			match mode:
				4:
					triangles += count / 3
				5, 6:
					triangles += maxi(count - 2, 0)
				_:
					_fail(
						"Part '%s' contains loose points or edges; delete them (only faces are allowed)"
						% name
					)
	if triangles > MAX_TRIANGLES:
		_fail("Triangle count %s exceeds %s" % [_thousands(triangles), _thousands(MAX_TRIANGLES)])

	var materials := _array(json, "materials")
	for i in materials.size():
		var material := _dict(materials[i])
		var label := "Material '%s'" % material.name if material.get("name") is String else "Material %d" % i
		var mode: Variant = material.get("alphaMode", "OPAQUE")
		if mode == "BLEND":
			_fail(
				"%s uses alpha blending; set Blend Mode to Opaque (fighters must be fully opaque)"
				% label
			)
		elif mode == "MASK":
			_fail(
				"%s uses alpha clipping; set Blend Mode to Opaque (fighters must be fully opaque)"
				% label
			)
		var factor := _array(_dict(material.get("pbrMetallicRoughness")), "baseColorFactor")
		if factor.size() == 4 and float(factor[3]) < 1.0:
			_fail("%s has alpha %.2f; set Alpha to 1.0" % [label, float(factor[3])])
		if _dict(material.get("extensions")).has("KHR_materials_transmission"):
			_fail(
				"%s uses transmission; set Transmission to 0 (fighters must be fully opaque)"
				% label
			)

	var animations := _array(json, "animations").size()
	if animations > 0:
		warnings.append("Ignored: %d animation(s); the game plays its own" % animations)
	var cameras := _array(json, "cameras").size()
	if cameras > 0:
		warnings.append("Ignored: %d camera(s)" % cameras)
	var lights := _array(_dict(_dict(json.get("extensions")).get("KHR_lights_punctual")), "lights").size()
	if lights > 0:
		warnings.append("Ignored: %d light(s)" % lights)
	if shape_keys:
		warnings.append("Ignored: shape keys")


func _under_joint(index: int, joints: Dictionary, parent_of: Dictionary) -> bool:
	var seen := { }
	while parent_of.has(index) and not seen.has(index):
		seen[index] = true
		index = parent_of[index]
		if joints.has(index):
			return true
	return false


static func _accessor_count(accessors: Array, index: Variant) -> int:
	var i := _int(index)
	return _int(_dict(accessors[i]).get("count")) if i >= 0 and i < accessors.size() else 0

# --- Stage 2: decoded scene (skeleton, rest pose, bounds) --------------------


func _decode(bytes: PackedByteArray, path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED
	var err := doc.append_from_buffer(bytes, "", state)
	if err != OK:
		_fail("Godot can't read '%s': %s" % [path.get_file(), error_string(err)])
		return null
	var root := doc.generate_scene(state) as Node3D
	if root == null:
		_fail("'%s' contains no scene" % path.get_file())
		return null
	root.name = path.get_file().get_basename().validate_node_name()
	CharacterLoader.bake_importer_meshes(root)
	return root


func _check_scene(root: Node3D) -> void:
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		_fail("No armature found; build the character on the template skeleton and export it")
		return
	if skeletons.size() > 1:
		_fail("Found %d armatures; export exactly one (the template's)" % skeletons.size())
		return
	var skeleton := skeletons[0] as Skeleton3D
	_check_bones(skeleton)
	if not _transform_to(skeleton, root).is_equal_approx(_reference_skeleton_transform):
		_fail(
			"The Armature object is moved, rotated, or scaled; keep it at the origin with no rotation and scale 1"
		)
	_check_bounds(root, skeleton)


func _check_bones(skeleton: Skeleton3D) -> void:
	_load_reference()
	var clashes := { } # bone names a part also used (already reported)
	for e in errors:
		if e.begins_with("Part '") and e.contains("same name as a bone"):
			clashes[e.get_slice("'", 1)] = true
	var names := { }
	for i in skeleton.get_bone_count():
		names[skeleton.get_bone_name(i)] = i
	for bone in CharacterLoader.REQUIRED_BONES:
		if names.has(bone) or clashes.has(bone):
			continue
		var similar := PackedStringArray()
		for other: String in names:
			if (
				not _reference_bones.has(other)
				and (other.begins_with(bone) or other.to_lower() == bone.to_lower())
			):
				similar.append("'%s'" % other)
		if similar.is_empty():
			_fail("Bone '%s' missing" % bone)
		else:
			_fail("Bone '%s' missing (found %s)" % [bone, ", ".join(similar)])
	for name: String in names:
		if _reference_bones.has(name):
			continue
		var base := name.rsplit("_", true, 1)[0]
		if clashes.has(base):
			continue # Godot renamed the bone after a part took its name
		if not _similar_to_required(name):
			_fail(
				"Extra bone '%s'; delete it (the skeleton must have exactly the %d template bones)"
				% [name, CharacterLoader.REQUIRED_BONES.size()]
			)
	for name: String in names:
		if not _reference_bones.has(name):
			continue
		var i: int = names[name]
		var expected: Dictionary = _reference_bones[name]
		var parent := skeleton.get_bone_parent(i)
		var parent_name := skeleton.get_bone_name(parent) if parent != -1 else ""
		if parent_name != expected.parent:
			_fail(
				"Bone '%s' has parent %s, expected %s"
				% [name, _quoted_or_none(parent_name), _quoted_or_none(expected.parent)]
			)
			continue
		var rest := skeleton.get_bone_rest(i)
		var want: Transform3D = expected.rest
		var moved := rest.origin.distance_to(want.origin)
		var turned := rest.basis.get_rotation_quaternion().angle_to(
			want.basis.get_rotation_quaternion()
		)
		var scaled := (rest.basis.get_scale() - want.basis.get_scale()).abs()
		if (
			moved > REST_POSITION_TOLERANCE or turned > REST_ANGLE_TOLERANCE
			or maxf(scaled.x, maxf(scaled.y, scaled.z)) > REST_SCALE_TOLERANCE
		):
			_fail(
				"Bone '%s' rest pose differs from the template (moved %.3f m, rotated %.1f°); don't edit bones, rebuild on the template skeleton"
				% [name, moved, rad_to_deg(turned)]
			)


# A non-template bone that `_check_bones` already named in a "missing (found …)" message.
func _similar_to_required(name: String) -> bool:
	for bone in CharacterLoader.REQUIRED_BONES:
		if name.begins_with(bone) or name.to_lower() == bone.to_lower():
			return true
	return false


func _check_bounds(root: Node3D, skeleton: Skeleton3D) -> void:
	var low := Vector3.INF
	var high := -Vector3.INF
	var body_low := Vector3.INF
	var body_high := -Vector3.INF
	var any := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin != null:
			continue
		var arm := false
		var ancestor := mi.get_parent()
		while ancestor != null and ancestor != root:
			if ancestor is BoneAttachment3D:
				var bone := (ancestor as BoneAttachment3D).bone_name
				for arm_bone in ARM_BONES:
					arm = arm or bone.begins_with(arm_bone) # also 'hand.L.001'
				break
			ancestor = ancestor.get_parent()
		var xform := _transform_to(mi, root, skeleton)
		for s in mi.mesh.get_surface_count():
			var vertices: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in vertices:
				var p := xform * v
				low = low.min(p)
				high = high.max(p)
				any = true
				if not arm:
					body_low = body_low.min(p)
					body_high = body_high.max(p)
	if not any:
		_fail("No mesh parts found; parent body parts to the bones")
		return
	var height := high.y - low.y
	if height < MIN_HEIGHT or height > MAX_HEIGHT:
		_fail("Height %.2f m is outside %.1f–%.1f m (Blender Z)" % [height, MIN_HEIGHT, MAX_HEIGHT])
	if absf(low.y) > FLOOR_TOLERANCE:
		_fail(
			"Lowest point is at %.2f m; the soles must rest on Z = 0 (±%.2f m)"
			% [low.y, FLOOR_TOLERANCE]
		)
	if body_low.x == INF:
		return
	# Godot +X = Blender +X (sideways); Godot +Z = Blender −Y (front-to-back).
	var side := maxf(absf(body_low.x), absf(body_high.x))
	if side > MAX_HALF_EXTENT:
		_fail(
			"Body (arms excluded) reaches %.2f m sideways (Blender X); the limit is ±%.1f m"
			% [side, MAX_HALF_EXTENT]
		)
	var depth := maxf(absf(body_low.z), absf(body_high.z))
	if depth > MAX_HALF_EXTENT:
		_fail(
			"Body (arms excluded) reaches %.2f m front-to-back (Blender Y); the limit is ±%.1f m"
			% [depth, MAX_HALF_EXTENT]
		)


## Rest-pose transform of `node` relative to `root`. Nodes under a
## `BoneAttachment3D` follow the bone's global rest (the scene isn't in the
## tree, so attachments haven't been posed).
static func _transform_to(node: Node, root: Node, skeleton: Skeleton3D = null) -> Transform3D:
	var xform := Transform3D.IDENTITY
	while node != null and node != root:
		if node is BoneAttachment3D and skeleton != null:
			xform = skeleton.get_bone_global_rest(
				skeleton.find_bone((node as BoneAttachment3D).bone_name)
			) * xform
		elif node is Node3D:
			xform = (node as Node3D).transform * xform
		node = node.get_parent()
	return xform


static func _load_reference() -> void:
	if not _reference_bones.is_empty():
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(REFERENCE, state) != OK:
		push_error("CharacterValidator: can't read reference '%s'" % REFERENCE)
		return
	var root := doc.generate_scene(state)
	var skeleton := CharacterLoader.find_skeleton(root)
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		_reference_bones[skeleton.get_bone_name(i)] = {
			"parent": skeleton.get_bone_name(parent) if parent != -1 else "",
			"rest": skeleton.get_bone_rest(i),
		}
	_reference_skeleton_transform = _transform_to(skeleton, root)
	root.free()

# --- Helpers ----------------------------------------------------------------


static func _array(dict: Variant, key: String) -> Array:
	var value: Variant = dict.get(key) if dict is Dictionary else null
	return value if value is Array else []


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else { }


## A JSON number that is a whole number, or -1.
static func _int(value: Variant) -> int:
	if (value is float or value is int) and value == floorf(value) and value >= 0 and value < 9.0e15:
		return int(value)
	return -1


static func _node_name(node: Dictionary, index: int) -> String:
	return node.name if node.get("name") is String else "node %d" % index


static func _quoted_or_none(name: String) -> String:
	return "'%s'" % name if not name.is_empty() else "none"


static func _short(text: Variant) -> String:
	var s := str(text)
	return s if s.length() <= 60 else s.left(57) + "..."


static func _bytes(count: int) -> String:
	return "%s bytes" % _thousands(count)


## 23410 -> "23,410".
static func _thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out
