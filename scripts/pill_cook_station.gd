extends Area3D

# Same cook-a-batch-over-time pattern as cook_station.gd, but gated on 2
# ingredients (bought at the Convenience Store's ingredient_shelf.gd)
# consumed per batch instead of being free/unlimited like weed. Visually a
# separate flask/beaker rig (not the weed pot) so the two stations read as
# distinct machines even though the underlying loop is the same.
const COOK_TIME := 8.0
const YIELD_MIN := 2
const YIELD_MAX := 4
const IDLE_PROMPT := "Press E to cook boner pills (needs 1 Blue Oyster Dust + 1 Horse Semen)"
const MISSING_PROMPT := "Need 1 Blue Oyster Dust + 1 Horse Semen to cook"

const FLASK_COLOR := Color(0.75, 0.85, 0.85, 0.35)
const LIQUID_COLOR := Color(0.95, 0.25, 0.65)

var prompt_text := IDLE_PROMPT
var cooking := false
var cook_timer := 0.0
var cooking_player: Node3D = null

var flask_mesh: MeshInstance3D
var liquid_mesh: MeshInstance3D
var liquid_material: StandardMaterial3D
var bubbles: GPUParticles3D
var shake_time := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()

func _build_visual() -> void:
	flask_mesh = MeshInstance3D.new()
	var flask := CylinderMesh.new()
	flask.top_radius = 0.16
	flask.bottom_radius = 0.28
	flask.height = 0.4
	flask_mesh.mesh = flask
	var flask_mat := StandardMaterial3D.new()
	flask_mat.albedo_color = FLASK_COLOR
	flask_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flask_mat.metallic = 0.1
	flask_mat.roughness = 0.05
	flask_mesh.material_override = flask_mat
	add_child(flask_mesh)

	liquid_mesh = MeshInstance3D.new()
	var liquid := CylinderMesh.new()
	liquid.top_radius = 0.13
	liquid.bottom_radius = 0.25
	liquid.height = 0.2
	liquid_mesh.mesh = liquid
	liquid_material = StandardMaterial3D.new()
	liquid_material.albedo_color = LIQUID_COLOR
	liquid_material.emission_enabled = true
	liquid_material.emission = LIQUID_COLOR
	liquid_material.emission_energy_multiplier = 0.3
	liquid_mesh.material_override = liquid_material
	liquid_mesh.position = Vector3(0, -0.08, 0)
	flask_mesh.add_child(liquid_mesh)

	bubbles = GPUParticles3D.new()
	bubbles.amount = 20
	bubbles.lifetime = 1.0
	bubbles.emitting = false
	bubbles.position = Vector3(0, 0.0, 0)
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 8.0
	proc.gravity = Vector3(0, 0.15, 0)
	proc.initial_velocity_min = 0.15
	proc.initial_velocity_max = 0.35
	proc.scale_min = 0.03
	proc.scale_max = 0.07
	proc.color = LIQUID_COLOR
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.12
	bubbles.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	bubbles.draw_pass_1 = quad
	flask_mesh.add_child(bubbles)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func _process(delta: float) -> void:
	if not cooking:
		return
	cook_timer -= delta
	shake_time += delta
	flask_mesh.position.x = sin(shake_time * 18.0) * 0.015
	liquid_material.emission_energy_multiplier = 0.3 + sin(shake_time * 6.0) * 0.2
	if cook_timer <= 0.0:
		cooking = false
		bubbles.emitting = false
		flask_mesh.position.x = 0.0
		if cooking_player and is_instance_valid(cooking_player) and cooking_player.has_method("add_pills"):
			cooking_player.add_pills(randi_range(YIELD_MIN, YIELD_MAX))
		cooking_player = null
		prompt_text = IDLE_PROMPT

func interact(player: Node3D) -> void:
	if cooking:
		return
	if player.get("blue_oyster_dust") == null or player.blue_oyster_dust <= 0 \
			or player.get("horse_semen") == null or player.horse_semen <= 0:
		prompt_text = MISSING_PROMPT
		return
	player.blue_oyster_dust -= 1
	player.horse_semen -= 1
	cooking = true
	cook_timer = COOK_TIME
	shake_time = 0.0
	cooking_player = player
	bubbles.emitting = true
	prompt_text = "Cooking..."
