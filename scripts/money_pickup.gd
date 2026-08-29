extends Area3D

const AMOUNT_MIN := 15
const AMOUNT_MAX := 65

@onready var mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	mesh.rotation.y = randf() * TAU

func _process(delta: float) -> void:
	mesh.rotation.y += delta * 1.5

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("add_money"):
		body.add_money(randi_range(AMOUNT_MIN, AMOUNT_MAX))
		queue_free()
