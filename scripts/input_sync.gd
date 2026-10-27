class_name InputSync
extends Node
## Exchanges inputs with the peer in an online match (`docs/netcode.md`).
## Every physics frame, after the `Match` has stepped, it sends the peer one
## unreliable packet with every `local` input the peer hasn't acknowledged
## yet (at most `MAX_INPUTS`) and an acknowledgement of the `remote` inputs
## received so far. A lost packet is never resent as such: the next one
## (a frame later) carries the same inputs again, until the peer acknowledges
## them. Packets go out even while the match stalls, so the acks keep flowing
## and a lost packet can't leave both sides waiting for each other.
##
## Tick sync: each packet also carries the sender's `Match.tick` and its
## smoothed `advantage` (how many ticks it thinks it is ahead of the peer,
## from the peer's last reported tick plus half the round trip). Half the
## difference of the two sides' advantages is how far this side really leads
## (the latency terms cancel); if that is at least `SKIP_THRESHOLD`, it
## holds `world` for one frame (`Match.skip_frame()`), at most every
## `SKIP_INTERVAL` frames, so a peer whose clock runs fast slows down
## slightly instead of running into the input delay and stalling in bursts.
##
## Timeout: if no packet from the peer arrives for `TIMEOUT_SECONDS` (wall
## clock, counted from `reset()`), it emits `timed_out` once and stops.
##
## Desync detection: each packet also carries the checksum of the sender's
## latest confirmed tick (`Match.confirmed_tick`, final on both sides). This
## side keeps its own confirmed checksums and states, and the peer's
## checksums, for the last `CHECK_HISTORY` ticks, and compares them wherever
## both are known. On a mismatch it freezes the match, stops sending inputs
## and sends the peer its state at that tick (reliable); the peer, told or
## finding the mismatch itself, does the same. The earliest mismatched tick
## either side reports wins. Once the peer's state for it arrives (or after
## `DESYNC_WAIT_SECONDS` without it) it emits `desynced` once and stops.
##
## Packet loss: each packet carries a sequence number (+1 per packet sent,
## from 0 at `reset()`); gaps in the received ones are lost (or arrived late
## and were dropped by the ordered channel). `packets_received`/`packets_lost`
## count them since `reset()`, `packet_loss` is the lost share over the last
## `LOSS_WINDOW` sequence numbers, for the HUD's debug overlay.
##
## Simulated network conditions (local testing, `apply_sim_args()`): with
## `sim_latency_ms`, `sim_jitter_ms` or `sim_loss` set, every input packet
## this side sends and receives is dropped with chance `sim_loss`, else
## delayed by `sim_latency_ms` plus a random 0..`sim_jitter_ms`, both ways,
## so setting them on one instance shapes the whole round trip. Jitter can
## reorder packets; the older ones are then dropped as on a real ordered
## channel. ENet doesn't see the delay, so `rtt_ms` (used for tick sync,
## where an error common to both sides cancels) leaves it out; `ping_ms()`
## adds it. The reliable desync reports aren't affected.
##
## Must sit at the same path on both peers (RPCs address it by path).

## No packet from the peer for `TIMEOUT_SECONDS`; this node has stopped.
signal timed_out
## The peers' confirmed states differ at tick `tick`: `own_state` /
## `peer_state` are both sides' `Match.state_at(tick)` (empty if that side
## had no record of it). The match is frozen and this node has stopped.
signal desynced(tick: int, own_state: PackedInt64Array, peer_state: PackedInt64Array)

## Most inputs per packet (1 s); more are only unacknowledged after a long
## stall, and the rest follow once the peer acknowledges the first ones.
const MAX_INPUTS := 60
## Weight of each frame's sample in the smoothed `advantage`.
const ADVANTAGE_SMOOTHING := 0.05
## Lead in ticks (`lead()`) from which this side holds a frame.
const SKIP_THRESHOLD := 1.0
## Fewest frames between two held frames: at most ~5% slower.
const SKIP_INTERVAL := 20
## Seconds without a packet from the peer before `timed_out`. Packets come
## every frame, so this is ~300 lost in a row; ENet's own peer timeout
## (unacknowledged reliable traffic) can take up to 30 s.
const TIMEOUT_SECONDS := 5.0
## Confirmed ticks whose checksums (own and the peer's) and own states are
## kept for comparison: ~2 s, well beyond how far the peers can drift apart.
const CHECK_HISTORY := 128
## Seconds to wait for the peer's state after a desync before giving up on
## it and emitting `desynced` with this side's only.
const DESYNC_WAIT_SECONDS := 2.0
## Sequence numbers per `packet_loss` sample (~1 s of packets).
const LOSS_WINDOW := 60

## This machine's player, the inputs sent.
@export var local: LocalInput
## The other player, filled from the packets received.
@export var remote: NetworkInput
## The match being synced: its tick is reported to the peer and it is held
## for a frame when this side runs ahead. null = no tick sync.
@export var world: Match
## Multiplayer peer id of the other player; packets from anyone else are
## ignored. 0 = not connected, nothing is sent.
var peer_id := 0
## Which match of the session this is (`Session.match_number`); packets
## tagged with another one (a late packet from before a rematch) are ignored.
var match_id := 0
## Round-trip time to the peer in ms (ENet's smoothed measure), 0 if unknown.
var rtt_ms := 0
## The peer's `Match.tick` as of its last packet.
var remote_tick := 0
## Smoothed ticks this side is ahead of the peer: own tick minus the peer's
## last reported tick advanced by half the round trip.
var advantage := 0.0
## The peer's `advantage`, from its last packet.
var remote_advantage := 0.0
## Valid packets received from the peer, and packets of it missing in the
## sequence, since `reset()`.
var packets_received := 0
var packets_lost := 0
## Lost share (0–1) of the peer's last full `LOSS_WINDOW` packets.
var packet_loss := 0.0
## Simulated one-way latency and extra random delay (ms) and loss chance
## (0–1), applied to input packets in both directions. All 0 = off.
var sim_latency_ms := 0
var sim_jitter_ms := 0
var sim_loss := 0.0

## First local tick the peer hasn't acknowledged: packets start here.
var _peer_has := 0
## Physics frames since this side last held a frame.
var _since_skip := 0
## `Time.get_ticks_msec()` of the last packet from the peer (or `reset()`).
var _last_packet_msec := 0
## Own confirmed checksums and states, and the peer's checksums, by tick in
## slot `tick % CHECK_HISTORY`; `_own_ticks`/`_peer_ticks` hold each slot's
## tick (-1 = empty).
var _own_ticks := PackedInt64Array()
var _own_sums := PackedInt64Array()
var _own_states: Array[PackedInt64Array] = []
var _peer_ticks := PackedInt64Array()
var _peer_sums := PackedInt64Array()
## Next own confirmed tick to record.
var _recorded := 0
## The mismatched tick being reported (-1 = in sync), when the report
## started, and whether `desynced` was emitted.
var _desync_tick := -1
var _desync_msec := 0
var _desync_done := false
## Sequence number of the next packet sent, and of the latest received
## (-1 = none yet).
var _send_seq := 0
var _recv_seq := -1
## First sequence number of the current `packet_loss` window (exclusive)
## and the packets lost in it so far.
var _window_start := 0
var _window_lost := 0
## Simulated in-flight packets, `[release msec, rpc args]`, by release time:
## sent ones not yet handed to ENet, and received ones not yet processed.
var _outbox: Array[Array] = []
var _inbox: Array[Array] = []
var _sim_rng := RandomNumberGenerator.new()


func _init() -> void:
	# After the `Match` (priority 0), so this frame's new input goes out now.
	process_physics_priority = 1


## Forgets what the peer acknowledged, the tick sync estimates, the
## checksums and the packet counts; call when the match (re)starts.
func reset() -> void:
	_peer_has = 0
	remote_tick = 0
	advantage = 0.0
	remote_advantage = 0.0
	_since_skip = 0
	_last_packet_msec = Time.get_ticks_msec()
	_own_ticks.resize(CHECK_HISTORY)
	_own_ticks.fill(-1)
	_own_sums.resize(CHECK_HISTORY)
	_own_states.resize(CHECK_HISTORY)
	_own_states.fill(PackedInt64Array())
	_peer_ticks.resize(CHECK_HISTORY)
	_peer_ticks.fill(-1)
	_peer_sums.resize(CHECK_HISTORY)
	_recorded = 0
	_desync_tick = -1
	_desync_done = false
	packets_received = 0
	packets_lost = 0
	packet_loss = 0.0
	_send_seq = 0
	_recv_seq = -1
	_window_start = 0
	_window_lost = 0
	_outbox.clear()
	_inbox.clear()


## How many ticks this side leads the peer (negative: trails it), from both
## sides' advantages; latency estimate errors common to both cancel out.
func lead() -> float:
	return (advantage - remote_advantage) / 2.0


## Round trip to the peer as players would see it (ms, 0 if unknown):
## `rtt_ms` plus the simulated delay of both directions (mean jitter).
func ping_ms() -> int:
	if rtt_ms <= 0:
		return 0
	return rtt_ms + 2 * sim_latency_ms + sim_jitter_ms


## Whether network conditions are being simulated.
func is_simulating() -> bool:
	return sim_latency_ms > 0 or sim_jitter_ms > 0 or sim_loss > 0.0


## Sets the simulated conditions from command-line user args
## `--net-latency=MS`, `--net-jitter=MS` and `--net-loss=PERCENT` (others
## ignored; values clamped to 0–1000 ms, 0–100 %).
func apply_sim_args(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--net-latency="):
			sim_latency_ms = clampi(int(arg.get_slice("=", 1)), 0, 1000)
		elif arg.begins_with("--net-jitter="):
			sim_jitter_ms = clampi(int(arg.get_slice("=", 1)), 0, 1000)
		elif arg.begins_with("--net-loss="):
			sim_loss = clampf(float(arg.get_slice("=", 1)) / 100.0, 0.0, 1.0)
	_sim_rng.randomize()


func _physics_process(_delta: float) -> void:
	if peer_id == 0:
		return
	_release(_inbox, _process_packet)
	if _desync_tick >= 0:
		if Time.get_ticks_msec() - _desync_msec > DESYNC_WAIT_SECONDS * 1000.0:
			_finish_desync(PackedInt64Array())
		return
	if Time.get_ticks_msec() - _last_packet_msec > TIMEOUT_SECONDS * 1000.0:
		set_physics_process(false)
		timed_out.emit()
		return
	var tick := 0
	var check_tick := -1
	var check_sum := 0
	if world != null:
		tick = world.tick
		_record_checksums()
		if _desync_tick >= 0:
			return
		check_tick = world.confirmed_tick
		check_sum = world.checksum_at(check_tick)
		_sync_ticks()
	_send([match_id, remote.end_tick(), _peer_has, local.inputs_from(_peer_has, MAX_INPUTS), tick, advantage, check_tick, check_sum, _send_seq])
	_send_seq += 1
	_release(_outbox, _transmit)


## Sends an input packet (`_receive_inputs` args) to the peer, through the
## simulated network if on.
func _send(args: Array) -> void:
	if is_simulating():
		_delay(_outbox, args)
	else:
		_transmit(args)


func _transmit(args: Array) -> void:
	callv(&"rpc_id", [peer_id, &"_receive_inputs"] + args)


## Simulated network: drops a packet with chance `sim_loss`, else queues it
## in `queue` until its delay is up.
func _delay(queue: Array[Array], args: Array) -> void:
	if _sim_rng.randf() < sim_loss:
		return
	var due := Time.get_ticks_msec() + sim_latency_ms + _sim_rng.randi_range(0, sim_jitter_ms)
	var i := queue.size()
	while i > 0 and queue[i - 1][0] > due:
		i -= 1
	queue.insert(i, [due, args])


## Simulated network: passes the args of each packet in `queue` whose delay
## is up to `deliver`, in release order.
func _release(queue: Array[Array], deliver: Callable) -> void:
	var now := Time.get_ticks_msec()
	while not queue.is_empty() and queue[0][0] <= now:
		deliver.call(queue.pop_front()[1])


## Records the own checksums and states of the ticks confirmed since the
## last frame, comparing each with the peer's if known.
func _record_checksums() -> void:
	while _recorded <= world.confirmed_tick and _desync_tick < 0:
		var t := _recorded
		_recorded += 1
		if not world.has_tick(t):
			continue
		var slot := t % CHECK_HISTORY
		_own_ticks[slot] = t
		_own_sums[slot] = world.checksum_at(t)
		_own_states[slot] = world.state_at(t)
		_compare(t)


## Starts a desync report if both sides' checksums for tick `t` are known
## and differ.
func _compare(t: int) -> void:
	var slot := t % CHECK_HISTORY
	if _own_ticks[slot] == t and _peer_ticks[slot] == t and _own_sums[slot] != _peer_sums[slot]:
		_start_desync(t)


## Freezes the match and sends the peer this side's state at the mismatched
## tick `t`, unless an earlier tick is already being reported.
func _start_desync(t: int) -> void:
	if _desync_tick >= 0 and _desync_tick <= t:
		return
	_desync_tick = t
	_desync_msec = Time.get_ticks_msec()
	if world != null:
		world.set_physics_process(false)
	_receive_desync_state.rpc_id(peer_id, match_id, t, _own_state(t))


## This side's recorded state at tick `t`, empty if there is none.
func _own_state(t: int) -> PackedInt64Array:
	var slot := t % CHECK_HISTORY
	return _own_states[slot] if _own_ticks[slot] == t else PackedInt64Array()


func _finish_desync(peer_state: PackedInt64Array) -> void:
	if _desync_done:
		return
	_desync_done = true
	set_physics_process(false)
	desynced.emit(_desync_tick, _own_state(_desync_tick), peer_state)


## Updates `rtt_ms` and `advantage`, and holds the match for a frame if this
## side leads by `SKIP_THRESHOLD` or more.
func _sync_ticks() -> void:
	rtt_ms = _measure_rtt()
	var half_rtt_ticks := rtt_ms * Engine.physics_ticks_per_second / 2000.0
	var sample := world.tick - (remote_tick + half_rtt_ticks)
	advantage += (sample - advantage) * ADVANTAGE_SMOOTHING
	_since_skip += 1
	if _since_skip >= SKIP_INTERVAL and lead() >= SKIP_THRESHOLD:
		world.skip_frame()
		_since_skip = 0


func _measure_rtt() -> int:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return 0
	var packet_peer := enet.get_peer(peer_id)
	if packet_peer == null:
		return 0
	return int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## A packet from the peer's match `match_number`: it has our inputs up to
## tick `ack - 1`, sends its inputs for ticks `first`, `first + 1`, ..., was
## at match tick `tick` with tick advantage `peer_advantage`, its checksum
## at its confirmed tick `check_tick` is `check_sum` (-1: none), and it is
## its packet number `seq`. Dropped whole if any value is impossible
## (`_valid_packet()`, `_valid_seq()`). Packets with the wrong argument
## count or types never get here: Godot's RPC layer rejects them (with an
## error in the log).
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_inputs(match_number: int, ack: int, first: int, inputs: PackedByteArray, tick: int, peer_advantage: float, check_tick: int, check_sum: int, seq: int) -> void:
	var mp := multiplayer
	if mp == null or mp.get_remote_sender_id() != peer_id or match_number != match_id:
		return
	if not _valid_seq(seq) or not _valid_packet(ack, first, inputs, tick, peer_advantage, check_tick, check_sum):
		return
	_count_packet(seq)
	_peer_has = maxi(ack, _peer_has)
	_last_packet_msec = Time.get_ticks_msec()
	remote.receive(first, inputs)
	remote_tick = maxi(remote_tick, tick)
	remote_advantage = peer_advantage
	if check_tick >= 0 and _desync_tick < 0 and not _peer_ticks.is_empty():
		var slot := check_tick % CHECK_HISTORY
		_peer_ticks[slot] = check_tick
		_peer_sums[slot] = check_sum
		_compare(check_tick)


## Updates the packet counts for a new packet numbered `seq` (above any
## before). The first one after `reset()` starts the count: the peer may
## have begun sending before this side was ready.
func _count_packet(seq: int) -> void:
	packets_received += 1
	if _recv_seq < 0:
		_window_start = seq - 1
	else:
		packets_lost += seq - _recv_seq - 1
		_window_lost += seq - _recv_seq - 1
	_recv_seq = seq
	if seq - _window_start >= LOSS_WINDOW:
		packet_loss = float(_window_lost) / (seq - _window_start)
		_window_start = seq
		_window_lost = 0


## Whether `seq` can be the peer's next packet number: above the last one,
## and (after the first) no further ahead than the packets of
## `TIMEOUT_SECONDS`, twice over for frame rate slack; a longer gap would
## have timed out.
func _valid_seq(seq: int) -> bool:
	if seq <= _recv_seq:
		return false
	return _recv_seq < 0 or seq - _recv_seq <= 2.0 * TIMEOUT_SECONDS * Engine.physics_ticks_per_second


## Whether an input packet's values are possible for a well-behaved peer:
## at most `MAX_INPUTS` inputs with only `InputSource.BUTTONS` bits,
## starting at a known tick or the next one (no gap; ticks before are
## repeats and harmless), an ack of no more than was sent, a match tick and
## confirmed tick no further ahead than our inputs allow (plus rollback), a
## finite advantage below `TIMEOUT_SECONDS` worth of ticks (peers further
## apart time out) and a 32-bit checksum.
func _valid_packet(ack: int, first: int, inputs: PackedByteArray, tick: int, peer_advantage: float, check_tick: int, check_sum: int) -> bool:
	if inputs.size() > MAX_INPUTS or first < 0 or first > remote.end_tick():
		return false
	for b in inputs:
		if b & ~InputSource.BUTTONS:
			return false
	# The peer can't simulate a tick before it has our input for it, except
	# on predictions, at most `Match.HISTORY` ticks.
	if ack < 0 or ack > local.end_tick() or tick < 0 or tick > local.end_tick() + Match.HISTORY:
		return false
	if check_tick < -1 or check_tick > mini(tick, local.end_tick()) or check_sum < 0 or check_sum > 0xFFFFFFFF:
		return false
	return is_finite(peer_advantage) and absf(peer_advantage) <= TIMEOUT_SECONDS * Engine.physics_ticks_per_second


## The peer found its state at `tick` differs from ours (`state`, empty if
## it had none). Reports the same tick back if it is the earliest known, and
## finishes once both states for the reported tick are known. Ignored if
## `tick` is outside the checksum window, `state` isn't a `Match.state_at()`
## of `tick`, or it equals ours (no desync).
@rpc("any_peer", "call_remote", "reliable")
func _receive_desync_state(match_number: int, tick: int, state: PackedInt64Array) -> void:
	var mp := multiplayer
	if mp == null or mp.get_remote_sender_id() != peer_id or match_number != match_id or _desync_done:
		return
	if tick < maxi(_recorded - CHECK_HISTORY, 0) or tick > local.end_tick():
		return
	if not state.is_empty() and (state.size() != 1 + 2 * Fighter.SNAPSHOT_SIZE or state[0] != tick or state == _own_state(tick)):
		return
	_start_desync(tick)
	if tick == _desync_tick:
		_finish_desync(state)
