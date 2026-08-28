class_name Car
extends VehicleBody3D

const MAX_ENGINE_FORCE := 150.0
const MAX_BRAKE_FORCE := 4.0
const MAX_STEER := 0.6
const STEER_SPEED := 3.0

@onready var driver_seat: Marker3D = $DriverSeat
@onready var exit_point: Marker3D = $ExitPoint
@onready var camera: Camera3D = $CameraPivot/Camera3D

var driver: Node3D = null
var steer_target := 0.0

func _ready() -> void:
	add_to_group("vehicles")
	camera.current = false

func driver_enter(who: Node3D) -> void:
	driver = who
	camera.current = true

func driver_exit() -> void:
	driver = null
	engine_force = 0.0
	brake = 2.0
	camera.current = false

func _physics_process(delta: float) -> void:
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
