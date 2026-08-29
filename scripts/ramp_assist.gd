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

const RAMP_HALF_WIDTH := 14.0
const RISE := 6.0

# Each entry: x center, z range the ramp covers, and which end (z_low) is
# ground level (height 0) vs which end (z_high) is deck level (height RISE).
const RAMPS := [
	{"x": 0.0, "z_low": 8.0, "z_high": 48.0},
	{"x": 60.0, "z_low": 8.0, "z_high": 48.0},
	{"x": 0.0, "z_low": -8.0, "z_high": -48.0},
	{"x": 60.0, "z_low": -8.0, "z_high": -48.0},
]

func _physics_process(_delta: float) -> void:
	var vehicles := get_tree().get_nodes_in_group("vehicles")
	vehicles.append_array(get_tree().get_nodes_in_group("traffic_cars"))
	vehicles.append_array(get_tree().get_nodes_in_group("parked_vehicles"))
	for v in vehicles:
		if not is_instance_valid(v) or v.get("destroyed") == true:
			continue
		var pos: Vector3 = v.global_position
		for ramp in RAMPS:
			if absf(pos.x - ramp.x) > RAMP_HALF_WIDTH:
				continue
			var z_low: float = ramp.z_low
			var z_high: float = ramp.z_high
			var lo: float = min(z_low, z_high)
			var hi: float = max(z_low, z_high)
			if pos.z < lo or pos.z > hi:
				continue
			var t: float = clamp(inverse_lerp(z_low, z_high, pos.z), 0.0, 1.0)
			v.global_position.y = lerp(0.0, RISE, t) + 0.35
			break
