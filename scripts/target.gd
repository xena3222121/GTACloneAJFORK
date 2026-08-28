extends StaticBody3D

@export var max_health: float = 50.0
@export var respawn_time: float = 3.0

@onready var collision: CollisionShape3D = $CollisionShape3D

var health: float
var start_position: Vector3

func _ready() -> void:
	health = max_health
	start_position = position

func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO) -> void:
	health -= amount
	if health <= 0.0:
		knock_down()

func knock_down() -> void:
	visible = false
	collision.disabled = true
	await get_tree().create_timer(respawn_time).timeout
	respawn()

func respawn() -> void:
	health = max_health
	position = start_position
	visible = true
	collision.disabled = false
