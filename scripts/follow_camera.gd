class_name FollowCamera
extends PixelCamera
## Side camera that keeps the midpoint of `fighters` centered along world X,
## clamped so it never shows past the `stage` walls' outer faces. Height and
## depth stay where the scene puts them. Runs on the physics tick after the
## fighters (it comes after them in the tree), so it sees this tick's positions.
##
## The view isn't flat side-on: on ready the scene's side view is swung
## `view_yaw` around the vertical axis, so a little of the fighters' and the
## street's depth shows. Following still slides the camera along world X.
##
## On ready it first plays an intro: it starts swung `intro_yaw` further around
## the fighters and tilted `intro_pitch` further down, zoomed by `intro_zoom`,
## and eases back into the resting view over `intro_duration` seconds
## (wall-clock, display only), then emits `intro_finished` and starts
## following. The orbit pivots on the point at the fighters' depth (z = 0)
## that the resting view is centered on. The stage walls are hidden meanwhile.

## Emitted once the intro has settled into the resting view (right away,
## during `_ready()`, when `intro_duration` is 0).
signal intro_finished

## Fighters to keep centered (their midpoint along X).
@export var fighters: Array[Fighter] = []
## Bounds the view; null means no clamping.
@export var stage: Stage
## Degrees the resting view is swung around the vertical axis from straight
## side-on (positive moves the camera to the right of the stage); 0 is flat 2D.
@export_range(-30.0, 30.0) var view_yaw := 10.0
## Length of the intro swing (s); 0 skips it.
@export_range(0.0, 10.0, 0.1) var intro_duration := 2.5
## Where the intro starts: degrees further around the vertical axis than the
## resting view (positive swings the camera to the right of the stage)...
@export_range(-180.0, 180.0) var intro_yaw := 35.0
## ...degrees tilted further down than the resting view...
@export_range(-60.0, 70.0) var intro_pitch := 15.0
## ...and `size` multiplier.
@export_range(0.1, 4.0) var intro_zoom := 1.0

## Seconds of intro played; negative once it is over.
var _intro_time := -1.0
## The resting view the intro settles into.
var _rest_basis: Basis
var _rest_size: float
var _pivot: Vector3
## Camera X minus the X of the point at the fighters' depth it centers on
## (nonzero once yawed).
var _follow_offset := 0.0


func _ready() -> void:
	# Swing the scene's side view by `view_yaw` around the point at the
	# fighters' depth (z = 0) it is centered on, before `PixelCamera` takes
	# its position as the target.
	var pivot := _center_at_fighters()
	var yaw := Basis(Vector3.UP, deg_to_rad(view_yaw))
	global_transform = Transform3D(yaw * global_basis, pivot + yaw * (global_position - pivot))
	_follow_offset = global_position.x - pivot.x
	super()
	_follow()
	if intro_duration <= 0.0:
		intro_finished.emit()
		return
	_rest_basis = global_basis
	_rest_size = size
	_pivot = _center_at_fighters()
	_intro_time = 0.0
	_set_walls_visible(false)
	_pose_intro(0.0)


## Where the view axis meets the fighters' plane (z = 0).
func _center_at_fighters() -> Vector3:
	var forward := -global_basis.z
	return global_position + forward * (-global_position.z / forward.z)


func _process(delta: float) -> void:
	if _intro_time < 0.0:
		return
	_intro_time += delta
	if _intro_time < intro_duration:
		_pose_intro(_intro_time / intro_duration)
		return
	_intro_time = -1.0
	global_basis = _rest_basis
	size = _rest_size
	_set_walls_visible(true)
	_follow()
	# Their visuals were last snapped to the intro's start pose.
	for f in fighters:
		f.sync_visual()
	intro_finished.emit()


func _physics_process(_delta: float) -> void:
	if _intro_time < 0.0:
		_follow()


## Whether the intro is still playing.
func in_intro() -> bool:
	return _intro_time >= 0.0


## Places the camera `t` (0..1) of the way from the intro's start pose to the
## resting view, eased in and out.
func _pose_intro(t: float) -> void:
	var left := 1.0 - ease(t, -2.5)
	var swing := Basis(Vector3.UP, deg_to_rad(intro_yaw * left)) \
			* Basis(_rest_basis.x, deg_to_rad(-intro_pitch * left))
	global_transform = Transform3D(swing * _rest_basis, _pivot + swing * (target_position - _pivot))
	size = _rest_size * lerpf(1.0, intro_zoom, left)


## The stage walls would stand between the swung camera and the fighters, and
## the resting view doesn't show them while the fighters are at their start
## (centered), so the intro hides them.
func _set_walls_visible(on: bool) -> void:
	if stage != null:
		stage.wall_left.visible = on
		stage.wall_right.visible = on


## Half the visible width along X (m) at the fighters' depth: orthographic
## `size` is the height, and the yaw stretches the screen's span along X.
func half_view_width() -> float:
	return pixel_size() * get_viewport().get_visible_rect().size.x * 0.5 \
			/ absf(global_basis.x.normalized().x)


func _follow() -> void:
	if fighters.is_empty():
		return
	var mid := 0.0
	for f in fighters:
		mid += f.global_position.x
	mid /= fighters.size()
	if stage != null:
		var limit := maxf(stage.outer_half_width() - half_view_width(), 0.0)
		mid = clampf(mid, stage.global_position.x - limit, stage.global_position.x + limit)
	var p := target_position
	p.x = mid + _follow_offset
	target_position = p
