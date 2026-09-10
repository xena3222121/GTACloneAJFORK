extends Node

# Rival crews own the city. Where district_event_director.gd makes the map
# feel BUSY between jobs, this makes it feel OWNED: every district on the
# map belongs to somebody, whoever owns it puts armed guys on the corner,
# and the only way to flip one is to take it off them.
#
# Nothing here reimplements an objective framework - a turf war runs through
# MissionSystem.start_side_mission(), so it gets the same minimap marker,
# objective line, banner, payout and cleanup as every story mission (same
# reasoning as the district event director's comment). The enforcers
# themselves are gang_enforcer.gd, a subclass of the existing police AI.

# Emitted for the HUD; player.gd routes it into the mission banner rather
# than this system needing to know a Label exists.
signal banner_requested(text: String, hold_time: float)

const PLAYER := "player"

const FACTIONS := {
	"vultures": {"name": "The Vultures", "color": Color(0.78, 0.16, 0.18)},
	"salt_kings": {"name": "The Salt Kings", "color": Color(0.14, 0.48, 0.85)},
	"westline": {"name": "The Westline Boys", "color": Color(0.56, 0.21, 0.78)},
}

# Downtown is where the Fixer, the dealer, the safehouse and the story
# drop-off all already are (see mission_system.gd's DISTRICT_POINTS), so it
# reads as the player's home block from the start. The other three are
# somebody else's until they are taken.
const STARTING_OWNERS := {
	"Downtown": PLAYER,
	"Eastside": "vultures",
	"Beachfront": "salt_kings",
	"Westside": "westline",
}

# How close to a DISTRICT_POINTS center counts as being "in" that district.
# The four centers sit 70-180 units apart and the nearest one always wins,
# so this only decides how far a district's influence reaches out into the
# empty streets between them.
const DISTRICT_RADIUS := 45.0

# Enforcers to put down to flip a district, and how many can be standing at
# once. The cap rises during a war so the player is not left hunting one
# last guy across an empty district.
const CREW_SIZE := 4
const PATROL_CAP := 2
const WAR_PATROL_CAP := 4
const PATROL_COOLDOWN := 10.0
const WAR_PATROL_COOLDOWN := 4.5
const SPAWN_RADIUS_MIN := 17.0
const SPAWN_RADIUS_MAX := 30.0
# Enforcers left behind once the player has driven well out of the district
# get freed instead of accumulating - same reasoning as WantedSystem capping
# its reinforcements.
const DESPAWN_DISTANCE := 80.0

const TAKEOVER_REWARD := 2400
const DEFENSE_REWARD := 1600

# A crew that lost a block comes back for it, but not immediately, and never
# while the player is already busy with something else (the attempt just
# re-arms instead - see _process).
const RETALIATION_DELAY_MIN := 210.0
const RETALIATION_DELAY_MAX := 320.0
const DEFENSE_DURATION := 75.0
const DEFENSE_SQUAD := 3
const DEFENSE_SPAWN_SPREAD := 10.0

const ENFORCER_SCENE := preload("res://scenes/GangEnforcer.tscn")
# A crew soldier is a real fight but not a SWAT officer (see wanted_system.gd's
# SWAT_* numbers) - a bit tougher than a beat cop, slightly worse aim.
const ENFORCER_HEALTH := 140.0
const ENFORCER_CHASE_SPEED := 3.6
const ENFORCER_FIRE_RATE := 1.7
const ENFORCER_GUN_DAMAGE := 8.0

# district name -> faction id (or PLAYER). Persisted by save_system.gd.
var territory := {}

var _patrols: Array = []
var _patrol_timer := 0.0
var _retaliation_timer := 0.0
# Set while a turf war mission is running, so enforcer kills in that
# district count toward it and the district can change hands on completion.
var _war_district := ""
var _war_faction := ""
var _war_is_defense := false

func _ready() -> void:
	reset_territory()
	MissionSystem.mission_completed.connect(_on_mission_completed)
	MissionSystem.mission_aborted.connect(_on_mission_aborted)

# New Game / a fresh profile: everything back to its starting owner.
func reset_territory() -> void:
	territory = STARTING_OWNERS.duplicate()
	reset()

# Autoloads survive reload_current_scene() and change_scene_to_file(), so the
# spawned-enforcer list and any in-progress war have to be dropped when the
# world is rebuilt - those nodes died with the old scene. Ownership
# deliberately survives: it is player progress, not world state.
func reset() -> void:
	_patrols.clear()
	_patrol_timer = 0.0
	_retaliation_timer = randf_range(RETALIATION_DELAY_MIN, RETALIATION_DELAY_MAX)
	_clear_war()

func district_owner(district_name: String) -> String:
	return String(territory.get(district_name, PLAYER))

func faction_display_name(faction_id: String) -> String:
	if faction_id == PLAYER:
		return "your crew"
	return String(FACTIONS.get(faction_id, {}).get("name", "an unknown crew"))

func player_district_count() -> int:
	var count := 0
	for district_name in territory:
		if String(territory[district_name]) == PLAYER:
			count += 1
	return count

# Nearest district center within DISTRICT_RADIUS, or {} out in between.
func district_at(position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := DISTRICT_RADIUS
	for district in MissionSystem.DISTRICT_POINTS:
		var center: Vector3 = district["position"]
		var distance := Vector2(position.x - center.x, position.z - center.z).length()
		if distance <= best_distance:
			best_distance = distance
			best = district
	return best

func _district_by_name(district_name: String) -> Dictionary:
	for district in MissionSystem.DISTRICT_POINTS:
		if String(district["name"]) == district_name:
			return district
	return {}

func _process(delta: float) -> void:
	_patrols = _patrols.filter(func(e): return is_instance_valid(e) and not e.dead)
	var player := _active_player()
	if not player:
		return

	_despawn_distant_patrols(player)

	var district := district_at(player.global_position)
	var district_name := String(district["name"]) if district else ""
	if district_name != "" and district_owner(district_name) != PLAYER:
		_patrol_timer -= delta
		if _patrol_timer <= 0.0:
			_patrol_timer = WAR_PATROL_COOLDOWN if _war_district == district_name else PATROL_COOLDOWN
			_maybe_spawn_patrol(player, district, district_owner(district_name))
	else:
		_patrol_timer = min(_patrol_timer, PATROL_COOLDOWN)

	# Retaliation only becomes a thing once the player has actually taken
	# something off a crew - losing Downtown to a raid before ever starting
	# a war would just read as random punishment.
	if player_district_count() >= 2:
		_retaliation_timer -= delta
		if _retaliation_timer <= 0.0:
			if _try_start_defense(player):
				_retaliation_timer = randf_range(RETALIATION_DELAY_MIN, RETALIATION_DELAY_MAX)
			else:
				# Player is mid-mission, or there is nothing sensible to
				# attack - wait a little and try again, rather than firing
				# the instant the current job ends.
				_retaliation_timer = 30.0

func _active_player() -> Node3D:
	var player := get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return null
	if player.get("dead") == true or player.get("current_interior") != null:
		return null
	return player

func _despawn_distant_patrols(player: Node3D) -> void:
	for enforcer in _patrols.duplicate():
		if not is_instance_valid(enforcer):
			continue
		if enforcer.hostile:
			continue
		if enforcer.global_position.distance_to(player.global_position) > DESPAWN_DISTANCE:
			_patrols.erase(enforcer)
			enforcer.queue_free()

func _patrol_cap(district_name: String) -> int:
	return WAR_PATROL_CAP if _war_district == district_name else PATROL_CAP

func _maybe_spawn_patrol(player: Node3D, district: Dictionary, faction_id: String) -> void:
	var district_name := String(district["name"])
	var here := _patrols.filter(func(e): return String(e.district_name) == district_name)
	if here.size() >= _patrol_cap(district_name):
		return
	var angle := randf() * TAU
	var radius := randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	var spawn_position: Vector3 = player.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_spawn_enforcer(spawn_position, faction_id, district_name)

func _spawn_enforcer(spawn_position: Vector3, faction_id: String, district_name: String) -> Node3D:
	var enforcer: Node3D = ENFORCER_SCENE.instantiate()
	# Set before add_child so the crew tint is already correct when the
	# inherited _ready() runs its uniform pass.
	enforcer.faction_id = faction_id
	enforcer.faction_name = faction_display_name(faction_id)
	enforcer.faction_color = FACTIONS.get(faction_id, {}).get("color", Color(0.78, 0.16, 0.18))
	enforcer.district_name = district_name
	enforcer.max_health = ENFORCER_HEALTH
	enforcer.chase_speed = ENFORCER_CHASE_SPEED
	enforcer.fire_rate = ENFORCER_FIRE_RATE
	enforcer.gun_damage = ENFORCER_GUN_DAMAGE
	enforcer.position = spawn_position
	get_tree().current_scene.add_child(enforcer)
	_patrols.append(enforcer)
	return enforcer

# Called by gang_enforcer.gd's die(). A body dropping on rival turf is what
# starts a war there - no menu and no mission giver, the same way a wanted
# level starts by doing something rather than accepting something.
func report_enforcer_killed(enforcer: Node3D, by_player: bool) -> void:
	_patrols.erase(enforcer)
	if not by_player:
		return
	var district_name := String(enforcer.district_name)
	if district_name == "":
		return
	if _war_district == district_name:
		MissionSystem.report_turf_kill(district_name)
		return
	if district_owner(district_name) == String(enforcer.faction_id):
		_try_start_takeover(district_name, String(enforcer.faction_id))

func _try_start_takeover(district_name: String, faction_id: String) -> void:
	if MissionSystem.active_mission:
		return
	var player := _active_player()
	if not player:
		return
	var district := _district_by_name(district_name)
	if district.is_empty():
		return
	var crew := faction_display_name(faction_id)
	var mission := {
		"id": "turf_war",
		"title": "Turf War: %s" % district_name,
		"briefing": "%s run this block. Put their whole crew down and it is yours." % crew,
		"type": "turf_war",
		"objective": "Wipe out %s in %s" % [crew, district_name],
		"reward": TAKEOVER_REWARD,
		"district_name": district_name,
		# The kill that started the war counts toward it.
		"kills_done": 1,
		"kill_count": CREW_SIZE,
	}
	if MissionSystem.start_side_mission(player, mission, district["position"], "TURF WAR"):
		_war_district = district_name
		_war_faction = faction_id
		_war_is_defense = false

func _try_start_defense(player: Node3D) -> bool:
	if MissionSystem.active_mission:
		return false
	# Pick a block the player took, and the crew it was taken from.
	var candidates: Array = []
	for district_name in territory:
		var name_string := String(district_name)
		if String(territory[name_string]) != PLAYER:
			continue
		var previous_owner := String(STARTING_OWNERS.get(name_string, PLAYER))
		if previous_owner != PLAYER:
			candidates.append({"district": name_string, "faction": previous_owner})
	if candidates.is_empty():
		return false
	var pick: Dictionary = candidates[randi() % candidates.size()]
	var district_name := String(pick["district"])
	var faction_id := String(pick["faction"])
	var district := _district_by_name(district_name)
	if district.is_empty():
		return false
	var crew := faction_display_name(faction_id)
	var mission := {
		"id": "turf_war",
		"title": "Defend %s" % district_name,
		"briefing": "%s are back for %s. Clear them out before they settle in." % [crew, district_name],
		"type": "turf_war",
		"objective": "Drive %s out of %s" % [crew, district_name],
		"reward": DEFENSE_REWARD,
		"district_name": district_name,
		"kills_done": 0,
		"kill_count": DEFENSE_SQUAD,
		"duration": DEFENSE_DURATION,
	}
	if not MissionSystem.start_side_mission(player, mission, district["position"], "UNDER ATTACK"):
		return false
	_war_district = district_name
	_war_faction = faction_id
	_war_is_defense = true
	# The raiding squad is placed on the block itself rather than around the
	# player - they came for the district, and the marker is what leads the
	# player back to it.
	for i in range(DEFENSE_SQUAD):
		var offset := Vector3(
			randf_range(-DEFENSE_SPAWN_SPREAD, DEFENSE_SPAWN_SPREAD),
			0.0,
			randf_range(-DEFENSE_SPAWN_SPREAD, DEFENSE_SPAWN_SPREAD))
		_spawn_enforcer(district["position"] + offset, faction_id, district_name)
	banner_requested.emit("%s IS UNDER ATTACK\n%s are trying to take it back." % [district_name.to_upper(), crew], 4.0)
	return true

func _on_mission_completed(mission: Dictionary) -> void:
	if String(mission.get("id", "")) != "turf_war":
		return
	var district_name := String(mission.get("district_name", ""))
	if district_name == "":
		return
	var crew := faction_display_name(_war_faction)
	if _war_is_defense:
		banner_requested.emit("%s HELD\n%s backed off." % [district_name.to_upper(), crew], 3.5)
	else:
		territory[district_name] = PLAYER
		banner_requested.emit("%s IS YOURS\nYou took the block off %s." % [district_name.to_upper(), crew], 4.0)
	_clear_war()

func _on_mission_aborted() -> void:
	if _war_district == "":
		return
	# A defense that ran out of time is the one way ground is actually lost.
	# An abandoned takeover just leaves the district where it already was.
	if _war_is_defense:
		territory[_war_district] = _war_faction
		banner_requested.emit("%s IS LOST\n%s took the block back." % [_war_district.to_upper(), faction_display_name(_war_faction)], 4.0)
	_clear_war()

func _clear_war() -> void:
	_war_district = ""
	_war_faction = ""
	_war_is_defense = false

func to_dict() -> Dictionary:
	return territory.duplicate()

func from_dict(data: Dictionary) -> void:
	# Only known district names are accepted, and anything the save does not
	# mention keeps its starting owner - so a district added in a later
	# update cannot be broken by an older save.
	territory = STARTING_OWNERS.duplicate()
	for district_name in data:
		var name_string := String(district_name)
		if not STARTING_OWNERS.has(name_string):
			continue
		var faction_id := String(data[district_name])
		if faction_id == PLAYER or FACTIONS.has(faction_id):
			territory[name_string] = faction_id
