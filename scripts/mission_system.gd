extends Node

# A small ordered story chain, sitting alongside job_board.gd's repeatable
# random contracts rather than replacing them: job_board is "grind money any
# time," this is "a fixer with a handful of one-off jobs, in order." Each
# entry below is pure content - adding a mission later means appending to
# MISSIONS, not writing a new script. Reuses the exact tint/marker trick and
# civilians/parked_vehicles groups job_board.gd already established, so NPCs
# and cars don't need to know missions exist.

signal mission_started(mission: Dictionary)
signal mission_completed(mission: Dictionary)
signal mission_aborted()
signal objective_changed(text: String)

const TARGET_COLOR := Color(0.15, 0.75, 1.0) # cyan, distinct from job_board's orange

# drop_position only used by "steal_deliver" - the Downtown plaza in front of
# the dealer (see World.tscn's Downtown/Pavement, centered at 10, 0.02, 115),
# an already-open space so nothing else has to be built for a drop-off spot.
const MISSIONS := [
	{
		"id": "first_blood",
		"title": "First Blood",
		"briefing": "Somebody's been running their mouth to the cops. Make sure they stop.",
		"type": "kill",
		"objective": "Find and kill the marked target",
		"reward": 500,
	},
	{
		"id": "grand_theft_auto",
		"title": "Grand Theft Auto",
		"briefing": "See the marked car? It's not parked, it's borrowed. Bring it to the Downtown plaza.",
		"type": "steal_deliver",
		"objective": "Steal the marked car and deliver it to the Downtown plaza",
		"reward": 750,
		"drop_position": Vector3(10, 0, 115),
		"drop_radius": 8.0,
	},
	{
		"id": "insurance_job",
		"title": "Insurance Job",
		"briefing": "Owner needs his own car gone, no questions asked. Wreck it.",
		"type": "wreck",
		"objective": "Destroy the marked car",
		"reward": 1000,
	},
	{
		"id": "double_or_nothing",
		"title": "Double or Nothing",
		"briefing": "Somebody owes somebody money and it isn't getting paid back. Handle it.",
		"type": "kill",
		"objective": "Find and kill the marked target",
		"reward": 1250,
	},
	{
		"id": "one_more_job",
		"title": "One More Job",
		"briefing": "Same deal as before - grab the marked car, bring it to the Downtown plaza. Try not to scratch it this time.",
		"type": "steal_deliver",
		"objective": "Steal the marked car and deliver it to the Downtown plaza",
		"reward": 1500,
		"drop_position": Vector3(10, 0, 115),
		"drop_radius": 8.0,
	},
	{
		"id": "endgame",
		"title": "Endgame",
		"briefing": "This is the one that ends the beef for good. Torch their ride and walk away.",
		"type": "wreck",
		"objective": "Destroy the marked car",
		"reward": 2000,
	},
]

# How many missions have been completed - also the index of the next one.
# Persisted by save_system.gd like every other player stat.
var mission_index := 0

var active_mission: Dictionary = {}
var active_target: Node3D = null
var contracted_player: Node3D = null
var target_marker: Label3D = null

func has_next_mission() -> bool:
	return not active_mission and mission_index < MISSIONS.size()

func get_next_mission() -> Dictionary:
	if mission_index < MISSIONS.size():
		return MISSIONS[mission_index]
	return {}

func start_mission(player: Node3D) -> bool:
	if active_mission or mission_index >= MISSIONS.size():
		return false
	var mission: Dictionary = MISSIONS[mission_index]
	var candidates: Array = []
	if mission["type"] == "kill":
		for npc in get_tree().get_nodes_in_group("civilians"):
			if is_instance_valid(npc) and not npc.dead and npc.get("is_dealer") != true:
				candidates.append(npc)
	else:
		for car in get_tree().get_nodes_in_group("parked_vehicles"):
			if is_instance_valid(car) and not car.destroyed:
				candidates.append(car)
	if candidates.is_empty():
		return false

	active_mission = mission
	contracted_player = player
	active_target = candidates[randi() % candidates.size()]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = TARGET_COLOR
	mat.emission_enabled = true
	mat.emission = TARGET_COLOR
	mat.emission_energy_multiplier = 1.2
	_tint_recursive(active_target.get_node("Model") if active_target.has_node("Model") else active_target, mat)

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

	mission_started.emit(mission)
	objective_changed.emit(String(mission["objective"]))
	return true

func _process(_delta: float) -> void:
	if not active_mission:
		return
	if not is_instance_valid(active_target):
		_abort_mission()
		return
	match active_mission["type"]:
		"kill":
			if active_target.dead:
				_complete_mission()
		"wreck":
			if active_target.destroyed:
				_complete_mission()
		"steal_deliver":
			if active_target.destroyed:
				_abort_mission()
			elif active_target.get("driver") == contracted_player:
				var drop_pos: Vector3 = active_mission["drop_position"]
				var flat_target := Vector3(active_target.global_position.x, drop_pos.y, active_target.global_position.z)
				if flat_target.distance_to(drop_pos) <= float(active_mission["drop_radius"]):
					_complete_mission()

func _tint_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_recursive(child, mat)

func _clear_target() -> void:
	if target_marker and is_instance_valid(target_marker):
		target_marker.queue_free()
	target_marker = null
	active_target = null

# Target died to something unrelated to the mission (cops, another NPC, a car
# crash) or a delivery car got wrecked before reaching the drop point - the
# mission just resets to "not started" rather than permanently failing, so
# the Fixer can hand the exact same job out again next time.
func _abort_mission() -> void:
	_clear_target()
	active_mission = {}
	contracted_player = null
	objective_changed.emit("")
	mission_aborted.emit()

func _complete_mission() -> void:
	var mission := active_mission
	if contracted_player and is_instance_valid(contracted_player) and contracted_player.has_method("add_money"):
		contracted_player.add_money(int(mission["reward"]))
	_clear_target()
	active_mission = {}
	contracted_player = null
	mission_index += 1
	objective_changed.emit("")
	mission_completed.emit(mission)
