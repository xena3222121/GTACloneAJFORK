extends Node

# Global, always-on background city atmosphere. The streets had zero
# ambient sound before this (just gunshots/sirens/etc. as they happened),
# which read as dead silence rather than a living city. Real recorded
# CC0/CC-BY field ambience (see Audio/Ambience/ATTRIBUTION.md) rather than
# procedural synthesis - a first pass here used synthesized noise loops for
# the hum/honk, but they read as a crude bass rumble rather than a city, so
# they were swapped for actual recordings.

const HONK_MIN_INTERVAL := 8.0
const HONK_MAX_INTERVAL := 22.0

const RAIN_FADE_SPEED := 6.0
const RAIN_TARGET_VOLUME := -12.0

const CITY_AMBIENCE_PATH := "res://Audio/Ambience/city_ambience.ogg"
const CAR_PASSING_BY_PATH := "res://Audio/Ambience/car_passing_by.wav"

@onready var hum_player: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var honk_player: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var rain_player: AudioStreamPlayer = AudioStreamPlayer.new()

var honk_timer := 0.0

func _ready() -> void:
	add_child(hum_player)
	add_child(honk_player)
	add_child(rain_player)

	var hum_stream: AudioStreamOggVorbis = load(CITY_AMBIENCE_PATH)
	hum_stream.loop = true
	hum_player.bus = "Master"
	hum_player.volume_db = -8.0
	hum_player.stream = hum_stream
	hum_player.play()
	_reset_honk_timer()

	rain_player.stream = _make_rain_patter()
	rain_player.volume_db = -80.0
	rain_player.play()

func _process(delta: float) -> void:
	honk_timer -= delta
	if honk_timer <= 0.0:
		_reset_honk_timer()
		honk_player.volume_db = randf_range(-14.0, -6.0)
		honk_player.pitch_scale = randf_range(0.9, 1.1)
		honk_player.stream = load(CAR_PASSING_BY_PATH)
		honk_player.play()

	var target: float = RAIN_TARGET_VOLUME if Weather.is_raining() else -80.0
	rain_player.volume_db = move_toward(rain_player.volume_db, target, RAIN_FADE_SPEED * delta)

func _reset_honk_timer() -> void:
	honk_timer = randf_range(HONK_MIN_INTERVAL, HONK_MAX_INTERVAL)

# Rain patter is still synthesized - the "real recording" complaint was
# specifically about the city hum/car sounds, not this. Kept as a tighter,
# higher-passed noise loop than before.
func _make_rain_patter() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 3.0
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var filtered := 0.0
	for i in range(sample_count):
		var noise := rng.randf_range(-1.0, 1.0)
		filtered = filtered * 0.55 + noise * 0.45
		var sample: float = clamp(filtered * 0.9, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = sample_count
	return stream
