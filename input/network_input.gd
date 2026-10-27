class_name NetworkInput
extends TickInput
## The remote player in an online match: serves the inputs received from the
## peer by tick. The network layer passes each received run of inputs to
## `receive()`; until the input for a tick has arrived, `has_input()` is false
## for it and the `Match` must not simulate that tick.


## Stores the samples `inputs` for ticks `first`, `first + 1`, ... Ticks
## already known are skipped (packets repeat recent inputs for redundancy).
## A run starting past `end_tick()` would leave a gap and is ignored; the
## sender always resends from the first tick this side lacks. Bits outside
## `BUTTONS` are dropped. Returns how many new ticks were stored.
func receive(first: int, inputs: PackedByteArray) -> int:
	var end := end_tick()
	if first < 0 or first > end:
		return 0
	var added := 0
	for i in range(end - first, inputs.size()):
		_inputs.append(inputs[i] & BUTTONS)
		added += 1
	return added
