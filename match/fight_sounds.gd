class_name FightSounds
extends Node
## The fight's sound effects: a whoosh when a fighter throws an attack (punch,
## air kick, sweep), a smack when one gets hit, a heavier thud when one goes
## down (swept, knocked out, slammed by a throw), a dull knock for a blocked
## hit and a rush of air when one leaps off the floor. Sounds are synthesized
## by `match/sounds/build_sounds.gd`.
##
## Display only, like the camera shake: each physics frame, after the `Match`
## stepped (this is its child, so it processes after it), it reads how many
## ticks ago each event started from the fighters' simulation state and plays
## every event once, keyed by its start tick. A stalled frame doesn't repeat
## it, and an event that first shows up after a rollback re-simulated the
## ticks it started in still plays, late, if it is at most `LATE_TICKS` old.
## An event that a rollback takes back has already been heard.

enum Sound {
	SWING,
	HIT,
	HEAVY_HIT,
	BLOCK,
	JUMP,
}

## One stream per `Sound`.
const STREAMS: Array[AudioStream] = [
	preload("res://match/sounds/swing.wav"),
	preload("res://match/sounds/hit.wav"),
	preload("res://match/sounds/heavy_hit.wav"),
	preload("res://match/sounds/block.wav"),
	preload("res://match/sounds/jump.wav"),
]
## Oldest an event may be when first seen and still play: as far as a
## rollback reaches back (`Match.HISTORY`).
const LATE_TICKS := Match.HISTORY
## Random pitch variation per play (`AudioStreamRandomizer.random_pitch`), so
## repeats don't sound identical.
const RANDOM_PITCH := 1.08
## Overlapping plays of the same sound (both fighters, quick repeats).
const POLYPHONY := 4

## The match whose fighters are listened to.
@export var fight: Match

## One player per `Sound`.
var _players: Array[AudioStreamPlayer] = []
## Per fighter, the start tick of the last event played for each `Sound`.
var _played: Array[PackedInt64Array] = []


func _ready() -> void:
	for stream in STREAMS:
		var randomizer := AudioStreamRandomizer.new()
		randomizer.add_stream(0, stream)
		randomizer.random_pitch = RANDOM_PITCH
		var player := AudioStreamPlayer.new()
		player.stream = randomizer
		player.max_polyphony = POLYPHONY
		add_child(player)
		_players.append(player)
	for f in fight.fighters:
		var played := PackedInt64Array()
		played.resize(Sound.size())
		played.fill(-1)
		_played.append(played)


func _physics_process(_delta: float) -> void:
	for i in fight.fighters.size():
		var f := fight.fighters[i]
		_play(i, Sound.SWING, swing_ticks(f))
		_play(i, Sound.HIT, hit_ticks(f))
		_play(i, Sound.HEAVY_HIT, heavy_hit_ticks(f))
		_play(i, Sound.BLOCK, block_ticks(f))
		_play(i, Sound.JUMP, jump_ticks(f))


## Plays `sound` for fighter `index` if its event started `age` ticks ago
## (-1 = none), is at most `LATE_TICKS` old and hasn't been played yet.
func _play(index: int, sound: Sound, age: int) -> void:
	if age < 0 or age > LATE_TICKS:
		return
	var start := fight.tick - age
	if _played[index][sound] == start:
		return
	_played[index][sound] = start
	_players[sound].play()


## Ticks since `f` started its punch, sweep or air kick, or -1. Played from
## the start of the move: the whoosh swells into the first active frame.
static func swing_ticks(f: Fighter) -> int:
	if f.state == Fighter.State.PUNCH or f.state == Fighter.State.SWEEP:
		return f.state_ticks
	if f.state == Fighter.State.JUMP and f.jump_phase == Fighter.JumpPhase.KICK:
		return f.state_ticks
	return -1


## Ticks since `f` was last hit into its hit reaction, or -1.
static func hit_ticks(f: Fighter) -> int:
	return f.state_ticks if f.state == Fighter.State.HIT else -1


## Ticks since `f` was swept, knocked out by a hit, or slammed its throw
## victim into the floor, or -1. A knockout by throw starts `KNOCKED_DOWN`
## past `LATE_TICKS` (already flat), so only the thrower's slam sounds.
static func heavy_hit_ticks(f: Fighter) -> int:
	if f.state == Fighter.State.SWEPT or f.state == Fighter.State.KNOCKED_DOWN:
		return f.state_ticks
	return f.slam_impact_ticks()


## Ticks since `f` last blocked a hit (during its blockstun), or -1.
static func block_ticks(f: Fighter) -> int:
	if f.state == Fighter.State.BLOCK and f.block_stun > 0:
		return Fighter.BLOCK_STUN - f.block_stun
	return -1


## Ticks since `f` left the floor (the end of the takeoff crouch), or -1. Only
## while airborne without kicking: an air kick restarts the phase timer, and
## the launch sounded before it.
static func jump_ticks(f: Fighter) -> int:
	if f.state == Fighter.State.JUMP and f.jump_phase == Fighter.JumpPhase.AIR:
		return f.state_ticks
	return -1
