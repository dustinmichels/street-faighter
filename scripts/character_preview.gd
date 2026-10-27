class_name CharacterPreview
extends SubViewportContainer
## A small turning view of one character for the library:
## its own 3D world with the in-game
## look (toon materials from `CharacterLoader`, the outline post-process,
## an orthographic camera at about the in-game pixel scale), the model playing
## `idle`. `punch()` plays the punch once, to check that the parts follow the
## bones.

## Turning speed of the model, radians per second.
const TURN_SPEED := 0.6
## Vertical extent of the camera in meters; ~1.8 m fighters fill most of it.
const CAMERA_SIZE := 2.3
const BACKGROUND := Color(0.07, 0.07, 0.13)
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")

## Path of the shown model ("" when empty or it failed to load).
var path := ""

var _viewport: SubViewport
var _pivot: Node3D
var _model: Node3D
var _anim: AnimationPlayer


func _init() -> void:
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.85)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.light_color = Color(0.85, 0.88, 1.0)
	light.light_energy = 0.9
	light.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(25.0), 0.0)
	_viewport.add_child(light)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_SIZE
	camera.near = 0.1
	camera.far = 20.0
	camera.position = Vector3(0.0, 0.95, 6.0)
	camera.current = true
	_viewport.add_child(camera)
	# Same post-process as `main.tscn`: a full-screen quad on the camera.
	var outline_material := ShaderMaterial.new()
	outline_material.shader = OUTLINE_SHADER
	outline_material.render_priority = 100
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.flip_faces = true
	quad.material = outline_material
	var outline := MeshInstance3D.new()
	outline.mesh = quad
	outline.extra_cull_margin = 16384.0
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(outline)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)


func _process(delta: float) -> void:
	if _model != null and is_visible_in_tree():
		_pivot.rotate_y(TURN_SPEED * delta)


## Shows the character at `model_path` ("" clears the view). Returns false if
## it can't be loaded (the view is then empty).
func show_character(model_path: String) -> bool:
	if model_path == path:
		return true
	clear()
	if model_path.is_empty():
		return true
	var model := CharacterLoader.load_character(model_path)
	if model == null:
		return false
	path = model_path
	_model = model
	var skeleton := CharacterLoader.find_skeleton(model)
	# Tracks are `Skeleton3D:<bone>`, resolved from the player's parent (as in
	# `Fighter.set_character`).
	_anim = AnimationPlayer.new()
	_anim.add_animation_library(&"", Fighter.ANIMATIONS)
	skeleton.get_parent().add_child(_anim)
	_pivot.rotation = Vector3.ZERO
	_pivot.add_child(model)
	_anim.play(&"idle")
	return true


## Removes the shown model.
func clear() -> void:
	path = ""
	_anim = null
	if _model != null:
		_model.free()
		_model = null


## Plays the punch once, then goes back to `idle`.
func punch() -> void:
	if _anim == null:
		return
	_anim.play(&"punch")
	_anim.queue(&"idle")
