class_name Match
extends Node3D
## Runs the fight: the one place gameplay advances. Each physics tick it polls
## both fighters' input sources (in `fighters` order) and calls `step()`,
## then refreshes the visuals. While an input isn't known yet (online: the
## peer's hasn't arrived) it either stalls (lockstep, `max_rollback` 0) or
## predicts it and simulates on, rewinding and re-simulating once the real
## input turns out different (rollback). `step()` depends only on the
## simulation state and its `inputs`, never on wall-clock time, the scene
## tree order or Godot physics, so two peers fed the same inputs stay
## identical (`docs/netcode.md`).
## Sits on the `World` node: it is ready after the fighters and processes
## before its children (the camera reads this tick's positions).
## In a mirror match (both fighters show the same model), fighter 2 gets
## `CharacterLoader.MIRROR_TINT`. Display only.

## The two fighters, in input order: `inputs[0]` drives `fighters[0]`.
@export var fighters: Array[Fighter] = []
## Its walls bound the fighters.
@export var stage: Stage
## Seed for all of the match's randomness. The simulation itself has none;
## each fighter's input source gets `rng_seed + index` through `start()` (the
## AI's decisions). Randomness added to the rules later must use an RNG
## seeded from this and owned by the match, and be part of its state.
@export var rng_seed := 1
## Rollback: how many ticks the match may simulate past the last tick whose
## inputs are all known, on predicted inputs (`InputSource.predict()`), before
## it stalls. 0 = lockstep (stall at once). Below `HISTORY`, so every tick it
## may have to rewind to is still in the history.
@export_range(0, 9) var max_rollback := 0
## Ticks before this one are the pre-fight countdown: they are simulated, but
## with every input treated as 0, so nobody moves before it. 0 = no countdown.
@export var start_tick := 0

## Ticks of gameplay state kept (`load_tick()`): the states at the start of
## the last `HISTORY` ticks simulated, in a ring buffer.
const HISTORY := 10

## Ticks simulated so far.
var tick := 0
## Hash of the whole gameplay state (`state_checksum()`) after the last
## `step()`. With rollback it may still change for the ticks after
## `confirmed_tick`; peers compare `checksum_at()` of confirmed ticks.
var checksum := 0
## Ticks before this one were simulated with every real input, so their
## states and checksums are final; later ones used predictions. Equal to
## `tick` in lockstep.
var confirmed_tick := 0
## Physics frames spent waiting for an input instead of simulating (stalls),
## for the HUD and tests.
var stalled_frames := 0
## Rewinds done because a prediction was wrong, and the ticks re-simulated.
var rollbacks := 0
var resimulated_ticks := 0
## Physics frames deliberately left unsimulated by `skip_frame()` (tick
## sync), for the HUD and tests.
var skipped_frames := 0

## `save_state()` and `checksum` at the start of tick `t`, and the inputs
## `t` was simulated with, in slot `t % HISTORY`, for the last `HISTORY`
## ticks stepped.
var _states: Array[PackedInt64Array] = []
var _checksums := PackedInt64Array()
var _used_inputs: Array[PackedInt32Array] = []
## `skip_frame()` was called: the next physics frame simulates nothing.
var _skip_next := false


func _ready() -> void:
	assert(fighters.size() == 2, "a match needs exactly two fighters")
	var limit := roundi(stage.half_width * Fighter.SCALE) - Fighter.BODY_RADIUS
	for i in fighters.size():
		fighters[i].wall_limit = limit
		if fighters[i].input != null:
			fighters[i].input.start(rng_seed + i)
	fighters[0].face(fighters[1].pos_x)
	fighters[1].face(fighters[0].pos_x)
	checksum = state_checksum()
	_states.resize(HISTORY)
	_checksums.resize(HISTORY)
	_used_inputs.resize(HISTORY)
	_sync_visuals()
	_tint_mirror()


func _tint_mirror() -> void:
	var second := fighters[1]
	if second.model != null and second.model_path == fighters[0].model_path:
		CharacterLoader.set_tint(second.model, CharacterLoader.MIRROR_TINT)


func _physics_process(_delta: float) -> void:
	assert(max_rollback >= 0 and max_rollback < HISTORY)
	if max_rollback > 0:
		_correct_predictions()
	if _skip_next:
		_skip_next = false
		skipped_frames += 1
	elif tick - confirmed_tick >= max_rollback and not _inputs_known(tick):
		stalled_frames += 1
	else:
		_advance()
	_sync_visuals()


## Leaves the next physics frame without a tick, so this side falls back by
## one tick: online, when it runs ahead of the peer (`InputSync`). Timing
## only; the simulation is unaffected.
func skip_frame() -> void:
	_skip_next = true


## Whether the fight is decided: a fighter has been knocked out (it stays
## down for good). Part of the simulation state, so peers agree on the tick.
func is_over() -> bool:
	for f in fighters:
		if f.state == Fighter.State.KNOCKED_DOWN:
			return true
	return false


## Confirms the predicted ticks whose real inputs have arrived, from
## `confirmed_tick` on. At the first one that was predicted wrong, rewinds to
## it and re-simulates up to the current tick with what is known now.
func _correct_predictions() -> void:
	var now := tick
	while confirmed_tick < now and _inputs_known(confirmed_tick):
		if _inputs(confirmed_tick) != _used_inputs[confirmed_tick % HISTORY]:
			load_tick(confirmed_tick)
			rollbacks += 1
			resimulated_ticks += now - tick
			while tick < now:
				_advance()
			return
		confirmed_tick += 1


## Simulates the current tick with the real inputs where known and
## predictions for the rest.
func _advance() -> void:
	var known := _inputs_known(tick)
	var inputs := _inputs(tick)
	_used_inputs[tick % HISTORY] = inputs
	step(inputs)
	if known and confirmed_tick == tick - 1:
		confirmed_tick = tick


func _inputs_known(t: int) -> bool:
	for f in fighters:
		if f.input != null and not f.input.has_input(t):
			return false
	return true


## Each fighter's input for tick `t`, or its prediction while unknown.
func _inputs(t: int) -> PackedInt32Array:
	var inputs := PackedInt32Array()
	for f in fighters:
		if f.input == null:
			inputs.append(0)
		elif f.input.has_input(t):
			inputs.append(f.input.poll(t))
		else:
			inputs.append(f.input.predict(t))
	return inputs


## Advances the match by one tick with each fighter's input bitmask. Both
## fighters move from where they stood at the start of the tick, a throw in
## progress carries its victim, then overlap and the screen-edge limit are
## resolved, then hits from both sides are detected before any is applied,
## so simultaneous attacks trade. Grabs are checked after the hits: a grab
## that was hit out of, or two grabs at once, catch nobody.
func step(inputs: PackedInt32Array) -> void:
	if tick < start_tick:
		inputs = PackedInt32Array([0, 0])
	_states[tick % HISTORY] = save_state()
	_checksums[tick % HISTORY] = checksum
	var a := fighters[0]
	var b := fighters[1]
	var ax := a.pos_x
	var bx := b.pos_x
	a.step(inputs[0], bx)
	b.step(inputs[1], ax)
	a.carry(b)
	b.carry(a)
	_push_apart(a, b)
	_stay_in_range(a, b, ax, bx)
	var a_hits := a.attack_connects(b)
	var b_hits := b.attack_connects(a)
	if a_hits:
		a.attack_landed = true
		if b.take_hit(a.attack_damage(), a.facing, a.pos_x, a.attack_knocks_over()):
			a.count_hit()
	if b_hits:
		b.attack_landed = true
		if a.take_hit(b.attack_damage(), b.facing, b.pos_x, b.attack_knocks_over()):
			b.count_hit()
	var a_grabs := a.grab_connects(b)
	var b_grabs := b.grab_connects(a)
	if a_grabs and not b_grabs:
		a.start_throw(b)
	elif b_grabs and not a_grabs:
		b.start_throw(a)
	tick += 1
	checksum = state_checksum()


## Sets up the match from an online match config (`Session.match_config`)
## before it is ready: stage `scenery_path` (`"stage"`), `rng_seed`,
## `max_rollback` and `start_tick`. Missing keys keep the scene's values.
## Characters are visual only, so `main.gd` sets them apart.
func apply_config(config: Dictionary) -> void:
	assert(not is_node_ready(), "apply the config before the match is ready")
	if config.has("stage"):
		stage.scenery_path = config["stage"]
	rng_seed = config.get("seed", rng_seed)
	max_rollback = config.get("max_rollback", max_rollback)
	start_tick = config.get("start_tick", start_tick)


## Everything both peers must agree on before the first tick, as this match
## is actually set up (once ready): the applied config plus the values taken
## from the scene files (stage width, start positions, tick rate). Peers
## compare it (`Session`), so a mismatch is found before it desyncs. The
## characters aren't in it: models are visual only, and each side may show
## another one (a fallback, a hidden opponent).
func effective_config() -> Dictionary:
	# Untyped, so they compare equal to the peer's after the trip over RPC.
	var start_x := []
	for f in fighters:
		start_x.append(f.pos_x)
	return {
		"stage": stage.scenery_path,
		"half_width": stage.half_width,
		"start_x": start_x,
		"seed": rng_seed,
		"max_rollback": max_rollback,
		"start_tick": start_tick,
		"tick_rate": Engine.physics_ticks_per_second,
	}


## The whole gameplay state as integers: `tick`, then both fighters'
## `snapshot()`s. `load_state()` returns the match to it exactly.
func save_state() -> PackedInt64Array:
	var values := PackedInt64Array([tick])
	for f in fighters:
		values.append_array(f.snapshot())
	return values


## Returns the match to a `save_state()`, including `tick` and `checksum`.
## Visuals are left as they are until the next `_sync_visuals()`.
func load_state(values: PackedInt64Array) -> void:
	tick = values[0]
	for i in fighters.size():
		fighters[i].restore(values, 1 + i * Fighter.SNAPSHOT_SIZE)
	checksum = _hash(values)


## Whether `load_tick(t)` can return to tick `t`: the current tick, or one of
## the last `HISTORY` ticks stepped through (after a rewind, only those up to
## the tick rewound to).
func has_tick(t: int) -> bool:
	if t == tick:
		return true
	if t < 0 or t > tick or t < tick - HISTORY:
		return false
	var saved := _states[t % HISTORY]
	return not saved.is_empty() and saved[0] == t


## Rewinds the match to the start of tick `t` (`has_tick(t)` must hold), as
## it was when that tick was first reached; stepping again from there
## overwrites the later history.
func load_tick(t: int) -> void:
	assert(has_tick(t), "tick %d is not in the history (now %d)" % [t, tick])
	if t == tick:
		return
	var slot := t % HISTORY
	load_state(_states[slot])
	assert(checksum == _checksums[slot])


## `checksum` at the start of tick `t` (after `t` ticks), for `has_tick(t)`.
func checksum_at(t: int) -> int:
	assert(has_tick(t), "tick %d is not in the history (now %d)" % [t, tick])
	return checksum if t == tick else _checksums[t % HISTORY]


## `save_state()` at the start of tick `t`, for `has_tick(t)` (desync logs).
func state_at(t: int) -> PackedInt64Array:
	assert(has_tick(t), "tick %d is not in the history (now %d)" % [t, tick])
	return save_state() if t == tick else _states[t % HISTORY]


## 32-bit FNV-1a-style hash (over 32-bit words, not bytes) of `tick` and both
## fighters' `snapshot()`s (`save_state()`), each value fed as its two 32-bit
## halves. Integer-only, so it is the same on every platform; equal on two
## peers exactly when their simulations agree (barring a collision).
func state_checksum() -> int:
	return _hash(save_state())


static func _hash(values: PackedInt64Array) -> int:
	var h := 2166136261
	for v in values:
		h = ((h ^ (v & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
		h = ((h ^ ((v >> 32) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	return h


## Bodies never collide, so overlap along X is resolved here: each fighter
## takes half, moving away from the other; if one is blocked by a wall, the
## other takes the rest. Walking into a fighter thus shoves it at half speed.
## An airborne fighter passes over a low one (crouching or sweeping), so a
## jump can cross it; any overlap left on landing pushes each toward the side
## it ended up on. A thrown fighter passes over (and lands clear of) the
## thrower, so nobody is pushed during a throw.
func _push_apart(a: Fighter, b: Fighter) -> void:
	if (a.pos_y > 0 and b.is_low()) or (b.pos_y > 0 and a.is_low()):
		return
	if a.state == Fighter.State.THROWN or b.state == Fighter.State.THROWN:
		return
	var dx := b.pos_x - a.pos_x
	var overlap := Fighter.PUSH_DISTANCE - absi(dx)
	if overlap <= 0:
		return
	# Exactly on top of each other: `a` steps back from where it faces.
	var dir := signi(dx) if dx != 0 else a.facing
	var pushed := b.shove(dir * (overlap / 2))
	pushed += a.shove(-dir * (overlap - pushed))
	b.shove(dir * (overlap - pushed))


## Screen-edge limit: fighters that end the tick more than `MAX_SEPARATION`
## apart step back toward each other, each in proportion to how far it moved
## away this tick (from `ax`/`bx`), so nobody is dragged along by the other.
func _stay_in_range(a: Fighter, b: Fighter, ax: int, bx: int) -> void:
	var dx := b.pos_x - a.pos_x
	var excess := absi(dx) - Fighter.MAX_SEPARATION
	if excess <= 0:
		return
	var dir := signi(dx)
	var a_out := maxi((ax - a.pos_x) * dir, 0)
	var b_out := maxi((b.pos_x - bx) * dir, 0)
	var a_back := excess * a_out / (a_out + b_out) if a_out + b_out > 0 else excess / 2
	a.shove(dir * a_back)
	b.shove(-dir * (excess - a_back))


func _sync_visuals() -> void:
	for f in fighters:
		f.sync_visual()
