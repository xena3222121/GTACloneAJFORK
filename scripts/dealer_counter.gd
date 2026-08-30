extends Area3D

@export var spawn_marker_path: NodePath
var prompt_text := "Press E to browse cars"

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func interact(player: Node3D) -> void:
	if player.has_method("open_dealer_menu"):
		player.open_dealer_menu()

func get_spawn_marker() -> Marker3D:
	return get_node(spawn_marker_path)
