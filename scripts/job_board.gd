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

var prompt_text := "Press E for a contract"
var active_target: Node3D = null
var contracted_player: Node3D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func _process(_delta: float) -> void:
	if active_target and (not is_instance_valid(active_target) or active_target.dead):
		_complete_contract()

func interact(player: Node3D) -> void:
	if active_target and is_instance_valid(active_target) and not active_target.dead:
		prompt_text = "Contract active - find the glowing orange target"
		return
	contracted_player = player
	_assign_contract()

func _assign_contract() -> void:
	var candidates: Array = []
	for npc in get_tree().get_nodes_in_group("civilians"):
		if is_instance_valid(npc) and not npc.dead:
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

func _tint_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_recursive(child, mat)

func _complete_contract() -> void:
	if contracted_player and is_instance_valid(contracted_player) and contracted_player.has_method("add_money"):
		contracted_player.add_money(randi_range(REWARD_MIN, REWARD_MAX))
	active_target = null
	prompt_text = "Contract complete! Press E for another"
