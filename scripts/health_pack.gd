extends Area3D

const HEAL_FRACTION := 0.35
const RESPAWN_TIME := 45.0

@onready var mesh: MeshInstance3D = $Mesh
@onready var collision: CollisionShape3D = $CollisionShape3D
var respawn_timer := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			mesh.visible = true
			collision.disabled = false
		return
	mesh.rotation.y += delta * 1.5

func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("add_health") or body.get("dead") == true:
		return
	body.add_health(HEAL_FRACTION * 100.0)
	mesh.visible = false
	collision.disabled = true
	respawn_timer = RESPAWN_TIME
