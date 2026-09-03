extends Camera3D

# Lives inside the HUD's minimap SubViewport (see Player.tscn's "Minimap"
# node) - that SubViewport has own_world_3d = false, so this camera renders
# the SAME live scene the main game camera does, just from directly
# overhead. That's what makes it show real-time traffic/cops/NPCs for free
# without needing separate blip tracking. Rotates with the player's facing
# (GTA-style, "you" always point up) rather than staying fixed north-up -
# AJ found the fixed version hard to read while driving/navigating, since it
# means constantly re-translating "which way is that blip relative to me"
# instead of just reading it directly off the map.
const HEIGHT := 80.0
const MAP_SIZE := 70.0 # was 90 - paired with the bigger on-screen minimap box, keeps icons/labels legible instead of just showing more tiny dots

func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = MAP_SIZE
	rotation_degrees = Vector3(-90, 0, 0)
	current = true

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		global_position = Vector3(player.global_position.x, player.global_position.y + HEIGHT, player.global_position.z)
		_face_player_direction(player)

# Re-orients the camera (still looking straight down) so its own local "up"
# axis - which becomes the top of the rendered minimap image - matches
# whichever way the player is actually facing/looking, instead of always
# world north. camera_pivot (not model) is used because it's the player's
# real aim/look direction (mouse-controlled), which is what a 3rd-person
# camera-behind-character view already visually tracks - model.rotation.y
# only follows movement direction and lags/holds still while strafing or
# standing still and looking around, which would leave the minimap not
# matching what's on screen in exactly the moments a rotating map matters most.
func _face_player_direction(player: Node3D) -> void:
	var camera_pivot: Node3D = player.get("camera_pivot")
	if not camera_pivot:
		return
	var forward: Vector3 = -camera_pivot.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return
	global_transform = global_transform.looking_at(global_position + Vector3.DOWN, forward.normalized())
