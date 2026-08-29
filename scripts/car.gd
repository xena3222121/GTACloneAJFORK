class_name Car
extends VehicleBody3D

const MAX_ENGINE_FORCE := 150.0
const MAX_BRAKE_FORCE := 4.0
const MAX_STEER := 0.6
const STEER_SPEED := 3.0

@export var max_health: float = 100.0
@export var blast_radius: float = 5.0

const INSTANT_KILL_DAMAGE := 99999.0
const EXPLOSION := preload("res://scenes/Explosion.tscn")
const SCORCH_MARK := preload("res://scenes/ScorchMark.tscn")
const FIRE := preload("res://scenes/Fire.tscn")

@onready var driver_seat: Marker3D = $DriverSeat
@onready var exit_point: Marker3D = $ExitPoint
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var model: Node3D = $CarModel

var driver: Node3D = null
var steer_target := 0.0
var health: float
var destroyed := false

func _ready() -> void:
	add_to_group("vehicles")
	camera.current = false
	health = max_health

func driver_enter(who: Node3D) -> void:
	driver = who
	camera.current = true

func driver_exit() -> void:
	driver = null
	engine_force = 0.0
	brake = 2.0
	camera.current = false

func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO) -> void:
	if destroyed:
		return
	health -= amount
	if health <= 0.0:
		explode()

# Wrecks the car in place rather than removing it: stays as a solid,
# charred, on-fire obstacle. Un-enterable (pulled from the "vehicles"
# group try_enter_vehicle() searches) and frozen in place (it's a
# RigidBody3D via VehicleBody3D, so without this residual momentum or a
# stray collision could still push the wreck around).
func explode() -> void:
	destroyed = true
	# The player can't currently shoot while driving (see player.gd's shoot()
	# guard), but eject defensively anyway in case something else ever damages
	# an occupied car - otherwise the player would be left controlling a wreck
	# that no longer responds to input.
	if driver and driver.has_method("exit_vehicle"):
		driver.exit_vehicle()
	remove_from_group("vehicles")
	freeze = true
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

func _physics_process(delta: float) -> void:
	if destroyed:
		return
	if not driver:
		engine_force = 0.0
		brake = 1.0
		return

	# Gamepad driving deliberately avoids the analog trigger axes - Godot's
	# reported idle/pressed range for JOY_AXIS_TRIGGER_LEFT/RIGHT isn't
	# consistent across controllers/drivers, and getting that wrong could
	# mean a car that silently creeps forward on its own. The left stick
	# (X for steer, Y for throttle) uses the regular -1..1 axis range every
	# controller reports consistently, so it can't misfire the same way.
	var joy_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var joy_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(joy_x) < 0.2:
		joy_x = 0.0
	if absf(joy_y) < 0.2:
		joy_y = 0.0

	var throttle_input := 0.0
	if Input.is_key_pressed(KEY_W):
		throttle_input += 1.0
	if Input.is_key_pressed(KEY_S):
		throttle_input -= 1.0
	throttle_input = clamp(throttle_input - joy_y, -1.0, 1.0)
	engine_force = throttle_input * MAX_ENGINE_FORCE

	var steer_input := 0.0
	if Input.is_key_pressed(KEY_A):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_D):
		steer_input -= 1.0
	steer_input = clamp(steer_input - joy_x, -1.0, 1.0)
	steer_target = steer_input * MAX_STEER
	steering = move_toward(steering, steer_target, STEER_SPEED * delta)

	brake = MAX_BRAKE_FORCE if (Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)) else 0.0
