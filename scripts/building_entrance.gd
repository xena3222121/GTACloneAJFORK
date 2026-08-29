extends Area3D

# A door trigger. Player walks in range, gets a "press E" prompt (handled
# generically by player.gd via nearby_interactable), and interact() teleports
# them to interior_spawn - no scene swap, no hiding the exterior world, the
# interior just physically lives far away in X (see World.tscn's *Interior
# groups) so nothing needs to be shown/hidden to "enter" a building.

@export var interior_spawn_path: NodePath
@export var prompt_text := "Press E to enter"

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
	if player.has_method("enter_building"):
		player.enter_building(self, global_position)

func get_interior_spawn() -> Marker3D:
	return get_node(interior_spawn_path)
