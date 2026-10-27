class_name Fighter
extends Node3D
## A fighter. Its character model is loaded at runtime from `character_path`
## and placed under `$Visual`, the node that is moved/mirrored for display.
##
## Gameplay is a deterministic simulation for netcode (`docs/netcode.md`): all
## of it lives in the plain variables below (fixed-point integers, see
## `SCALE`), advanced only by `step()`, which the `Match` calls once per tick
## for both fighters in a fixed order. No Godot physics is involved: movement
## is custom kinematics along world X/Y bounded by the floor (y = 0) and the
## stage walls, and hits are game-defined shapes tested by the `Match`. The
## node itself (`position`, `visual`, the animation) only displays the state,
## via `sync_visual()`.

enum State { IDLE, WALK, JUMP, PUNCH, HIT, KNOCKED_DOWN, BLOCK, CROUCH, SWEEP, SWEPT, GRAB, THROW, THROWN }
## Parts of the `jump` state, each with its own clip (`JUMP_CLIPS`). `KICK`
## replaces `AIR` once the attack button is pressed mid-air and lasts until
## touchdown (the clip ends back in the tuck and holds it).
enum JumpPhase { TAKEOFF, AIR, LANDING, KICK }

## Gameplay rate: `step()` runs once per physics tick and times are counted in
## whole ticks. Must equal the project's `physics/common/physics_ticks_per_second`.
const TICK_RATE := 60
const TICK := 1.0 / TICK_RATE
## Fixed-point units per metre for positions; speeds are units per tick and
## accelerations units per tick². Integer math gives the same results on
## every platform, so peers never drift apart.
const SCALE := 10000

## Shared clips (`animations/build_base.gd`), played on every character.
const ANIMATIONS := preload("res://animations/base.res")

## How long a `hit` reaction locks the fighter before returning to idle (0.3 s).
const HIT_STUN := 18
## End of the recoil key in the `knockdown` clip; `hit` plays only that part.
const HIT_RECOIL_END := 0.1
## Health a fighter starts with.
const MAX_HEALTH := 100
## Health one landed punch takes off.
const PUNCH_DAMAGE := 10
## Health one landed air kick takes off.
const AIR_KICK_DAMAGE := 10
## Health one landed sweep takes off (it also knocks the victim over, `SWEPT`).
const SWEEP_DAMAGE := 10
## Push speed a hit gives the victim, away from the attacker (3 m/s).
const KNOCKBACK_SPEED := 500
## Deceleration of that push (≈ 15 m/s²): it stops after 12 ticks, ≈ 0.3 m.
const KNOCKBACK_FRICTION := 42
## Push speed a blocked hit gives the blocker (1.5 m/s); the same friction
## stops it after 6 ticks, ≈ 0.06 m.
const BLOCK_PUSH_SPEED := 250
## Blockstun after a blocked hit (0.2 s): the guard holds even if the block
## button is released.
const BLOCK_STUN := 12
## How long an attack press stays buffered: 5 ticks, i.e. up to 4 ticks early
## (Street Fighter 6's buffer), so a press during recovery, stun or the
## landing comes out on the first tick it can.
const INPUT_BUFFER := 5
## Body radius (0.3 m): how close a body center gets to a wall.
const BODY_RADIUS := 3000
## Closest two fighters' body centers may get along X: twice `BODY_RADIUS`.
const PUSH_DISTANCE := 6000
## Farthest two fighters' body centers may get along X (7 m), so both stay on
## screen: the follow camera (`FollowCamera`) shows ≈ 9 m along X at the
## fighters' depth, which leaves ≈ 1 m past each body for limbs and the
## knockdown slide.
const MAX_SEPARATION := 70000
## Ground walking speed (≈ 2 m/s), the same forward and backward.
const WALK_SPEED := 333
## Downward acceleration (≈ 25 m/s²) whenever the body is off the floor.
const GRAVITY := 69
## Upward launch speed (≈ 8 m/s): peak ≈ 1.3 m, ≈ 0.64 s in the air.
const JUMP_VELOCITY := 1333
## Grounded crouch before launch (0.15 s); matches the `jump_start` clip.
const JUMP_TAKEOFF := 9
## Grounded recovery after touchdown (0.2 s); matches the `jump_land` clip.
const JUMP_LANDING := 12
const JUMP_CLIPS: Array[StringName] = [&"jump_start", &"jump_air", &"jump_land", &"air_kick"]
## Full punch duration in ticks (startup + active + recovery), from the clip.
static var PUNCH_LENGTH := ticks(ANIMATIONS.get_animation(&"punch").length)
## The punch clip's active window in ticks (markers `active_start`/`active_end`);
## the hitbox is live from the start up to, not including, the end.
static var PUNCH_ACTIVE_START := ticks(ANIMATIONS.get_animation(&"punch").get_marker_time(&"active_start"))
static var PUNCH_ACTIVE_END := ticks(ANIMATIONS.get_animation(&"punch").get_marker_time(&"active_end"))
## The air kick clip's active window, counted from the start of `KICK`.
static var AIR_KICK_ACTIVE_START := ticks(ANIMATIONS.get_animation(&"air_kick").get_marker_time(&"active_start"))
static var AIR_KICK_ACTIVE_END := ticks(ANIMATIONS.get_animation(&"air_kick").get_marker_time(&"active_end"))
## Full sweep duration and its active window (`sweep` clip).
static var SWEEP_LENGTH := ticks(ANIMATIONS.get_animation(&"sweep").length)
static var SWEEP_ACTIVE_START := ticks(ANIMATIONS.get_animation(&"sweep").get_marker_time(&"active_start"))
static var SWEEP_ACTIVE_END := ticks(ANIMATIONS.get_animation(&"sweep").get_marker_time(&"active_end"))
## How long a swept fighter is down before acting again: the whole `swept`
## clip (fall, lie, get up).
static var SWEPT_LENGTH := ticks(ANIMATIONS.get_animation(&"swept").length)
## Ticks the `crouch` clip takes to reach the held crouch; a sweep that ends
## with crouch held resumes the crouch there instead of rising first.
static var CROUCH_LENGTH := ticks(ANIMATIONS.get_animation(&"crouch").length)
## Hitbox center relative to the feet (facing +X) per attack: the extended fist
## (≈ 0.57–0.73 m forward, 1.33 m up), the extended kicking foot (ankle
## 0.75 m forward, 0.52 m up; heel/sole just past it) and the sweeping foot
## along the floor (0.6–0.9 m forward, 0–0.25 m up).
const PUNCH_HITBOX := Vector2i(6200, 13300)
const AIR_KICK_HITBOX := Vector2i(8000, 5500)
const SWEEP_HITBOX := Vector2i(7500, 1000)
## Half the side of the square hitbox (0.3 m box).
const HITBOX_HALF := 1500
## Hurtbox: the body capsule (r = 0.3 m, 1.8 m tall), seen from the side as a
## vertical segment from `HURTBOX_BOTTOM` to `HURTBOX_TOP` above the feet,
## widened by `BODY_RADIUS`. Fixed, never taken from the mesh.
const HURTBOX_BOTTOM := 3000
const HURTBOX_TOP := 15000
## Hurtbox top while low (crouching or sweeping): the body reaches 1.1 m
## (head top in the `crouch` clip ≈ 1.15 m), under the punch hitbox's bottom
## edge (1.18 m), so punches pass over; the air kick and the sweep still hit.
const CROUCH_HURTBOX_TOP := 8000
## Landed hits in a row, without taking one, that make the special ready.
const SPECIAL_HITS := 3
## Health the special throw takes off when the victim hits the floor.
const THROW_DAMAGE := 20
## Farthest the opponent's body center may be in front of the grabber's for
## the grab to catch it (0.9 m: past arm's reach of a standing pair, 0.6 m).
const GRAB_RANGE := 9000
## The grab clip's active window (`grab` markers) and whiff length.
static var GRAB_ACTIVE_START := ticks(ANIMATIONS.get_animation(&"grab").get_marker_time(&"active_start"))
static var GRAB_ACTIVE_END := ticks(ANIMATIONS.get_animation(&"grab").get_marker_time(&"active_end"))
static var GRAB_LENGTH := ticks(ANIMATIONS.get_animation(&"grab").length)
## Thrower's whole throw, the tick the victim lands (`throw` clip, marker
## `slam`) and the victim's whole `thrown` state (slam, lie, get up).
static var THROW_LENGTH := ticks(ANIMATIONS.get_animation(&"throw").length)
static var THROW_SLAM := ticks(ANIMATIONS.get_animation(&"throw").get_marker_time(&"slam"))
static var THROWN_LENGTH := ticks(ANIMATIONS.get_animation(&"thrown").length)
## The victim's body (feet) relative to the thrower's during the throw:
## `[tick, forward, up]`, forward along the thrower's facing, linearly
## interpolated in between. From arm's reach in front, up over the
## thrower's head, down 1.3 m behind it on `THROW_SLAM` (the last key), where
## it stays. Keyed with the `thrown` clip (`animations/build_base.gd`): the
## height holds the flipping body's hips (rest ≈ 0.95 m above the feet) clear
## over the thrower.
const THROW_PATH: Array[Vector3i] = [
	Vector3i(0, 6000, 0),
	Vector3i(8, 3000, 8000),
	Vector3i(16, -1000, 11500),
	Vector3i(22, -10000, 2500),
	Vector3i(26, -13000, 0),
]
## How far `knockdown`'s held `LYING` pose puts the hips behind the body
## origin (0.8 m); a throw that knocks out moves the body forward that much
## so the hips stay where `thrown` left them.
const KNOCKDOWN_HIPS_BACK := 8000
## `knockdown` clip length: a knockout by throw starts there (already flat).
static var KNOCKDOWN_LENGTH := ticks(ANIMATIONS.get_animation(&"knockdown").length)

## Character `.glb` to load on ready (see `docs/skeleton.md`).
@export_file("*.glb") var character_path: String
## Controls, sampled once per tick by the `Match`. Swap in another
## `InputSource` (network, AI) to drive the fighter without touching this
## script; assigning one calls its `bind(self)`.
@export var input: InputSource = IdleInput.new():
	set(value):
		input = value
		if input != null:
			input.bind(self)
## The other fighter, for input sources that look at the match (the AI).
@export var opponent: Fighter
## Whether this fighter may use the special at all: players yes, the
## computer opponent no (`main.gd` turns it off for `AIInput`). Fixed for
## the match, the same on both peers.
@export var specials_enabled := true

# --- Simulation state: everything `step()` reads or writes, nothing else. ---

## Body center (feet) along X and height above the floor, in `SCALE` units.
var pos_x := 0
var pos_y := 0
## Velocity in units per tick.
var vel_x := 0
var vel_y := 0
## Current state; change it only via `change_state()`.
var state := State.IDLE
## Ticks spent in the current state (and jump phase).
var state_ticks := 0
## Part of the jump while `state == State.JUMP`.
var jump_phase := JumpPhase.TAKEOFF
## +1 when the fighter faces +X, -1 when it faces -X.
var facing := 1
## Held direction (-1, 0 or +1) in idle/walk/block/crouch; while jumping, the
## locked jump direction.
var move_dir := 0
## Buttons held last tick, to turn the input bitmask into fresh presses.
var prev_buttons := 0
## Ticks the last attack press stays buffered (0 = none), see `INPUT_BUFFER`.
var attack_buffer := 0
## Same for the special press.
var special_buffer := 0
## Hits landed in a row without taking one, up to `SPECIAL_HITS`; the special
## is ready at `SPECIAL_HITS` (`special_ready()`) and using it starts over.
var hit_streak := 0
## Blockstun ticks left while `state == State.BLOCK` (0 = guarding by choice).
var block_stun := 0
## Remaining health, 0..`MAX_HEALTH`.
var health := MAX_HEALTH
## Set once the current punch or air kick connects, so it hits at most once.
var attack_landed := false
## Farthest a body center may get from the stage center along X (walls);
## set by the `Match` before the first tick.
var wall_limit := 1 << 40

# --- Display only. ---

## Loaded character scene root (child of `visual`), or null if loading failed.
var model: Node3D
## The model's skeleton; animations target its bones by name.
var skeleton: Skeleton3D
## Plays `ANIMATIONS` (default library, so clips are `&"idle"`, `&"punch"`, ...)
## on `skeleton`. Recreated with each model.
var anim: AnimationPlayer

@onready var visual: Node3D = $Visual


func _ready() -> void:
	assert(Engine.physics_ticks_per_second == TICK_RATE, "physics tick rate must be %d Hz" % TICK_RATE)
	pos_x = roundi(position.x * SCALE)
	pos_y = roundi(position.y * SCALE)
	if not character_path.is_empty():
		set_character(character_path)


## Advances this fighter by one tick: `buttons` is this tick's input bitmask
## and `opponent_x` the opponent's `pos_x` at the start of the tick (so the
## order in which the two fighters step doesn't matter). Pushing apart and
## hits involve both fighters and are resolved by the `Match` afterwards.
##
## Hold the block button to guard in place, hold crouch to duck under punches,
## hold jump to keep jumping; attack and special presses are buffered.
func step(buttons: int, opponent_x: int) -> void:
	state_ticks += 1
	var pressed := buttons & ~prev_buttons
	prev_buttons = buttons
	var dir := int((buttons & InputSource.RIGHT) != 0) - int((buttons & InputSource.LEFT) != 0)
	attack_buffer = INPUT_BUFFER if (pressed & InputSource.PUNCH) != 0 else maxi(attack_buffer - 1, 0)
	special_buffer = INPUT_BUFFER if (pressed & InputSource.SPECIAL) != 0 else maxi(special_buffer - 1, 0)
	var jump_held := (buttons & InputSource.JUMP) != 0
	var block_held := (buttons & InputSource.BLOCK) != 0
	var crouch_held := (buttons & InputSource.CROUCH) != 0
	var on_floor := pos_y == 0
	if not on_floor:
		vel_y -= GRAVITY
	match state:
		State.IDLE, State.WALK, State.CROUCH:
			face(opponent_x)
			_neutral(dir, jump_held, block_held, crouch_held, on_floor)
		State.JUMP:
			_jump(dir, on_floor)
		State.PUNCH:
			# Rooted and deaf to input until the clip ends; only a hit cuts it short.
			vel_x = 0
			if state_ticks >= PUNCH_LENGTH:
				move_dir = 0
				change_state(State.IDLE)
		State.SWEEP:
			# Like the punch; ends back in the crouch if crouch is still held.
			vel_x = 0
			if state_ticks >= SWEEP_LENGTH:
				if crouch_held:
					change_state(State.CROUCH)
					state_ticks = CROUCH_LENGTH
				else:
					change_state(State.IDLE)
		State.SWEPT:
			# Down, ignoring input and hits, until back on its feet.
			vel_x = 0
			if state_ticks >= SWEPT_LENGTH:
				change_state(State.IDLE)
		State.GRAB:
			# Rooted like the punch; a catch turns it into `THROW` (`Match`).
			vel_x = 0
			if state_ticks >= GRAB_LENGTH:
				move_dir = 0
				change_state(State.IDLE)
		State.THROW:
			# Rooted while the `Match` carries the victim (`carry()`).
			vel_x = 0
			if state_ticks >= THROW_LENGTH:
				move_dir = 0
				change_state(State.IDLE)
		State.THROWN:
			# Carried by the thrower until the slam, then down like `SWEPT`.
			vel_x = 0
			vel_y = 0
			if state_ticks >= THROWN_LENGTH:
				move_dir = 0
				change_state(State.IDLE)
		State.HIT:
			vel_x = _toward_zero(vel_x, KNOCKBACK_FRICTION)
		State.KNOCKED_DOWN:
			vel_x = 0
		State.BLOCK:
			# Rooted during blockstun; afterwards the guard lasts while the
			# button is held. Keeps turning to face the opponent.
			face(opponent_x)
			vel_x = _toward_zero(vel_x, KNOCKBACK_FRICTION)
			if block_stun > 0:
				block_stun -= 1
			else:
				_neutral(dir, jump_held, block_held, crouch_held, on_floor)
	if state == State.HIT and state_ticks >= HIT_STUN:
		change_state(State.IDLE)
	_move()


## Applies velocity: the walls stop (and zero) horizontal motion, the floor
## stops a fall.
func _move() -> void:
	pos_x += vel_x
	if absi(pos_x) > wall_limit:
		pos_x = signi(pos_x) * wall_limit
		vel_x = 0
	pos_y += vel_y
	if pos_y <= 0:
		pos_y = 0
		vel_y = maxi(vel_y, 0)


## Moves the body `dx` along X, stopping at the walls. Returns the distance
## actually travelled.
func shove(dx: int) -> int:
	var start := pos_x
	pos_x = clampi(pos_x + dx, -wall_limit, wall_limit)
	return absi(pos_x - start)


static func _toward_zero(v: int, amount: int) -> int:
	return v - signi(v) * mini(absi(v), amount)


## The simulation state as integers, in a fixed order: every variable
## `step()` reads or writes (the "Simulation state" variables). Equal snapshots mean equal
## fighters; the `Match` hashes them into its per-tick checksum and keeps
## recent ones for rollback (`restore()`).
func snapshot() -> PackedInt64Array:
	return PackedInt64Array([
		pos_x, pos_y, vel_x, vel_y, state, state_ticks, jump_phase, facing,
		move_dir, prev_buttons, attack_buffer, special_buffer, hit_streak, block_stun, health,
		int(attack_landed), wall_limit,
	])


## Number of values in a `snapshot()`.
const SNAPSHOT_SIZE := 17
## Names of the `snapshot()` values, in order (desync logs).
const SNAPSHOT_FIELDS: PackedStringArray = [
	"pos_x", "pos_y", "vel_x", "vel_y", "state", "state_ticks", "jump_phase", "facing",
	"move_dir", "prev_buttons", "attack_buffer", "special_buffer", "hit_streak", "block_stun", "health",
	"attack_landed", "wall_limit",
]


## Sets the simulation state from `values[offset ..]`, a `snapshot()` (the
## same order), so the fighter is exactly as when it was taken. The display
## isn't touched; `sync_visual()` shows the restored state.
func restore(values: PackedInt64Array, offset := 0) -> void:
	pos_x = values[offset]
	pos_y = values[offset + 1]
	vel_x = values[offset + 2]
	vel_y = values[offset + 3]
	state = values[offset + 4] as State
	state_ticks = values[offset + 5]
	jump_phase = values[offset + 6] as JumpPhase
	facing = values[offset + 7]
	move_dir = values[offset + 8]
	prev_buttons = values[offset + 9]
	attack_buffer = values[offset + 10]
	special_buffer = values[offset + 11]
	hit_streak = values[offset + 12]
	block_stun = values[offset + 13]
	health = values[offset + 14]
	attack_landed = values[offset + 15] != 0
	wall_limit = values[offset + 16]


## Neutral (idle, walk, crouch, guard outside blockstun): a buffered special
## press grabs when the special is ready (`special_ready()`, else it does
## nothing), else a held block button guards in place, else a held crouch
## button crouches in place (sweeping on a buffered punch), else a buffered
## punch, then a held jump, else walk or stand.
func _neutral(dir: int, jump_held: bool, block_held: bool, crouch_held: bool, on_floor: bool) -> void:
	if special_buffer > 0 and on_floor and special_ready():
		special_buffer = 0
		attack_buffer = 0
		hit_streak = 0
		vel_x = 0
		move_dir = 0
		change_state(State.GRAB)
	elif block_held and on_floor:
		if state != State.BLOCK:
			vel_x = 0
			block_stun = 0
			change_state(State.BLOCK)
	elif crouch_held and on_floor:
		vel_x = 0
		move_dir = 0
		if attack_buffer > 0:
			attack_buffer = 0
			attack_landed = false
			change_state(State.SWEEP)
		elif state != State.CROUCH:
			change_state(State.CROUCH)
	elif attack_buffer > 0 and on_floor:
		attack_buffer = 0
		vel_x = 0
		attack_landed = false
		change_state(State.PUNCH)
	elif jump_held and on_floor:
		move_dir = dir
		jump_phase = JumpPhase.TAKEOFF
		change_state(State.JUMP)
		vel_x = 0
	else:
		_ground_move(dir)


## Walk at `WALK_SPEED` toward `dir`, or stand when it is 0.
func _ground_move(dir: int) -> void:
	vel_x = dir * WALK_SPEED
	if dir == move_dir and state == (State.WALK if dir != 0 else State.IDLE):
		return
	move_dir = dir
	change_state(State.WALK if dir != 0 else State.IDLE)


## Turns toward an opponent at `opponent_x` if it is now on the other side.
## A walk in progress keeps its direction but switches between forward and
## backward stepping. Turning happens only in idle/walk/block/crouch, so a
## fighter that crosses over mid-jump or mid-punch turns around once back to
## neutral.
func face(opponent_x: int) -> void:
	var dx := opponent_x - pos_x
	if dx == 0 or signi(dx) == facing:
		return
	facing = signi(dx)


## Whole ticks in `seconds` (rounded), for comparing with `state_ticks`.
static func ticks(seconds: float) -> int:
	return roundi(seconds * TICK_RATE)


## True on the active frames of the punch (ticks 5–7), the air kick (ticks
## 4–15 of `KICK`) or the sweep (ticks 6–9).
func is_hitbox_active() -> bool:
	if state == State.PUNCH:
		return state_ticks >= PUNCH_ACTIVE_START and state_ticks < PUNCH_ACTIVE_END
	if state == State.SWEEP:
		return state_ticks >= SWEEP_ACTIVE_START and state_ticks < SWEEP_ACTIVE_END
	if state == State.JUMP and jump_phase == JumpPhase.KICK:
		return state_ticks >= AIR_KICK_ACTIVE_START and state_ticks < AIR_KICK_ACTIVE_END
	return false


## Health the current attack takes off when it lands.
func attack_damage() -> int:
	match state:
		State.PUNCH:
			return PUNCH_DAMAGE
		State.SWEEP:
			return SWEEP_DAMAGE
	return AIR_KICK_DAMAGE


## True if the current attack knocks the victim over (`SWEPT`) instead of a
## hit reaction, through a block: the sweep.
func attack_knocks_over() -> bool:
	return state == State.SWEEP


## Center of the current attack's hitbox in world units, on the facing side.
func hitbox_center() -> Vector2i:
	var offset := AIR_KICK_HITBOX
	match state:
		State.PUNCH:
			offset = PUNCH_HITBOX
		State.SWEEP:
			offset = SWEEP_HITBOX
	return Vector2i(pos_x + facing * offset.x, pos_y + offset.y)


## True if this fighter's attack is live, hasn't landed yet and its hitbox
## overlaps `target`'s hurtbox. The sweep misses a jumping target from the
## moment the jump starts (takeoff included) until it lands: jumping is the
## only way to avoid it.
func attack_connects(target: Fighter) -> bool:
	if not is_hitbox_active() or attack_landed:
		return false
	if state == State.SWEEP and target.state == State.JUMP and target.jump_phase != JumpPhase.LANDING:
		return false
	return target.hurtbox_overlaps(hitbox_center(), HITBOX_HALF)


## True while crouching or sweeping: the hurtbox is low (`CROUCH_HURTBOX_TOP`)
## and an airborne opponent passes over the body instead of being pushed
## (`Match._push_apart`), so it can be jumped over.
func is_low() -> bool:
	return state == State.CROUCH or state == State.SWEEP


## True if the square of half side `half` around `center` overlaps the
## hurtbox: the distance from the square to the hurtbox segment is below
## `BODY_RADIUS`. The segment is shorter while crouching or sweeping.
func hurtbox_overlaps(center: Vector2i, half: int) -> bool:
	var top := CROUCH_HURTBOX_TOP if is_low() else HURTBOX_TOP
	var dx := maxi(maxi(center.x - half - pos_x, pos_x - center.x - half), 0)
	var dy := maxi(maxi(center.y - half - (pos_y + top), pos_y + HURTBOX_BOTTOM - center.y - half), 0)
	return dx * dx + dy * dy < BODY_RADIUS * BODY_RADIUS


## Whether the special is ready: `SPECIAL_HITS` hits landed in a row
## (`hit_streak`), and this fighter may use specials at all.
func special_ready() -> bool:
	return specials_enabled and hit_streak >= SPECIAL_HITS


## Counts a hit this fighter landed (not blocked) toward the special.
func count_hit() -> void:
	hit_streak = mini(hit_streak + 1, SPECIAL_HITS)


## True if this fighter's grab is on its active frames and can catch
## `target`: on the floor, its body center at most `GRAB_RANGE` in front, and
## not reeling, down or already thrown. Guarding and crouching don't help.
func grab_connects(target: Fighter) -> bool:
	if state != State.GRAB or state_ticks < GRAB_ACTIVE_START or state_ticks >= GRAB_ACTIVE_END:
		return false
	match target.state:
		State.HIT, State.KNOCKED_DOWN, State.SWEPT, State.THROWN:
			return false
	if target.pos_y != 0:
		return false
	var ahead := (target.pos_x - pos_x) * facing
	return ahead >= 0 and ahead <= GRAB_RANGE


## The grab caught `target`: this fighter starts the throw (`THROW`) and the
## target is thrown (`THROWN`), both from tick 0, and the target is put on
## the start of `THROW_PATH`. If the landing spot behind would be past the
## wall, this fighter first steps forward so the victim lands at the wall
## and the two still switch sides.
func start_throw(target: Fighter) -> void:
	var land := pos_x + facing * THROW_PATH[-1].y
	var overflow := absi(land) - wall_limit
	if overflow > 0:
		shove(facing * overflow)
	change_state(State.THROW)
	target.move_dir = 0
	target.attack_buffer = 0
	target.special_buffer = 0
	target.block_stun = 0
	target.change_state(State.THROWN)
	carry(target)


## During the throw, up to the slam: puts the thrown `target` where
## `THROW_PATH` has it on this tick, and on `THROW_SLAM` slams it into the
## floor (`slammed()`). Called by the `Match` each tick after both fighters
## stepped.
func carry(target: Fighter) -> void:
	if state != State.THROW or target.state != State.THROWN or state_ticks > THROW_SLAM:
		return
	var offset := throw_offset(state_ticks)
	target.pos_x = clampi(pos_x + facing * offset.x, -target.wall_limit, target.wall_limit)
	target.pos_y = offset.y
	target.vel_x = 0
	target.vel_y = 0
	if state_ticks == THROW_SLAM:
		target.slammed(THROW_DAMAGE)


## `THROW_PATH` at throw tick `t` (forward, up), interpolated in integers.
static func throw_offset(t: int) -> Vector2i:
	var a := THROW_PATH[0]
	for b in THROW_PATH:
		if t <= b.x:
			if b.x == a.x:
				return Vector2i(b.y, b.z)
			var k := t - a.x
			var n := b.x - a.x
			return Vector2i(a.y + (b.y - a.y) * k / n, a.z + (b.z - a.z) * k / n)
		a = b
	return Vector2i(a.y, a.z)


## Hit the floor at the end of a throw: loses `damage` health. At 0 it is
## knocked out, already lying flat (the end of `knockdown`), moved so the
## hips stay put (`KNOCKDOWN_HIPS_BACK`).
func slammed(damage: int) -> void:
	_lose_health(damage)
	if health == 0:
		shove(facing * KNOCKDOWN_HIPS_BACK)
		knock_down()
		state_ticks = KNOCKDOWN_LENGTH


## Ticks since this fighter hit the floor from a sweep or a throw (camera
## shake), or -1 if it didn't.
func floor_impact_ticks() -> int:
	if state == State.SWEPT:
		return state_ticks
	if state == State.THROWN and state_ticks >= THROW_SLAM:
		return state_ticks - THROW_SLAM
	return -1


## Jump: crouch, launch, fall under gravity, then a landing crouch back into
## idle. No air control: the arc follows the direction held during the
## takeoff crouch (the latest non-neutral one, so up then forward a few ticks
## apart still jumps forward). A buffered attack while airborne throws one air
## kick (`KICK`, until touchdown).
func _jump(dir: int, on_floor: bool) -> void:
	match jump_phase:
		JumpPhase.TAKEOFF:
			if dir != 0:
				move_dir = dir
			if state_ticks >= JUMP_TAKEOFF:
				vel_x = move_dir * WALK_SPEED
				vel_y = JUMP_VELOCITY
				_set_jump_phase(JumpPhase.AIR)
		JumpPhase.AIR, JumpPhase.KICK:
			if on_floor and vel_y <= 0:
				vel_x = 0
				_set_jump_phase(JumpPhase.LANDING)
			elif attack_buffer > 0 and jump_phase == JumpPhase.AIR:
				attack_buffer = 0
				attack_landed = false
				_set_jump_phase(JumpPhase.KICK)
		JumpPhase.LANDING:
			if state_ticks >= JUMP_LANDING:
				move_dir = 0
				change_state(State.IDLE)


func _set_jump_phase(phase: JumpPhase) -> void:
	jump_phase = phase
	state_ticks = 0


## Enters `new_state`, restarting its timer (and so its animation).
func change_state(new_state: State) -> void:
	state = new_state
	state_ticks = 0


## Interrupts whatever the fighter is doing with a hit reaction: loses `damage`
## health and is shoved along `push_dir` (±1, the attacker's facing) at
## `KNOCKBACK_SPEED`, sliding to a stop during the stun. The hit that empties
## health knocks the fighter down instead (the clip carries it back). A
## guarding fighter hit from the front (the attacker at `attacker_x` is on the
## side it faces) takes no damage: it stays in the guard for `BLOCK_STUN` and
## slides back at `BLOCK_PUSH_SPEED`. With `knocks_over` (the sweep) the guard
## doesn't help and the fighter falls in place (`SWEPT`) instead of reeling.
## Ignored while down (knocked out or swept) or thrown. Returns true if the
## hit took health (not blocked or ignored).
func take_hit(damage: int, push_dir: int, attacker_x: int, knocks_over: bool) -> bool:
	if state == State.KNOCKED_DOWN or state == State.SWEPT or state == State.THROWN:
		return false
	var side := signi(attacker_x - pos_x)
	if state == State.BLOCK and not knocks_over and (side == facing or side == 0):
		block_stun = BLOCK_STUN
		vel_x = push_dir * BLOCK_PUSH_SPEED
		return false
	_lose_health(damage)
	if health == 0:
		knock_down()
		return true
	if knocks_over:
		vel_x = 0
		change_state(State.SWEPT)
		return true
	vel_x = push_dir * KNOCKBACK_SPEED
	change_state(State.HIT)
	return true


## Takes `damage` off health (down to 0); being hurt ends the hit streak, so
## a ready special is lost too.
func _lose_health(damage: int) -> void:
	health = maxi(health - damage, 0)
	hit_streak = 0


## Knocks the fighter down for good: it stays down (no get-up), ignores input
## and further hits. Also how a KO happens, from `take_hit()` at 0 health.
func knock_down() -> void:
	vel_x = 0
	change_state(State.KNOCKED_DOWN)


## Shows the simulation state: places the node at the body position, puts
## `visual` on the pixel grid, mirrors it along `facing` and poses the model.
func sync_visual() -> void:
	position = Vector3(float(pos_x) / SCALE, float(pos_y) / SCALE, 0.0)
	# The model is authored facing +Z: a quarter turn to +X, mirrored across X
	# for -X so the same side always faces the camera.
	visual.basis = Basis.from_scale(Vector3(facing, 1.0, 1.0)) * Basis(Vector3.UP, PI / 2.0)
	var camera := get_viewport().get_camera_3d() as PixelCamera
	if camera != null:
		visual.global_position = camera.snap(global_position)
	_pose()


## Seeks the animation to the current state's frame: tick `state_ticks` of a
## state shows its clip at `state_ticks * TICK` (wrapped for looping clips,
## held at the end otherwise). The player never advances on its own, so the
## pose is a pure function of the simulation state (also after a rollback).
func _pose() -> void:
	if anim == null:
		return
	var clip := _state_clip()
	var animation := ANIMATIONS.get_animation(clip)
	var length := animation.length
	var end := HIT_RECOIL_END if state == State.HIT else length
	var t := state_ticks * TICK
	if animation.loop_mode != Animation.LOOP_NONE:
		t = fposmod(t, length)
	else:
		t = minf(t, end)
	# One walk clip for both directions: backwards when retreating.
	if state == State.WALK and move_dir * facing < 0:
		t = length - t
	if anim.assigned_animation != clip:
		anim.assigned_animation = clip
	anim.seek(t, true)


## The clip showing the current state (`HIT` is the start of `knockdown`).
func _state_clip() -> StringName:
	match state:
		State.WALK:
			return &"walk"
		State.JUMP:
			return JUMP_CLIPS[jump_phase]
		State.PUNCH:
			return &"punch"
		State.HIT, State.KNOCKED_DOWN:
			return &"knockdown"
		State.BLOCK:
			return &"block"
		State.CROUCH:
			return &"crouch"
		State.SWEEP:
			return &"sweep"
		State.SWEPT:
			return &"swept"
		State.GRAB:
			return &"grab"
		State.THROW:
			return &"throw"
		State.THROWN:
			return &"thrown"
	return &"idle"


## Replaces the current model with the character at `path`. Returns false if it
## fails `CharacterValidator` or can't be loaded; the fighter then keeps its old
## model, or gets `CharacterLoader.DEFAULT_CHARACTER` if it has none yet.
func set_character(path: String) -> bool:
	var new_model := CharacterLoader.load_character(path)
	if new_model == null:
		if model == null and path != CharacterLoader.DEFAULT_CHARACTER:
			set_character(CharacterLoader.DEFAULT_CHARACTER)
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
	# Posed only by `_pose()`, never advanced by Godot's process loop.
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	visual.add_child(model)
	_pose()
	return true
