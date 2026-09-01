extends CharacterBody3D

const WALK_SPEED := 1.8
const WANDER_RADIUS := 14.0 # was 3.0 - too tight a bubble around a fixed post made cops nearly impossible to stumble across in a city this size
const ARRIVE_DIST := 0.6
const IDLE_TIME_MIN := 1.5
const IDLE_TIME_MAX := 4.0
const TURN_SPEED := 8.0

const ENGAGE_RANGE := 13.0 # was 16 - cops opened fire from further away than a player could reasonably react to
const STOP_DISTANCE := 7.0
const RAY_LENGTH := 60.0

# Every cop used to be identical regardless of how much heat called them in -
# a 1-star beat cop and a 3-star response were the same guy. Exported so
# WantedSystem can hand tougher, faster, harder-hitting numbers to
# reinforcements spawned at high tiers (see SWAT_* constants there) while
# the 4 hand-placed patrol cops in World.tscn just keep these defaults
# (the original hardcoded values).
@export var max_health: float = 120.0
@export var chase_speed: float = 3.4
@export var fire_rate: float = 1.5 # was 1.3
@export var gun_damage: float = 9.0 # was 12 - stacked up brutally once 2-3 cops were shooting at once
# Set true only by WantedSystem's top-tier reinforcement spawns - swaps the
# uniform tint to tactical black and nothing else (no separate model exists).
@export var is_swat: bool = false
const MONEY_DROP_CHANCE := 0.4
const AMMO_DROP_CHANCE := 0.4

const DETECTION_RANGE := 9.0 # was 14 - wandering cops were piling onto an already-active incident too readily
const LEASH_RADIUS := 22.0 # was 30 - cops should back off sooner once you've actually put distance between you
const GIVE_UP_TIME := 4.0 # was 6
const HIT_HEAT := 5.0
const KILLED_HEAT := 35.0
const INVESTIGATE_GIVE_UP_TIME := 10.0

const VEHICLE_HIT_MIN_SPEED := 2.0
const VEHICLE_HIT_DAMAGE_PER_SPEED := 4.0
const VEHICLE_HIT_MAX_DAMAGE := 80.0
# See launch() below - routed through the eject-stun pattern (matching
# npc.gd) instead of a flat velocity add, since _process_hostile/
# _process_investigate/_process_wander would otherwise overwrite
# velocity.x/z the very next physics tick and the knockback would never
# actually read as getting hit.
const VEHICLE_HIT_KNOCKBACK_BASE := 5.0
const VEHICLE_HIT_KNOCKBACK_PER_SPEED := 0.55
const VEHICLE_HIT_LAUNCH_UP := 4.5
const VEHICLE_HIT_STUN_TIME := 1.4
const VEHICLE_HIT_COOLDOWN := 0.6

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

# Played once, the moment a cop actually spots/engages the player (see
# _engage below) - AJ's own recorded lines, not the synthesized gunshot/siren.
const SEES_PLAYER_AUDIO_CLIPS := [
	"res://Audio/Arnold/Police Sees Player/This is the police Show me your hands.wav",
	"res://Audio/Arnold/Police Sees Player/Hey you stop right there.wav",
	"res://Audio/Arnold/Police Sees Player/Stop resisting Comply now.wav",
]

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
@onready var hit_audio: AudioStreamPlayer3D = $HitAudio
@onready var gunshot_audio: AudioStreamPlayer3D = $GunshotAudio
@onready var siren_audio: AudioStreamPlayer3D = $SirenAudio
@onready var voice_audio: AudioStreamPlayer3D = $VoiceAudio

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var home_position: Vector3
var target_position: Vector3
var idle_timer := 0.0
var health: float
var dead := false
var hostile := false
var alerted := false
var alert_target := Vector3.ZERO
var investigate_timer := 0.0
var fire_cooldown := 0.0
var lost_sight_timer := 0.0
var vehicle_hit_cooldown := 0.0
var eject_stun_timer := 0.0
# Set right before take_damage() by whatever actually dealt the hit - a cop
# run over by ambient AI traffic (or shot by another cop's stray fire, if
# that ever happens) shouldn't go hostile on the player or add heat.
var killed_by_player := false
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
	health = max_health
	home_position = global_position
	_pick_new_target()
	# Deferred rather than looked up directly here: the 4 hand-placed police
	# in World.tscn are declared BEFORE the Player node, so their _ready()
	# runs first - looking the player up right now would silently grab
	# nothing (Player hasn't added itself to the "player" group yet),
	# leaving `player` null for the rest of the game. Reinforcement cops
	# (spawned later at runtime by WantedSystem) never hit this, which is
	# why the bug wasn't obvious - only the original 4 were ever affected.
	call_deferred("_resolve_player")
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
# tinted to read as "police" at a glance. The shared model (Male_LongSleeve)
# is a single mesh with named surfaces (Skin/Eyes/Hair/TieTexture/Shirt/
# Pants/Details) rather than separate submeshes - a blanket
# material_override was recoloring the WHOLE mesh navy, wiping out the
# face/skin/hair along with the clothes (this is why cops looked like a flat
# solid-color blob instead of a person in a uniform). Overriding only the
# named clothing surfaces keeps skin/eyes/hair looking like an actual face.
func _tint_uniform() -> void:
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = Color(0.03, 0.03, 0.04) if is_swat else Color(0.08, 0.11, 0.22)
	var pants := StandardMaterial3D.new()
	pants.albedo_color = Color(0.02, 0.02, 0.025) if is_swat else Color(0.05, 0.05, 0.07)
	_tint_surfaces(model, {"Shirt": shirt, "Pants": pants, "Details": pants})

func _tint_surfaces(node: Node, by_surface_name: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				var surface_name: String = mesh.surface_get_name(i)
				if by_surface_name.has(surface_name):
					mi.set_surface_override_material(i, by_surface_name[surface_name])
	for child in node.get_children():
		_tint_surfaces(child, by_surface_name)

# Every path that flips a cop from not-hostile to hostile (proactive spot,
# radio-alert-with-LOS, spotting the player while investigating, or getting
# shot) routes through here so the "sees you" voice line only ever plays
# once per engagement, not every frame hostile stays true.
func _engage() -> void:
	if hostile:
		return
	hostile = true
	alerted = false
	voice_audio.stream = load(SEES_PLAYER_AUDIO_CLIPS[randi() % SEES_PLAYER_AUDIO_CLIPS.size()])
	voice_audio.play()

func _resolve_player() -> void:
	player = get_tree().get_first_node_in_group("player")

func _pick_new_target() -> void:
	var angle := randf() * TAU
	var dist := randf() * WANDER_RADIUS
	target_position = home_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

# Mirrors npc.gd's launch() - a car-hit impulse strong enough to send a cop
# flying needs to survive at least a few frames without the movement AI
# immediately overwriting velocity.x/z with its own.
func launch(impulse: Vector3, stun_duration: float = 1.1) -> void:
	velocity = impulse
	eject_stun_timer = stun_duration

func _physics_process(delta: float) -> void:
	if dead:
		return

	fire_cooldown = max(0.0, fire_cooldown - delta)
	vehicle_hit_cooldown = max(0.0, vehicle_hit_cooldown - delta)

	if eject_stun_timer > 0.0:
		eject_stun_timer -= delta
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		_check_vehicle_collisions()
		return

	if hostile and not siren_audio.playing:
		siren_audio.stream = _make_siren_sound()
		siren_audio.play()
	elif not hostile and siren_audio.playing:
		siren_audio.stop()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if hostile and player and is_instance_valid(player):
		_process_hostile(delta)
	elif alerted and player and is_instance_valid(player):
		_process_investigate(delta)
	else:
		_process_wander(delta)
		_check_proactive_detection()

	move_and_slide()
	_check_vehicle_collisions()

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
		killed_by_player = collider.get("driver") == player
		take_damage(clamp(car_speed * VEHICLE_HIT_DAMAGE_PER_SPEED, 0.0, VEHICLE_HIT_MAX_DAMAGE))
		if dead:
			return
		var away: Vector3 = global_position - collider.global_position
		away.y = 0.0
		var horizontal_dir: Vector3 = away.normalized() if away.length() > 0.01 else -collision.get_normal()
		var knockback_speed: float = VEHICLE_HIT_KNOCKBACK_BASE + car_speed * VEHICLE_HIT_KNOCKBACK_PER_SPEED
		launch(horizontal_dir * knockback_speed + Vector3(0, VEHICLE_HIT_LAUNCH_UP, 0), VEHICLE_HIT_STUN_TIME)
		break

# A wandering cop only joins an already-in-progress incident it happens to
# physically spot nearby (WantedSystem.heat > 0) - it doesn't go hostile
# over a clean, quiet player just walking past. Direct alerts from a new
# crime (see alert()) are what actually starts an incident.
#
# An unarmed player (see player.gd's Weapon.UNARMED) never trips this at
# all, even with residual heat still ticking down from something unrelated
# a minute ago - AJ asked for a way to just not have cops on him constantly;
# holstering everything is that "I'm not a threat" signal.
func _check_proactive_detection() -> void:
	if not player or not is_instance_valid(player) or WantedSystem.heat <= 0.0:
		return
	if _player_is_unarmed():
		return
	var to_player := player.global_position - global_position
	if to_player.length() <= DETECTION_RANGE and _has_line_of_sight(player.global_position):
		_engage()

func _player_is_unarmed() -> bool:
	return player and is_instance_valid(player) and player.has_method("is_unarmed") and player.is_unarmed()

# Called by WantedSystem when a crime happens within this cop's alert
# radius. AJ asked for cops to have to actually SEE the player before
# engaging rather than insta-aggroing the moment a crime happens nearby -
# so this only grants instant hostility if the cop already has a clean shot
# at the player right now; otherwise it just sends the cop to go check out
# where the report came from ("alerted"/investigating), same as a real cop
# responding to a radio call but still needing eyes-on before opening fire.
func alert(source_position: Vector3) -> void:
	if dead or hostile:
		return
	if player and is_instance_valid(player) and not _player_is_unarmed() \
			and global_position.distance_to(player.global_position) <= ENGAGE_RANGE \
			and _has_line_of_sight(player.global_position):
		_engage()
	else:
		alerted = true
		alert_target = source_position
		investigate_timer = INVESTIGATE_GIVE_UP_TIME

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

# Heading toward wherever a reported crime happened, not yet actually
# engaging - drops into full _process_hostile the instant it gets a real
# line of sight on the player, and gives up (back to normal wandering) if it
# either reaches the reported spot or spends too long looking without
# spotting anyone.
func _process_investigate(delta: float) -> void:
	investigate_timer -= delta

	var to_player := player.global_position - global_position
	to_player.y = 0
	if not _player_is_unarmed() and to_player.length() <= DETECTION_RANGE and _has_line_of_sight(player.global_position):
		_engage()
		return

	if investigate_timer <= 0.0:
		alerted = false
		_pick_new_target()
		return

	var to_target := alert_target - global_position
	to_target.y = 0
	if to_target.length() < ARRIVE_DIST:
		# Arrived at the reported spot without spotting anyone - stand and
		# keep looking (still checking LOS above every frame) until
		# investigate_timer runs out, rather than giving up the instant it
		# arrives. Found via playtesting: alert_target can equal the cop's
		# own current position (e.g. a crime reported right on top of it),
		# which used to make it give up the very same frame it got alerted.
		velocity.x = 0.0
		velocity.z = 0.0
		return

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
		velocity.x = dir.x * chase_speed
		velocity.z = dir.z * chase_speed
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
	NPC.scare_nearby(get_tree(), global_position)
	fire_cooldown = fire_rate
	_play(anim_attack)

	gunshot_audio.stream = _make_gunshot_sound()
	gunshot_audio.play()

	var origin: Vector3 = global_position + Vector3(0, 1.4, 0)
	var target: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var to_target: Vector3 = target - origin
	var dist_to_target: float = to_target.length()
	var forward: Vector3 = to_target.normalized()

	# Cops used to be perfect hitscan - every shot in range/LOS landed for
	# GUN_DAMAGE, no way to feel "lucky" getting shot at from across the
	# street. This adds a cone of inaccuracy that widens with range (tight
	# up close, sprays wide at ENGAGE_RANGE) so distant shots often miss.
	var spread_amount: float = clamp(dist_to_target / ENGAGE_RANGE, 0.0, 1.0) * 1.1
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(forward)
	var spread_offset: Vector3 = (right * randf_range(-1.0, 1.0) + up * randf_range(-1.0, 1.0)) * spread_amount
	forward = (to_target + spread_offset).normalized()

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
		player.take_damage(gun_damage, result.position)

func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	# Consumed immediately so an unrelated later hit (e.g. car-explosion
	# blast damage, which never sets this) can't inherit a stale true from
	# whatever last set it.
	var by_player := killed_by_player
	killed_by_player = false
	_play_hit_audio()
	if by_player:
		if not hostile and player and player.has_method("play_cops_incoming_line"):
			player.play_cops_incoming_line()
		_engage()
		WantedSystem.add_heat(HIT_HEAT, global_position)
	health -= amount
	if health <= 0.0:
		die(by_player)

func _play_hit_audio() -> void:
	if hit_audio.playing:
		return
	hit_audio.stream = load(HIT_AUDIO_CLIPS[randi() % HIT_AUDIO_CLIPS.size()])
	hit_audio.play()

func die(by_player: bool = false) -> void:
	dead = true
	collision.disabled = true
	siren_audio.stop()
	_play(anim_die)
	_spawn_blood_pool()
	_maybe_drop_loot()
	if by_player:
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

# Same procedural-synthesis approach as the gunshot above rather than a
# real audio asset. A phase accumulator (not naive sin(freq*t) with a
# changing freq, which clicks/pops) gives a continuous "wee-oo" wail that
# loops seamlessly while hostile.
func _make_siren_sound() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 2.4
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	for i in range(sample_count):
		var t := float(i) / mix_rate
		var lfo: float = (sin(t / duration * TAU) + 1.0) / 2.0
		var freq: float = lerp(650.0, 1000.0, lfo)
		phase += freq / mix_rate * TAU
		var sample: float = sin(phase) * 0.35
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = sample_count
	return stream
