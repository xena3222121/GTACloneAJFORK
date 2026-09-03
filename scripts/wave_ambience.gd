extends AudioStreamPlayer3D

# Positional ambient surf sound along the shoreline - fades in/out naturally
# via unit_size as the player approaches/leaves the beach, same technique
# every other spot sound in this project already uses (HitAudio etc.), just
# looping and always-on rather than one-shot.
#
# No real ocean/surf recording exists in this project's Audio/ folder (see
# Audio/Ambience/ATTRIBUTION.md - city_ambience.gd's hum/honk are real CC0/
# CC-BY recordings specifically because a synthesized first pass read as a
# crude bass rumble rather than a city). This is synthesized instead,
# matching this codebase's existing accepted pattern for effects a real
# recording isn't available for (rain patter, gunshots, sirens) - the goal
# here is a filtered-noise "whoosh" shaped by a slow crash/recede envelope
# rather than a flat rumble, so it actually reads as surf.
const DURATION := 18.4
const WAVE_PERIOD := 4.6 # 4 full cycles fit exactly in DURATION - the noise
# floor still carries a tiny loop-seam discontinuity (see _make_wave_sound),
# but the envelope itself loops with zero volume jump.

func _ready() -> void:
	unit_size = 55.0
	max_db = -4.0
	volume_db = -4.0
	stream = _make_wave_sound()
	autoplay = true
	play()

func _make_wave_sound() -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := int(mix_rate * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var filtered := 0.0
	for i in range(sample_count):
		var t := float(i) / mix_rate
		var noise := rng.randf_range(-1.0, 1.0)
		# Much heavier smoothing than city_ambience.gd's rain patter (0.93 vs
		# 0.55) - waves read as a deep, broad whoosh, not a crisp patter.
		filtered = filtered * 0.93 + noise * 0.07
		# Crash-and-recede envelope: quiet trough between waves, a rounded
		# swell into each crash (the pow() skews the curve so the loud part
		# is a shorter crest rather than a symmetric sine bulge).
		var phase := t / WAVE_PERIOD * TAU
		var envelope: float = pow((sin(phase - PI * 0.5) + 1.0) * 0.5, 1.6)
		var sample: float = clamp(filtered * (0.35 + envelope * 0.9), -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = sample_count
	return stream
