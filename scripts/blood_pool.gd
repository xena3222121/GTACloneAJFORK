extends Node3D

@onready var mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	mesh.scale = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
