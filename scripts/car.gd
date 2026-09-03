class_name Car
extends VehicleBody3D

@export var max_health: float = 100.0
@export var blast_radius: float = 5.0

# Was hardcoded (150/4/0.6/3.0) - exported for the same reason
# parked_car.gd's driving consts were: this VehicleBody3D is currently
# only used for the one hero car near the safehouse, but future car.gd
# instances can now be tuned individually instead of being stuck identical.
@export var max_engine_force: float = 150.0
@export var max_brake_force: float = 4.0
@export var max_steer: float = 0.6
@export var steer_speed: float = 3.0

# Same nitro mechanic as parked_car.gd, adapted to a real VehicleBody3D -
# boosts engine_force directly rather than a speed cap, since this car has
# actual physics-driven acceleration instead of the kinematic model's
# move_toward. Same Shift/right-shoulder input as parked_car.gd.
const BOOST_MULTIPLIER := 1.6
const BOOST_FUEL_MAX := 3.0
const BOOST_DRAIN_RATE := 1.0
const BOOST_REGEN_RATE := 0.5

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
var boost_fuel := BOOST_FUEL_MAX
var health: float
var destroyed := false
var engine_audio: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("vehicles")
	camera.current = false
	health = max_health
	_setup_engine_audio()
	_setup_headlights()
	_setup_collision_detection()

# Every other drivable car (parked_car.gd's StaticBody3D, traffic_car.gd's
# AnimatableBody3D) registers a hit on whatever it rams via its own
# move_and_collide result each frame - but this is a real RigidBody3D, which
# never moves that way and never had contact_monitor on at all. That meant
# ramming a standing-still pedestrian with THIS car (the one already parked
# outside the safehouse the player starts with) did nothing whatsoever - no
# damage, no knockback - while every other car type in the game worked fine.
# contact_monitor + body_entered is the RigidBody3D-native equivalent; the
# driver's own CharacterBody3D collision is disabled while driving (see
# player.gd's enter_vehicle), so this never fires on the player driving it.
func _setup_collision_detection() -> void:
	contact_monitor = true
	max_contacts_reported = 8
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if destroyed or not body.has_method("register_vehicle_hit"):
		return
	body.register_vehicle_hit(self, linear_velocity.length())

# City streets were dead silent otherwise - every moving car (player's and
# traffic's alike) gets a real recorded engine loop (see
# Audio/Ambience/ATTRIBUTION.md - CC BY 4.0, qubodup), pitched and mixed
# based on actual speed each frame (see _update_engine_audio). A first pass
# here used a synthesized sawtooth loop, but it read as a crude bass rumble
# rather than an engine, so it was swapped for a real recording.
const ENGINE_LOOP_PATH := "res://Audio/Ambience/car_engine_loop.wav"

func _setup_engine_audio() -> void:
	engine_audio = AudioStreamPlayer3D.new()
	engine_audio.unit_size = 20.0
	engine_audio.volume_db = -14.0
	var stream: AudioStreamWAV = load(ENGINE_LOOP_PATH)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	engine_audio.stream = stream
	add_child(engine_audio)

# Only plays while actually being driven - both because a parked car with
# its engine off should be silent, and because a real Godot quirk found via
# playtesting: a child AudioStreamPlayer3D on a SLEEPING RigidBody3D (which
# this is, once parked and still) can't sustain playback at all - it starts
# and gets cut within the same frame, over and over. Gating on `driver`
# sidesteps that entirely rather than fighting the engine's sleep state.
func _update_engine_audio() -> void:
	if destroyed or not driver:
		if engine_audio.playing:
			engine_audio.stop()
		return
	var speed_ratio: float = clamp(linear_velocity.length() / 20.0, 0.0, 1.0)
	engine_audio.pitch_scale = lerp(0.8, 2.0, speed_ratio)
	engine_audio.volume_db = lerp(-14.0, -6.0, speed_ratio)
	if not engine_audio.playing:
		engine_audio.play()

# Nothing in this project's car scripts had any light source at all - fine
# while every other light in the city ran at a flat constant brightness, but
# now that streetlights actually go dark by day and light up at night (see
# world_sky.gd), a car with zero headlight cone driving through a genuinely
# dark street reads as broken, not just "less detailed". Two SpotLight3D
# children built in code rather than hand-placed per car scene - every one
# of the ~13 car models in this project would otherwise need its own
# manually-tuned light position, and this generic forward-and-low placement
# reads fine across all of them at this low-poly scale.
const HEADLIGHT_FORWARD_OFFSET := 2.0
const HEADLIGHT_SIDE_OFFSET := 0.6
const HEADLIGHT_HEIGHT := 0.5
const HEADLIGHT_RANGE := 18.0
const HEADLIGHT_SPOT_ANGLE := 35.0
const HEADLIGHT_ENERGY := 6.0
const HEADLIGHT_COLOR := Color(1.0, 0.97, 0.85)
# Matches world_sky.gd's STREETLIGHT_ON_THRESHOLD so headlights and
# streetlights click on together, like a real dusk sensor.
const HEADLIGHT_ON_THRESHOLD := 0.4

var headlight_left: SpotLight3D
var headlight_right: SpotLight3D

func _setup_headlights() -> void:
	headlight_left = _make_headlight(-HEADLIGHT_SIDE_OFFSET)
	headlight_right = _make_headlight(HEADLIGHT_SIDE_OFFSET)

func _make_headlight(x_offset: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.position = Vector3(x_offset, HEADLIGHT_HEIGHT, HEADLIGHT_FORWARD_OFFSET)
	# SpotLight3D points down its own local -Z by default; this project's
	# cars treat +Z as forward (see the drive_speed motion vector below /
	# in parked_car.gd/traffic_car.gd), so a 180-degree yaw aims the cone
	# forward instead of out the back of the car.
	light.rotation_degrees = Vector3(0, 180, 0)
	light.spot_range = HEADLIGHT_RANGE
	light.spot_angle = HEADLIGHT_SPOT_ANGLE
	light.light_energy = HEADLIGHT_ENERGY
	light.light_color = HEADLIGHT_COLOR
	light.visible = false
	add_child(light)
	return light

# Only lit while actually being driven (an empty parked car's headlights
# shouldn't glow) and only once it's actually gotten dark - same gating
# _update_engine_audio() already does for `driver`, same threshold
# world_sky.gd uses for streetlights.
func _update_headlights() -> void:
	var should_be_on: bool = driver != null and not destroyed and DayNightCycle.sun_altitude() < HEADLIGHT_ON_THRESHOLD
	headlight_left.visible = should_be_on
	headlight_right.visible = should_be_on

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
	_update_engine_audio()
	_update_headlights()
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

	var boosting := (Input.is_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)) \
			and boost_fuel > 0.0 and throttle_input > 0.01
	boost_fuel = clamp(boost_fuel + (-BOOST_DRAIN_RATE if boosting else BOOST_REGEN_RATE) * delta, 0.0, BOOST_FUEL_MAX)
	engine_force = throttle_input * max_engine_force * (BOOST_MULTIPLIER if boosting else 1.0)

	var steer_input := 0.0
	if Input.is_key_pressed(KEY_A):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_D):
		steer_input -= 1.0
	steer_input = clamp(steer_input - joy_x, -1.0, 1.0)
	steer_target = steer_input * max_steer
	steering = move_toward(steering, steer_target, steer_speed * delta)

	brake = max_brake_force if (Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)) else 0.0
