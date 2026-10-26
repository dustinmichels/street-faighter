extends SceneTree
## Builds the game's shared animations from the pose tables below and saves
## them as an `AnimationLibrary` to `OUTPUT`. Rerun after editing a pose:
##
##     godot --headless --path . -s animations/build_base.gd
##
## Tracks are `Skeleton3D:<bone>` paths, so the library plays on any character
## with the template skeleton: put the `AnimationPlayer` next to the model's
## `Skeleton3D` (its default `root_node` is the parent).
##
## Poses are authored against the template skeleton (`docs/skeleton.md`):
## each bone's value is a rotation in degrees (Euler, Godot's default YXZ order)
## relative to the bone's rest pose, in the bone's own local axes. `.R` bones
## are written through `_m()`, which mirrors a `.L` rotation, so the same
## numbers mean the same motion on both sides:
##
## - Torso, neck, head: +X bends forward.
## - Thighs, shins: +X swings the limb backward (shin +X bends the knee).
## - Feet: +X points the toes down.
## - Arms: -X lowers from the T-pose, -Z swings forward (in the arm's own frame).
##
## `HIPS_POS` is an offset (meters) from the hips' rest position, in model space.
## The model faces +Z; gameplay turns the whole model to face the opponent.

const OUTPUT := "res://animations/base.res"
const REFERENCE := "res://characters/default/default.glb"
const HIPS_POS := &"hips_pos"
const BONES: PackedStringArray = [
	"hips", "spine", "chest", "neck", "head",
	"upper_arm.L", "forearm.L", "hand.L",
	"upper_arm.R", "forearm.R", "hand.R",
	"thigh.L", "shin.L", "foot.L",
	"thigh.R", "shin.R", "foot.R",
]


func _init() -> void:
	var err := ResourceSaver.save(build_library(), OUTPUT)
	if err != OK:
		push_error("can't save %s: %s" % [OUTPUT, error_string(err)])
	else:
		print("saved ", OUTPUT)
	quit(err)


## Fighting stance: left foot forward, knees bent, fists up guarding the face.
static var STANCE := {
	HIPS_POS: Vector3(0, -0.07, 0),
	"spine": Vector3(4, 0, 0),
	"chest": Vector3(4, 0, 0),
	"neck": Vector3(-4, 0, 0),
	"head": Vector3(-4, 0, 0),
	"upper_arm.L": Vector3(-75, 0, -20),
	"forearm.L": Vector3(0, 0, -135),
	"upper_arm.R": _m(Vector3(-75, 0, -12)),
	"forearm.R": _m(Vector3(0, 0, -140)),
	"thigh.L": Vector3(-30, 0, -4),
	"shin.L": Vector3(40, 0, 0),
	"foot.L": Vector3(-10, 0, 0),
	"thigh.R": _m(Vector3(15, 0, -4)),
	"shin.R": Vector3(15, 0, 0),
	"foot.R": Vector3(-30, 0, 0),
}

## Mirrors a `.L` rotation for the matching `.R` bone.
static func _m(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.y, -v.z)


## `base` with `over` applied on top (a pose that only lists what changes).
static func _pose(base: Dictionary, over: Dictionary) -> Dictionary:
	var p := base.duplicate()
	p.merge(over, true)
	return p


## `base` with each value in `delta` added to it (a small change from a pose).
static func _add(base: Dictionary, delta: Dictionary) -> Dictionary:
	var p := base.duplicate()
	for k in delta:
		p[k] = p.get(k, Vector3.ZERO) + delta[k]
	return p


## Idle: the stance with a slow breathing bob. Loops.
static func idle() -> Array:
	var breathe_in := _add(STANCE, {
		HIPS_POS: Vector3(0, -0.015, 0),
		"chest": Vector3(-2, 0, 0),
		"thigh.L": Vector3(-3, 0, 0),
		"shin.L": Vector3(6, 0, 0),
		"foot.L": Vector3(-3, 0, 0),
		"thigh.R": Vector3(-3, 0, 0),
		"shin.R": Vector3(6, 0, 0),
		"foot.R": Vector3(-3, 0, 0),
		"upper_arm.L": Vector3(2, 0, 0),
		"upper_arm.R": Vector3(2, 0, 0),
	})
	return [[0.0, STANCE], [0.5, breathe_in], [1.0, STANCE]]


## Walk: a guarded shuffle (front foot steps, back foot follows). Loops; play it
## backwards to walk back.
static func walk() -> Array:
	var front_step := _add(STANCE, {
		"spine": Vector3(2, 0, 0),
		"thigh.L": Vector3(-20, 0, 0),
		"shin.L": Vector3(15, 0, 0),
		"foot.L": Vector3(5, 0, 0),
		"thigh.R": Vector3(7, 0, 0),
		"shin.R": Vector3(-11, 0, 0),
		"foot.R": Vector3(4, 0, 0),
	})
	var back_step := _add(STANCE, {
		"spine": Vector3(-2, 0, 0),
		"thigh.R": Vector3(-30, 0, 0),
		"shin.R": Vector3(45, 0, 0),
		"foot.R": Vector3(-15, 0, 0),
	})
	return [[0.0, STANCE], [0.2, front_step], [0.4, STANCE], [0.6, back_step], [0.8, STANCE]]


## Deep crouch with both feet planted: wind-up for a jump and the landing squash.
static var CROUCH := _pose(STANCE, {
	HIPS_POS: Vector3(0, -0.25, 0),
	"spine": Vector3(15, 0, 0),
	"chest": Vector3(6, 0, 0),
	"neck": Vector3(-8, 0, 0),
	"head": Vector3(-8, 0, 0),
	"thigh.L": Vector3(-55, 0, -6),
	"shin.L": Vector3(85, 0, 0),
	"foot.L": Vector3(-30, 0, 0),
	"thigh.R": _m(Vector3(-20, 0, -6)),
	"shin.R": Vector3(82, 0, 0),
	"foot.R": Vector3(-62, 0, 0),
})

## Legs straight and toes pointed, as the feet leave the ground.
static var EXTENDED := _pose(STANCE, {
	HIPS_POS: Vector3(0, 0.09, 0),
	"spine": Vector3(-2, 0, 0),
	"chest": Vector3(0, 0, 0),
	"thigh.L": Vector3(-8, 0, -3),
	"shin.L": Vector3(6, 0, 0),
	"foot.L": Vector3(35, 0, 0),
	"thigh.R": _m(Vector3(6, 0, -3)),
	"shin.R": Vector3(6, 0, 0),
	"foot.R": Vector3(35, 0, 0),
})

## Knees tucked up, airborne.
static var TUCK := _pose(STANCE, {
	HIPS_POS: Vector3(0, 0.0, 0),
	"spine": Vector3(10, 0, 0),
	"chest": Vector3(4, 0, 0),
	"thigh.L": Vector3(-75, 0, -6),
	"shin.L": Vector3(100, 0, 0),
	"foot.L": Vector3(15, 0, 0),
	"thigh.R": _m(Vector3(-55, 0, -6)),
	"shin.R": Vector3(110, 0, 0),
	"foot.R": Vector3(15, 0, 0),
})


## Jump takeoff: crouch, then spring up to `EXTENDED`. Launch the body (give it
## upward velocity) when this ends, then play `jump_air`.
static func jump_start() -> Array:
	return [[0.0, STANCE], [0.05, CROUCH], [0.1, CROUCH], [0.15, EXTENDED]]


## Airborne: from `EXTENDED` into the tuck, then holds it until landing.
static func jump_air() -> Array:
	return [[0.0, EXTENDED], [0.25, TUCK]]


## Landing: absorb into a crouch, then rise back to the stance; ends in idle's
## first pose.
static func jump_land() -> Array:
	return [[0.0, CROUCH], [0.06, CROUCH], [0.2, STANCE]]


## Punch timing at 60 fps: 5 startup, 3 active, 12 recovery frames. The punch
## clip carries these as markers (`active_start`, `active_end`) so gameplay can
## turn the hitbox on and off without repeating the numbers.
const PUNCH_ACTIVE_START := 5.0 / 60.0
const PUNCH_ACTIVE_END := 8.0 / 60.0
const PUNCH_LENGTH := 20.0 / 60.0

## Right straight fully extended: torso turned left so the right shoulder leads.
static var PUNCH := _pose(STANCE, {
	HIPS_POS: Vector3(0, -0.08, 0.03),
	"hips": Vector3(0, 10, 0),
	"spine": Vector3(8, 12, 0),
	"chest": Vector3(4, 12, 0),
	"neck": Vector3(-6, -12, 0),
	"head": Vector3(-6, -10, 0),
	"upper_arm.R": _m(Vector3(0, -12, -82)),
	"forearm.R": _m(Vector3(0, 0, -5)),
	"upper_arm.L": Vector3(-78, 0, -12),
	"forearm.L": Vector3(0, 0, -145),
	"thigh.L": Vector3(-34, 0, -4),
	"shin.L": Vector3(42, 0, 0),
	"foot.L": Vector3(-8, 0, 0),
	"thigh.R": _m(Vector3(22, 0, -4)),
	"shin.R": Vector3(8, 0, 0),
	"foot.R": Vector3(-25, 0, 0),
})


## Punch (right hand): startup (wind back slightly, then extend), active (held
## at full reach), recovery (back to the stance).
static func punch() -> Array:
	var windup := _add(STANCE, {
		"hips": Vector3(0, -6, 0),
		"chest": Vector3(0, -6, 0),
		"upper_arm.R": _m(Vector3(0, 0, 8)),
	})
	return [
		[0.0, STANCE],
		[2.0 / 60.0, windup],
		[PUNCH_ACTIVE_START, PUNCH],
		[PUNCH_ACTIVE_END, PUNCH],
		[PUNCH_LENGTH, STANCE],
	]


## Flat on the back on the floor, feet toward where the fighter stood (the
## hips end 0.8 m behind their start), arms out at the sides.
static var LYING := _pose(STANCE, {
	HIPS_POS: Vector3(0, -0.83, -0.8),
	"hips": Vector3(-90, 0, 0),
	"spine": Vector3(0, 0, 0),
	"chest": Vector3(0, 0, 0),
	"neck": Vector3(5, 0, 0),
	"head": Vector3(5, 0, 0),
	"upper_arm.L": Vector3(-35, 0, 0),
	"forearm.L": Vector3(0, 0, -20),
	"upper_arm.R": _m(Vector3(-35, 0, 0)),
	"forearm.R": _m(Vector3(0, 0, -20)),
	"thigh.L": Vector3(-8, 0, -4),
	"shin.L": Vector3(12, 0, 0),
	"foot.L": Vector3(25, 0, 0),
	"thigh.R": _m(Vector3(-5, 0, -6)),
	"shin.R": Vector3(10, 0, 0),
	"foot.R": Vector3(30, 0, 0),
})


## Knockdown: snaps back from the blow, topples backward, lands on the back with
## a small bounce and stays down (holds the last frame).
static func knockdown() -> Array:
	var recoil := _pose(STANCE, {
		HIPS_POS: Vector3(0, -0.06, -0.08),
		"hips": Vector3(-12, 0, 0),
		"spine": Vector3(-10, 0, 0),
		"chest": Vector3(-8, 0, 0),
		"neck": Vector3(-15, 0, 0),
		"head": Vector3(-20, 0, 0),
		"upper_arm.L": Vector3(-50, 0, 15),
		"forearm.L": Vector3(0, 0, -60),
		"upper_arm.R": _m(Vector3(-50, 0, 15)),
		"forearm.R": _m(Vector3(0, 0, -60)),
		"thigh.L": Vector3(-25, 0, -4),
		"shin.L": Vector3(35, 0, 0),
		"foot.L": Vector3(2, 0, 0),
		"thigh.R": _m(Vector3(-10, 0, -4)),
		"shin.R": Vector3(45, 0, 0),
		"foot.R": Vector3(-23, 0, 0),
	})
	# Knees buckle and the body sits back toward the heels.
	var sit := _pose(STANCE, {
		HIPS_POS: Vector3(0, -0.3, -0.3),
		"hips": Vector3(-30, 0, 0),
		"spine": Vector3(-8, 0, 0),
		"chest": Vector3(-5, 0, 0),
		"neck": Vector3(5, 0, 0),
		"head": Vector3(0, 0, 0),
		"upper_arm.L": Vector3(-35, 0, 25),
		"forearm.L": Vector3(0, 0, -45),
		"upper_arm.R": _m(Vector3(-35, 0, 25)),
		"forearm.R": _m(Vector3(0, 0, -45)),
		"thigh.L": Vector3(-40, 0, -4),
		"shin.L": Vector3(70, 0, 0),
		"foot.L": Vector3(0, 0, 0),
		"thigh.R": _m(Vector3(-40, 0, -4)),
		"shin.R": Vector3(70, 0, 0),
		"foot.R": Vector3(0, 0, 0),
	})
	var falling := _pose(STANCE, {
		HIPS_POS: Vector3(0, -0.46, -0.45),
		"hips": Vector3(-55, 0, 0),
		"spine": Vector3(-5, 0, 0),
		"chest": Vector3(-5, 0, 0),
		"neck": Vector3(15, 0, 0),
		"head": Vector3(10, 0, 0),
		"upper_arm.L": Vector3(-20, 0, 25),
		"forearm.L": Vector3(0, 0, -40),
		"upper_arm.R": _m(Vector3(-20, 0, 25)),
		"forearm.R": _m(Vector3(0, 0, -40)),
		"thigh.L": Vector3(-42, 0, -4),
		"shin.L": Vector3(90, 0, 0),
		"foot.L": Vector3(15, 0, 0),
		"thigh.R": _m(Vector3(-42, 0, -4)),
		"shin.R": Vector3(90, 0, 0),
		"foot.R": Vector3(15, 0, 0),
	})
	# Back hits the floor; the legs swing up.
	var impact := _pose(falling, {
		HIPS_POS: Vector3(0, -0.68, -0.68),
		"hips": Vector3(-75, 0, 0),
		"spine": Vector3(0, 0, 0),
		"chest": Vector3(0, 0, 0),
		"thigh.L": Vector3(-40, 0, -4),
		"shin.L": Vector3(60, 0, 0),
		"foot.L": Vector3(15, 0, 0),
		"thigh.R": _m(Vector3(-35, 0, -5)),
		"shin.R": Vector3(55, 0, 0),
		"foot.R": Vector3(15, 0, 0),
	})
	var bounce := _add(LYING, {
		HIPS_POS: Vector3(0, 0.05, 0),
		"spine": Vector3(8, 0, 0),
		"neck": Vector3(10, 0, 0),
		"thigh.L": Vector3(-15, 0, 0),
		"shin.L": Vector3(10, 0, 0),
		"thigh.R": Vector3(-12, 0, 0),
		"shin.R": Vector3(8, 0, 0),
		"upper_arm.L": Vector3(0, 0, -10),
		"upper_arm.R": Vector3(0, 0, -10),
	})
	return [
		[0.0, STANCE],
		[0.1, recoil],
		[0.22, sit],
		[0.35, falling],
		[0.45, impact],
		[0.55, LYING],
		[0.68, bounce],
		[0.85, LYING],
	]


## Name → [length (s), loop, cubic, keys, markers]. Keys are [time, pose]
## pairs; markers (optional) map a name to a time.
static func clips() -> Dictionary:
	return {
		&"idle": [1.0, true, true, idle()],
		&"jump_start": [0.15, false, true, jump_start()],
		&"jump_air": [0.25, false, true, jump_air()],
		&"jump_land": [0.2, false, true, jump_land()],
		&"knockdown": [0.85, false, true, knockdown()],
		&"punch": [PUNCH_LENGTH, false, false, punch(),
			{&"active_start": PUNCH_ACTIVE_START, &"active_end": PUNCH_ACTIVE_END}],
		&"walk": [0.8, true, true, walk()],
	}


## Builds one `Animation` from `[time, pose]` keys. Every bone gets a rotation
## track (unlisted bones hold their rest pose) plus a hips position track, so a
## clip fully defines the pose and never leaks bones from the previous clip.
static func build(length: float, loop: bool, cubic: bool, keys: Array, rest: Dictionary, markers := {}) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var interp := Animation.INTERPOLATION_CUBIC if cubic else Animation.INTERPOLATION_LINEAR
	for marker in markers:
		anim.add_marker(marker, markers[marker])
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, "Skeleton3D:hips")
	anim.track_set_interpolation_type(pos_track, interp)
	for key in keys:
		var t: float = key[0]
		var pose: Dictionary = key[1]
		anim.position_track_insert_key(pos_track, t, rest[HIPS_POS] + pose.get(HIPS_POS, Vector3.ZERO))
	for bone in BONES:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, "Skeleton3D:" + bone)
		anim.track_set_interpolation_type(track, interp)
		for key in keys:
			var t: float = key[0]
			var pose: Dictionary = key[1]
			var deg: Vector3 = pose.get(bone, Vector3.ZERO)
			var delta := Quaternion.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))
			anim.rotation_track_insert_key(track, t, rest[bone] * delta)
	return anim


## Rest rotations of every bone (and the hips' rest position) from the
## reference character, which carries the template skeleton unchanged.
static func reference_rest() -> Dictionary:
	var root := CharacterLoader.load_character(REFERENCE)
	assert(root != null, "can't load " + REFERENCE)
	var skeleton := CharacterLoader.find_skeleton(root)
	var rest := {}
	for bone in BONES:
		rest[bone] = skeleton.get_bone_rest(skeleton.find_bone(bone)).basis.get_rotation_quaternion()
	rest[HIPS_POS] = skeleton.get_bone_rest(skeleton.find_bone("hips")).origin
	root.free()
	return rest


## All clips as an `AnimationLibrary`.
static func build_library() -> AnimationLibrary:
	var rest := reference_rest()
	var lib := AnimationLibrary.new()
	var all := clips()
	for clip_name in all:
		var c: Array = all[clip_name]
		lib.add_animation(clip_name, build(c[0], c[1], c[2], c[3], rest, c[4] if c.size() > 4 else {}))
	return lib
