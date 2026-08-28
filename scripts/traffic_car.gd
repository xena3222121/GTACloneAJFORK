extends AnimatableBody3D

@export var speed: float = 6.0
@export var min_z: float = -45.0
@export var max_z: float = 45.0
@export var start_direction: float = 1.0

var direction: float = 1.0

func _ready() -> void:
	direction = 1.0 if start_direction >= 0.0 else -1.0
	rotation.y = 0.0 if direction > 0.0 else PI

func _physics_process(delta: float) -> void:
	position.z += direction * speed * delta
	if position.z >= max_z:
		position.z = max_z
		direction = -1.0
		rotation.y = PI
	elif position.z <= min_z:
		position.z = min_z
		direction = 1.0
		rotation.y = 0.0
