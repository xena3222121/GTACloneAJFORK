extends Node3D

@onready var fireball: GPUParticles3D = $Fireball
@onready var smoke: GPUParticles3D = $Smoke
@onready var flash: OmniLight3D = $Flash
@onready var boom_audio: AudioStreamPlayer3D = $BoomAudio

func _ready() -> void:
	fireball.emitting = true
	smoke.emitting = true

	flash.light_energy = 8.0
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.25).set_trans(Tween.TRANS_QUAD)

	boom_audio.stream = _make_boom_sound()
	boom_audio.play()

	var lifetime: float = max(fireball.lifetime, smoke.lifetime) + 0.3
	await get_tree().create_timer(lifetime).timeout
	queue_free()

# Two layered noise filters rather than one (see player.gd's _make_gunshot_sound
# for the single-layer version): a fast-decaying "crack" on top of a
# slow-decaying, heavily-smoothed "rumble" is what actually reads as a boom
# instead of just a longer gunshot.
func _make_boom_sound() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.9
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var crack := 0.0
	var rumble := 0.0
	for i in range(sample_count):
		var t := float(i) / sample_count
		var envelope: float = pow(1.0 - t, 2.2)
		var noise := rng.randf_range(-1.0, 1.0)
		crack = crack * 0.6 + noise * 0.4
		rumble = rumble * 0.93 + noise * 0.07
		var sample: float = clamp((crack * 0.6 + rumble * 0.9) * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream
