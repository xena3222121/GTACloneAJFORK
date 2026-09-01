extends StaticBody3D

@export var max_health: float = 100.0
@export var blast_radius: float = 5.0

# Every stealable/buyable car used these same 4 numbers regardless of model -
# a Camaro drove identically to a delivery SUV. Exported so each
# ParkedCar_*.tscn can set its own feel (see the per-scene values there):
# sports cars quick and fast but fragile, SUVs/vans heavy and stable but
# sluggish, everything else at these defaults (the old hardcoded baseline).
@export var drive_max_speed: float = 14.0
@export var drive_accel: float = 10.0
@export var drive_brake_decel: float = 18.0
@export var drive_turn_speed: float = 2.2

const HANDBRAKE_TURN_MULTIPLIER := 1.8
const HANDBRAKE_DECEL_MULTIPLIER := 2.2

# Nitro - a temporary multiplier on top of whatever drive_max_speed/
# drive_accel this specific car already has, so a boosted Camaro is still
# faster than a boosted delivery van rather than every car converging on
# the same top speed. Same Shift key player.gd already uses for on-foot
# sprint (only one of the two contexts is ever active at once).
const BOOST_SPEED_MULTIPLIER := 1.5
const BOOST_ACCEL_MULTIPLIER := 1.4
const BOOST_FUEL_MAX := 3.0
const BOOST_DRAIN_RATE := 1.0
const BOOST_REGEN_RATE := 0.5

const INSTANT_KILL_DAMAGE := 99999.0
const EXPLOSION := preload("res://scenes/Explosion.tscn")
const SCORCH_MARK := preload("res://scenes/ScorchMark.tscn")
const FIRE := preload("res://scenes/Fire.tscn")

@onready var model: Node3D = $Model
@onready var driver_seat: Marker3D = _get_or_create_marker("DriverSeat", Vector3(0, 0.9, 0))
@onready var exit_point: Marker3D = _get_or_create_marker("ExitPoint", Vector3(1.8, 0.1, 0))

var health: float
var destroyed := false

# No driver to eject here (unlike traffic_car.gd) - a parked car is just
# sitting empty until stolen. Simple kinematic drive (direct position/
# rotation updates), same technique traffic_car.gd already uses for its
# own AI patrol - a StaticBody3D has no physics forces to apply throttle
# to, so this isn't optional simplification, it's the only way a static
# body moves at all.
var driver: Node3D = null
var drive_speed := 0.0
var boost_fuel := BOOST_FUEL_MAX
var engine_audio: AudioStreamPlayer3D

# Same real recorded engine loop as car.gd/traffic_car.gd - a parked car
# that gets stolen was silent while every other drivable car got real
# engine audio this session.
const ENGINE_LOOP_PATH := "res://Audio/Ambience/car_engine_loop.wav"

func _ready() -> void:
	health = max_health
	add_to_group("parked_vehicles")
	_setup_engine_audio()

func _setup_engine_audio() -> void:
	engine_audio = AudioStreamPlayer3D.new()
	engine_audio.unit_size = 20.0
	engine_audio.volume_db = -14.0
	var stream: AudioStreamWAV = (load(ENGINE_LOOP_PATH) as AudioStreamWAV).duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	engine_audio.stream = stream
	add_child(engine_audio)

func _update_engine_audio() -> void:
	if destroyed or not driver:
		if engine_audio.playing:
			engine_audio.stop()
		return
	var speed_ratio: float = clamp(absf(drive_speed) / drive_max_speed, 0.0, 1.0)
	engine_audio.pitch_scale = lerp(0.8, 2.0, speed_ratio)
	engine_audio.volume_db = lerp(-14.0, -6.0, speed_ratio)
	if not engine_audio.playing:
		engine_audio.play()

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
	_update_engine_audio()
	if destroyed or not driver:
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

	# Handbrake turn - the classic arcade GTA move (same SPACE/A-button brake
	# key car.gd already uses for its own VehicleBody3D). Cuts throttle and
	# bleeds speed hard, but sharpens the turn rate while it does, so
	# stomping it into a corner reads as a slide instead of just braking.
	var handbrake := Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)

	var boosting := (Input.is_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)) \
			and boost_fuel > 0.0 and throttle > 0.01 and not handbrake
	boost_fuel = clamp(boost_fuel + (-BOOST_DRAIN_RATE if boosting else BOOST_REGEN_RATE) * delta, 0.0, BOOST_FUEL_MAX)
	var effective_max_speed: float = drive_max_speed * (BOOST_SPEED_MULTIPLIER if boosting else 1.0)
	var effective_accel: float = drive_accel * (BOOST_ACCEL_MULTIPLIER if boosting else 1.0)

	if absf(throttle) > 0.01 and not handbrake:
		drive_speed = move_toward(drive_speed, throttle * effective_max_speed, effective_accel * delta)
	else:
		var decel: float = drive_brake_decel * (HANDBRAKE_DECEL_MULTIPLIER if handbrake else 1.0)
		drive_speed = move_toward(drive_speed, 0.0, decel * delta)

	if absf(drive_speed) > 0.1:
		var turn_rate: float = drive_turn_speed * (HANDBRAKE_TURN_MULTIPLIER if handbrake else 1.0)
		rotation.y += steer * turn_rate * delta * sign(drive_speed)

	# Was a raw `position +=` - a StaticBody3D moved that way never tests for
	# collisions at all, so a driven car could pass straight through walls,
	# buildings, other cars, anything. move_and_collide (available on any
	# PhysicsBody3D, not just CharacterBody3D) actually stops the car at
	# whatever it hits instead of tunneling through it.
	var motion := Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * drive_speed * delta
	if move_and_collide(motion):
		drive_speed = 0.0

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
	NPC.scare_nearby(get_tree(), global_position, blast_radius * 2.5)
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
