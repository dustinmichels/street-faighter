class_name LocalInput
extends TickInput
## This machine's player in an online match. Samples `source` (the keyboard by
## default) once per simulated tick and keeps each sample under the tick it is
## for, so the network layer can send it to the peer tagged with that tick.
##
## Input delay: the sample taken while simulating tick `t` is for tick
## `t + delay`, so it has `delay` ticks to reach the peer before either side
## needs it; ticks `0 .. delay - 1` are empty. Both players feel the delay of
## their own `LocalInput`; the peers may use different values. At least 1:
## lockstep needs both samples of a tick before either peer simulates it, and
## a sample taken only when its own tick is simulated would wait forever.

## Default `delay`: 3 ticks (50 ms) covers a one-way latency up to ~50 ms
## without stalling (`docs/netcode.md`).
const DEFAULT_DELAY := 3

## Live source sampled each tick (keyboard and gamepad by default).
@export var source: InputSource = PlayerInput.new()
## Input delay in ticks. Takes effect at the next `start()`.
@export_range(1, 15) var delay := DEFAULT_DELAY


func bind(fighter: Fighter) -> void:
	source.bind(fighter)


func start(match_seed: int) -> void:
	assert(delay >= 1, "LocalInput.delay must be at least 1")
	super(match_seed)
	_inputs.resize(delay)
	_inputs.fill(0)
	source.start(match_seed)


## Always: the sample is taken on demand.
func has_input(_tick: int) -> bool:
	return true


## Samples `source` for tick `tick + delay` when asked for `tick` the first
## time, and returns the sample taken `delay` ticks earlier.
func poll(tick: int) -> int:
	if tick + delay == end_tick():
		_inputs.append(source.poll(tick + delay) & BUTTONS)
	return _inputs[tick]
