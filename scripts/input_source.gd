class_name InputSource
extends Resource
## Where a `Fighter` gets its controls from, one sample per physics tick.
## A sample is a bitmask of the buttons held that tick (fits in a byte, so it
## can be sent over the network or produced by an AI as-is); `Fighter` derives
## direction and fresh presses from it. Subclass and override `poll()`.

const LEFT := 1
const RIGHT := 2
const JUMP := 4
const PUNCH := 8


## Buttons held this tick (`LEFT | RIGHT | JUMP | PUNCH` bits). Default: none.
func poll() -> int:
	return 0
