class_name FollowCamera
extends PixelCamera
## Side camera that keeps the midpoint of `fighters` centered along world X,
## clamped so it never shows past the `stage` walls' outer faces. Height and
## depth stay where the scene puts them. Runs on the physics tick after the
## fighters (it comes after them in the tree), so it sees this tick's positions.
##
## On ready it first plays an intro: it starts swung `intro_yaw` around the
## fighters and tilted `intro_pitch` further down, zoomed out by
## `intro_zoom`, and eases back into the side view over `intro_duration`
## seconds (wall-clock, display only), then emits `intro_finished` and starts
## following. The orbit pivots on the point at the fighters' depth (z = 0)
## that the side view is centered on.

## Emitted once the intro has settled into the side view (right away, during
## `_ready()`, when `intro_duration` is 0).
signal intro_finished

## Fighters to keep centered (their midpoint along X).
@export var fighters: Array[Fighter] = []
## Bounds the view; null means no clamping.
@export var stage: Stage
## Length of the intro swing (s); 0 skips it.
@export_range(0.0, 10.0, 0.1) var intro_duration := 2.5
## Where the intro starts: degrees around the vertical axis (positive swings
## the camera to the right of the stage)...
@export_range(-180.0, 180.0) var intro_yaw := 30.0
## ...degrees tilted further down than the side view...
@export_range(-60.0, 70.0) var intro_pitch := 50.0
## ...and `size` multiplier.
@export_range(0.1, 4.0) var intro_zoom := 1.6

## Seconds of intro played; negative once it is over.
var _intro_time := -1.0
## The side view the intro settles into.
var _rest_basis: Basis
var _rest_size: float
var _pivot: Vector3


func _ready() -> void:
	super()
	_follow()
	if intro_duration <= 0.0:
		intro_finished.emit()
		return
	_rest_basis = global_basis
	_rest_size = size
	# Where the view axis meets the fighters' plane (z = 0).
	var forward := -_rest_basis.z
	_pivot = global_position + forward * (-global_position.z / forward.z)
	_intro_time = 0.0
	_pose_intro(0.0)


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
## side view, eased in and out.
func _pose_intro(t: float) -> void:
	var left := 1.0 - ease(t, -2.5)
	var swing := Basis(Vector3.UP, deg_to_rad(intro_yaw * left)) \
			* Basis(_rest_basis.x, deg_to_rad(-intro_pitch * left))
	global_transform = Transform3D(swing * _rest_basis, _pivot + swing * (target_position - _pivot))
	size = _rest_size * lerpf(1.0, intro_zoom, left)


## Half the visible width along X (m): orthographic `size` is the height.
func half_view_width() -> float:
	return pixel_size() * get_viewport().get_visible_rect().size.x * 0.5


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
	p.x = mid
	target_position = p
