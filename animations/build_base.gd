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
## Poses are authored against the template skeleton (`creator_kit/SKELETON.md`):
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
	var breathe_in := _add(
		STANCE,
		{
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
		},
	)
	return [[0.0, STANCE], [0.5, breathe_in], [1.0, STANCE]]


## Walk: a guarded shuffle (front foot steps, back foot follows). Loops; play it
## backwards to walk back.
static func walk() -> Array:
	var front_step := _add(
		STANCE,
		{
			"spine": Vector3(2, 0, 0),
			"thigh.L": Vector3(-20, 0, 0),
			"shin.L": Vector3(15, 0, 0),
			"foot.L": Vector3(5, 0, 0),
			"thigh.R": Vector3(7, 0, 0),
			"shin.R": Vector3(-11, 0, 0),
			"foot.R": Vector3(4, 0, 0),
		},
	)
	var back_step := _add(
		STANCE,
		{
			"spine": Vector3(-2, 0, 0),
			"thigh.R": Vector3(-30, 0, 0),
			"shin.R": Vector3(45, 0, 0),
			"foot.R": Vector3(-15, 0, 0),
		},
	)
	return [[0.0, STANCE], [0.2, front_step], [0.4, STANCE], [0.6, back_step], [0.8, STANCE]]


## Deep crouch with both feet planted: wind-up for a jump and the landing squash.
static var CROUCH := _pose(
	STANCE,
	{
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
	},
)

## Legs straight and toes pointed, as the feet leave the ground.
static var EXTENDED := _pose(
	STANCE,
	{
		HIPS_POS: Vector3(0, 0.09, 0),
		"spine": Vector3(-2, 0, 0),
		"chest": Vector3(0, 0, 0),
		"thigh.L": Vector3(-8, 0, -3),
		"shin.L": Vector3(6, 0, 0),
		"foot.L": Vector3(35, 0, 0),
		"thigh.R": _m(Vector3(6, 0, -3)),
		"shin.R": Vector3(6, 0, 0),
		"foot.R": Vector3(35, 0, 0),
	},
)

## Knees tucked up, airborne.
static var TUCK := _pose(
	STANCE,
	{
		HIPS_POS: Vector3(0, 0.0, 0),
		"spine": Vector3(10, 0, 0),
		"chest": Vector3(4, 0, 0),
		"thigh.L": Vector3(-75, 0, -6),
		"shin.L": Vector3(100, 0, 0),
		"foot.L": Vector3(15, 0, 0),
		"thigh.R": _m(Vector3(-55, 0, -6)),
		"shin.R": Vector3(110, 0, 0),
		"foot.R": Vector3(15, 0, 0),
	},
)


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
## clips (`punch`, `punch_left`) carry these as markers (`active_start`,
## `active_end`) so gameplay can turn the hitbox on and off without repeating
## the numbers. Both hands share the timing; gameplay alternates them.
const PUNCH_ACTIVE_START := 5.0 / 60.0
const PUNCH_ACTIVE_END := 8.0 / 60.0
const PUNCH_LENGTH := 20.0 / 60.0

## Right straight fully extended: torso turned left so the right shoulder leads.
static var PUNCH := _pose(
	STANCE,
	{
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
	},
)


## Left (lead) straight fully extended, `PUNCH` mirrored above the hips: torso
## turned right so the left shoulder leads, right fist guarding. The twist sits
## in the spine and chest so the hips (and feet) stay put in the stance. The
## fist ends where `PUNCH`'s does, so both hands share one hitbox.
static var PUNCH_LEFT := _pose(
	STANCE,
	{
		HIPS_POS: Vector3(0, -0.08, 0.02),
		"hips": Vector3(0, -3, 0),
		"spine": Vector3(8, -15, 0),
		"chest": Vector3(4, -15, 0),
		"neck": Vector3(-6, 15, 0),
		"head": Vector3(-6, 12, 0),
		"upper_arm.L": Vector3(0, -12, -82),
		"forearm.L": Vector3(0, 0, -5),
		"upper_arm.R": _m(Vector3(-78, 0, -12)),
		"forearm.R": _m(Vector3(0, 0, -145)),
	},
)


## Punch (right hand): startup (wind back slightly, then extend), active (held
## at full reach), recovery (back to the stance).
static func punch() -> Array:
	var windup := _add(
		STANCE,
		{
			"hips": Vector3(0, -6, 0),
			"chest": Vector3(0, -6, 0),
			"upper_arm.R": _m(Vector3(0, 0, 8)),
		},
	)
	return _punch_keys(windup, PUNCH)


## Punch with the left hand: `punch` mirrored above the hips.
static func punch_left() -> Array:
	var windup := _add(
		STANCE,
		{
			"hips": Vector3(0, 6, 0),
			"chest": Vector3(0, 6, 0),
			"upper_arm.L": Vector3(0, 0, 8),
		},
	)
	return _punch_keys(windup, PUNCH_LEFT)


## A punch's keys on the shared punch timing: `windup`, then `extended` held
## through the active frames, then back to the stance.
static func _punch_keys(windup: Dictionary, extended: Dictionary) -> Array:
	return [
		[0.0, STANCE],
		[2.0 / 60.0, windup],
		[PUNCH_ACTIVE_START, extended],
		[PUNCH_ACTIVE_END, extended],
		[PUNCH_LENGTH, STANCE],
	]


## Air kick timing at 60 fps: 4 startup, 12 active, 12 recovery frames; markers
## `active_start`/`active_end` like the punch. The long active window lets a
## kick thrown near the top of the jump still connect on the way down.
const AIR_KICK_ACTIVE_START := 4.0 / 60.0
const AIR_KICK_ACTIVE_END := 16.0 / 60.0
const AIR_KICK_LENGTH := 28.0 / 60.0

## Flying kick fully extended: front (left) leg straight, angled down-forward
## (≈30° below horizontal, heel leading), back leg tucked, torso leaning back to
## balance, fists still guarding.
static var AIR_KICK := _pose(
	TUCK,
	{
		"spine": Vector3(-10, 0, 0),
		"chest": Vector3(-4, 0, 0),
		"neck": Vector3(8, 0, 0),
		"head": Vector3(8, 0, 0),
		"thigh.L": Vector3(-60, 0, -4),
		"shin.L": Vector3(0, 0, 0),
		"foot.L": Vector3(-15, 0, 0),
		"thigh.R": _m(Vector3(-40, 0, -6)),
		"shin.R": Vector3(115, 0, 0),
		"foot.R": Vector3(20, 0, 0),
	},
)


## Air kick: chamber the knee, snap the leg out and hold it (active), then pull
## back into the jump's `TUCK`, which it holds until landing.
static func air_kick() -> Array:
	var chamber := _pose(
		TUCK,
		{ "spine": Vector3(-4, 0, 0), "thigh.L": Vector3(-95, 0, -4), "shin.L": Vector3(110, 0, 0) },
	)
	return [
		[0.0, TUCK],
		[2.0 / 60.0, chamber],
		[AIR_KICK_ACTIVE_START, AIR_KICK],
		[AIR_KICK_ACTIVE_END, AIR_KICK],
		[AIR_KICK_LENGTH, TUCK],
	]


## Time to raise the guard (4 frames at 60 fps); the clip holds it afterwards.
const BLOCK_LENGTH := 4.0 / 60.0

## Guard: a lower stance, torso hunched forward, both forearms raised in
## front of the face and chest.
static var BLOCK := _pose(
	STANCE,
	{
		HIPS_POS: Vector3(0, -0.16, -0.03),
		"spine": Vector3(18, 0, 0),
		"chest": Vector3(10, 0, 0),
		"neck": Vector3(-14, 0, 0),
		"head": Vector3(-10, 0, 0),
		"upper_arm.L": Vector3(-50, 0, -70),
		"forearm.L": Vector3(0, 0, -120),
		"upper_arm.R": _m(Vector3(-50, 0, -65)),
		"forearm.R": _m(Vector3(0, 0, -125)),
		"thigh.L": Vector3(-38, 0, -4),
		"shin.L": Vector3(52, 0, 0),
		"foot.L": Vector3(-14, 0, 0),
		"thigh.R": _m(Vector3(8, 0, -4)),
		"shin.R": Vector3(28, 0, 0),
		"foot.R": Vector3(-34, 0, 0),
	},
)


## Block: snap from the stance into the guard, then hold it while blocking.
static func block() -> Array:
	return [[0.0, STANCE], [BLOCK_LENGTH, BLOCK]]


## Time to drop into the crouch (5 frames at 60 fps); the clip holds it afterwards.
const DUCK_LENGTH := 5.0 / 60.0

## Held crouch: hips dropped 0.4 m, front knee folded with the foot flat, back
## knee low on its toes, torso folded forward with the head up and fists still
## guarding. The head top stays under ≈ 1.15 m so punches (`Fighter`'s
## `CROUCH_HURTBOX_TOP`) visibly pass over it.
static var DUCK := _pose(
	STANCE,
	{
		HIPS_POS: Vector3(0, -0.4, -0.05),
		"spine": Vector3(28, 0, 0),
		"chest": Vector3(16, 0, 0),
		"neck": Vector3(-18, 0, 0),
		"head": Vector3(-14, 0, 0),
		"thigh.L": Vector3(-70, 0, -6),
		"shin.L": Vector3(111, 0, 0),
		"foot.L": Vector3(-41, 0, 0),
		"thigh.R": _m(Vector3(-40, 0, -6)),
		"shin.R": Vector3(113, 0, 0),
		"foot.R": Vector3(-72, 0, 0),
	},
)


## Crouch: drop from the stance into `DUCK`, then hold it while crouching.
static func crouch() -> Array:
	return [[0.0, STANCE], [DUCK_LENGTH, DUCK]]


## Sweep timing at 60 fps: 6 startup, 4 active, 18 recovery frames; markers
## `active_start`/`active_end` like the punch.
const SWEEP_ACTIVE_START := 6.0 / 60.0
const SWEEP_ACTIVE_END := 10.0 / 60.0
const SWEEP_LENGTH := 28.0 / 60.0

## Low spinning sweep, leg fully out: the back (right) leg straight and
## reaching behind the body along the floor (ankle ≈ 0.75 m from the hips,
## 0.08 m up), the front leg folded under as the pivot, torso leaning away
## over it. `sweep()` spins the whole body around the hips so this leg arrives
## in front, toward the opponent, on the active frames.
static var SWEEP := _pose(
	DUCK,
	{
		HIPS_POS: Vector3(0, -0.42, -0.1),
		"spine": Vector3(35, 0, 0),
		"chest": Vector3(15, 0, 0),
		"neck": Vector3(-25, 0, 0),
		"head": Vector3(-15, 0, 0),
		"thigh.R": _m(Vector3(59, 0, -4)),
		"shin.R": Vector3(0, 0, 0),
		"foot.R": Vector3(-10, 0, 0),
	},
)


## `pose` with the body turned `yaw` degrees around the vertical axis at the
## hips (everything above and below them turns along).
static func _spun(pose: Dictionary, yaw: float) -> Dictionary:
	return _pose(pose, { "hips": Vector3(0, yaw, 0) })


## Sweep: one full turn on the crouched front foot. The back leg kicks out
## behind while the body turns, sweeps across the front (yaw 150°–210°, the
## leg pointing at the opponent at 180°) on the active frames, keeps turning
## while it is pulled back in and ends facing forward again in `DUCK`. Keys
## are at most 70° apart, so rotation interpolation can't take the short
## way back.
static func sweep() -> Array:
	var chamber := _pose(
		DUCK,
		{
			"thigh.R": _m(Vector3(20, 0, -4)),
			"shin.R": Vector3(70, 0, 0),
			"foot.R": Vector3(-20, 0, 0),
		},
	)
	var retract := _pose(
		SWEEP,
		{
			"thigh.R": _m(Vector3(10, 0, -4)),
			"shin.R": Vector3(90, 0, 0),
			"foot.R": Vector3(-40, 0, 0),
		},
	)
	var active_mid := (SWEEP_ACTIVE_START + SWEEP_ACTIVE_END) / 2.0
	return [
		[0.0, DUCK],
		[2.0 / 60.0, _spun(chamber, 40)],
		[4.0 / 60.0, _spun(SWEEP, 100)],
		[SWEEP_ACTIVE_START, _spun(SWEEP, 150)],
		[active_mid, _spun(SWEEP, 180)],
		[SWEEP_ACTIVE_END, _spun(SWEEP, 210)],
		[16.0 / 60.0, _spun(SWEEP, 280)],
		[22.0 / 60.0, _spun(retract, 340)],
		[SWEEP_LENGTH, _spun(DUCK, 360)],
	]


## Length of `swept`: falling, lying, getting back up (69 frames).
const SWEPT_LENGTH := 69.0 / 60.0


## Swept off the feet: the legs fly forward, the body drops onto its back
## (feet slid ≈ 0.5 m forward), bounces, lies still, sits up and rises
## through `DUCK` back to the stance, where it ends.
static func swept() -> Array:
	var legs_out := _pose(
		STANCE,
		{
			HIPS_POS: Vector3(0, -0.2, -0.15),
			"hips": Vector3(-30, 0, 0),
			"spine": Vector3(-10, 0, 0),
			"neck": Vector3(-10, 0, 0),
			"head": Vector3(-10, 0, 0),
			"upper_arm.L": Vector3(-50, 0, 15),
			"forearm.L": Vector3(0, 0, -60),
			"upper_arm.R": _m(Vector3(-50, 0, 15)),
			"forearm.R": _m(Vector3(0, 0, -60)),
			"thigh.L": Vector3(-25, 0, -4),
			"shin.L": Vector3(10, 0, 0),
			"foot.L": Vector3(20, 0, 0),
			"thigh.R": _m(Vector3(-15, 0, -4)),
			"shin.R": Vector3(10, 0, 0),
			"foot.R": Vector3(20, 0, 0),
		},
	)
	var falling := _pose(
		legs_out,
		{
			HIPS_POS: Vector3(0, -0.55, -0.25),
			"hips": Vector3(-70, 0, 0),
			"spine": Vector3(-5, 0, 0),
			"neck": Vector3(15, 0, 0),
			"head": Vector3(10, 0, 0),
			"upper_arm.L": Vector3(-20, 0, 25),
			"forearm.L": Vector3(0, 0, -40),
			"upper_arm.R": _m(Vector3(-20, 0, 25)),
			"forearm.R": _m(Vector3(0, 0, -40)),
			"thigh.L": Vector3(-20, 0, -4),
			"shin.L": Vector3(15, 0, 0),
			"thigh.R": _m(Vector3(-20, 0, -4)),
			"shin.R": Vector3(15, 0, 0),
		},
	)
	var lying := _pose(LYING, { HIPS_POS: Vector3(0, -0.83, -0.35) })
	var bounce := _add(
		lying,
		{
			HIPS_POS: Vector3(0, 0.03, 0),
			"thigh.L": Vector3(-10, 0, 0),
			"thigh.R": Vector3(-10, 0, 0),
		},
	)
	# Sitting on the floor, legs out in front, fists back up.
	var sit := _pose(
		STANCE,
		{
			HIPS_POS: Vector3(0, -0.83, -0.35),
			"spine": Vector3(15, 0, 0),
			"chest": Vector3(5, 0, 0),
			"neck": Vector3(0, 0, 0),
			"head": Vector3(0, 0, 0),
			"thigh.L": Vector3(-85, 0, -4),
			"shin.L": Vector3(25, 0, 0),
			"foot.L": Vector3(0, 0, 0),
			"thigh.R": _m(Vector3(-85, 0, -6)),
			"shin.R": Vector3(25, 0, 0),
			"foot.R": Vector3(0, 0, 0),
		},
	)
	return [
		[0.0, STANCE],
		[0.1, legs_out],
		[0.22, falling],
		[0.32, lying],
		[0.4, bounce],
		[0.48, lying],
		[0.7, lying],
		[0.85, sit],
		[1.0, DUCK],
		[SWEPT_LENGTH, STANCE],
	]


## Flat on the back on the floor, feet toward where the fighter stood (the
## hips end 0.8 m behind their start), arms out at the sides.
static var LYING := _pose(
	STANCE,
	{
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
	},
)


## Knockdown: snaps back from the blow, topples backward, lands on the back with
## a small bounce and stays down (holds the last frame).
static func knockdown() -> Array:
	var recoil := _pose(
		STANCE,
		{
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
		},
	)
	# Knees buckle and the body sits back toward the heels.
	var sit := _pose(
		STANCE,
		{
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
		},
	)
	var falling := _pose(
		STANCE,
		{
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
		},
	)
	# Back hits the floor; the legs swing up.
	var impact := _pose(
		falling,
		{
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
		},
	)
	var bounce := _add(
		LYING,
		{
			HIPS_POS: Vector3(0, 0.05, 0),
			"spine": Vector3(8, 0, 0),
			"neck": Vector3(10, 0, 0),
			"thigh.L": Vector3(-15, 0, 0),
			"shin.L": Vector3(10, 0, 0),
			"thigh.R": Vector3(-12, 0, 0),
			"shin.R": Vector3(8, 0, 0),
			"upper_arm.L": Vector3(0, 0, -10),
			"upper_arm.R": Vector3(0, 0, -10),
		},
	)
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


## Grab timing at 60 fps: 4 startup, 3 active, 20 recovery frames (whiff);
## markers `active_start`/`active_end` like the punch. A grab that connects
## leaves the clip for `throw` on the spot.
const GRAB_ACTIVE_START := 4.0 / 60.0
const GRAB_ACTIVE_END := 7.0 / 60.0
const GRAB_LENGTH := 27.0 / 60.0

## Both arms reaching straight out at chest height, torso leaning in.
static var GRAB := _pose(
	STANCE,
	{
		HIPS_POS: Vector3(0, -0.1, 0.05),
		"spine": Vector3(12, 0, 0),
		"chest": Vector3(6, 0, 0),
		"neck": Vector3(-10, 0, 0),
		"head": Vector3(-8, 0, 0),
		"upper_arm.L": Vector3(-15, 0, -75),
		"forearm.L": Vector3(0, 0, -20),
		"upper_arm.R": _m(Vector3(-15, 0, -75)),
		"forearm.R": _m(Vector3(0, 0, -20)),
		"thigh.L": Vector3(-36, 0, -4),
		"shin.L": Vector3(40, 0, 0),
		"thigh.R": _m(Vector3(22, 0, -4)),
		"shin.R": Vector3(10, 0, 0),
	},
)


## Grab (special): lunge both hands forward, hold them out (active), pull back.
static func grab() -> Array:
	var windup := _add(
		STANCE,
		{
			"spine": Vector3(-4, 0, 0),
			"upper_arm.L": Vector3(0, 0, 15),
			"upper_arm.R": _m(Vector3(0, 0, 15)),
		},
	)
	return [
		[0.0, STANCE],
		[2.0 / 60.0, windup],
		[GRAB_ACTIVE_START, GRAB],
		[GRAB_ACTIVE_END, GRAB],
		[GRAB_LENGTH, STANCE],
	]


## Throw timing, shared by `throw` (thrower) and `thrown` (victim), counted
## from the tick the grab connects: lift by 8, overhead at 16, coming down
## at 22, slammed on `THROW_SLAM`. `Fighter.THROW_PATH` carries the victim's
## body along the same keys; its heights assume the victim's hips stay at
## their rest offset until `THROW_SLAM - 4` (keep both in step).
const THROW_SLAM := 26.0 / 60.0
## End of the thrower's slam hold (marker `follow_up`): a follow-up queued
## during the throw (`elbow_drop`) leaves the throw here.
const THROW_FOLLOW_UP := THROW_SLAM + 6.0 / 60.0
## Thrower's recovery ends here; the victim lies, then gets up until
## `THROWN_LENGTH`.
const THROW_LENGTH := 44.0 / 60.0
## The victim is done bouncing off the slam and lies still (marker `lie`)
## until 52 / 60.
const THROWN_LIE := THROW_SLAM + 8.0 / 60.0
const THROWN_LENGTH := 84.0 / 60.0


## Over-the-head throw (thrower): from the grab, squat and heave the victim up
## to the chest, straighten with both arms overhead, then arch back and swing
## the arms down behind for the slam, and settle back into the stance.
static func throw() -> Array:
	var heave := _pose(
		STANCE,
		{
			HIPS_POS: Vector3(0, -0.2, 0.02),
			"spine": Vector3(5, 0, 0),
			"chest": Vector3(0, 0, 0),
			"neck": Vector3(-6, 0, 0),
			"head": Vector3(-10, 0, 0),
			"upper_arm.L": Vector3(20, 0, -70),
			"forearm.L": Vector3(0, 0, -50),
			"upper_arm.R": _m(Vector3(20, 0, -70)),
			"forearm.R": _m(Vector3(0, 0, -50)),
			"thigh.L": Vector3(-50, 0, -8),
			"shin.L": Vector3(75, 0, 0),
			"foot.L": Vector3(-25, 0, 0),
			"thigh.R": _m(Vector3(-15, 0, -8)),
			"shin.R": Vector3(60, 0, 0),
			"foot.R": Vector3(-45, 0, 0),
		},
	)
	var overhead := _pose(
		STANCE,
		{
			HIPS_POS: Vector3(0, -0.02, 0),
			"spine": Vector3(-12, 0, 0),
			"chest": Vector3(-8, 0, 0),
			"neck": Vector3(-10, 0, 0),
			"head": Vector3(-15, 0, 0),
			"upper_arm.L": Vector3(70, 0, -15),
			"forearm.L": Vector3(0, 0, -15),
			"upper_arm.R": _m(Vector3(70, 0, -15)),
			"forearm.R": _m(Vector3(0, 0, -15)),
			"thigh.L": Vector3(-20, 0, -4),
			"shin.L": Vector3(20, 0, 0),
			"foot.L": Vector3(-5, 0, 0),
			"thigh.R": _m(Vector3(10, 0, -4)),
			"shin.R": Vector3(10, 0, 0),
			"foot.R": Vector3(-20, 0, 0),
		},
	)
	var arch := _pose(
		overhead,
		{
			HIPS_POS: Vector3(0, -0.12, 0.08),
			"spine": Vector3(-25, 0, 0),
			"chest": Vector3(-15, 0, 0),
			"neck": Vector3(-10, 0, 0),
			"head": Vector3(-10, 0, 0),
			"upper_arm.L": Vector3(85, 0, 20),
			"forearm.L": Vector3(0, 0, -5),
			"upper_arm.R": _m(Vector3(85, 0, 20)),
			"forearm.R": _m(Vector3(0, 0, -5)),
			"thigh.L": Vector3(-35, 0, -6),
			"shin.L": Vector3(55, 0, 0),
			"foot.L": Vector3(-20, 0, 0),
			"thigh.R": _m(Vector3(-5, 0, -6)),
			"shin.R": Vector3(45, 0, 0),
			"foot.R": Vector3(-40, 0, 0),
		},
	)
	# The slam: folded forward over the arms, which end down behind.
	var slam := _pose(
		arch,
		{
			HIPS_POS: Vector3(0, -0.22, 0.1),
			"spine": Vector3(10, 0, 0),
			"chest": Vector3(5, 0, 0),
			"neck": Vector3(-15, 0, 0),
			"head": Vector3(-5, 0, 0),
			"upper_arm.L": Vector3(-60, 0, 40),
			"forearm.L": Vector3(0, 0, -10),
			"upper_arm.R": _m(Vector3(-60, 0, 40)),
			"forearm.R": _m(Vector3(0, 0, -10)),
			"thigh.L": Vector3(-55, 0, -8),
			"shin.L": Vector3(80, 0, 0),
			"foot.L": Vector3(-25, 0, 0),
			"thigh.R": _m(Vector3(-15, 0, -8)),
			"shin.R": Vector3(70, 0, 0),
			"foot.R": Vector3(-50, 0, 0),
		},
	)
	return [
		[0.0, GRAB],
		[8.0 / 60.0, heave],
		[16.0 / 60.0, overhead],
		[22.0 / 60.0, arch],
		[THROW_SLAM, slam],
		[THROW_FOLLOW_UP, slam],
		[THROW_LENGTH, STANCE],
	]


## Flat on the back with the hips straight under the body origin (no slide
## back like `LYING`): where the thrown victim lands.
static var THROWN_LYING := _pose(LYING, { HIPS_POS: Vector3(0, -0.83, 0) })


## Thrown (victim): grabbed and lifted, flipped forward head first over the
## thrower (one ¾ turn of the whole body around the hips, keys < 180° apart
## so it turns the long way round), slammed flat on the back on
## `THROW_SLAM`, bounces, lies still, sits up and rises through `DUCK` back
## to the stance. Linear keys, so the flip doesn't overshoot.
static func thrown() -> Array:
	var grabbed := _pose(
		STANCE,
		{
			HIPS_POS: Vector3(0, 0.02, -0.03),
			"hips": Vector3(-8, 0, 0),
			"spine": Vector3(-8, 0, 0),
			"neck": Vector3(-12, 0, 0),
			"head": Vector3(-15, 0, 0),
			"upper_arm.L": Vector3(-40, 0, 20),
			"forearm.L": Vector3(0, 0, -50),
			"upper_arm.R": _m(Vector3(-40, 0, 20)),
			"forearm.R": _m(Vector3(0, 0, -50)),
			"thigh.L": Vector3(-10, 0, -4),
			"shin.L": Vector3(15, 0, 0),
			"foot.L": Vector3(20, 0, 0),
			"thigh.R": _m(Vector3(-5, 0, -4)),
			"shin.R": Vector3(20, 0, 0),
			"foot.R": Vector3(20, 0, 0),
		},
	)
	# Airborne and limp: arms thrown out, legs loosely bent.
	var flung := _pose(
		grabbed,
		{
			"spine": Vector3(-5, 0, 0),
			"upper_arm.L": Vector3(10, 0, 30),
			"forearm.L": Vector3(0, 0, -30),
			"upper_arm.R": _m(Vector3(10, 0, 30)),
			"forearm.R": _m(Vector3(0, 0, -30)),
			"thigh.L": Vector3(-30, 0, -6),
			"shin.L": Vector3(40, 0, 0),
			"thigh.R": _m(Vector3(-20, 0, -6)),
			"shin.R": Vector3(50, 0, 0),
		},
	)
	var bounce := _add(
		THROWN_LYING,
		{
			HIPS_POS: Vector3(0, 0.05, 0),
			"spine": Vector3(8, 0, 0),
			"neck": Vector3(10, 0, 0),
			"thigh.L": Vector3(-15, 0, 0),
			"thigh.R": Vector3(-12, 0, 0),
		},
	)
	var sit := _pose(
		STANCE,
		{
			HIPS_POS: Vector3(0, -0.83, 0),
			"spine": Vector3(15, 0, 0),
			"chest": Vector3(5, 0, 0),
			"neck": Vector3(0, 0, 0),
			"head": Vector3(0, 0, 0),
			"thigh.L": Vector3(-85, 0, -4),
			"shin.L": Vector3(25, 0, 0),
			"foot.L": Vector3(0, 0, 0),
			"thigh.R": _m(Vector3(-85, 0, -6)),
			"shin.R": Vector3(25, 0, 0),
			"foot.R": Vector3(0, 0, 0),
		},
	)
	return [
		[0.0, grabbed],
		[8.0 / 60.0, _pose(flung, { "hips": Vector3(60, 0, 0) })],
		[16.0 / 60.0, _pose(flung, { "hips": Vector3(160, 0, 0) })],
		[22.0 / 60.0, _pose(flung, { "hips": Vector3(230, 0, 0) })],
		[THROW_SLAM, THROWN_LYING],
		[THROW_SLAM + 4.0 / 60.0, bounce],
		[THROWN_LIE, THROWN_LYING],
		[52.0 / 60.0, THROWN_LYING],
		[64.0 / 60.0, sit],
		[74.0 / 60.0, _pose(DUCK, { HIPS_POS: Vector3(0, -0.4, 0) })],
		[THROWN_LENGTH, STANCE],
	]


## Elbow drop timing (the throw's follow-up), counted from the end of the
## throw's slam hold: crouch and leave the floor on `ELBOW_TAKEOFF` (marker
## `takeoff`), land with the elbow in the lying victim on `ELBOW_IMPACT`
## (marker `impact`), back up by `ELBOW_LENGTH`. `Fighter` flies the body
## between the two markers; the poses only bend it.
const ELBOW_TAKEOFF := 6.0 / 60.0
const ELBOW_IMPACT := 30.0 / 60.0
const ELBOW_LENGTH := 56.0 / 60.0

## Landed on both knees, torso folded forward over the victim, the right
## upper arm pointing down with the forearm folded back up, so the elbow is
## the arm's lowest point, in front of the knees near the floor
## (`Fighter.ELBOW_REACH`). The left arm is thrown out for balance.
static var ELBOW_DROP := _pose(
	STANCE,
	{
		HIPS_POS: Vector3(0, -0.5, 0.1),
		"hips": Vector3(30, 0, 0),
		"spine": Vector3(50, 0, 0),
		"chest": Vector3(30, 0, 0),
		"neck": Vector3(-40, 0, 0),
		"head": Vector3(-30, 0, 0),
		"upper_arm.R": _m(Vector3(-15, 0, -80)),
		"forearm.R": _m(Vector3(0, 0, -150)),
		"upper_arm.L": Vector3(-60, 0, 30),
		"forearm.L": Vector3(0, 0, -40),
		"thigh.L": Vector3(-10, 0, -6),
		"shin.L": Vector3(70, 0, 0),
		"foot.L": Vector3(70, 0, 0),
		"thigh.R": _m(Vector3(-5, 0, -6)),
		"shin.R": Vector3(70, 0, 0),
		"foot.R": Vector3(70, 0, 0),
	},
)


## Elbow drop (follow-up to the special throw): turned toward the victim
## lying behind, crouch, spring up with the right elbow cocked over the
## head, fold forward at the top of the leap and drop knees and elbow first
## onto the victim on `ELBOW_IMPACT`, hold, then push back up through the
## crouch into the stance.
static func elbow_drop() -> Array:
	var takeoff := _pose(
		EXTENDED,
		{
			"upper_arm.R": _m(Vector3(60, 0, -10)),
			"forearm.R": _m(Vector3(0, 0, -110)),
			"upper_arm.L": Vector3(-30, 0, 20),
			"forearm.L": Vector3(0, 0, -40),
		},
	)
	var cocked := _pose(
		TUCK,
		{
			"spine": Vector3(-6, 0, 0),
			"chest": Vector3(-4, 0, 0),
			"upper_arm.R": _m(Vector3(75, 0, -10)),
			"forearm.R": _m(Vector3(0, 0, -130)),
			"upper_arm.L": Vector3(-20, 0, 30),
			"forearm.L": Vector3(0, 0, -40),
		},
	)
	# Top of the leap: folding forward, the elbow coming down, knees under.
	var fold := _pose(
		ELBOW_DROP,
		{
			HIPS_POS: Vector3(0, 0.0, 0),
			"spine": Vector3(20, 0, 0),
			"chest": Vector3(15, 0, 0),
			"upper_arm.R": _m(Vector3(-10, 0, -60)),
			"thigh.L": Vector3(-45, 0, -6),
			"shin.L": Vector3(100, 0, 0),
			"thigh.R": _m(Vector3(-30, 0, -6)),
			"shin.R": Vector3(105, 0, 0),
		},
	)
	var drop := _pose(ELBOW_DROP, { HIPS_POS: Vector3(0, -0.1, -0.05) })
	# Pushing back up: torso and arms lifting, still on the knees.
	var push_up := _pose(
		ELBOW_DROP,
		{
			"spine": Vector3(15, 0, 0),
			"chest": Vector3(8, 0, 0),
			"neck": Vector3(-8, 0, 0),
			"head": Vector3(-8, 0, 0),
			"upper_arm.R": _m(Vector3(-75, 0, -12)),
			"forearm.R": _m(Vector3(0, 0, -140)),
			"upper_arm.L": Vector3(-75, 0, -20),
			"forearm.L": Vector3(0, 0, -135),
		},
	)
	return [
		[0.0, STANCE],
		[4.0 / 60.0, CROUCH],
		[ELBOW_TAKEOFF, takeoff],
		[14.0 / 60.0, cocked],
		[20.0 / 60.0, fold],
		[26.0 / 60.0, drop],
		[ELBOW_IMPACT, ELBOW_DROP],
		[36.0 / 60.0, ELBOW_DROP],
		[44.0 / 60.0, push_up],
		[50.0 / 60.0, CROUCH],
		[ELBOW_LENGTH, STANCE],
	]


## Name → [length (s), loop, cubic, keys, markers]. Keys are [time, pose]
## pairs; markers (optional) map a name to a time.
static func clips() -> Dictionary:
	return {
		&"air_kick": [
			AIR_KICK_LENGTH,
			false,
			false,
			air_kick(),
			{ &"active_start": AIR_KICK_ACTIVE_START, &"active_end": AIR_KICK_ACTIVE_END },
		],
		&"block": [BLOCK_LENGTH, false, false, block()],
		&"grab": [
			GRAB_LENGTH,
			false,
			false,
			grab(),
			{ &"active_start": GRAB_ACTIVE_START, &"active_end": GRAB_ACTIVE_END },
		],
		&"throw": [
			THROW_LENGTH,
			false,
			true,
			throw(),
			{ &"slam": THROW_SLAM, &"follow_up": THROW_FOLLOW_UP },
		],
		&"thrown": [
			THROWN_LENGTH,
			false,
			false,
			thrown(),
			{ &"slam": THROW_SLAM, &"lie": THROWN_LIE },
		],
		&"elbow_drop": [
			ELBOW_LENGTH,
			false,
			false,
			elbow_drop(),
			{ &"takeoff": ELBOW_TAKEOFF, &"impact": ELBOW_IMPACT },
		],
		&"crouch": [DUCK_LENGTH, false, false, crouch()],
		&"sweep": [
			SWEEP_LENGTH,
			false,
			false,
			sweep(),
			{ &"active_start": SWEEP_ACTIVE_START, &"active_end": SWEEP_ACTIVE_END },
		],
		&"swept": [SWEPT_LENGTH, false, true, swept()],
		&"idle": [1.0, true, true, idle()],
		&"jump_start": [0.15, false, true, jump_start()],
		&"jump_air": [0.25, false, true, jump_air()],
		&"jump_land": [0.2, false, true, jump_land()],
		&"knockdown": [0.85, false, true, knockdown()],
		&"punch": [
			PUNCH_LENGTH,
			false,
			false,
			punch(),
			{ &"active_start": PUNCH_ACTIVE_START, &"active_end": PUNCH_ACTIVE_END },
		],
		&"punch_left": [
			PUNCH_LENGTH,
			false,
			false,
			punch_left(),
			{ &"active_start": PUNCH_ACTIVE_START, &"active_end": PUNCH_ACTIVE_END },
		],
		&"walk": [0.8, true, true, walk()],
	}


## Builds one `Animation` from `[time, pose]` keys. Every bone gets a rotation
## track (unlisted bones hold their rest pose) plus a hips position track, so a
## clip fully defines the pose and never leaks bones from the previous clip.
static func build(
	length: float,
	loop: bool,
	cubic: bool,
	keys: Array,
	rest: Dictionary,
	markers := { },
) -> Animation:
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
		anim.position_track_insert_key(
			pos_track,
			t,
			rest[HIPS_POS] + pose.get(HIPS_POS, Vector3.ZERO),
		)
	for bone in BONES:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, "Skeleton3D:" + bone)
		anim.track_set_interpolation_type(track, interp)
		for key in keys:
			var t: float = key[0]
			var pose: Dictionary = key[1]
			var deg: Vector3 = pose.get(bone, Vector3.ZERO)
			var delta := Quaternion.from_euler(
				Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
			)
			anim.rotation_track_insert_key(track, t, rest[bone] * delta)
	return anim


## Rest rotations of every bone (and the hips' rest position) from the
## reference character, which carries the template skeleton unchanged.
static func reference_rest() -> Dictionary:
	var root := CharacterLoader.load_character(REFERENCE)
	assert(root != null, "can't load " + REFERENCE)
	var skeleton := CharacterLoader.find_skeleton(root)
	var rest := { }
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
		lib.add_animation(
			clip_name,
			build(c[0], c[1], c[2], c[3], rest, c[4] if c.size() > 4 else { }),
		)
	return lib
