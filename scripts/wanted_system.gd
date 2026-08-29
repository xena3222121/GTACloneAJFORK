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
const DECAY_RATE := 6.0
const DECAY_GRACE := 4.0
const TIER_THRESHOLDS := [25.0, 55.0, 85.0]
const BASE_ALERT_RADIUS := 14.0
const TIER_ALERT_RADIUS_BONUS := 8.0

var heat := 0.0
var _grace_timer := 0.0
var _tier := 0

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
		return
	if heat > 0.0:
		heat = max(0.0, heat - DECAY_RATE * delta)
		_update_tier()

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
