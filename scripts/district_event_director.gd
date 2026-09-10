extends Node

# Small, timed city events make the map feel like it carries on between
# Fixer jobs. They use MissionSystem's existing holdout machinery, so they
# get the same HUD, target marker, reward, and cleanup behavior as story
# missions instead of becoming a second competing objective framework.
const EVENT_INTERVAL_MIN := 100.0
const EVENT_INTERVAL_MAX := 160.0

var timer := 45.0

func _ready() -> void:
	MissionSystem.mission_completed.connect(_reset_timer)
	MissionSystem.mission_aborted.connect(_reset_timer)

func _process(delta: float) -> void:
	if MissionSystem.active_mission:
		return
	timer -= delta
	if timer > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player")
	if not player or player.get("current_interior") != null:
		return
	var district: Dictionary = MissionSystem._random_district()
	if MissionSystem.start_district_event(player, district):
		timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)

func _reset_timer(_mission = null) -> void:
	# A completed/failed event should leave breathing room before the city
	# asks for the next one; story missions don't force an immediate event.
	timer = max(timer, randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX))
