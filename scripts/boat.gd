extends StaticBody3D

# Reuses the "parked_vehicles" group wholesale rather than adding a new
# "boats" group - player.gd's try_enter_vehicle() and every take_damage/
# vehicle-hit speed lookup (npc.gd/police.gd/player.gd's _speed_of_vehicle)
# already handles that group generically via drive_speed, so a boat gets
# entry/exit and hit-registration for free with zero changes to any of those
# scripts, as long as it exposes the same drive_speed var name parked_car.gd
# does.
@export var drive_max_speed: float = 9.0
@export var drive_accel: float = 6.0
@export var drive_brake_decel: float = 8.0
@export var drive_turn_speed: float = 1.3

# Gentle idle bob/roll on the visual model only (never on the StaticBody3D
# itself - that would drag the collision shape and DriverSeat/ExitPoint
# markers up and down with it) so a boat sitting at the dock doesn't look
# like a static prop glued to the water.
const BOB_HEIGHT := 0.06
const BOB_SPEED := 1.4
const ROLL_AMOUNT := 0.025

@onready var model: Node3D = $Model
@onready var driver_seat: Marker3D = _get_or_create_marker("DriverSeat", Vector3(0, 0.9, -0.6))
@onready var exit_point: Marker3D = _get_or_create_marker("ExitPoint", Vector3(1.8, 0.1, 0))

var driver: Node3D = null
var drive_speed := 0.0
var bob_time := 0.0

func _ready() -> void:
	add_to_group("parked_vehicles")
	bob_time = randf() * TAU # so multiple boats don't bob in lockstep

func _get_or_create_marker(marker_name: String, local_pos: Vector3) -> Marker3D:
	if has_node(marker_name):
		return get_node(marker_name)
	var m := Marker3D.new()
	m.name = marker_name
	add_child(m)
	m.position = local_pos
	return m

func driver_enter(who: Node3D) -> void:
	driver = who

func driver_exit() -> void:
	driver = null
	drive_speed = 0.0

func _physics_process(delta: float) -> void:
	bob_time += delta * BOB_SPEED
	model.position.y = sin(bob_time) * BOB_HEIGHT
	model.rotation.x = sin(bob_time * 0.7) * ROLL_AMOUNT
	model.rotation.z = cos(bob_time * 0.9) * ROLL_AMOUNT

	if not driver:
		return

	var throttle := 0.0
	if Input.is_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_key_pressed(KEY_S):
		throttle -= 1.0
	var joy_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(joy_y) > 0.2:
		throttle -= joy_y
	throttle = clamp(throttle, -1.0, 1.0)

	var steer := 0.0
	if Input.is_key_pressed(KEY_A):
		steer += 1.0
	if Input.is_key_pressed(KEY_D):
		steer -= 1.0
	var joy_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(joy_x) > 0.2:
		steer -= joy_x
	steer = clamp(steer, -1.0, 1.0)

	if absf(throttle) > 0.01:
		drive_speed = move_toward(drive_speed, throttle * drive_max_speed, drive_accel * delta)
	else:
		drive_speed = move_toward(drive_speed, 0.0, drive_brake_decel * delta)

	# Boats turn only while actually moving, same as parked_car.gd's cars -
	# spinning in place with zero speed doesn't make sense for either.
	if absf(drive_speed) > 0.1:
		rotation.y += steer * drive_turn_speed * delta * sign(drive_speed)

	var motion := Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * drive_speed * delta
	move_and_collide(motion)
