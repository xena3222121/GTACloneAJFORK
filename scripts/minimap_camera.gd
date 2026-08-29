extends Camera3D

# Lives inside the HUD's minimap SubViewport (see Player.tscn's "Minimap"
# node) - that SubViewport has own_world_3d = false, so this camera renders
# the SAME live scene the main game camera does, just from directly
# overhead. That's what makes it show real-time traffic/cops/NPCs for free
# without needing separate blip tracking. Fixed north-up rotation rather
# than matching player facing - simpler, and standard for this style of map.
const HEIGHT := 80.0
const MAP_SIZE := 90.0

func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = MAP_SIZE
	rotation_degrees = Vector3(-90, 0, 0)
	current = true

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		global_position = Vector3(player.global_position.x, player.global_position.y + HEIGHT, player.global_position.z)
