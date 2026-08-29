extends CharacterBody3D

const WALK_SPEED := 1.8
const WANDER_RADIUS := 3.0
const ARRIVE_DIST := 0.6
const IDLE_TIME_MIN := 1.5
const IDLE_TIME_MAX := 4.0
const MAX_HEALTH := 150.0
const KILLED_HEAT := 7.0 # was 18 - two casual civilian kills (a normal way to farm cash now that they drop money) stacked past the first wanted tier almost immediately
const MONEY_DROP_CHANCE := 0.5

const MELEE_RANGE := 1.5
const MELEE_DAMAGE := 8.0
const MELEE_COOLDOWN := 1.0
const CHASE_SPEED := 2.2
const PATRON_AGGRO_CHECK_INTERVAL := 2.0
const PATRON_AGGRO_RANGE := 4.0
const PATRON_AGGRO_CHANCE := 0.35

const VEHICLE_HIT_MIN_SPEED := 2.0
const VEHICLE_HIT_DAMAGE_PER_SPEED := 4.0
const VEHICLE_HIT_MAX_DAMAGE := 80.0
const VEHICLE_HIT_KNOCKBACK := 6.0
const VEHICLE_HIT_COOLDOWN := 0.6

const BLOOD_POOL := preload("res://scenes/BloodPool.tscn")
const MONEY_PICKUP := preload("res://scenes/MoneyPickup.tscn")

const HIT_AUDIO_CLIPS := [
	"res://Audio/Arnold/NPC Getting attacked/ahhhhhhhh.wav",
	"res://Audio/Arnold/NPC Getting attacked/Im dying someone fucking help.wav",
	"res://Audio/Arnold/NPC Getting attacked/oh fml im getting attacked.wav",
	"res://Audio/Arnold/NPC Getting attacked/Oh No This Guys Crazy.wav",
	"res://Audio/Arnold/NPC Getting attacked/OMG Shot in D.wav",
]

# Background "city chatter" - only one line exists to draw from right now
# (this project's "Random Lines" folder), so this will sound repetitive
# until more get recorded and added here. The system itself (proximity +
# cooldown + random chance) is the actual point of this pass.
const CHATTER_AUDIO_CLIPS := [
	"res://Audio/Arnold/Random Lines/I havent felt this sad and pathetic since band camp.wav",
]
const CHATTER_CHECK_INTERVAL := 6.0
const CHATTER_RANGE := 5.0
const CHATTER_CHANCE := 0.12

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
@onready var hit_audio: AudioStreamPlayer3D = $HitAudio

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var home_position: Vector3
var target_position: Vector3
var idle_timer := 0.0
var health := MAX_HEALTH
var dead := false

# Only ever set true on the couple of NPC instances placed inside the bar
# (see World.tscn's BarInterior) - a regular street civilian never fights
# back, this is purely opt-in per-instance.
@export var is_bar_patron := false
var hostile := false
var attack_cooldown := 0.0
var patron_aggro_timer := 0.0
var player: Node3D = null
var vehicle_hit_cooldown := 0.0
var eject_stun_timer := 0.0
var chatter_audio: AudioStreamPlayer3D
var chatter_timer := 0.0
var interact_zone: Area3D
var prompt_text := "Press E to talk"

var anim_idle := ""
var anim_walk := ""
var anim_die := ""

func _find_anim(keyword: String) -> String:
	if not anim:
		return ""
	for a in anim.get_animation_list():
		if a.to_lower().contains(keyword):
			return a
	return ""

# Godot's retarget import injects a bogus track that re-keys the armature
# root's own transform; playing it corrupts the whole character's scale/pose.
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

# Cycle animations (walk, idle) import with loop_mode NONE, so once played to
# the end they freeze on the last frame instead of restarting — the NPC keeps
# moving via velocity while its legs stay frozen mid-step (looks like gliding)
# for the rest of any wander leg longer than the clip itself.
func _force_loop(anim_name: String) -> void:
	if anim and anim.has_animation(anim_name):
		anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

func _ready() -> void:
	add_to_group("civilians")
	home_position = global_position
	_pick_new_target()
	if anim:
		_strip_armature_root_tracks()
		anim_idle = _find_anim("idle")
		anim_walk = _find_anim("walk")
		anim_die = _find_anim("death")
		_force_loop(anim_idle)
		_force_loop(anim_walk)
	_play(anim_idle)
	chatter_audio = AudioStreamPlayer3D.new()
	chatter_audio.unit_size = 8.0
	add_child(chatter_audio)
	chatter_timer = randf_range(0.0, CHATTER_CHECK_INTERVAL)

	# Lets the player walk up to any civilian and press E to get a talk/sell
	# menu (see player.gd's open_npc_menu) instead of the old blind "E sells
	# drugs to whoever's nearest" behavior - that fallback still exists
	# (try_sell_drugs_to_nearby_npc) for the thin gap between this zone's
	# radius and SELL_RANGE, but this is now the primary path.
	interact_zone = Area3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.2
	var coll := CollisionShape3D.new()
	coll.shape = shape
	interact_zone.add_child(coll)
	add_child(interact_zone)
	interact_zone.body_entered.connect(_on_interact_zone_entered)
	interact_zone.body_exited.connect(_on_interact_zone_exited)

func _pick_new_target() -> void:
	var angle := randf() * TAU
	var dist := randf() * WANDER_RADIUS
	target_position = home_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func _physics_process(delta: float) -> void:
	if dead:
		return

	attack_cooldown = max(0.0, attack_cooldown - delta)
	vehicle_hit_cooldown = max(0.0, vehicle_hit_cooldown - delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Thrown-from-car state (see launch(), called by traffic_car.gd's driver
	# eject) - just gravity plus whatever impulse was given, no wander/AI
	# input, so the launch velocity actually carries through and arcs
	# instead of being overwritten by wander logic on the very next frame.
	if eject_stun_timer > 0.0:
		eject_stun_timer -= delta
		move_and_slide()
		_check_vehicle_collisions()
		return

	if hostile and player and is_instance_valid(player):
		_process_hostile(delta)
	else:
		_process_wander(delta)
		_check_ambient_chatter(delta)
		if is_bar_patron:
			_check_patron_aggro(delta)

	move_and_slide()
	_check_vehicle_collisions()

# Called by traffic_car.gd when this NPC gets thrown out of a stolen car.
func launch(impulse: Vector3, stun_duration: float = 1.1) -> void:
	velocity = impulse
	eject_stun_timer = stun_duration

# Same technique as player.gd's car-collision check - cars never look for
# pedestrians themselves, so this runs from the pedestrian's own
# move_and_slide() results instead.
func _check_vehicle_collisions() -> void:
	if vehicle_hit_cooldown > 0.0:
		return
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if not collider:
			continue
		var car_speed := 0.0
		if collider.is_in_group("vehicles"):
			car_speed = collider.linear_velocity.length()
		elif collider.is_in_group("traffic_cars"):
			car_speed = collider.speed
		else:
			continue
		if car_speed < VEHICLE_HIT_MIN_SPEED:
			continue
		vehicle_hit_cooldown = VEHICLE_HIT_COOLDOWN
		take_damage(clamp(car_speed * VEHICLE_HIT_DAMAGE_PER_SPEED, 0.0, VEHICLE_HIT_MAX_DAMAGE))
		if dead:
			return
		var away: Vector3 = global_position - collider.global_position
		away.y = 0.0
		velocity += (away.normalized() if away.length() > 0.01 else -collision.get_normal()) * VEHICLE_HIT_KNOCKBACK
		break

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
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 8.0 * delta)
		_play(anim_walk)

# A drunk player standing near a bar patron has a periodic chance to set
# this specific NPC hostile - checked on a timer rather than every frame so
# aggro doesn't become a near-certain instant reaction to walking up.
func _check_patron_aggro(delta: float) -> void:
	patron_aggro_timer -= delta
	if patron_aggro_timer > 0.0:
		return
	patron_aggro_timer = PATRON_AGGRO_CHECK_INTERVAL
	var p := get_tree().get_first_node_in_group("player")
	if not p or not is_instance_valid(p):
		return
	if float(p.get("drunk_timer")) <= 0.0:
		return
	if global_position.distance_to(p.global_position) > PATRON_AGGRO_RANGE:
		return
	if randf() < PATRON_AGGRO_CHANCE:
		player = p
		hostile = true

func _on_interact_zone_entered(body: Node3D) -> void:
	if dead:
		return
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_interact_zone_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func interact(player: Node3D) -> void:
	if player.has_method("open_npc_menu"):
		player.open_npc_menu(self)

# Reuses the ambient-chatter clip pool (see CHATTER_AUDIO_CLIPS) - only one
# line exists to draw from right now, same limitation as the ambient bark.
func say_hello() -> void:
	if chatter_audio.playing:
		return
	chatter_audio.stream = load(CHATTER_AUDIO_CLIPS[randi() % CHATTER_AUDIO_CLIPS.size()])
	chatter_audio.play()

# Occasional background bark when the player's standing near a peaceful
# civilian - checked on a timer (not every frame) so it can't spam.
func _check_ambient_chatter(delta: float) -> void:
	chatter_timer -= delta
	if chatter_timer > 0.0:
		return
	chatter_timer = CHATTER_CHECK_INTERVAL
	if chatter_audio.playing:
		return
	var p := get_tree().get_first_node_in_group("player")
	if not p or not is_instance_valid(p):
		return
	if global_position.distance_to(p.global_position) > CHATTER_RANGE:
		return
	if randf() < CHATTER_CHANCE:
		chatter_audio.stream = load(CHATTER_AUDIO_CLIPS[randi() % CHATTER_AUDIO_CLIPS.size()])
		chatter_audio.play()

func _process_hostile(delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0
	var dist := to_player.length()

	if dist > MELEE_RANGE:
		var dir := to_player.normalized()
		velocity.x = dir.x * CHASE_SPEED
		velocity.z = dir.z * CHASE_SPEED
		_play(anim_walk)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if attack_cooldown <= 0.0:
			attack_cooldown = MELEE_COOLDOWN
			if player.has_method("take_damage"):
				player.take_damage(MELEE_DAMAGE, global_position)

	if to_player.length() > 0.01:
		var target_yaw := atan2(to_player.x, to_player.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 8.0 * delta)

func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	_play_hit_audio()
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
	interact_zone.monitoring = false
	var p := get_tree().get_first_node_in_group("player")
	if p and p.get("nearby_interactable") == self:
		p.clear_nearby_interactable(self)
	_play(anim_die)
	_spawn_blood_pool()
	_maybe_drop_money()
	WantedSystem.add_heat(KILLED_HEAT, global_position)

func _maybe_drop_money() -> void:
	if randf() < MONEY_DROP_CHANCE:
		var money: Node3D = MONEY_PICKUP.instantiate()
		get_tree().current_scene.add_child(money)
		money.global_position = Vector3(global_position.x, 0.3, global_position.z)

func _spawn_blood_pool() -> void:
	var pool: Node3D = BLOOD_POOL.instantiate()
	get_tree().current_scene.add_child(pool)
	pool.global_position = Vector3(global_position.x, 0.02, global_position.z)
	pool.rotation.y = randf() * TAU
	pool.scale = Vector3.ONE * randf_range(0.8, 1.3)
