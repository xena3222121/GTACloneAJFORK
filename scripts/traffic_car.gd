extends AnimatableBody3D

@export var speed: float = 6.0
@export var axis: int = 0  # 0 = drives back and forth along Z (a north-south street), 1 = along X (an east-west street)
@export var min_pos: float = -45.0
@export var max_pos: float = 45.0
@export var start_direction: float = 1.0
@export var max_health: float = 100.0
@export var blast_radius: float = 5.0

const INSTANT_KILL_DAMAGE := 99999.0
const EXPLOSION := preload("res://scenes/Explosion.tscn")
const SCORCH_MARK := preload("res://scenes/ScorchMark.tscn")
const FIRE := preload("res://scenes/Fire.tscn")

@onready var model: Node3D = $Model

var direction: float = 1.0
var health: float
var destroyed := false

func _ready() -> void:
	# sync_to_physics (on by default for AnimatableBody3D) re-syncs the node's
	# transform from the physics server every step, which was silently
	# discarding our rotation changes each frame — the car kept moving but
	# never actually turned to face its direction of travel.
	sync_to_physics = false
	direction = 1.0 if start_direction >= 0.0 else -1.0
	_update_facing()
	health = max_health

func _update_facing() -> void:
	if axis == 0:
		rotation.y = 0.0 if direction > 0.0 else PI
	else:
		rotation.y = PI / 2.0 if direction > 0.0 else -PI / 2.0

func _physics_process(delta: float) -> void:
	if destroyed:
		return
	var pos: float = position.z if axis == 0 else position.x
	pos += direction * speed * delta
	if pos >= max_pos:
		pos = max_pos
		direction = -1.0
		_update_facing()
	elif pos <= min_pos:
		pos = min_pos
		direction = 1.0
		_update_facing()
	if axis == 0:
		position.z = pos
	else:
		position.x = pos

func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO) -> void:
	if destroyed:
		return
	health -= amount
	if health <= 0.0:
		explode()

# Wrecks the car in place rather than removing it (movement already stops
# via the `destroyed` guard in _physics_process above).
func explode() -> void:
	destroyed = true
	_spawn_explosion()
	_spawn_scorch_mark()
	_apply_blast_damage()
	_char_model()
	_spawn_fire()

func _spawn_explosion() -> void:
	var fx: Node3D = EXPLOSION.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.global_position = global_position + Vector3(0, 0.6, 0)

func _spawn_scorch_mark() -> void:
	var mark: Node3D = SCORCH_MARK.instantiate()
	get_tree().current_scene.add_child(mark)
	mark.global_position = Vector3(global_position.x, 0.02, global_position.z)
	mark.rotation.y = randf() * TAU

# Anything the shape query finds is by definition within blast_radius (that's
# the query's own shape), so no distance check is needed - the whole radius
# is a kill zone now, not just an inner subset of it.
func _apply_blast_damage() -> void:
	var space_state := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [self.get_rid()]
	for result in space_state.intersect_shape(query, 32):
		var collider: Object = result.get("collider")
		if collider and collider.has_method("take_damage"):
			collider.take_damage(INSTANT_KILL_DAMAGE, global_position)

func _char_model() -> void:
	var burnt := StandardMaterial3D.new()
	burnt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	burnt.albedo_color = Color(0.045, 0.045, 0.045)
	_darken_recursive(model, burnt)

func _darken_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_darken_recursive(child, mat)

func _spawn_fire() -> void:
	var fire: Node3D = FIRE.instantiate()
	add_child(fire)
	fire.position = Vector3(0, 0.6, 0)
