extends Node3D

@onready var particles: GPUParticles3D = $Particles

func _ready() -> void:
	particles.emitting = true
	await get_tree().create_timer(particles.lifetime + 0.15).timeout
	queue_free()
