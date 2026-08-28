extends Area3D

@export var weapon: String = "shotgun"
@export var amount: int = 16

@onready var mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	mesh.rotation.y = randf() * TAU

func _process(delta: float) -> void:
	mesh.rotation.y += delta * 1.5

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("add_ammo"):
		body.add_ammo(amount, weapon)
		queue_free()
