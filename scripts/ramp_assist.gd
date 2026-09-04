extends Node

# The physical tilted-box ramp collision proved unreliable for
# VehicleBody3D/traffic cars - extensive playtesting found cars stalling
# out partway up regardless of slope angle, ramp width, or engine power,
# with no single clear root cause found. Rather than keep guessing blind,
# this guarantees smooth traversal directly: any vehicle whose XZ position
# falls within a ramp's footprint gets its height pinned to exactly what
# the ramp surface should be at that Z, every physics frame. The real ramp
# collision/mesh stays in place for looks and for anything standing still
# on it; this only overrides height for vehicles actively crossing.

const RAMP_HALF_WIDTH := 3.5 # was 14 - a full-width ramp box straddled the entire main road beneath it, snapping straight-through traffic onto the ramp slope instead of just vehicles actually using it. Narrowed (and the ramp geometry in World.tscn shifted to x=4/56, off the x=0/60 road centerlines) so it only covers the ramp lane itself.
const RISE := 6.0

# Each entry: x center, z range the ramp covers, and which end (z_low) is
# ground level (height 0) vs which end (z_high) is deck level (height RISE).
const RAMPS := [
	{"x": 4.0, "z_low": 8.0, "z_high": 48.0},
	{"x": 56.0, "z_low": 8.0, "z_high": 48.0},
	{"x": 4.0, "z_low": -8.0, "z_high": -48.0},
	{"x": 56.0, "z_low": -8.0, "z_high": -48.0},
	# Midtown (StreetC, x=120) and Eastside (StreetD, x=180) ramps up to
	# HighwayEast/HighwaySouthEast - same +4/-4 off-road offset as the
	# original pair, learned from that fix instead of repeating the mistake.
	{"x": 124.0, "z_low": 8.0, "z_high": 48.0},
	{"x": 176.0, "z_low": 8.0, "z_high": 48.0},
	{"x": 124.0, "z_low": -8.0, "z_high": -48.0},
	{"x": 176.0, "z_low": -8.0, "z_high": -48.0},
]

# How hard to correct back toward the ideal slope height if a RigidBody3D
# vehicle drifts off it (bounced, suspension travel, etc). Only a gentle
# nudge on top of the velocity-follows-slope term below - see
# _apply_physics_vehicle for why this exists instead of a position teleport.
const HEIGHT_CORRECT_RATE := 4.0

func _physics_process(_delta: float) -> void:
	var kinematic_vehicles := get_tree().get_nodes_in_group("traffic_cars")
	kinematic_vehicles.append_array(get_tree().get_nodes_in_group("parked_vehicles"))
	for v in kinematic_vehicles:
		_apply_teleport(v)
	for v in get_tree().get_nodes_in_group("vehicles"):
		_apply_physics_vehicle(v)

# Kinematic cars (AnimatableBody3D/StaticBody3D, no real physics velocity to
# fight) - a straight position teleport works fine and always has.
func _apply_teleport(v: Node3D) -> void:
	if not is_instance_valid(v) or v.get("destroyed") == true:
		return
	var pos: Vector3 = v.global_position
	for ramp in RAMPS:
		if absf(pos.x - ramp.x) > RAMP_HALF_WIDTH:
			continue
		var lo: float = min(ramp.z_low, ramp.z_high)
		var hi: float = max(ramp.z_low, ramp.z_high)
		if pos.z < lo or pos.z > hi:
			continue
		var t: float = clamp(inverse_lerp(ramp.z_low, ramp.z_high, pos.z), 0.0, 1.0)
		v.global_position.y = lerp(0.0, RISE, t) + 0.35
		return

# The real VehicleBody3D (RigidBody3D) doesn't get a position teleport at
# all - confirmed via an automated drive-up-the-ramp test that teleporting
# its position every physics frame (even after zeroing vertical velocity/
# angular velocity right after) still built up a slow, then runaway, yaw
# spin over a few seconds, eventually spinning the car out. Instead this
# drives its height purely through velocity - matching vertical speed to
# how fast it's actually climbing the slope (so gravity/suspension/steering
# all keep working normally, nothing gets teleported) plus a small
# proportional nudge back toward the exact slope height if it drifts.
func _apply_physics_vehicle(v: Node3D) -> void:
	if not is_instance_valid(v) or v.get("destroyed") == true:
		return
	var pos: Vector3 = v.global_position
	for ramp in RAMPS:
		if absf(pos.x - ramp.x) > RAMP_HALF_WIDTH:
			continue
		var lo: float = min(ramp.z_low, ramp.z_high)
		var hi: float = max(ramp.z_low, ramp.z_high)
		if pos.z < lo or pos.z > hi:
			continue
		var slope: float = RISE / (ramp.z_high - ramp.z_low)
		var t: float = clamp(inverse_lerp(ramp.z_low, ramp.z_high, pos.z), 0.0, 1.0)
		var target_y: float = lerp(0.0, RISE, t) + 0.35
		var height_error: float = target_y - pos.y
		# Confirmed via an automated test: the body would fall asleep mid-
		# climb (Godot's default "not moving enough" heuristic, misfired by
		# this exact velocity nudge being small and steady) which freezes
		# its horizontal velocity entirely while this kept overwriting the
		# now-meaningless vertical component of a body the engine had
		# stopped simulating - reading as the car just stopping dead for no
		# reason. It has an active driver climbing an incline; it should
		# never be considered "at rest."
		v.sleeping = false
		v.linear_velocity.y = v.linear_velocity.z * slope + height_error * HEIGHT_CORRECT_RATE
		return
