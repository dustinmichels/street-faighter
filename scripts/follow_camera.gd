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
##
## While `player` sweeps (`Fighter.State.SWEEP`), the view orbits one full
## turn around the same kind of pivot, timed by the sweep's `state_ticks`
## (display only, so rollbacks agree with the simulation), the opposite way to
## the kicker's own spin so that spin stays visible. The backdrop dims
## meanwhile (shader global `backdrop_dim`, see `toon.gdshader`) so the
## fighters stand out. The opponent's sweeps leave the view alone.

## Emitted once the intro has settled into the resting view (right away,
## during `_ready()`, when `intro_duration` is 0).
signal intro_finished

## Fighters to keep centered (their midpoint along X).
@export var fighters: Array[Fighter] = []
## This machine's player (set by `Main`): only its sweeps spin the view. Null
## means no fighter's do.
var player: Fighter
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
## While the view orbits for a sweep, how far (m) in front of the nearest
## fighter the camera comes, measured along the ground. The camera moves in
## that close, so from behind the street the buildings and props are behind
## it (clipped), not between it and the fighters.
@export_range(0.3, 5.0, 0.1) var spin_clearance := 1.2

## Seconds of intro played; negative once it is over.
var _intro_time := -1.0
## The resting view the intro settles into.
var _rest_basis: Basis
var _rest_size: float
var _pivot: Vector3
## Camera X minus the X of the point at the fighters' depth it centers on
## (nonzero once yawed).
var _follow_offset := 0.0
## The view is currently orbiting for a sweep (`_spin_for_sweep()`).
var _spinning := false
## Ticks the backdrop takes to dim at the start of a sweep's spin, and to
## come back at its end.
const DIM_FADE_TICKS := 4


func _enter_tree() -> void:
	# A scene reload can cut a spin short; never start dimmed.
	_set_backdrop_dim(0.0)


func _exit_tree() -> void:
	_set_backdrop_dim(0.0)


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
	_rest_basis = global_basis
	_rest_size = size
	if intro_duration <= 0.0:
		intro_finished.emit()
		return
	_pivot = _center_at_fighters()
	_intro_time = 0.0
	_set_walls_visible(false)
	_pose_intro(0.0)


## Where the view axis meets the fighters' plane (z = 0).
func _center_at_fighters() -> Vector3:
	return _center_at(global_position, global_basis)


## Where the view axis of a camera at `from` with basis `basis` meets the
## fighters' plane (z = 0).
static func _center_at(from: Vector3, basis: Basis) -> Vector3:
	var forward := -basis.z
	return from + forward * (-from.z / forward.z)


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
	if _intro_time >= 0.0:
		return
	if _spinning:
		# `_follow()` measures the view in the resting orientation.
		global_basis = _rest_basis
		_spinning = false
		_set_backdrop_dim(0.0)
	_follow()
	_spin_for_sweep()


## If `player` is sweeping, orbits the view around the point at the
## fighters' depth it is centered on, one full turn eased in and out over
## the sweep. Midway the camera comes in to `spin_clearance` in front of the
## nearest fighter; at both ends it is at the resting distance, so the orbit
## starts and ends without a jump. The backdrop is dimmed, fading in and out
## over `DIM_FADE_TICKS`. The fighters' visuals are re-snapped to the turned
## pixel grid.
func _spin_for_sweep() -> void:
	var kicker := player
	if kicker == null or kicker.state != Fighter.State.SWEEP:
		return
	_spinning = true
	var ticks := kicker.state_ticks
	_set_backdrop_dim(clampf(float(mini(ticks, Fighter.SWEEP_LENGTH - ticks)) / DIM_FADE_TICKS, 0.0, 1.0))
	var turn := smoothstep(0.0, 1.0, clampf(float(ticks) / Fighter.SWEEP_LENGTH, 0.0, 1.0))
	# The kicker's model spins toward +yaw mirrored by `facing`; go against it.
	var swing := Basis(Vector3.UP, -kicker.facing * TAU * turn)
	var pivot := _center_at(target_position, _rest_basis)
	var rest_distance := pivot.distance_to(target_position)
	var dir := swing * (target_position - pivot) / rest_distance
	var ground := Vector3(dir.x, 0.0, dir.z)
	var reach := 0.0
	for f in fighters:
		reach = maxf(reach, (f.global_position - pivot).dot(ground.normalized()))
	var close_distance := (reach + spin_clearance) / ground.length()
	var distance := lerpf(rest_distance, close_distance, sin(PI * turn))
	global_basis = swing * _rest_basis
	global_position = snap(pivot + dir * distance)
	for f in fighters:
		f.sync_visual()


## Sets the shader global that dims everything but the fighters (0 = normal,
## 1 = fully dimmed).
static func _set_backdrop_dim(amount: float) -> void:
	RenderingServer.global_shader_parameter_set(&"backdrop_dim", amount)


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
