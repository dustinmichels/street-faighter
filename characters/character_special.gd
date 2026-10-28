class_name CharacterSpecial
extends RefCounted
## A custom character's own special throw: how both bodies move from the tick
## the grab connects until the victim hits the floor. It replaces the standard
## `throw` (thrower) and `thrown` (victim) clips on both fighters while this
## character throws. Display only: the simulation keeps the standard throw's
## timing, damage and landing spot (`Fighter.THROW_PATH`), so a side that
## shows another model (a fallback, a hidden opponent) simulates identically.
##
## The data is in the character's `.glb`, in the top-level glTF `extras`
## (`EXTRAS_KEY` → `SPECIAL_KEY`), where the creator kit's `kit.py` puts it.
## `CharacterValidator` checks it with `parse()`:
##
##     {"version": 1,
##      "attacker": [{"tick": 0, "pose": {...}}, ...],
##      "victim": [{"tick": 0, "pose": {...}, "root": [forward, up]}, ...]}
##
## Ticks count `Fighter` ticks (60 per second) from the grab connecting. A
## pose maps bone names to `[x, y, z]` degrees and `hips_pos` to `[x, y, z]`
## meters, exactly like the pose tables in `animations/build_base.gd`
## (unlisted bones hold their rest, the T-pose). The attacker's keys run
## before `Fighter.THROW_LENGTH`, where the game adds the stance. The
## victim's run before `Fighter.THROW_SLAM`, where it lies on its back at the
## end of `THROW_PATH` and the standard `thrown` clip takes over (bounce,
## lie, get up). `root` is the victim's body origin (its feet at rest)
## relative to the thrower's, in meters, forward along the thrower's facing
## and up; the victim faces the thrower. Keys interpolate linearly (rotations
## along the shorter way round); before the first key, the first one holds.
## `kit_base()` is what a creator kit needs to author one.

const BUILD := preload("res://animations/build_base.gd")
const VERSION := 1
## glTF top-level `extras` key holding the game's data, and its key for the special.
const EXTRAS_KEY := "street_faighter"
const SPECIAL_KEY := "special"
## Where `CharacterLoader.load_character()` leaves the parsed special on the
## model's root node (`of()`).
const META := &"character_special"
## Name of `library()` in a fighter's `AnimationPlayer`.
const LIBRARY_NAME := &"special"
## Limits per side and per value, far beyond any sensible throw.
const MAX_KEYS := 64
const MAX_ANGLE := 360.0
## Farthest `hips_pos` may move the hips from their rest position, per axis (m).
const MAX_HIPS_OFFSET := 2.0
## Range of the victim's `root` (m).
const MAX_FORWARD := 3.0
const MIN_UP := -1.0
const MAX_UP := 3.0

## Problems `parse()` found, one per line (empty = usable).
var errors := PackedStringArray()

# Keys in `BUILD.build()` format ([seconds, pose]), the game's own keys added.
var _attacker := []
var _victim := []
# The victim's root as (tick, forward, up), the landing spot added.
var _root: Array[Vector3] = []
var _library: AnimationLibrary

# `BUILD.reference_rest()`, loaded once.
static var _rest := { }


## The special in `data` (the value of `SPECIAL_KEY`). Check `errors` before
## using it.
static func parse(data: Variant) -> CharacterSpecial:
	var special := CharacterSpecial.new()
	if not data is Dictionary:
		special.errors.append("Special: must be an object with 'version', 'attacker' and 'victim'")
		return special
	var version: Variant = data.get("version")
	if not _finite(version) or version != VERSION:
		special.errors.append(
			"Special: 'version' is %s; this game reads version %d" % [_short(version), VERSION]
		)
		return special
	var attacker := special._keys(data.get("attacker"), "attacker", Fighter.THROW_LENGTH, false)
	var victim := special._keys(data.get("victim"), "victim", Fighter.THROW_SLAM, true)
	if not special.errors.is_empty():
		return special
	for key: Array in attacker:
		special._attacker.append([_seconds(key[0]), key[1]])
	special._attacker.append([_seconds(Fighter.THROW_LENGTH), BUILD.STANCE])
	for key: Array in victim:
		special._victim.append([_seconds(key[0]), key[1]])
		special._root.append(Vector3(key[0], key[2].x, key[2].y))
	for key: Array in BUILD.thrown():
		if Fighter.ticks(key[0]) >= Fighter.THROW_SLAM:
			special._victim.append(key)
	var landing := Fighter.THROW_PATH[-1]
	special._root.append(
		Vector3(Fighter.THROW_SLAM, float(landing.y) / Fighter.SCALE, float(landing.z) / Fighter.SCALE)
	)
	return special


## The special a `CharacterLoader.load_character()` model carries, or null.
static func of(model: Node) -> CharacterSpecial:
	return model.get_meta(META) as CharacterSpecial if model.has_meta(META) else null


## The clips, named like the standard ones they replace: `throw` (the
## thrower, `Fighter.THROW_LENGTH` long) and `thrown` (the victim,
## `Fighter.THROWN_LENGTH` long). Built on first use.
func library() -> AnimationLibrary:
	if _library == null:
		if _rest.is_empty():
			_rest = BUILD.reference_rest()
		_library = AnimationLibrary.new()
		_library.add_animation(
			&"throw",
			BUILD.build(_seconds(Fighter.THROW_LENGTH), false, false, _attacker, _rest),
		)
		_library.add_animation(
			&"thrown",
			BUILD.build(_seconds(Fighter.THROWN_LENGTH), false, false, _victim, _rest),
		)
	return _library


## The victim's body origin on throw tick `tick`, relative to the thrower's:
## (forward along the thrower's facing, up), in meters.
func victim_root(tick: int) -> Vector2:
	var a := _root[0]
	if tick <= a.x:
		return Vector2(a.y, a.z)
	for b in _root:
		if tick <= b.x:
			var w := (tick - a.x) / (b.x - a.x)
			return Vector2(lerpf(a.y, b.y, w), lerpf(a.z, b.z, w))
		a = b
	return Vector2(a.y, a.z)


## What a creator kit needs to author a special, saved in every kit
## (`CreatorKit.write()`): the timing (`throw_ticks`, `slam_tick`,
## `thrown_ticks`), the victim's `landing` spot ([forward, up] m), the keys the
## game adds (`poses.stance` at `throw_ticks`, `after_slam` from `slam_tick`
## on), the `poses.grab` the throw starts from, and `standard`: the standard
## throw in the special format, a working example.
static func kit_base() -> Dictionary:
	var attacker := []
	for key: Array in BUILD.throw():
		var tick := Fighter.ticks(key[0])
		if tick < Fighter.THROW_LENGTH:
			attacker.append({ "tick": tick, "pose": _pose_json(key[1]) })
	var victim := []
	var after_slam := []
	for key: Array in BUILD.thrown():
		var tick := Fighter.ticks(key[0])
		if tick < Fighter.THROW_SLAM:
			var root := Fighter.throw_offset(tick)
			victim.append(
				{
					"tick": tick,
					"pose": _pose_json(key[1]),
					"root": [float(root.x) / Fighter.SCALE, float(root.y) / Fighter.SCALE],
				}
			)
		else:
			after_slam.append({ "tick": tick, "pose": _pose_json(key[1]) })
	var landing := Fighter.THROW_PATH[-1]
	return {
		"version": VERSION,
		"throw_ticks": Fighter.THROW_LENGTH,
		"slam_tick": Fighter.THROW_SLAM,
		"thrown_ticks": Fighter.THROWN_LENGTH,
		"landing": [float(landing.y) / Fighter.SCALE, float(landing.z) / Fighter.SCALE],
		"poses": { "stance": _pose_json(BUILD.STANCE), "grab": _pose_json(BUILD.GRAB) },
		"after_slam": after_slam,
		"standard": { "version": VERSION, "attacker": attacker, "victim": victim },
	}


# Checks one side's key list; returns [tick, pose, root] per key.
func _keys(list: Variant, side: String, end_tick: int, with_root: bool) -> Array:
	var shape := "{'tick', 'pose', 'root'}" if with_root else "{'tick', 'pose'}"
	if not list is Array or list.is_empty():
		errors.append("Special: '%s' must be a list of 1–%d keys %s" % [side, MAX_KEYS, shape])
		return []
	if list.size() > MAX_KEYS:
		errors.append("Special: '%s' has %d keys; the limit is %d" % [side, list.size(), MAX_KEYS])
		return []
	var out := []
	var last := -1
	for i in list.size():
		var label := "Special: %s[%d]" % [side, i]
		var key: Variant = list[i]
		if not key is Dictionary:
			errors.append("%s must be an object %s" % [label, shape])
			continue
		var tick := _whole(key.get("tick"))
		if tick < 0:
			errors.append(
				"%s: 'tick' must be a whole number 0–%d, not %s"
				% [label, end_tick - 1, _short(JSON.stringify(key.get("tick")))]
			)
			continue
		if tick >= end_tick:
			errors.append("%s: tick %d is outside 0–%d" % [label, tick, end_tick - 1])
			continue
		if tick <= last:
			errors.append("%s: tick %d must come after the previous key's (%d)" % [label, tick, last])
		last = maxi(last, tick)
		var pose := _pose(key.get("pose"), label)
		var root := _root_offset(key.get("root"), label) if with_root else Vector2.ZERO
		out.append([tick, pose, root])
	return out


func _pose(value: Variant, label: String) -> Dictionary:
	if not value is Dictionary:
		errors.append("%s: 'pose' must be an object of bone name → [x, y, z]" % label)
		return { }
	var pose := { }
	for name: Variant in value:
		var v: Variant = _vec3(value[name])
		if name == String(BUILD.HIPS_POS):
			if v == null:
				errors.append("%s: 'hips_pos' must be 3 numbers (meters)" % label)
			elif absf(v.x) > MAX_HIPS_OFFSET or absf(v.y) > MAX_HIPS_OFFSET or absf(v.z) > MAX_HIPS_OFFSET:
				errors.append(
					"%s: 'hips_pos' %s moves the hips more than %.0f m" % [label, v, MAX_HIPS_OFFSET]
				)
			else:
				pose[BUILD.HIPS_POS] = v
		elif name in CharacterLoader.REQUIRED_BONES:
			if v == null:
				errors.append("%s: '%s' must be 3 numbers (degrees)" % [label, name])
			elif absf(v.x) > MAX_ANGLE or absf(v.y) > MAX_ANGLE or absf(v.z) > MAX_ANGLE:
				errors.append("%s: '%s' %s is past ±%.0f°" % [label, name, v, MAX_ANGLE])
			else:
				pose[name] = v
		else:
			errors.append(
				"%s: unknown bone '%s'; bones: %s, and hips_pos"
				% [label, _short(str(name)), ", ".join(CharacterLoader.REQUIRED_BONES)]
			)
	return pose


func _root_offset(value: Variant, label: String) -> Vector2:
	if (
		not value is Array or value.size() != 2 or not _finite(value[0])
		or not _finite(value[1])
	):
		errors.append("%s: 'root' must be [forward, up] in meters" % label)
		return Vector2.ZERO
	var root := Vector2(value[0], value[1])
	if absf(root.x) > MAX_FORWARD:
		errors.append("%s: root forward %.2f m is past ±%.0f m" % [label, root.x, MAX_FORWARD])
	if root.y < MIN_UP or root.y > MAX_UP:
		errors.append(
			"%s: root up %.2f m is outside %.0f–%.0f m" % [label, root.y, MIN_UP, MAX_UP]
		)
	return root


static func _vec3(value: Variant) -> Variant:
	if not value is Array or value.size() != 3:
		return null
	for c: Variant in value:
		if not _finite(c):
			return null
	return Vector3(value[0], value[1], value[2])


static func _finite(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


## A JSON number that is a whole number, or -1.
static func _whole(value: Variant) -> int:
	if _finite(value) and value == floorf(value) and value >= 0 and value < 1.0e9:
		return int(value)
	return -1


static func _seconds(tick: int) -> float:
	return float(tick) / Fighter.TICK_RATE


## `pose` as JSON values, rounded to 0.0001 (no float32 noise in the kit).
static func _pose_json(pose: Dictionary) -> Dictionary:
	var out := { }
	for name: Variant in pose:
		var v: Vector3 = pose[name]
		out[String(name)] = [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
	return out


## `value` as JSON (strings as they are), cut to 40 characters.
static func _short(value: Variant) -> String:
	var s: String = value if value is String else JSON.stringify(value)
	return s if s.length() <= 40 else s.left(37) + "..."
