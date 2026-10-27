class_name InputSource
extends Resource
## Where a `Fighter` gets its controls from, one sample per simulation tick.
## A sample is a bitmask of the buttons held that tick (fits in a byte, so it
## can be sent over the network or produced by an AI as-is); `Fighter` derives
## direction and fresh presses from it. Subclass and override `poll()`; the
## `Match` calls it once per tick, in tick order, starting at tick 0.

const LEFT := 1
const RIGHT := 2
const JUMP := 4
const PUNCH := 8
const BLOCK := 16
const CROUCH := 32
const SPECIAL := 64
## Every defined button bit. A sample is always within it (one byte on the
## wire, `docs/netcode.md`); bits outside it from the network are dropped.
const BUTTONS := LEFT | RIGHT | JUMP | PUNCH | BLOCK | CROUCH | SPECIAL


## Buttons held at simulation tick `tick` (`LEFT | RIGHT | JUMP | PUNCH |
## BLOCK | CROUCH | SPECIAL` bits). Live sources (keyboard, AI) sample now and ignore `tick`.
## Default: none.
func poll(_tick: int) -> int:
	return 0


## Whether the input for `tick` is known yet, so `poll(tick)` may be called.
## Only remote players' can be missing (not arrived yet). Default: always.
func has_input(_tick: int) -> bool:
	return true


## A guess for a `tick` whose input isn't known yet (`has_input()` false),
## used by rollback until the real one arrives. Default: no buttons.
func predict(_tick: int) -> int:
	return 0


## Called by `Fighter` whenever this source is assigned to it, so sources that
## need to look at the match (an AI) know whom they drive. Default: nothing.
func bind(_fighter: Fighter) -> void:
	pass


## Called by the `Match` before its first tick with a seed derived from the
## match's `rng_seed` (different per fighter). Sources with randomness seed
## from it and reset their state, so a match replays exactly. Default: nothing.
func start(_match_seed: int) -> void:
	pass
