class_name TickInput
extends InputSource
## Input kept by simulation tick: one sample byte for every tick from 0 up to
## `end_tick() - 1`, all of the match's (an hour is ~216 KB). Base of
## `LocalInput` (sampled on this machine) and `NetworkInput` (received from
## the peer); the network layer sends and receives ranges of it by tick.

var _inputs := PackedByteArray()


func start(_match_seed: int) -> void:
	_inputs.clear()


## The first tick without an input yet (= number of ticks known).
func end_tick() -> int:
	return _inputs.size()


## The samples for ticks `first` .. `first + count - 1` (fewer past the end).
func inputs_from(first: int, count: int) -> PackedByteArray:
	return _inputs.slice(first, first + count)


func has_input(tick: int) -> bool:
	return tick < _inputs.size()


func poll(tick: int) -> int:
	return _inputs[tick]


## The last input known (no buttons before the first): players mostly keep
## holding what they held.
func predict(_tick: int) -> int:
	return _inputs[-1] if not _inputs.is_empty() else 0
