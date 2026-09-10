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
# Fired once, the moment the story chain's last mission (Endgame) pays out -
# separate from mission_completed so the HUD can give that specific moment a
# bigger, longer banner than the routine "+$reward" one every job gets,
# instead of the story just quietly rolling into endless Fixer work unmarked.
signal story_completed()

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
		"id": "shake_the_heat",
		"title": "Shake the Heat",
		"briefing": "The cops are watching the block. Make some noise, lose their line of sight, and get clear.",
		"type": "evade",
		"objective": "Lose the police and stay hidden",
		"reward": 900,
	},
	{
		"id": "high_speed_hit",
		"title": "High Speed Hit",
		"briefing": "A marked runner is moving through the city. Take their car out before they disappear.",
		"type": "chase",
		"objective": "Stop the marked runner",
		"reward": 1200,
		"duration": 55.0,
	},
	{
		"id": "dead_drop",
		"title": "Dead Drop",
		"briefing": "Pick up the package, then get it across town before anyone else gets there.",
		"type": "pickup_delivery",
		"objective": "Collect the package",
		"reward": 1000,
	},
	{
		"id": "hold_the_block",
		"title": "Hold the Block",
		"briefing": "Show the neighborhood this corner is ours. Hold the marked block until the timer clears.",
		"type": "holdout",
		"objective": "Hold the marked block",
		"reward": 1350,
		"duration": 25.0,
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
		"id": "clean_sweep",
		"title": "Clean Sweep",
		"briefing": "Three loose ends. Tie them all up before somebody talks.",
		"type": "kill",
		"objective": "Find and kill the marked targets",
		"reward": 1100,
		"kill_count": 3,
	},
	{
		"id": "chop_shop",
		"title": "Chop Shop",
		"briefing": "Two of theirs need to disappear before the insurance check clears. Both of them, torched.",
		"type": "wreck",
		"objective": "Destroy the marked cars",
		"reward": 1150,
		"kill_count": 2,
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
		"id": "the_setup",
		"title": "The Setup",
		"briefing": "Two of their guys are about to flip on everybody. Get to them before they get to a cop.",
		"type": "kill",
		"objective": "Find and kill the marked targets",
		"reward": 1700,
		"kill_count": 2,
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
var completed_mission_ids: Array[String] = []

# Saves written before stable IDs only knew a numeric position. Keep this
# historical order for one-time migration so an update can insert missions
# without silently moving an existing player to the wrong story beat.
const LEGACY_MISSION_ORDER := [
	"first_blood", "grand_theft_auto", "insurance_job", "clean_sweep",
	"chop_shop", "double_or_nothing", "one_more_job", "the_setup", "endgame",
]

var active_mission: Dictionary = {}
var active_target: Node3D = null
var contracted_player: Node3D = null
var target_marker: Label3D = null
# Only meaningful for "kill" missions with a "kill_count" above 1 (see
# Clean Sweep) - how many of the required kills are done so far, and the
# required total for this run, cached from the mission dict so _process
# doesn't have to re-read it every frame.
var kills_done := 0
var kill_count := 1
var mission_timer := 0.0
var pickup_collected := false
var location_radius := 7.0
var last_progress_second := -1

# Clear, open existing map locations for delivery and territory objectives.
const DISTRICT_POINTS := [
	{"name": "Downtown", "position": Vector3(10, 0, 115)},
	{"name": "Beachfront", "position": Vector3(65, 0, 160)},
	{"name": "Westside", "position": Vector3(-55, 0, 20)},
	{"name": "Eastside", "position": Vector3(125, 0, 20)},
]

# Once the story chain (MISSIONS) runs out, the Fixer doesn't just go quiet -
# same pattern job_board.gd already established (a repeatable random job),
# just from the Fixer instead of the board, at a flat high payout befitting
# someone who already finished the actual story.
const ENDLESS_REWARD_MIN := 1800
const ENDLESS_REWARD_MAX := 2500
const ENDLESS_BRIEFINGS := [
	"Story's done, but the work never stops. One more for the road.",
	"Another day, another job. You know the drill by now.",
	"No shortage of people who need a problem handled.",
]

func has_next_mission() -> bool:
	return not active_mission

func start_district_event(player: Node3D, district: Dictionary) -> bool:
	if active_mission:
		return false
	active_mission = {
		"id": "district_event",
		"title": "%s Is Under Pressure" % district["name"],
		"briefing": "A crew is testing the neighborhood. Hold the marked block and make it clear who runs it.",
		"type": "holdout",
		"objective": "Hold the marked block",
		"reward": 650,
		"district_name": district["name"],
	}
	contracted_player = player
	kills_done = 0
	kill_count = 1
	mission_timer = 18.0
	pickup_collected = false
	last_progress_second = -1
	_spawn_location_target(district["position"], "DISTRICT EVENT")
	mission_started.emit(active_mission)
	_emit_objective()
	return true

# Generic entry point for jobs that come from somewhere other than the
# Fixer (see faction_system.gd's turf wars): the caller supplies the mission
# dict and where to put the marker, and the job then behaves like any other
# one - same objective line, minimap marker, banner, payout and cleanup -
# instead of every system growing its own parallel objective framework.
func start_side_mission(player: Node3D, mission: Dictionary, marker_position: Vector3, marker_label: String) -> bool:
	if active_mission:
		return false
	active_mission = mission.duplicate(true)
	contracted_player = player
	kills_done = int(mission.get("kills_done", 0))
	kill_count = int(mission.get("kill_count", 1))
	mission_timer = float(mission.get("duration", 0.0))
	pickup_collected = false
	last_progress_second = -1
	_spawn_location_target(marker_position, marker_label)
	mission_started.emit(active_mission)
	_emit_objective()
	return true

# Called by faction_system.gd when the player puts down an enforcer during a
# turf war. Kills are reported rather than polled because the enforcers are
# individual nodes that free themselves - there is no single target node for
# _process to watch the way a "kill" or "wreck" mission has.
func report_turf_kill(district_name: String) -> void:
	if not active_mission or String(active_mission.get("type", "")) != "turf_war":
		return
	if String(active_mission.get("district_name", "")) != district_name:
		return
	kills_done += 1
	if kills_done >= kill_count:
		_complete_mission()
	else:
		_emit_objective()

func get_next_mission() -> Dictionary:
	if mission_index < MISSIONS.size():
		return MISSIONS[mission_index]
	return {}

func restore_completed_missions(ids: Array) -> void:
	completed_mission_ids.clear()
	for id in ids:
		if typeof(id) == TYPE_STRING and not completed_mission_ids.has(id):
			completed_mission_ids.append(id)
	mission_index = 0
	# Story order remains authoritative: this preserves a coherent chain even
	# if content is inserted in a later update.
	while mission_index < MISSIONS.size() and completed_mission_ids.has(MISSIONS[mission_index]["id"]):
		mission_index += 1

func migrate_legacy_progress(old_index: int) -> void:
	restore_completed_missions(LEGACY_MISSION_ORDER.slice(0, clampi(old_index, 0, LEGACY_MISSION_ORDER.size())))

# Shared by start_mission() and the mid-mission re-pick Clean Sweep-style
# multi-kill missions need after each kill - null if nothing valid is left
# to target (e.g. every civilian on the map is already dead).
func _pick_target_for_type(mission_type: String) -> Node3D:
	var candidates: Array = []
	if mission_type == "kill":
		for npc in get_tree().get_nodes_in_group("civilians"):
			if is_instance_valid(npc) and not npc.dead and npc.get("is_dealer") != true:
				candidates.append(npc)
	elif mission_type == "chase":
		for car in get_tree().get_nodes_in_group("traffic_cars"):
			if is_instance_valid(car) and not car.destroyed and car.driver == null:
				candidates.append(car)
	else:
		for car in get_tree().get_nodes_in_group("parked_vehicles"):
			if is_instance_valid(car) and not car.destroyed:
				candidates.append(car)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

func _set_target(target: Node3D) -> void:
	active_target = target

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

func _emit_objective() -> void:
	var text: String = String(active_mission["objective"])
	if kill_count > 1:
		text += " (%d/%d)" % [kills_done, kill_count]
	objective_changed.emit(text)

func _spawn_location_target(position: Vector3, label_text: String) -> void:
	var marker := Node3D.new()
	marker.name = "MissionZoneMarker"
	marker.set_meta("mission_marker", true)
	get_tree().current_scene.add_child(marker)
	marker.global_position = position
	_set_target(marker)
	target_marker.text = label_text

func _random_district(except_index: int = -1) -> Dictionary:
	var choices: Array = []
	for i in range(DISTRICT_POINTS.size()):
		if i != except_index:
			choices.append(DISTRICT_POINTS[i])
	return choices[randi() % choices.size()]

func _make_endless_mission() -> Dictionary:
	var roll := randf()
	var mtype := "kill" if roll < 0.4 else ("wreck" if roll < 0.75 else "holdout")
	return {
		"id": "fixer_job",
		"title": "Fixer Job",
		"briefing": ENDLESS_BRIEFINGS[randi() % ENDLESS_BRIEFINGS.size()],
		"type": mtype,
		"objective": "Find and kill the marked target" if mtype == "kill" else ("Destroy the marked car" if mtype == "wreck" else "Hold the marked block"),
		"reward": randi_range(ENDLESS_REWARD_MIN, ENDLESS_REWARD_MAX),
		"duration": 22.0,
	}

func start_mission(player: Node3D) -> bool:
	if active_mission:
		return false
	var mission: Dictionary = MISSIONS[mission_index] if mission_index < MISSIONS.size() else _make_endless_mission()
	var target: Node3D = null
	if mission["type"] not in ["evade", "pickup_delivery", "holdout"]:
		target = _pick_target_for_type(mission["type"])
	if mission["type"] not in ["evade", "pickup_delivery", "holdout"] and not target:
		return false

	active_mission = mission
	contracted_player = player
	kills_done = 0
	kill_count = int(mission.get("kill_count", 1))
	mission_timer = float(mission.get("duration", 0.0))
	pickup_collected = false
	last_progress_second = -1
	if target:
		_set_target(target)
	elif mission["type"] == "evade":
		# A mission-specific heat spike makes the escape feel like a job with
		# stakes instead of a passive version of the normal wanted-meter decay.
		WantedSystem.add_heat(60.0, player.global_position)
		WantedSystem.request_escape_objective()
	elif mission["type"] == "pickup_delivery":
		var pickup := _random_district()
		_spawn_location_target(pickup["position"], "PICKUP")
	elif mission["type"] == "holdout":
		var district := _random_district()
		_spawn_location_target(district["position"], "HOLD THIS BLOCK")
		active_mission["district_name"] = district["name"]

	mission_started.emit(mission)
	_emit_objective()
	return true

func _process(_delta: float) -> void:
	if not active_mission:
		return
	if active_mission["type"] != "evade" and not is_instance_valid(active_target):
		_abort_mission()
		return
	match active_mission["type"]:
		"evade":
			if not WantedSystem.escape_objective_active and WantedSystem.heat <= 0.0:
				_complete_mission()
		"chase":
			mission_timer -= _delta
			if mission_timer <= 0.0:
				_abort_mission()
				return
			if ceili(mission_timer) != last_progress_second:
				last_progress_second = ceili(mission_timer)
				objective_changed.emit("Stop the marked runner (%ds)" % last_progress_second)
			if active_target.destroyed:
				_complete_mission()
		"pickup_delivery":
			var player_position := contracted_player.global_position
			if not pickup_collected and player_position.distance_to(active_target.global_position) <= location_radius:
				pickup_collected = true
				_clear_target()
				var drop := _random_district()
				_spawn_location_target(drop["position"], "DELIVER")
				active_mission["objective"] = "Deliver the package to %s" % drop["name"]
				_emit_objective()
			elif pickup_collected and player_position.distance_to(active_target.global_position) <= location_radius:
				_complete_mission()
		"holdout":
			if contracted_player.global_position.distance_to(active_target.global_position) <= location_radius:
				mission_timer = max(0.0, mission_timer - _delta)
				if ceili(mission_timer) != last_progress_second:
					last_progress_second = ceili(mission_timer)
					objective_changed.emit("Hold %s (%ds)" % [active_mission["district_name"], last_progress_second])
				if mission_timer <= 0.0:
					_complete_mission()
		"turf_war":
			# Only a defense carries a duration (see faction_system.gd) - a
			# takeover has no clock, so the war stays open until the crew is
			# down or the player walks away from it.
			if mission_timer > 0.0:
				mission_timer = max(0.0, mission_timer - _delta)
				if ceili(mission_timer) != last_progress_second:
					last_progress_second = ceili(mission_timer)
					objective_changed.emit("%s (%d/%d, %ds)" % [String(active_mission["objective"]), kills_done, kill_count, last_progress_second])
				if mission_timer <= 0.0:
					_abort_mission()
		"kill":
			if active_target.dead:
				kills_done += 1
				if kills_done >= kill_count:
					_complete_mission()
					return
				_clear_target()
				var next_target := _pick_target_for_type("kill")
				if not next_target:
					# Ran out of civilians to mark before hitting kill_count -
					# pay out for what's done rather than softlocking the chain.
					_complete_mission()
					return
				_set_target(next_target)
				_emit_objective()
		"wreck":
			if active_target.destroyed:
				kills_done += 1
				if kills_done >= kill_count:
					_complete_mission()
					return
				_clear_target()
				var next_wreck_target := _pick_target_for_type("wreck")
				if not next_wreck_target:
					# Same reasoning as the "kill" branch above - ran out of cars
					# to mark before hitting kill_count, pay out for what's done.
					_complete_mission()
					return
				_set_target(next_wreck_target)
				_emit_objective()
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
	if active_target and active_target.get_meta("mission_marker", false):
		active_target.queue_free()
	active_target = null

# Target died to something unrelated to the mission (cops, another NPC, a car
# crash) or a delivery car got wrecked before reaching the drop point - the
# mission just resets to "not started" rather than permanently failing, so
# the Fixer can hand the exact same job out again next time.
func _abort_mission() -> void:
	_clear_target()
	active_mission = {}
	contracted_player = null
	mission_timer = 0.0
	pickup_collected = false
	objective_changed.emit("")
	mission_aborted.emit()

func _complete_mission() -> void:
	var mission := active_mission
	if contracted_player and is_instance_valid(contracted_player) and contracted_player.has_method("add_money"):
		contracted_player.add_money(int(mission["reward"]))
	_clear_target()
	active_mission = {}
	contracted_player = null
	mission_timer = 0.0
	pickup_collected = false
	var is_story_mission: bool = mission_index < MISSIONS.size() and String(mission.get("id", "")) == String(MISSIONS[mission_index]["id"])
	if is_story_mission:
		if not completed_mission_ids.has(mission["id"]):
			completed_mission_ids.append(mission["id"])
		mission_index += 1
	objective_changed.emit("")
	mission_completed.emit(mission)
	if is_story_mission and mission_index == MISSIONS.size():
		story_completed.emit()
