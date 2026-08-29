extends CharacterBody3D

const WALK_SPEED := 1.8
const CHASE_SPEED := 3.4
const WANDER_RADIUS := 3.0
const ARRIVE_DIST := 0.6
const IDLE_TIME_MIN := 1.5
const IDLE_TIME_MAX := 4.0
const MAX_HEALTH := 120.0
const TURN_SPEED := 8.0

const ENGAGE_RANGE := 16.0
const STOP_DISTANCE := 7.0
const FIRE_COOLDOWN := 1.3
const GUN_DAMAGE := 12.0
const RAY_LENGTH := 60.0
const MONEY_DROP_CHANCE := 0.4
const AMMO_DROP_CHANCE := 0.4

const DETECTION_RANGE := 14.0
const LEASH_RADIUS := 30.0
const GIVE_UP_TIME := 6.0
const HIT_HEAT := 5.0
const KILLED_HEAT := 35.0

const BLOOD_POOL := preload("res://scenes/BloodPool.tscn")
const IMPACT_EFFECT := preload("res://scenes/ImpactEffect.tscn")
const MONEY_PICKUP := preload("res://scenes/MoneyPickup.tscn")
const AMMO_PICKUP := preload("res://scenes/AmmoPickup.tscn")

# No dedicated police model/rig exists (only the generic civilian
# characters), and giving them a properly bone-attached, correctly-oriented
# held pistol would mean redoing the entire multi-hour player gun-attachment
# investigation for a second, differently-named skeleton - not worth it for
# a secondary enemy. They "shoot" via sound + raycast + muzzle flash + a
# punch-like arm animation instead of an actual modeled weapon.
const HIT_AUDIO_CLIPS := [
	"res://Audio/Arnold/NPC Getting attacked/ahhhhhhhh.wav",
	"res://Audio/Arnold/NPC Getting attacked/Im dying someone fucking help.wav",
	"res://Audio/Arnold/NPC Getting attacked/oh fml im getting attacked.wav",
	"res://Audio/Arnold/NPC Getting attacked/Oh No This Guys Crazy.wav",
	"res://Audio/Arnold/NPC Getting attacked/OMG Shot in D.wav",
]

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
@onready var hit_audio: AudioStreamPlayer3D = $HitAudio
@onready var gunshot_audio: AudioStreamPlayer3D = $GunshotAudio

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var home_position: Vector3
var target_position: Vector3
var idle_timer := 0.0
var health := MAX_HEALTH
var dead := false
var hostile := false
var fire_cooldown := 0.0
var lost_sight_timer := 0.0
var player: Node3D = null

var anim_idle := ""
var anim_walk := ""
var anim_die := ""
var anim_attack := ""

func _find_anim(keyword: String) -> String:
	if not anim:
		return ""
	for a in anim.get_animation_list():
		if a.to_lower().contains(keyword):
			return a
	return ""

# Same fix as npc.gd/player.gd - the retarget import injects a bogus track
# that re-keys the armature root's own transform; playing it corrupts the
# whole character's scale/pose.
func _strip_armature_root_tracks() -> void:
	if not anim:
		return
	for anim_name in anim.get_animation_list():
		var a: Animation = anim.get_animation(anim_name)
		for i in range(a.get_track_count() - 1, -1, -1):
			if str(a.track_get_path(i)) == "HumanArmature":
				a.remove_track(i)

func _play(anim_name: String) -> void:
	if anim and anim_name != "" and anim.current_animation != anim_name:
		anim.play(anim_name)

func _force_loop(anim_name: String) -> void:
	if anim and anim.has_animation(anim_name):
		anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

func _ready() -> void:
	add_to_group("police")
	home_position = global_position
	_pick_new_target()
	player = get_tree().get_first_node_in_group("player")
	if anim:
		_strip_armature_root_tracks()
		anim_idle = _find_anim("idle")
		anim_walk = _find_anim("walk")
		anim_die = _find_anim("death")
		anim_attack = _find_anim("punch")
		_force_loop(anim_idle)
		_force_loop(anim_walk)
	_play(anim_idle)
	_tint_uniform()

# No dedicated police model exists, so the generic civilian character is
# tinted dark navy (like a uniform) to read as "police" at a glance -
# same recursive material_override trick used for charred car wrecks.
func _tint_uniform() -> void:
	var uniform := StandardMaterial3D.new()
	uniform.albedo_color = Color(0.08, 0.11, 0.22)
	_tint_recursive(model, uniform)

func _tint_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_recursive(child, mat)

func _pick_new_target() -> void:
	var angle := randf() * TAU
	var dist := randf() * WANDER_RADIUS
	target_position = home_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func _physics_process(delta: float) -> void:
	if dead:
		return

	fire_cooldown = max(0.0, fire_cooldown - delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if hostile and player and is_instance_valid(player):
		_process_hostile(delta)
	else:
		_process_wander(delta)
		_check_proactive_detection()

	move_and_slide()

# A wandering cop only joins an already-in-progress incident it happens to
# physically spot nearby (WantedSystem.heat > 0) - it doesn't go hostile
# over a clean, quiet player just walking past. Direct alerts from a new
# crime (see alert()) are what actually starts an incident.
func _check_proactive_detection() -> void:
	if not player or not is_instance_valid(player) or WantedSystem.heat <= 0.0:
		return
	var to_player := player.global_position - global_position
	if to_player.length() <= DETECTION_RANGE and _has_line_of_sight(player.global_position):
		hostile = true

# Called by WantedSystem when a crime happens within this cop's alert
# radius - skips the detection roll entirely, matching a real cop reacting
# to a radio call rather than needing to personally witness anything.
func alert(_source_position: Vector3) -> void:
	if not dead:
		hostile = true

func _has_line_of_sight(target_pos: Vector3) -> bool:
	var origin: Vector3 = global_position + Vector3(0, 1.4, 0)
	var target: Vector3 = target_pos + Vector3(0, 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [self.get_rid()]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.get("collider") == player

func _process_wander(delta: float) -> void:
	var to_target := target_position - global_position
	to_target.y = 0

	if idle_timer > 0.0:
		idle_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
	elif to_target.length() < ARRIVE_DIST:
		idle_timer = randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)
		_play(anim_idle)
		_pick_new_target()
	else:
		var dir := to_target.normalized()
		velocity.x = dir.x * WALK_SPEED
		velocity.z = dir.z * WALK_SPEED
		var target_yaw := atan2(dir.x, dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, TURN_SPEED * delta)
		_play(anim_walk)

func _process_hostile(delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0
	var dist := to_player.length()

	# Give up the chase once the player's actually gotten away with it -
	# not the instant they duck behind cover, only once they've stayed lost
	# AND put real distance between the cop and its post. Without the leash
	# check a cop hiding just around a corner from home would give up almost
	# immediately; without the sight check it'd never give up at all.
	if dist <= ENGAGE_RANGE and _has_line_of_sight(player.global_position):
		lost_sight_timer = 0.0
		WantedSystem.report_sighting()
	elif global_position.distance_to(home_position) > LEASH_RADIUS:
		lost_sight_timer += delta
		if lost_sight_timer >= GIVE_UP_TIME:
			hostile = false
			lost_sight_timer = 0.0
			return

	if dist > STOP_DISTANCE:
		var dir := to_player.normalized()
		velocity.x = dir.x * CHASE_SPEED
		velocity.z = dir.z * CHASE_SPEED
		_play(anim_walk)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if fire_cooldown <= 0.0 and dist <= ENGAGE_RANGE:
			_shoot_at_player()

	if to_player.length() > 0.01:
		var target_yaw := atan2(to_player.x, to_player.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, TURN_SPEED * delta)

func _shoot_at_player() -> void:
	fire_cooldown = FIRE_COOLDOWN
	_play(anim_attack)

	gunshot_audio.stream = _make_gunshot_sound()
	gunshot_audio.play()

	var origin: Vector3 = global_position + Vector3(0, 1.4, 0)
	var target: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var forward: Vector3 = (target - origin).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * RAY_LENGTH)
	query.exclude = [self.get_rid()]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)

	var fx: Node3D = IMPACT_EFFECT.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.global_position = origin + forward * 0.6

	# A raycast naturally handles line-of-sight - if a wall or car is in the
	# way, result.collider is that obstruction, not the player, so cover
	# actually blocks their shots rather than damage going through it.
	if result and result.collider == player and player.has_method("take_damage"):
		player.take_damage(GUN_DAMAGE, result.position)

func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	_play_hit_audio()
	if not hostile and player and player.has_method("play_cops_incoming_line"):
		player.play_cops_incoming_line()
	hostile = true
	WantedSystem.add_heat(HIT_HEAT, global_position)
	health -= amount
	if health <= 0.0:
		die()

func _play_hit_audio() -> void:
	if hit_audio.playing:
		return
	hit_audio.stream = load(HIT_AUDIO_CLIPS[randi() % HIT_AUDIO_CLIPS.size()])
	hit_audio.play()

func die() -> void:
	dead = true
	collision.disabled = true
	_play(anim_die)
	_spawn_blood_pool()
	_maybe_drop_loot()
	WantedSystem.add_heat(KILLED_HEAT, global_position)

func _spawn_blood_pool() -> void:
	var pool: Node3D = BLOOD_POOL.instantiate()
	get_tree().current_scene.add_child(pool)
	pool.global_position = Vector3(global_position.x, 0.02, global_position.z)
	pool.rotation.y = randf() * TAU
	pool.scale = Vector3.ONE * randf_range(0.8, 1.3)

func _maybe_drop_loot() -> void:
	if randf() < MONEY_DROP_CHANCE:
		var money: Node3D = MONEY_PICKUP.instantiate()
		get_tree().current_scene.add_child(money)
		money.global_position = Vector3(global_position.x, 0.3, global_position.z)
	if randf() < AMMO_DROP_CHANCE:
		var ammo: Node3D = AMMO_PICKUP.instantiate()
		get_tree().current_scene.add_child(ammo)
		ammo.global_position = Vector3(global_position.x + 0.4, 0.3, global_position.z + 0.4)

# _make_gunshot_sound duplicated from player.gd rather than shared, matching
# this codebase's existing pattern of small duplicated blocks across scripts
# (see car.gd/traffic_car.gd/parked_car.gd's identical blast-damage helper).
func _make_gunshot_sound() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.16
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var filtered := 0.0
	for i in range(sample_count):
		var t := float(i) / sample_count
		var envelope: float = pow(1.0 - t, 4.0)
		var noise := rng.randf_range(-1.0, 1.0)
		filtered = filtered * 0.3 + noise * 0.7
		var sample: float = clamp(filtered * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream
