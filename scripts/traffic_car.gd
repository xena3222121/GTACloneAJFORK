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

const EJECTED_NPC_SCENES := [
	preload("res://scenes/NPC_A.tscn"),
	preload("res://scenes/NPC_B.tscn"),
	preload("res://scenes/NPC_C.tscn"),
	preload("res://scenes/NPC_D.tscn"),
	preload("res://scenes/NPC_Megan.tscn"),
	preload("res://scenes/NPC_Leonard.tscn"),
]
const EJECT_KNOCKBACK := 7.0
const EJECT_UP := 4.5

const DRIVE_MAX_SPEED := 14.0
const DRIVE_ACCEL := 10.0
const DRIVE_BRAKE_DECEL := 18.0
const DRIVE_TURN_SPEED := 2.2

# Called from npc.gd's NPC.scare_nearby() - ambient traffic screeching down
# to a crawl near a shooting/explosion/death instead of just cruising
# obliviously through it. No steering/lane-change logic, just a temporary
# speed cut on the existing back-and-forth patrol - a stopped car reads as
# "reacting" without needing real swerve/avoidance behavior.
const PANIC_BRAKE_TIME := 2.0
const PANIC_BRAKE_SPEED_MULTIPLIER := 0.15

# How long a patrol car will just sit blocked (waiting, like real traffic)
# before giving up and reversing as an escape valve for a genuine dead end.
const PATROL_STUCK_REVERSE_TIME := 1.5

@onready var model: Node3D = $Model
@onready var driver_seat: Marker3D = _get_or_create_marker("DriverSeat", Vector3(0, 0.9, 0))
@onready var exit_point: Marker3D = _get_or_create_marker("ExitPoint", Vector3(1.8, 0.1, 0))

var direction: float = 1.0
var health: float
var destroyed := false
var panic_brake_timer := 0.0
var patrol_stuck_timer := 0.0

# Player-driven state. Traffic cars stay in the "traffic_cars" group (not
# "vehicles") even though they're now stealable - the car-vs-pedestrian
# damage code elsewhere keys off that group name to know to read `speed`
# instead of a RigidBody3D's linear_velocity, so it can't be repurposed as
# a generic "is a car" flag. player.gd's try_enter_vehicle() searches all
# three vehicle-ish groups separately instead.
var driver: Node3D = null
var drive_speed := 0.0
var already_ejected := false
var engine_audio: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("traffic_cars")
	# sync_to_physics (on by default for AnimatableBody3D) re-syncs the node's
	# transform from the physics server every step, which was silently
	# discarding our rotation changes each frame — the car kept moving but
	# never actually turned to face its direction of travel.
	sync_to_physics = false
	direction = 1.0 if start_direction >= 0.0 else -1.0
	_update_facing()
	health = max_health
	_setup_engine_audio()
	_setup_headlights()

# Same real recorded engine loop as car.gd (see Audio/Ambience/
# ATTRIBUTION.md), kept duplicated rather than shared, matching this
# codebase's existing pattern of small duplicated audio blocks per script -
# every wandering traffic car gets one too, not just the player's, since a
# city full of silent-engine traffic was a big part of why the streets felt
# dead.
const ENGINE_LOOP_PATH := "res://Audio/Ambience/car_engine_loop.wav"

func _setup_engine_audio() -> void:
	engine_audio = AudioStreamPlayer3D.new()
	engine_audio.unit_size = 20.0
	engine_audio.volume_db = -14.0
	# .duplicate() rather than sharing the cached resource directly - dozens
	# of traffic cars all load()-ing and setting .loop_mode on the exact same
	# shared AudioStreamWAV at once was a suspected source of playback
	# flakiness found via playtesting.
	var stream: AudioStreamWAV = (load(ENGINE_LOOP_PATH) as AudioStreamWAV).duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	engine_audio.stream = stream
	add_child(engine_audio)
	engine_audio.play()

func _update_engine_audio() -> void:
	if destroyed:
		if engine_audio.playing:
			engine_audio.stop()
		return
	var current_speed: float = absf(drive_speed) if driver else speed
	var speed_ratio: float = clamp(current_speed / 14.0, 0.0, 1.0)
	engine_audio.pitch_scale = lerp(0.8, 2.0, speed_ratio)
	engine_audio.volume_db = lerp(-14.0, -6.0, speed_ratio)
	if not engine_audio.playing:
		engine_audio.play()

# See car.gd's identical headlight setup/comment. Unlike car.gd/
# parked_car.gd, gated on night alone rather than `driver` too - a wandering
# traffic car is always "being driven" by its own AI patrol regardless of
# whether a player has stolen it, unlike a player-owned car sitting empty
# and parked.
const HEADLIGHT_FORWARD_OFFSET := 2.0
const HEADLIGHT_SIDE_OFFSET := 0.6
const HEADLIGHT_HEIGHT := 0.5
const HEADLIGHT_RANGE := 18.0
const HEADLIGHT_SPOT_ANGLE := 35.0
const HEADLIGHT_ENERGY := 6.0
const HEADLIGHT_COLOR := Color(1.0, 0.97, 0.85)
const HEADLIGHT_ON_THRESHOLD := 0.4

var headlight_left: SpotLight3D
var headlight_right: SpotLight3D

func _setup_headlights() -> void:
	headlight_left = _make_headlight(-HEADLIGHT_SIDE_OFFSET)
	headlight_right = _make_headlight(HEADLIGHT_SIDE_OFFSET)

func _make_headlight(x_offset: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.position = Vector3(x_offset, HEADLIGHT_HEIGHT, HEADLIGHT_FORWARD_OFFSET)
	light.rotation_degrees = Vector3(0, 180, 0)
	light.spot_range = HEADLIGHT_RANGE
	light.spot_angle = HEADLIGHT_SPOT_ANGLE
	light.light_energy = HEADLIGHT_ENERGY
	light.light_color = HEADLIGHT_COLOR
	light.visible = false
	add_child(light)
	return light

func _update_headlights() -> void:
	var should_be_on: bool = not destroyed and DayNightCycle.sun_altitude() < HEADLIGHT_ON_THRESHOLD
	headlight_left.visible = should_be_on
	headlight_right.visible = should_be_on

func _get_or_create_marker(marker_name: String, local_pos: Vector3) -> Marker3D:
	if has_node(marker_name):
		return get_node(marker_name)
	var m := Marker3D.new()
	m.name = marker_name
	add_child(m)
	m.position = local_pos
	return m

func driver_enter(who: Node3D) -> void:
	if not already_ejected:
		already_ejected = true
		_eject_driver()
	driver = who

func driver_exit() -> void:
	driver = null
	drive_speed = 0.0

func panic_brake() -> void:
	if driver or destroyed:
		return
	panic_brake_timer = PANIC_BRAKE_TIME

# No ragdoll system exists, so this is the "thrown from the car" animation:
# pop a generic pedestrian out and launch it (see npc.gd's launch()), which
# lets gravity carry out an actual arc-and-land rather than a single-frame
# nudge that would otherwise get overwritten by the NPC's own wander
# movement on the very next physics frame.
func _eject_driver() -> void:
	var npc: CharacterBody3D = EJECTED_NPC_SCENES[randi() % EJECTED_NPC_SCENES.size()].instantiate()
	get_tree().current_scene.add_child(npc)
	npc.global_position = global_position + Vector3(0, 0.3, 0) - global_transform.basis.z * 1.2
	var away: Vector3 = -global_transform.basis.z
	if npc.has_method("launch"):
		npc.launch(away.normalized() * EJECT_KNOCKBACK + Vector3(0, EJECT_UP, 0))

func _process_driving(delta: float) -> void:
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
		drive_speed = move_toward(drive_speed, throttle * DRIVE_MAX_SPEED, DRIVE_ACCEL * delta)
	else:
		drive_speed = move_toward(drive_speed, 0.0, DRIVE_BRAKE_DECEL * delta)

	if absf(drive_speed) > 0.1:
		rotation.y += steer * DRIVE_TURN_SPEED * delta * sign(drive_speed)

	# Same fix as parked_car.gd - a raw `position +=` never tests for
	# collisions, so a stolen traffic car could drive straight through
	# walls/buildings/other cars.
	var impact_speed := absf(drive_speed)
	var motion := Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * drive_speed * delta
	var collision := move_and_collide(motion)
	if collision:
		drive_speed = 0.0
		# Same reasoning as parked_car.gd's driven branch - with
		# sync_to_physics off (required for move_and_collide, see _ready),
		# this AnimatableBody3D no longer pushes/notifies a CharacterBody3D
		# just by touching it, so apply the hit directly from this side.
		var hit: Object = collision.get_collider()
		if hit and hit.has_method("register_vehicle_hit"):
			hit.register_vehicle_hit(self, impact_speed)

func _update_facing() -> void:
	if axis == 0:
		rotation.y = 0.0 if direction > 0.0 else PI
	else:
		rotation.y = PI / 2.0 if direction > 0.0 else -PI / 2.0

func _physics_process(delta: float) -> void:
	_update_engine_audio()
	_update_headlights()
	if destroyed:
		return
	if driver:
		_process_driving(delta)
		return
	panic_brake_timer = max(0.0, panic_brake_timer - delta)
	var effective_speed: float = speed * (PANIC_BRAKE_SPEED_MULTIPLIER if panic_brake_timer > 0.0 else 1.0)
	var pos: float = position.z if axis == 0 else position.x
	var target_pos: float = pos + direction * effective_speed * delta
	var reached_bound := false
	if target_pos >= max_pos:
		target_pos = max_pos
		direction = -1.0
		reached_bound = true
	elif target_pos <= min_pos:
		target_pos = min_pos
		direction = 1.0
		reached_bound = true

	# The ambient AI patrol used to just set position.z/x directly - no
	# collision test at all, so a wandering traffic car could drive straight
	# through walls, buildings, wrecks, other cars, anything in its path.
	# _process_driving (the player-stolen branch, below) already fixed this
	# the same way move_and_collide fixed it for parked_car.gd - this is the
	# same pattern applied to the AI's own default patrol state, which is
	# what almost every traffic car in the city is doing almost all the time.
	var delta_pos: float = target_pos - pos
	var motion: Vector3 = Vector3(0, 0, delta_pos) if axis == 0 else Vector3(delta_pos, 0, 0)
	var collision := move_and_collide(motion)
	if collision:
		var hit: Object = collision.get_collider()
		if hit and hit.has_method("register_vehicle_hit"):
			hit.register_vehicle_hit(self, effective_speed)
		# A first version reversed direction the instant it touched anything -
		# two patrol cars meeting nose-to-nose would flip toward each other
		# again, meet again, flip again: a visible ping-pong bounce between
		# them. move_and_collide already stops the car right at the contact
		# point on its own (partial motion), so no extra reaction is needed
		# for the common case of another car just passing through - only
		# reverse (an escape valve for a genuine dead end) after sitting
		# blocked for a while, same as a real driver eventually giving up
		# and backing out instead of nudging forward over and over.
		patrol_stuck_timer += delta
		if patrol_stuck_timer >= PATROL_STUCK_REVERSE_TIME:
			direction *= -1.0
			patrol_stuck_timer = 0.0
			reached_bound = true
	else:
		patrol_stuck_timer = 0.0

	if reached_bound:
		_update_facing()

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
