class_name AIInput
extends InputSource
## Computer opponent for singleplayer. Each tick it looks at its fighter and
## `fighter.opponent` and returns the buttons a player would hold, so `Fighter`
## can't tell it from a human.
##
## Rule-based, in priority order:
## 1. Defense: an incoming punch or jump-in counts as a threat; once per threat
##    it rolls `block_chance`, and on success holds block from `reaction_ticks`
##    into the threat until the attack's active frames are over. A punch that
##    isn't blocked may instead be ducked (`duck_chance`, crouch held the same
##    way); jump-ins aren't ducked, the air kick hits crouchers.
## 2. Duck punish: right after a ducked punch, while the puncher is still
##    recovering and within `SWEEP_RANGE`, it sweeps from the crouch.
## 3. Airborne: throws the air kick as soon as the opponent is within reach.
## 4. A plan, re-rolled every 15–45 ticks from the distance and `aggression`:
##    `ATTACK` (walk into punch range and jab, or sweep with `sweep_chance`;
##    at most one attack per `punch_cooldown_ticks`), `JUMP_IN` (jump toward
##    from mid range, then attack), `RETREAT` (walk back) or `WAIT`.
##
## Randomness comes from its own RNG, seeded by the `Match` through `start()`
## from the match's `rng_seed`, so the same match seed and player inputs
## replay the same match (tick-based, no wall clock). It is input-side
## randomness: only the AI's resulting buttons enter the simulation.

enum Plan { WAIT, ATTACK, RETREAT, JUMP_IN }
## Answer chosen for the current threat.
enum Defense { NONE, BLOCK, DUCK }

## Names the HUD gives a computer opponent (`random_name()`), at most
## `Session.MAX_NAME_LENGTH` characters.
const NAMES: Array[String] = [
	"CHIP", "BYTE", "GLITCH", "NEURO", "VECTOR", "PIXEL", "TENSOR",
	"CIRCUIT", "SPARKY", "MAINFRAME", "OVERCLOCK", "BOTZILLA", "KILOBYTE",
	"ALGO", "SYNTAX", "RUNTIME", "DEBUGGER", "MEGAHERTZ",
]

## Distances below are in `Fighter.SCALE` units (1/10000 m).
## Center-to-center distance at which a punch connects: hitbox reach 0.77 m
## (`Fighter.PUNCH_HITBOX` + half its 0.3 m box) + hurtbox radius 0.3 ≈ 1.07,
## minus a margin so knockback doesn't make it whiff.
const PUNCH_RANGE := 9500
## Same for the air kick (`Fighter.AIR_KICK_HITBOX`): 0.95 + 0.3 ≈ 1.25.
const KICK_RANGE := 11500
## Same for the sweep (`Fighter.SWEEP_HITBOX`): 0.9 + 0.3 ≈ 1.2, minus a margin.
const SWEEP_RANGE := 11000
## Distance band a jump-in starts from: a jump carries ≈ 1.3 m forward.
const JUMP_IN_MIN := 15000
const JUMP_IN_MAX := 24000
## How far away an opponent's punch / jump still counts as a threat.
const PUNCH_THREAT_RANGE := 13000
const JUMP_THREAT_RANGE := 22000
## Plan length range, in ticks.
const PLAN_MIN_TICKS := 15
const PLAN_MAX_TICKS := 45

## Ticks between seeing an attack start and holding block. A punch hits on its
## 5th tick, so values above 4 can't block punches, only jump-ins.
@export_range(1, 30) var reaction_ticks := 4
## Chance (0–1) to try blocking each incoming attack.
@export_range(0.0, 1.0) var block_chance := 0.4
## Chance (0–1) to duck an incoming punch it didn't choose to block.
@export_range(0.0, 1.0) var duck_chance := 0.25
## Chance (0–1) that a ground attack is a sweep instead of a jab.
@export_range(0.0, 1.0) var sweep_chance := 0.25
## Chance (0–1) to pick an offensive plan when re-planning.
@export_range(0.0, 1.0) var aggression := 0.6
## Minimum ticks between ground attack presses (plus 0–15 random).
@export_range(0, 120) var punch_cooldown_ticks := 30

var _fighter: Fighter
var _rng := RandomNumberGenerator.new()
var _plan := Plan.WAIT
var _plan_ticks := 0
var _cooldown := 0
## Consecutive ticks the current threat has lasted (0 = none).
var _threat_ticks := 0
var _defense := Defense.NONE
## Set once a punch was ducked, until the punish sweep or the chance passes.
var _ducked := false


## A random entry of `NAMES`. Cosmetic only: uses the global RNG, not the
## match seed, so it never affects the simulation.
static func random_name() -> String:
	return NAMES.pick_random()


func bind(fighter: Fighter) -> void:
	_fighter = fighter


func start(match_seed: int) -> void:
	_rng.seed = match_seed
	_plan = Plan.WAIT
	_plan_ticks = PLAN_MIN_TICKS
	_cooldown = 0
	_threat_ticks = 0
	_defense = Defense.NONE
	_ducked = false


func poll(_tick: int) -> int:
	if _fighter == null:
		return 0
	var opp := _fighter.opponent
	if opp == null or _fighter.state == Fighter.State.KNOCKED_DOWN or opp.state == Fighter.State.KNOCKED_DOWN:
		return 0
	var dx := opp.pos_x - _fighter.pos_x
	var dist := absi(dx)
	var toward := RIGHT if dx > 0 else LEFT
	var away := LEFT if dx > 0 else RIGHT
	_cooldown = maxi(_cooldown - 1, 0)

	if _is_threat(opp, dist):
		_threat_ticks += 1
		if _threat_ticks == 1:
			var r := _rng.randf()
			_defense = Defense.NONE
			if r < block_chance:
				_defense = Defense.BLOCK
			elif opp.state == Fighter.State.PUNCH and r < block_chance + duck_chance:
				_defense = Defense.DUCK
		if _threat_ticks >= reaction_ticks:
			match _defense:
				Defense.BLOCK:
					return BLOCK
				Defense.DUCK:
					if _fighter.state == Fighter.State.CROUCH:
						_ducked = true
					return CROUCH
	else:
		_threat_ticks = 0
		if _ducked:
			_ducked = false
			if _fighter.state == Fighter.State.CROUCH and opp.state == Fighter.State.PUNCH and dist < SWEEP_RANGE:
				return CROUCH | PUNCH

	if _fighter.state == Fighter.State.JUMP:
		if _fighter.jump_phase == Fighter.JumpPhase.AIR and dist < KICK_RANGE:
			return PUNCH
		return 0

	_plan_ticks -= 1
	if _plan_ticks <= 0:
		_choose_plan(dist)
	var neutral := _fighter.state == Fighter.State.IDLE or _fighter.state == Fighter.State.WALK
	match _plan:
		Plan.ATTACK:
			if dist > PUNCH_RANGE:
				return toward
			if neutral and _cooldown == 0:
				_cooldown = punch_cooldown_ticks + _rng.randi_range(0, 15)
				# Crouch and punch on the same tick comes out as the sweep.
				return CROUCH | PUNCH if _rng.randf() < sweep_chance else PUNCH
		Plan.JUMP_IN:
			if neutral:
				# Direction is locked at the press, so hold it on the same tick.
				_plan = Plan.ATTACK
				return JUMP | toward
		Plan.RETREAT:
			return away
	return 0


## The opponent is starting an attack that can reach us: a punch before its
## active frames end, or a jump (with or without the kick) still in the air.
func _is_threat(opp: Fighter, dist: int) -> bool:
	match opp.state:
		Fighter.State.PUNCH:
			return dist < PUNCH_THREAT_RANGE and opp.state_ticks < Fighter.PUNCH_ACTIVE_END
		Fighter.State.JUMP:
			var airborne := opp.jump_phase == Fighter.JumpPhase.AIR or opp.jump_phase == Fighter.JumpPhase.KICK
			return airborne and dist < JUMP_THREAT_RANGE
	return false


func _choose_plan(dist: int) -> void:
	var r := _rng.randf()
	if dist <= PUNCH_RANGE:
		if r < aggression:
			_plan = Plan.ATTACK
		elif r < aggression + (1.0 - aggression) * 0.5:
			_plan = Plan.RETREAT
		else:
			_plan = Plan.WAIT
	elif dist >= JUMP_IN_MIN and dist <= JUMP_IN_MAX and r < aggression * 0.3:
		_plan = Plan.JUMP_IN
	elif r < aggression:
		_plan = Plan.ATTACK
	else:
		_plan = Plan.WAIT
	_plan_ticks = _rng.randi_range(PLAN_MIN_TICKS, PLAN_MAX_TICKS)
