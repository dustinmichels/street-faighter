class_name FollowCamera
extends PixelCamera
## Side camera that keeps the midpoint of `fighters` centered along world X,
## clamped so it never shows past the `stage` walls' outer faces. Height and
## depth stay where the scene puts them. Runs on the physics tick after the
## fighters (it comes after them in the tree), so it sees this tick's positions.
##
## The view isn't flat side-on: the scene's side view is swung `view_yaw`
## around the vertical axis, so a little of the fighters' and the street's
## depth shows. Following still slides the camera along world X. The fighter
## ahead on health pulls the swing its way (`lead_yaw`), so the camera turns
## to show the leader from the front; the view eases there at
## `lead_yaw_speed`.
##
## On ready it first plays an intro: it starts swung `intro_yaw` further around
## the fighters and tilted `intro_pitch` further down, zoomed by `intro_zoom`,
## and eases back into the resting view over `intro_duration` seconds
## (wall-clock, display only), then emits `intro_finished` and starts
## following. The orbit pivots on the point at the fighters' depth (z = 0)
## that the resting view is centered on. The stage walls are hidden meanwhile.
##
## When a sweep knocks a fighter over (`Fighter.sweep_impact_ticks()`) the
## view shakes lightly for `SHAKE_TICKS`; when the special throw slams one
## into the floor (`Fighter.slam_impact_ticks()`, timed by the thrower so a
## KO slam shakes too) it shakes harder (`throw_shake_pixels`,
## `THROW_SHAKE_TICKS`). Display only, timed by simulation ticks, so
## rollbacks agree with the simulation.

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
## Degrees added to `view_yaw` at a full health lead, toward the side the
## leader faces (the camera then sees it from the front); scales with the
## health difference, so even health keeps `view_yaw`.
@export_range(0.0, 30.0) var lead_yaw := 20.0
## How fast the view swings to a changed lead (degrees per second).
@export_range(1.0, 180.0) var lead_yaw_speed := 12.0
## Length of the intro swing (s); 0 skips it.
@export_range(0.0, 10.0, 0.1) var intro_duration := 2.5
## Where the intro starts: degrees further around the vertical axis than the
## resting view (positive swings the camera to the right of the stage)...
@export_range(-180.0, 180.0) var intro_yaw := 35.0
## ...degrees tilted further down than the resting view...
@export_range(-60.0, 70.0) var intro_pitch := 15.0
## ...and `size` multiplier.
@export_range(0.1, 4.0) var intro_zoom := 1.0
## Shake when a sweep lands: starting offset in screen pixels, fading out
## over `SHAKE_TICKS`.
@export_range(0.0, 8.0, 0.5) var shake_pixels := 2.0
## Ticks the shake lasts after a sweep lands (0.2 s).
const SHAKE_TICKS := 12
## Shake when the special throw slams the opponent down: starting offset in
## screen pixels, fading out over `THROW_SHAKE_TICKS`.
@export_range(0.0, 16.0, 0.5) var throw_shake_pixels := 6.0
## Ticks the shake lasts after a throw slam (0.3 s): the rest of the
## thrower's `throw` state after the slam (`THROW_LENGTH - THROW_SLAM`).
const THROW_SHAKE_TICKS := 18

## Seconds of intro played; negative once it is over.
var _intro_time := -1.0
## The resting view the intro settles into.
var _rest_basis: Basis
var _rest_size: float
var _pivot: Vector3
## The scene's unswung side view: its basis, and the camera's offset from
## the point at the fighters' depth (z = 0) it is centered on.
var _side_basis: Basis
var _side_offset: Vector3
## X of that point in the scene, held when there are no fighters to follow.
var _home_x := 0.0
## Current swing around the vertical axis (degrees), easing toward
## `_lead_yaw()`.
var _yaw := 0.0


func _ready() -> void:
	# Keep the scene's side view; `_follow()` swings it by `_yaw` around the
	# point at the fighters' depth it is centered on.
	var pivot := _center_at_fighters()
	_side_basis = global_basis
	_side_offset = global_position - Vector3(pivot.x, 0.0, 0.0)
	_home_x = pivot.x
	_yaw = _lead_yaw()
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
	size = _rest_size
	_set_walls_visible(true)
	_follow()
	# Their visuals were last snapped to the intro's start pose.
	for f in fighters:
		f.sync_visual()
	intro_finished.emit()


func _physics_process(delta: float) -> void:
	if _intro_time >= 0.0:
		return
	var yaw := move_toward(_yaw, _lead_yaw(), lead_yaw_speed * delta)
	var turned := yaw != _yaw
	_yaw = yaw
	_follow()
	_shake()
	if turned:
		# `Match` snapped their visuals along the previous view's axes.
		for f in fighters:
			f.sync_visual()


## `view_yaw` swung toward the side the fighter ahead on health faces, by
## `lead_yaw` times the health difference over `Fighter.MAX_HEALTH`.
## Positive yaw moves the camera to the right, where it sees the front of a
## fighter facing +X. Uses the leader's `facing`: it only turns in neutral
## states, so a cross-up jump doesn't flip the view mid-air.
func _lead_yaw() -> float:
	if fighters.size() < 2:
		return view_yaw
	var a := fighters[0]
	var b := fighters[1]
	var leader := a if a.health >= b.health else b
	var lead := float(absi(a.health - b.health)) / Fighter.MAX_HEALTH
	return view_yaw + lead_yaw * lead * leader.facing


## While a fighter has just been swept (first `SHAKE_TICKS` of
## `Fighter.sweep_impact_ticks()`) or has just slammed its throw victim down
## (first `THROW_SHAKE_TICKS` of `Fighter.slam_impact_ticks()`), offsets the
## view from its followed position along the screen's axes: up to
## `shake_pixels` (`throw_shake_pixels` for a slam), shrinking linearly,
## changing direction every tick. The strongest shake wins. Snapped like any
## position, so it moves in whole pixels. The next `_follow()` puts the view
## back.
func _shake() -> void:
	var amount := 0.0
	var ticks := 0
	for f in fighters:
		for impact: Vector3 in [
			Vector3(f.sweep_impact_ticks(), SHAKE_TICKS, shake_pixels),
			Vector3(f.slam_impact_ticks(), THROW_SHAKE_TICKS, throw_shake_pixels),
		]:
			if impact.x < 0.0 or impact.x >= impact.y:
				continue
			var a := impact.z * (1.0 - impact.x / impact.y)
			if a > amount:
				amount = a
				ticks = int(impact.x)
	if amount <= 0.0:
		return
	var b := global_basis.orthonormalized()
	var offset := b.x * sin(ticks * 2.4) + b.y * cos(ticks * 3.1) * 0.5
	global_position = snap(target_position + offset * amount * pixel_size())


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


## Swings the view by `_yaw` and slides it so the fighters' X midpoint is
## centered, clamped to the stage.
func _follow() -> void:
	var swing := Basis(Vector3.UP, deg_to_rad(_yaw))
	global_basis = swing * _side_basis
	var mid := _home_x
	if not fighters.is_empty():
		mid = 0.0
		for f in fighters:
			mid += f.global_position.x
		mid /= fighters.size()
	if stage != null:
		var limit := maxf(stage.outer_half_width() - half_view_width(), 0.0)
		mid = clampf(mid, stage.global_position.x - limit, stage.global_position.x + limit)
	target_position = Vector3(mid, 0.0, 0.0) + swing * _side_offset
