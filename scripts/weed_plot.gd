extends Area3D

# Real-time stand-in for "a day" - this project has no day/night cycle yet
# (same trick cook_station.gd uses for its real 8s "cook a batch" timer,
# just a much longer wait to match the GTA-style "plant it, come back later"
# fantasy). Uses wall-clock time rather than a running in-scene timer so the
# plant keeps growing across a save/reload instead of resetting.
const GROW_TIME_SECONDS := 300.0
const YIELD_MIN := 4
const YIELD_MAX := 8

const POT_COLOR := Color(0.32, 0.22, 0.14)
const PLANT_COLOR := Color(0.16, 0.5, 0.14)
const READY_COLOR := Color(0.42, 0.82, 0.18)
const MIN_PLANT_SCALE := 0.08

enum State { EMPTY, GROWING, READY }

var state: int = State.EMPTY
var planted_at: int = 0
var prompt_text := "Press E to plant weed seeds"

var plant_mesh: MeshInstance3D
var plant_material: StandardMaterial3D
var sway_time := 0.0

func _ready() -> void:
	add_to_group("weed_plot")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()
	_refresh()

# This node's own origin sits at y=1 (shared "counter height" convention
# for the interact sphere, same as every other station in the house) - the
# pot needs to actually sit on the floor, so everything here is offset by
# -GROUND_OFFSET to land at world y=0 without moving the interact zone.
const GROUND_OFFSET := 1.0

func _build_visual() -> void:
	var pot := MeshInstance3D.new()
	var pot_mesh := CylinderMesh.new()
	pot_mesh.top_radius = 0.32
	pot_mesh.bottom_radius = 0.38
	pot_mesh.height = 0.3
	pot.mesh = pot_mesh
	var pot_mat := StandardMaterial3D.new()
	pot_mat.albedo_color = POT_COLOR
	pot.material_override = pot_mat
	pot.position = Vector3(0, 0.15 - GROUND_OFFSET, 0)
	add_child(pot)

	plant_mesh = MeshInstance3D.new()
	var foliage := SphereMesh.new()
	foliage.radius = 0.4
	foliage.height = 0.75
	foliage.radial_segments = 10
	foliage.rings = 6
	plant_mesh.mesh = foliage
	plant_material = StandardMaterial3D.new()
	plant_material.albedo_color = PLANT_COLOR
	plant_mesh.material_override = plant_material
	plant_mesh.position = Vector3(0, 0.32 - GROUND_OFFSET, 0)
	plant_mesh.scale = Vector3.ONE * MIN_PLANT_SCALE
	add_child(plant_mesh)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func _process(delta: float) -> void:
	_refresh()
	_update_visual(delta)

func _elapsed() -> int:
	return Time.get_unix_time_from_system() - planted_at

func _growth_fraction() -> float:
	match state:
		State.EMPTY:
			return 0.0
		State.READY:
			return 1.0
		State.GROWING:
			return clamp(float(_elapsed()) / GROW_TIME_SECONDS, 0.0, 1.0)
	return 0.0

func _update_visual(delta: float) -> void:
	sway_time += delta
	var t := _growth_fraction()
	var s: float = lerp(MIN_PLANT_SCALE, 1.0, t)
	plant_mesh.scale = Vector3.ONE * s
	plant_mesh.position.y = 0.32 * s - GROUND_OFFSET
	# A gentle idle sway once there's actually something to sway - a static
	# plant reads as a prop, a swaying one reads as alive/growing.
	plant_mesh.rotation.z = sin(sway_time * 1.4) * 0.05 * t
	plant_mesh.rotation.x = cos(sway_time * 1.1) * 0.04 * t
	plant_material.albedo_color = READY_COLOR if state == State.READY else PLANT_COLOR
	if state == State.READY:
		plant_material.emission_enabled = true
		plant_material.emission = READY_COLOR
		plant_material.emission_energy_multiplier = 0.5 + sin(sway_time * 2.0) * 0.15
	else:
		plant_material.emission_enabled = false

func _refresh() -> void:
	if state == State.GROWING:
		var remaining: int = int(max(0.0, GROW_TIME_SECONDS - _elapsed()))
		if remaining <= 0:
			state = State.READY
		else:
			prompt_text = "Growing... ready in %dm %ds" % [remaining / 60, remaining % 60]
	if state == State.EMPTY:
		prompt_text = "Press E to plant weed seeds"
	elif state == State.READY:
		prompt_text = "Press E to harvest the weed"

func interact(player: Node3D) -> void:
	match state:
		State.EMPTY:
			state = State.GROWING
			planted_at = Time.get_unix_time_from_system()
		State.READY:
			if player.has_method("add_drugs"):
				player.add_drugs(randi_range(YIELD_MIN, YIELD_MAX))
			state = State.EMPTY
		State.GROWING:
			pass
	_refresh()
