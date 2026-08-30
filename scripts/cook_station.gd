extends Area3D

const COOK_TIME := 8.0
const YIELD_MIN := 3
const YIELD_MAX := 6
const COOK_COST := 5
const IDLE_PROMPT := "Press E to cook a batch - $%d" % COOK_COST
const NO_MONEY_PROMPT := "Need $%d to cook a batch" % COOK_COST

const POT_COLOR := Color(0.22, 0.24, 0.22)
const CONTENTS_COLOR := Color(0.32, 0.55, 0.2)

var prompt_text := IDLE_PROMPT
var cooking := false
var cook_timer := 0.0
var cooking_player: Node3D = null

var pot_mesh: MeshInstance3D
var steam: GPUParticles3D
var bob_time := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()

func _build_visual() -> void:
	pot_mesh = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.34
	mesh.height = 0.35
	pot_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = POT_COLOR
	mat.metallic = 0.4
	mat.roughness = 0.5
	pot_mesh.material_override = mat
	add_child(pot_mesh)

	var contents := MeshInstance3D.new()
	var contents_mesh := CylinderMesh.new()
	contents_mesh.top_radius = 0.27
	contents_mesh.bottom_radius = 0.27
	contents_mesh.height = 0.05
	contents.mesh = contents_mesh
	var contents_mat := StandardMaterial3D.new()
	contents_mat.albedo_color = CONTENTS_COLOR
	contents.material_override = contents_mat
	contents.position = Vector3(0, 0.18, 0)
	pot_mesh.add_child(contents)

	steam = GPUParticles3D.new()
	steam.amount = 24
	steam.lifetime = 1.4
	steam.emitting = false
	steam.position = Vector3(0, 0.22, 0)
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 20.0
	proc.gravity = Vector3(0, 0.3, 0)
	proc.initial_velocity_min = 0.3
	proc.initial_velocity_max = 0.6
	proc.scale_min = 0.05
	proc.scale_max = 0.12
	proc.color = Color(0.85, 0.85, 0.85, 0.5)
	steam.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	steam.draw_pass_1 = quad
	add_child(steam)

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
	bob_time += delta
	pot_mesh.position.y = sin(bob_time * 10.0) * 0.02
	if cook_timer <= 0.0:
		cooking = false
		steam.emitting = false
		pot_mesh.position.y = 0.0
		if cooking_player and is_instance_valid(cooking_player) and cooking_player.has_method("add_drugs"):
			cooking_player.add_drugs(randi_range(YIELD_MIN, YIELD_MAX))
		cooking_player = null
		prompt_text = IDLE_PROMPT

func interact(player: Node3D) -> void:
	if cooking:
		return
	if player.get("money") == null or player.money < COOK_COST:
		prompt_text = NO_MONEY_PROMPT
		return
	player.add_money(-COOK_COST)
	cooking = true
	cook_timer = COOK_TIME
	bob_time = 0.0
	cooking_player = player
	steam.emitting = true
	prompt_text = "Cooking..."
