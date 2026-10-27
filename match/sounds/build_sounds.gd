extends SceneTree
## Synthesizes the fight's sound effects (`FightSounds`) and saves them as
## 16-bit mono WAV files next to this script. Rerun after editing a sound:
##
##     godot --headless --path . -s match/sounds/build_sounds.gd
##
## Each sound is a few layers (a pitch-dropping sine thump, filtered noise),
## summed, softly clipped and normalized to its `peak`. The noise is seeded,
## so a rebuild gives the same files. Any WAV of the same name can replace
## one of them.

const DIR := "res://match/sounds/"
const MIX_RATE := 22050


func _init() -> void:
	_save("swing", _swing(), 0.45)
	_save("hit", _hit(), 0.9)
	_save("heavy_hit", _heavy_hit(), 1.0)
	_save("block", _block(), 0.7)
	_save("jump", _jump(), 0.4)
	quit()


## Whoosh of a punch or kick: noise through a band-pass whose center sweeps
## up and back down, swelling to its loudest ≈ 70 ms in (the punch's first
## active frame is at 83 ms).
func _swing() -> PackedFloat32Array:
	var n := _samples(0.18)
	var noise := _noise(n, 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / n
		var freq := lerpf(500.0, 2600.0, sin(t * PI) ** 0.7)
		var f := 2.0 * sin(PI * freq / MIX_RATE)
		# Chamberlin state-variable filter, q = 1.4 (a soft, wide band).
		low += f * band
		var high := noise[i] - low - band / 1.4
		band += f * high
		var env := (t / 0.4) ** 2 if t < 0.4 else (1.0 - (t - 0.4) / 0.6) ** 2
		out[i] = band * env
	return out


## Fist meets body: a low thump dropping 170 → 60 Hz, a short snap of noise
## for the smack and a mid-band slap.
func _hit() -> PackedFloat32Array:
	var n := _samples(0.2)
	var thump := _thump(n, 170.0, 60.0, 0.055)
	var snap := _decay(_low_pass(_noise(n, 2), 5000.0), 0.008)
	var slap := _decay(_band_pass(_noise(n, 3), 1100.0, 2.0), 0.03)
	return _mix([thump, snap, slap], [1.0, 0.7, 0.9], 1.8)


## Knockdown, sweep or throw slam: a deeper, longer thump with more body,
## driven harder into the clip.
func _heavy_hit() -> PackedFloat32Array:
	var n := _samples(0.4)
	var thump := _thump(n, 130.0, 38.0, 0.12)
	var snap := _decay(_low_pass(_noise(n, 4), 3500.0), 0.015)
	var rumble := _decay(_low_pass(_noise(n, 5), 400.0), 0.09)
	return _mix([thump, snap, rumble], [1.0, 0.6, 1.6], 2.5)


## Hit on the guard: a short, dull knock, higher and drier than a hit.
func _block() -> PackedFloat32Array:
	var n := _samples(0.12)
	var knock := _thump(n, 260.0, 150.0, 0.02)
	var tap := _decay(_band_pass(_noise(n, 6), 700.0, 3.0), 0.018)
	return _mix([knock, tap], [1.0, 0.8], 1.5)


## Launch of a jump: a soft scuff of the feet pushing off, then air rushing
## past as a band of noise sweeping up 400 → 1800 Hz and fading.
func _jump() -> PackedFloat32Array:
	var n := _samples(0.2)
	var scuff := _decay(_low_pass(_noise(n, 7), 1800.0), 0.02)
	var noise := _noise(n, 8)
	var rush := PackedFloat32Array()
	rush.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / n
		var f := 2.0 * sin(PI * lerpf(400.0, 1800.0, sqrt(t)) / MIX_RATE)
		low += f * band
		var high := noise[i] - low - band / 1.2
		band += f * high
		var env := t / 0.15 if t < 0.15 else (1.0 - (t - 0.15) / 0.85) ** 2
		rush[i] = band * env
	return _mix([scuff, rush], [1.0, 1.4], 1.2)


func _samples(seconds: float) -> int:
	return roundi(seconds * MIX_RATE)


## White noise in -1..1, from a fixed `seed`.
func _noise(n: int, noise_seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


## Sine whose pitch falls exponentially from `from_hz` to `to_hz` over the
## sound, fading with time constant `tau` (s).
func _thump(n: int, from_hz: float, to_hz: float, tau: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * from_hz * (to_hz / from_hz) ** t / MIX_RATE
		out[i] = sin(phase) * exp(-float(i) / MIX_RATE / tau)
	return out


## `wave` faded out with time constant `tau` (s), after a 1 ms fade-in so
## it doesn't click.
func _decay(wave: PackedFloat32Array, tau: float) -> PackedFloat32Array:
	var attack := MIX_RATE / 1000
	for i in wave.size():
		wave[i] *= exp(-float(i) / MIX_RATE / tau) * minf(float(i) / attack, 1.0)
	return wave


## One-pole low-pass at `cutoff` Hz.
func _low_pass(wave: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / MIX_RATE)
	var y := 0.0
	for i in wave.size():
		y += a * (wave[i] - y)
		wave[i] = y
	return wave


## State-variable band-pass at `center` Hz with quality `q`.
func _band_pass(wave: PackedFloat32Array, center: float, q: float) -> PackedFloat32Array:
	var f := 2.0 * sin(PI * center / MIX_RATE)
	var low := 0.0
	var band := 0.0
	for i in wave.size():
		low += f * band
		var high := wave[i] - low - band / q
		band += f * high
		wave[i] = band
	return wave


## Sum of `layers` weighted by `gains`, through a `tanh` soft clip with
## `drive` (more drive, more crunch).
func _mix(layers: Array, gains: Array, drive: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize((layers[0] as PackedFloat32Array).size())
	for i in out.size():
		var sum := 0.0
		for l in layers.size():
			sum += (layers[l] as PackedFloat32Array)[i] * gains[l]
		out[i] = tanh(sum * drive)
	return out


## Normalizes `wave` to `peak`, fades out its last 5 ms and writes
## `DIR/<name>.wav`.
func _save(sound_name: String, wave: PackedFloat32Array, peak: float) -> void:
	var top := 0.0
	for s in wave:
		top = maxf(top, absf(s))
	var fade := MIX_RATE / 200
	var data := PackedByteArray()
	data.resize(wave.size() * 2)
	for i in wave.size():
		var s := wave[i] * peak / top * minf(float(wave.size() - 1 - i) / fade, 1.0)
		data.encode_s16(i * 2, clampi(roundi(s * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	var path := DIR + sound_name + ".wav"
	var err := wav.save_to_wav(path)
	if err != OK:
		push_error("couldn't write %s: %s" % [path, error_string(err)])
		return
	print("wrote %s (%.2f s)" % [path, float(wave.size()) / MIX_RATE])
