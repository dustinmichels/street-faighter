class_name Fighter
extends CharacterBody3D
## A fighter. Its character model is loaded at runtime from `character_path`
## and placed under `$Visual`, the node that is moved/mirrored for display.
## The body is a capsule (layer 2, colliding only with the world on layer 1, so
## fighters pass through each other; `_push_apart()` keeps them apart) that only
## moves along world X: Z velocity and position are forced to zero every tick.

enum State { IDLE, WALK, JUMP, PUNCH, HIT, KNOCKED_DOWN }
## Parts of the `jump` state, each with its own clip (`JUMP_CLIPS`).
enum JumpPhase { TAKEOFF, AIR, LANDING }

## Shared clips (`animations/build_base.gd`), played on every character.
const ANIMATIONS := preload("res://animations/base.res")

## How long a `hit` reaction locks the fighter before returning to idle.
const HIT_STUN := 0.3
## End of the recoil key in the `knockdown` clip; `hit` plays only that part.
const HIT_RECOIL_END := 0.1
## Health a fighter starts with.
const MAX_HEALTH := 100
## Health one landed punch takes off.
const PUNCH_DAMAGE := 10
## Push speed (m/s) a hit gives the victim, away from the attacker.
const KNOCKBACK_SPEED := 3.0
## Deceleration (m/s²) of that push: it stops after 0.2 s, ≈ 0.3 m.
const KNOCKBACK_FRICTION := 15.0
## Closest two fighters' body centers may get along X: twice the body
## capsule's radius (0.3, `fighter.tscn`).
const PUSH_DISTANCE := 0.6
## Farthest two fighters' body centers may get along X, so both stay on
## screen: the follow camera (`FollowCamera`) shows 8.89 m, which leaves
## ≈ 0.95 m past each body for limbs and the knockdown slide.
const MAX_SEPARATION := 7.0
## Ground walking speed (m/s), the same forward and backward.
const WALK_SPEED := 2.0
## Downward acceleration (m/s²) whenever the body is off the floor.
const GRAVITY := 25.0
## Upward launch speed (m/s): peak ≈ 1.3 m, ≈ 0.64 s in the air.
const JUMP_VELOCITY := 8.0
## Grounded crouch before launch; matches the `jump_start` clip.
const JUMP_TAKEOFF := 0.15
## Grounded recovery after touchdown; matches the `jump_land` clip.
const JUMP_LANDING := 0.2
const JUMP_CLIPS: Array[StringName] = [&"jump_start", &"jump_air", &"jump_land"]
## Full punch duration (startup + active + recovery), taken from the clip.
static var PUNCH_LENGTH := ANIMATIONS.get_animation(&"punch").length
## The punch clip's active window (markers `active_start`/`active_end`); the
## hitbox is live from the start up to, not including, the end.
static var PUNCH_ACTIVE_START := ANIMATIONS.get_animation(&"punch").get_marker_time(&"active_start")
static var PUNCH_ACTIVE_END := ANIMATIONS.get_animation(&"punch").get_marker_time(&"active_end")

## Character `.glb` to load on ready (see `docs/skeleton.md`).
@export_file("*.glb") var character_path: String
## Controls, sampled once per physics tick. Swap in another `InputSource`
## (network, AI) to drive the fighter without touching this script.
@export var input: InputSource = IdleInput.new()
## The fighter to face. Turning happens only in idle/walk, so a fighter that
## crosses over mid-jump or mid-punch turns around once it is back to neutral.
@export var opponent: Fighter

## Loaded character scene root (child of `visual`), or null if loading failed.
var model: Node3D
## The model's skeleton; animations target its bones by name.
var skeleton: Skeleton3D
## Plays `ANIMATIONS` (default library, so clips are `&"idle"`, `&"punch"`, ...)
## on `skeleton`. Recreated with each model.
var anim: AnimationPlayer

## Current state; change it only via `change_state()`.
var state := State.IDLE
## Seconds spent in the current state (and jump phase).
var state_time := 0.0
## Part of the jump while `state == State.JUMP`.
var jump_phase := JumpPhase.TAKEOFF
## +1 when the fighter faces +X, -1 when it faces -X.
var facing := 1.0
## Walk direction along X (-1, 0 or +1); while jumping, the locked jump direction.
var move_dir := 0.0
## Buttons held last tick, to turn `input.poll()` into fresh presses.
var prev_buttons := 0
## Remaining health, 0..`MAX_HEALTH`.
var health := MAX_HEALTH
## Set once the current punch connects, so it hits at most once.
var punch_landed := false

@onready var visual: Node3D = $Visual
## Where this fighter can be hit: a fixed capsule matching the body (layer 3,
## `hurtboxes`), never taken from the mesh. Only queried, never monitoring.
@onready var hurtbox: Area3D = $Hurtbox
## The punch's reach: a fixed box in front of the chest at fist height (the
## extended fist spans ≈ 0.57–0.73 m forward, 1.33 m up), mirrored with
## `facing`. Its shape is enabled only on active frames; hits come from
## `hitbox_targets()`, a direct space query, so they land on the same tick.
@onready var hitbox: Area3D = $Hitbox
@onready var hitbox_shape: CollisionShape3D = $Hitbox/Collision


func _ready() -> void:
	if not character_path.is_empty():
		set_character(character_path)
	_update_facing()
	_apply_facing()


func _physics_process(delta: float) -> void:
	state_time += delta
	var buttons := input.poll() if input != null else 0
	var pressed := buttons & ~prev_buttons
	prev_buttons = buttons
	var dir := float(int((buttons & InputSource.RIGHT) != 0) - int((buttons & InputSource.LEFT) != 0))
	var jump_pressed := (pressed & InputSource.JUMP) != 0
	var punch_pressed := (pressed & InputSource.PUNCH) != 0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	match state:
		State.IDLE, State.WALK:
			_update_facing()
			if punch_pressed and is_on_floor():
				velocity.x = 0.0
				punch_landed = false
				change_state(State.PUNCH)
			elif jump_pressed and is_on_floor():
				move_dir = dir
				jump_phase = JumpPhase.TAKEOFF
				change_state(State.JUMP)
				velocity.x = 0.0
			else:
				_ground_move(dir)
		State.JUMP:
			_jump()
		State.PUNCH:
			# Rooted and deaf to input until the clip ends; only a hit cuts it short.
			velocity.x = 0.0
			if state_time >= PUNCH_LENGTH:
				move_dir = 0.0
				change_state(State.IDLE)
		State.HIT:
			velocity.x = move_toward(velocity.x, 0.0, KNOCKBACK_FRICTION * delta)
		State.KNOCKED_DOWN:
			velocity.x = 0.0
	if state == State.HIT and state_time >= HIT_STUN:
		change_state(State.IDLE)
	velocity.z = 0.0
	move_and_slide()
	position.z = 0.0
	if opponent != null:
		_push_apart(opponent)
		_stay_in_range(opponent)
	hitbox_shape.disabled = not is_hitbox_active()
	if not hitbox_shape.disabled and not punch_landed:
		for target in hitbox_targets():
			target.take_hit(PUNCH_DAMAGE, facing)
			punch_landed = true
	_snap_visual()


## Puts `visual` on the pixel grid at the body's position (§2 pixel snapping).
func _snap_visual() -> void:
	var camera := get_viewport().get_camera_3d() as PixelCamera
	if camera != null:
		visual.global_position = camera.snap(global_position)


## Bodies don't collide with each other (mask is world only), so overlap along
## X is resolved here instead: each fighter takes half, moving away from the
## other; if one is blocked (by a wall), the other takes the rest. Runs after
## each fighter's own move, so walking into a fighter shoves it at half speed.
func _push_apart(other: Fighter) -> void:
	var dx := other.global_position.x - global_position.x
	var overlap := PUSH_DISTANCE - absf(dx)
	if overlap <= 0.0:
		return
	# Exactly on top of each other: step back from where we're facing.
	var dir := signf(dx) if not is_zero_approx(dx) else facing
	var pushed := other._shove(dir * overlap * 0.5)
	pushed += _shove(-dir * (overlap - pushed))
	other._shove(dir * (overlap - pushed))
	other._snap_visual()


## Screen-edge limit: a fighter that ends its move more than `MAX_SEPARATION`
## from `other` steps back toward it. Only the mover is held (each fighter
## checks after its own move), so nobody is dragged along by the other.
func _stay_in_range(other: Fighter) -> void:
	var dx := other.global_position.x - global_position.x
	var excess := absf(dx) - MAX_SEPARATION
	if excess > 0.0:
		_shove(signf(dx) * excess)


## Moves the body `dx` along X, stopping at world geometry. Returns the
## distance actually travelled.
func _shove(dx: float) -> float:
	if is_zero_approx(dx):
		return 0.0
	var start := global_position.x
	move_and_collide(Vector3(dx, 0.0, 0.0))
	position.z = 0.0
	return absf(global_position.x - start)


## Idle/walk: walk at `WALK_SPEED` toward `dir`, or stand when it is 0.
func _ground_move(dir: float) -> void:
	velocity.x = dir * WALK_SPEED
	if dir == move_dir and (state == State.WALK) == (dir != 0.0):
		return
	move_dir = dir
	change_state(State.WALK if dir != 0.0 else State.IDLE)


## Turns toward `opponent` if it is now on the other side. A walk in progress
## keeps its direction but switches between forward and backward stepping.
func _update_facing() -> void:
	if opponent == null:
		return
	var dx := opponent.global_position.x - global_position.x
	if is_zero_approx(dx) or signf(dx) == facing:
		return
	facing = signf(dx)
	_apply_facing()
	if state == State.WALK:
		_play_state_animation()


## Points the model (authored facing +Z) along `facing`: a quarter turn to +X,
## mirrored across X for -X so the same side always faces the camera. The
## hitbox moves to the facing side (moved, not scaled: physics shapes don't
## take negative scale).
func _apply_facing() -> void:
	visual.basis = Basis.from_scale(Vector3(facing, 1.0, 1.0)) * Basis(Vector3.UP, PI / 2.0)
	hitbox.position.x = facing * absf(hitbox.position.x)


## True on the punch's active frames. Compared in whole physics ticks so float
## drift in `state_time` can't add or drop a frame.
func is_hitbox_active() -> bool:
	if state != State.PUNCH:
		return false
	var tps := Engine.physics_ticks_per_second
	var frame := roundi(state_time * tps)
	return frame >= roundi(PUNCH_ACTIVE_START * tps) and frame < roundi(PUNCH_ACTIVE_END * tps)


## Other fighters whose hurtbox overlaps the hitbox right now (regardless of
## whether the hitbox is active).
func hitbox_targets() -> Array[Fighter]:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hitbox_shape.shape
	query.transform = hitbox_shape.global_transform
	query.collision_mask = hitbox.collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [hurtbox.get_rid()]
	var targets: Array[Fighter] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query):
		var target := (hit.collider as Node).get_parent() as Fighter
		if target != null and target != self and not targets.has(target):
			targets.append(target)
	return targets


## Jump: crouch, launch toward the direction held at the press (no air
## control), fall under gravity, then a landing crouch back into idle.
func _jump() -> void:
	match jump_phase:
		JumpPhase.TAKEOFF:
			if state_time >= JUMP_TAKEOFF:
				velocity = Vector3(move_dir * WALK_SPEED, JUMP_VELOCITY, 0.0)
				_set_jump_phase(JumpPhase.AIR)
		JumpPhase.AIR:
			if is_on_floor() and velocity.y <= 0.0:
				velocity.x = 0.0
				_set_jump_phase(JumpPhase.LANDING)
		JumpPhase.LANDING:
			if state_time >= JUMP_LANDING:
				move_dir = 0.0
				change_state(State.IDLE)


func _set_jump_phase(phase: JumpPhase) -> void:
	jump_phase = phase
	state_time = 0.0
	_play_state_animation()


## Enters `new_state`, restarting its timer and animation.
func change_state(new_state: State) -> void:
	state = new_state
	state_time = 0.0
	_play_state_animation()


## Interrupts whatever the fighter is doing with a hit reaction: loses `damage`
## health and is shoved along `push_dir` (±1, the attacker's facing) at
## `KNOCKBACK_SPEED`, sliding to a stop during the stun. The hit that empties
## health knocks the fighter down instead (the clip carries it back). Ignored
## once knocked down.
func take_hit(damage: int, push_dir: float) -> void:
	if state == State.KNOCKED_DOWN:
		return
	health = maxi(health - damage, 0)
	if health == 0:
		knock_down()
		return
	velocity.x = push_dir * KNOCKBACK_SPEED
	change_state(State.HIT)


## Knocks the fighter down for good: it stays down (no get-up), ignores input
## and further hits. Also how a KO happens, from `take_hit()` at 0 health.
func knock_down() -> void:
	velocity.x = 0.0
	change_state(State.KNOCKED_DOWN)


func _play_state_animation() -> void:
	if anim == null:
		return
	match state:
		State.IDLE:
			anim.play(&"idle")
		State.WALK:
			# One clip for both directions: backwards when retreating.
			if move_dir * facing < 0.0:
				anim.play_backwards(&"walk")
			else:
				anim.play(&"walk")
		State.JUMP:
			anim.play(JUMP_CLIPS[jump_phase])
		State.PUNCH:
			anim.play(&"punch")
		State.HIT:
			anim.play_section(&"knockdown", 0.0, HIT_RECOIL_END)
		State.KNOCKED_DOWN:
			anim.play(&"knockdown")


## Replaces the current model with the character at `path`. Returns false (and
## keeps the old model) if it can't be loaded or lacks the required skeleton.
func set_character(path: String) -> bool:
	var new_model := CharacterLoader.load_character(path)
	if new_model == null:
		return false
	if model != null:
		model.queue_free()
	model = new_model
	skeleton = CharacterLoader.find_skeleton(model)
	# Tracks are `Skeleton3D:<bone>`, resolved from the player's parent.
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	anim.add_animation_library(&"", ANIMATIONS)
	skeleton.get_parent().add_child(anim)
	# Advance on the physics tick so poses stay in lockstep with gameplay.
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	visual.add_child(model)
	_play_state_animation()
	return true
