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
## Must sit at the same path on both peers (RPCs address it by path).

## Most inputs per packet (1 s); more are only unacknowledged after a long
## stall, and the rest follow once the peer acknowledges the first ones.
const MAX_INPUTS := 60
## Weight of each frame's sample in the smoothed `advantage`.
const ADVANTAGE_SMOOTHING := 0.05
## Lead in ticks (`lead()`) from which this side holds a frame.
const SKIP_THRESHOLD := 1.0
## Fewest frames between two held frames: at most ~5% slower.
const SKIP_INTERVAL := 20

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

## First local tick the peer hasn't acknowledged: packets start here.
var _peer_has := 0
## Physics frames since this side last held a frame.
var _since_skip := 0


func _init() -> void:
	# After the `Match` (priority 0), so this frame's new input goes out now.
	process_physics_priority = 1


## Forgets what the peer acknowledged and the tick sync estimates; call when
## the match (re)starts.
func reset() -> void:
	_peer_has = 0
	remote_tick = 0
	advantage = 0.0
	remote_advantage = 0.0
	_since_skip = 0


## How many ticks this side leads the peer (negative: trails it), from both
## sides' advantages; latency estimate errors common to both cancel out.
func lead() -> float:
	return (advantage - remote_advantage) / 2.0


func _physics_process(_delta: float) -> void:
	if peer_id == 0:
		return
	var tick := 0
	if world != null:
		tick = world.tick
		_sync_ticks()
	_receive_inputs.rpc_id(peer_id, match_id, remote.end_tick(), _peer_has, local.inputs_from(_peer_has, MAX_INPUTS), tick, advantage)


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
## tick `ack - 1`, sends its inputs for ticks `first`, `first + 1`, ..., and
## was at match tick `tick` with tick advantage `peer_advantage`.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_inputs(match_number: int, ack: int, first: int, inputs: PackedByteArray, tick: int, peer_advantage: float) -> void:
	var mp := multiplayer
	if mp == null or mp.get_remote_sender_id() != peer_id or match_number != match_id:
		return
	_peer_has = clampi(ack, _peer_has, local.end_tick())
	remote.receive(first, inputs)
	remote_tick = maxi(remote_tick, tick)
	remote_advantage = peer_advantage
