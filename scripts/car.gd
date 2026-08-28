class_name Car
extends VehicleBody3D

const MAX_ENGINE_FORCE := 150.0
const MAX_BRAKE_FORCE := 4.0
const MAX_STEER := 0.6
const STEER_SPEED := 3.0

@export var max_health: float = 100.0

const EXPLOSION := preload("res://scenes/Explosion.tscn")
const SCORCH_MARK := preload("res://scenes/ScorchMark.tscn")

@onready var driver_seat: Marker3D = $DriverSeat
@onready var exit_point: Marker3D = $ExitPoint
@onready var camera: Camera3D = $CameraPivot/Camera3D

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

func explode() -> void:
	destroyed = true
	# The player can't currently shoot while driving (see player.gd's shoot()
	# guard), but eject defensively anyway in case something else ever damages
	# an occupied car - otherwise the player would be left controlling a freed node.
	if driver and driver.has_method("exit_vehicle"):
		driver.exit_vehicle()
	_spawn_explosion()
	_spawn_scorch_mark()
	queue_free()

func _spawn_explosion() -> void:
	var fx: Node3D = EXPLOSION.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.global_position = global_position + Vector3(0, 0.6, 0)

func _spawn_scorch_mark() -> void:
	var mark: Node3D = SCORCH_MARK.instantiate()
	get_tree().current_scene.add_child(mark)
	mark.global_position = Vector3(global_position.x, 0.02, global_position.z)
	mark.rotation.y = randf() * TAU

func _physics_process(delta: float) -> void:
	if destroyed:
		return
	if not driver:
		engine_force = 0.0
		brake = 1.0
		return

	var throttle_input := 0.0
	if Input.is_key_pressed(KEY_W):
		throttle_input += 1.0
	if Input.is_key_pressed(KEY_S):
		throttle_input -= 1.0
	engine_force = throttle_input * MAX_ENGINE_FORCE

	var steer_input := 0.0
	if Input.is_key_pressed(KEY_A):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_D):
		steer_input -= 1.0
	steer_target = steer_input * MAX_STEER
	steering = move_toward(steering, steer_target, STEER_SPEED * delta)

	brake = MAX_BRAKE_FORCE if Input.is_key_pressed(KEY_SPACE) else 0.0
