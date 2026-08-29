extends Area3D

# The game had zero objectives before this - a pure open sandbox with no
# goals at all, which is a real gap for "a true GTA type game." A
# repeatable contract/hit is the smallest version of that: pick a random
# living civilian, mark them unmistakably (a bright emissive tint, the same
# recursive material_override trick used everywhere else - police uniforms,
# store outfits), and pay out once they're dead. No new UI screen, no
# mission-state machine - just reuses money, NPC death, and tinting that
# already exist.

const REWARD_MIN := 150
const REWARD_MAX := 300
const TARGET_COLOR := Color(1.0, 0.35, 0.05)
# Matches register.gd's own cooldown pattern - without this, completing a
# contract immediately re-armed the board, letting a player chain $150-300
# payouts far faster than any other money loop in the game.
const COOLDOWN := 60.0

var prompt_text := "Press E for a contract"
var active_target: Node3D = null
var contracted_player: Node3D = null
var cooldown_timer := 0.0
var target_marker: Label3D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func _process(delta: float) -> void:
	if active_target and (not is_instance_valid(active_target) or active_target.dead):
		_complete_contract()
	if cooldown_timer > 0.0:
		cooldown_timer = max(0.0, cooldown_timer - delta)
		prompt_text = "Contract board cooling down..."
	elif not active_target:
		prompt_text = "Press E for a contract"

func interact(player: Node3D) -> void:
	if active_target and is_instance_valid(active_target) and not active_target.dead:
		prompt_text = "Contract active - find the glowing orange target"
		return
	if cooldown_timer > 0.0:
		return
	contracted_player = player
	_assign_contract()

func _assign_contract() -> void:
	var candidates: Array = []
	for npc in get_tree().get_nodes_in_group("civilians"):
		if is_instance_valid(npc) and not npc.dead and npc.get("is_dealer") != true:
			candidates.append(npc)
	if candidates.is_empty():
		prompt_text = "No targets available right now"
		return
	active_target = candidates[randi() % candidates.size()]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = TARGET_COLOR
	mat.emission_enabled = true
	mat.emission = TARGET_COLOR
	mat.emission_energy_multiplier = 1.2
	_tint_recursive(active_target.get_node("Model"), mat)
	prompt_text = "Contract: kill the glowing orange target"

	# The city's a lot bigger than one screen now (4 neighborhoods) - the
	# in-world glow only helps once you're already close. A minimap-only
	# marker (same dedicated render layer the shop/landmark labels use, see
	# minimap_camera.gd) gives an actual way-finding aid.
	target_marker = Label3D.new()
	target_marker.text = "TARGET"
	target_marker.layers = 524288
	target_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	target_marker.no_depth_test = true
	target_marker.font_size = 64
	target_marker.outline_size = 12
	target_marker.pixel_size = 0.08
	target_marker.modulate = TARGET_COLOR
	target_marker.position = Vector3(0, 2.2, 0)
	active_target.add_child(target_marker)

func _tint_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_recursive(child, mat)

func _complete_contract() -> void:
	if contracted_player and is_instance_valid(contracted_player) and contracted_player.has_method("add_money"):
		contracted_player.add_money(randi_range(REWARD_MIN, REWARD_MAX))
	if target_marker and is_instance_valid(target_marker):
		target_marker.queue_free()
	target_marker = null
	active_target = null
	cooldown_timer = COOLDOWN
	prompt_text = "Contract complete! Board's cooling down"
