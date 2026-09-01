extends Node

# Global heat/wanted-level tracker. Autoloaded as "WantedSystem" (see
# project.godot's [autoload] section - the first one this project has).
#
# Heat only decays once nothing has reported a crime or an active sighting
# for DECAY_GRACE seconds, and it drives which nearby police get pulled
# straight into hostile/chasing state (via alert()) rather than relying on
# each cop to notice the player on its own - that's what makes the response
# "escalate" as more crimes stack up before the grace period resets.

signal tier_changed(tier: int)

const MAX_HEAT := 100.0
const DECAY_RATE := 9.0 # was 6 - heat (and with it, the reinforcement spawner below) used to linger too long after the player actually stopped causing trouble
const DECAY_GRACE := 4.0
const TIER_THRESHOLDS := [25.0, 55.0, 85.0]
const BASE_ALERT_RADIUS := 14.0
const TIER_ALERT_RADIUS_BONUS := 8.0

const POLICE_SCENE := preload("res://scenes/Police.tscn")
# Reinforcements were too aggressive: spawning off any nonzero heat (a single
# grazing hit was enough), every 7s, up to 6 at once. Now requires real,
# sustained heat before backup gets called at all, arrives far less often,
# and caps much lower.
const MIN_SPAWN_HEAT := 20.0
const SPAWN_RADIUS_MIN := 16.0
const SPAWN_RADIUS_MAX := 26.0

# Response used to be flat regardless of how hot the player was - the exact
# same trickle of cops at 1 star as at max heat. Indexed by _tier (0..3,
# matching TIER_THRESHOLDS.size()) so it actually escalates: more cops
# allowed, called in faster, the higher the heat climbs.
const MAX_SPAWNED_BY_TIER := [2, 2, 3, 5]
const SPAWN_COOLDOWN_BY_TIER := [16.0, 16.0, 11.0, 7.0]

# At max heat, reinforcements stop being regular beat cops and come in as
# SWAT - tougher, faster, hits harder (see police.gd's exported max_health/
# chase_speed/fire_rate/gun_damage). Only reinforcements get this; the 4
# hand-placed patrol cops stay regular no matter how hot the player gets.
const SWAT_TIER := 3
const SWAT_HEALTH := 180.0
const SWAT_CHASE_SPEED := 4.2
const SWAT_FIRE_RATE := 0.9
const SWAT_GUN_DAMAGE := 14.0

var heat := 0.0
var _grace_timer := 0.0
var _tier := 0
var _spawn_timer := 0.0
var _spawned: Array = []

func get_tier() -> int:
	return _tier

func add_heat(amount: float, source_position: Vector3) -> void:
	heat = clamp(heat + amount, 0.0, MAX_HEAT)
	_grace_timer = DECAY_GRACE
	_update_tier()
	_alert_nearby_police(source_position)

func report_sighting() -> void:
	_grace_timer = DECAY_GRACE

# Autoloads survive get_tree().reload_current_scene() (unlike everything on
# Player, which reinstantiates from scratch) - without this, dying at a high
# wanted level would leave the very next life already hot for no reason.
func reset() -> void:
	heat = 0.0
	_grace_timer = 0.0
	_update_tier()

func _process(delta: float) -> void:
	if _grace_timer > 0.0:
		_grace_timer -= delta
	elif heat > 0.0:
		heat = max(0.0, heat - DECAY_RATE * delta)
		_update_tier()

	if heat >= MIN_SPAWN_HEAT:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_COOLDOWN_BY_TIER[_tier]
			_maybe_spawn_reinforcement()
	else:
		_spawn_timer = 0.0

# The 4 hand-placed officers are sparse enough across a ~150-unit city that
# most crimes happen nowhere near any of them - alert() alone (see
# add_heat below) only ever reaches whoever's already close by. This is
# what actually makes heat spawn a response anywhere it happens, capped so
# a long chase doesn't spiral into an unlimited swarm.
func _maybe_spawn_reinforcement() -> void:
	if heat < MIN_SPAWN_HEAT:
		return
	_spawned = _spawned.filter(func(c): return is_instance_valid(c) and not c.dead)
	if _spawned.size() >= MAX_SPAWNED_BY_TIER[_tier]:
		return
	var player := get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player) or player.get("current_interior") != null:
		return
	var angle := randf() * TAU
	var radius := randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	var spawn_pos: Vector3 = player.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

	var cop: Node3D = POLICE_SCENE.instantiate()
	cop.position = spawn_pos
	if _tier >= SWAT_TIER:
		cop.max_health = SWAT_HEALTH
		cop.chase_speed = SWAT_CHASE_SPEED
		cop.fire_rate = SWAT_FIRE_RATE
		cop.gun_damage = SWAT_GUN_DAMAGE
		cop.is_swat = true
	get_tree().current_scene.add_child(cop)
	_spawned.append(cop)
	cop.alert(player.global_position)

func _compute_tier() -> int:
	for i in range(TIER_THRESHOLDS.size() - 1, -1, -1):
		if heat >= TIER_THRESHOLDS[i]:
			return i + 1
	return 0

func _update_tier() -> void:
	var new_tier := _compute_tier()
	if new_tier != _tier:
		_tier = new_tier
		tier_changed.emit(_tier)

func _alert_nearby_police(source_position: Vector3) -> void:
	var radius: float = BASE_ALERT_RADIUS + _tier * TIER_ALERT_RADIUS_BONUS
	for cop in get_tree().get_nodes_in_group("police"):
		if cop.global_position.distance_to(source_position) <= radius and cop.has_method("alert"):
			cop.alert(source_position)
