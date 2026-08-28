extends StaticBody3D

@export var max_health: float = 100.0
@export var blast_radius: float = 5.0
@export var blast_damage: float = 80.0
@export var kill_radius: float = 2.5

const INSTANT_KILL_DAMAGE := 99999.0
const EXPLOSION := preload("res://scenes/Explosion.tscn")
const SCORCH_MARK := preload("res://scenes/ScorchMark.tscn")
const FIRE := preload("res://scenes/Fire.tscn")

@onready var model: Node3D = $Model

var health: float
var destroyed := false

func _ready() -> void:
	health = max_health

func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO) -> void:
	if destroyed:
		return
	health -= amount
	if health <= 0.0:
		explode()

# Wrecks the car in place rather than removing it: charred and on fire,
# but it stays as a solid obstacle - only the drivable Car (car.gd) needs
# to additionally become un-enterable and physically frozen.
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
			var dist: float = global_position.distance_to(collider.global_position)
			var falloff: float = clamp(1.0 - dist / blast_radius, 0.0, 1.0)
			if falloff > 0.0:
				collider.take_damage(blast_damage * falloff, global_position)

# One shared unshaded near-black material applied to every mesh in the model,
# rather than trying to tint each of the FBX's original materials - simpler
# and gives a consistent "burnt husk" silhouette across every car variant.
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
