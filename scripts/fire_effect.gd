extends Node3D

const BURN_DURATION := 18.0
const FADE_TIME := 1.5

@onready var flames: GPUParticles3D = $Flames
@onready var smoke: GPUParticles3D = $Smoke
@onready var light: OmniLight3D = $FlickerLight

var elapsed := 0.0
var burning := true

func _ready() -> void:
	flames.emitting = true
	smoke.emitting = true

func _process(delta: float) -> void:
	if not burning:
		return
	elapsed += delta
	# Cheap flicker: random jitter each frame reads as flame flicker without
	# needing a real noise texture.
	light.light_energy = 2.2 + randf_range(-0.4, 0.4)
	if elapsed >= BURN_DURATION:
		_burn_out()

func _burn_out() -> void:
	burning = false
	flames.emitting = false
	smoke.emitting = false
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, FADE_TIME)
	await tween.finished
	queue_free()
