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
const HIT_STAGGER_TIME := 0.25

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
# Detection/engage used to be flat no matter how hot the player already was -
# a cop at 1 star noticed you from exactly as far as one at max heat. Every
# cop (patrol or reinforcement) now widens its own bubble with the current
# tier, so a hot player gets spotted and shot at from further away instead
# of the response staying static while only the reinforcement count changes.
const TIER_RANGE_BONUS := 4.0
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

# Same cross-file Mixamo retarget trick as npc.gd/player.gd - every Mixamo
# download shares the same skeleton/bone names, so these clips (borrowed from
# James's and Pete's own downloads) play back correctly on the cop's generic
# Male_LongSleeve rig too even though neither was exported for it.
const EXTRA_ANIM_SOURCE_NAME := "mixamo_com"
const HIT_REACT_SOURCE := "res://assets/characters-pete/Pete_FallingIdle.fbx"
const LAND_SOURCE := "res://assets/characters-pete/Pete_HardLanding.fbx"
const RUN_SOURCE := "res://assets/characters-pete/Pete_Run.fbx"
# James's own aim-and-fire clip - a real held-pistol pose instead of the flat
# "punch" reuse this used to fall back to (see the old comment above about no
# dedicated police model/weapon - still true, but the pose reads far more like
# "cop shooting a gun" than a haymaker).
const SHOOT_SOURCE := "res://assets/characters-james/James_Shoot.fbx"

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

const SIREN_VOLUME_DB := -8.0

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
var hit_stagger_timer := 0.0
# Set right before take_damage() by whatever actually dealt the hit - a cop
# run over by ambient AI traffic (or shot by another cop's stray fire, if
# that ever happens) shouldn't go hostile on the player or add heat.
var killed_by_player := false
var player: Node3D = null
var wanted_tier := 0

var anim_idle := ""
var anim_walk := ""
var anim_die := ""
var anim_attack := ""
var anim_run := ""
var anim_hit_react := ""
var anim_land := ""

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

# Unlike _play() above, always restarts from frame 0 even if this is already
# the current animation. Firing was previously routed through _play(), which
# played the attack pose exactly once - after that first shot,
# current_animation stayed on anim_attack forever (fire_cooldown just
# gated the shot itself), so every following shot in the same firefight was
# silently mute: the cop stood there in the frozen end-pose while gunshots
# kept firing. This forces the pose to actually replay every time.
func _play_once(anim_name: String) -> void:
	if anim and anim_name != "":
		anim.stop()
		anim.play(anim_name)

func _force_loop(anim_name: String) -> void:
	if anim and anim.has_animation(anim_name):
		anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

# See npc.gd's identical functions/comments - not every Mixamo download in
# this project's characters uses identical bone names even though they're
# all the same underlying rig (confirmed via a before/after bone-pose
# comparison, not just import warnings, which turned out not to reliably
# fire either way): Pete's pack carries "mixamorig1_Hips", James's Shoot clip
# carries "mixamorig9_Hips", the cop/Josh rig itself uses plain
# "mixamorig_Hips". That numeric infix is a per-download disambiguation
# artifact, not a real skeleton difference - stripping it, matching on the
# normalized name, and rewriting each track to the target's own actual bone
# name retargets correctly instead of either silently no-op'ing (the
# original bug) or refusing to merge anything not byte-identical (an earlier,
# overly conservative version of this fix that rejected Police/Josh's own
# genuinely working merges along with the truly incompatible ones).
func _normalize_bone_name(bone_name: String) -> String:
	if not bone_name.begins_with("mixamorig"):
		return bone_name
	var rest := bone_name.substr(9) # len("mixamorig")
	var i := 0
	while i < rest.length() and rest[i].is_valid_int():
		i += 1
	if i < rest.length() and rest[i] == "_":
		return "mixamorig_" + rest.substr(i + 1)
	return bone_name

func _resolve_track_target(track_path: NodePath) -> Skeleton3D:
	if not anim.has_node(anim.root_node):
		return null
	var node: Node = anim.get_node(anim.root_node)
	for i in range(track_path.get_name_count()):
		if not node:
			return null
		node = node.get_node_or_null(String(track_path.get_name(i)))
	return node as Skeleton3D

const RETARGET_MIN_MATCH_RATIO := 0.8

func _retarget_clip(clip: Animation, target_skeleton: Skeleton3D) -> Animation:
	var bone_map := {}
	for i in range(target_skeleton.get_bone_count()):
		var bone_name := target_skeleton.get_bone_name(i)
		bone_map[_normalize_bone_name(bone_name)] = bone_name

	var retargeted: Animation = clip.duplicate()
	var matched := 0
	var total := 0
	for i in range(retargeted.get_track_count()):
		var path: NodePath = retargeted.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		total += 1
		var normalized := _normalize_bone_name(String(path.get_subname(0)))
		if not bone_map.has(normalized):
			continue
		matched += 1
		var node_names: PackedStringArray = []
		for n in range(path.get_name_count()):
			node_names.append(String(path.get_name(n)))
		retargeted.track_set_path(i, NodePath("/".join(node_names) + ":" + bone_map[normalized]))

	if total == 0 or float(matched) / float(total) < RETARGET_MIN_MATCH_RATIO:
		return null
	return retargeted

func _merge_external_clip(lib: AnimationLibrary, target_name: String, source_path: String) -> void:
	if lib.has_animation(target_name):
		return
	var packed: PackedScene = load(source_path)
	if not packed:
		return
	var source := packed.instantiate()
	var source_ap: AnimationPlayer = source.find_child("AnimationPlayer", true, false)
	if source_ap and source_ap.has_animation(EXTRA_ANIM_SOURCE_NAME):
		var clip: Animation = source_ap.get_animation(EXTRA_ANIM_SOURCE_NAME)
		if clip.get_track_count() > 0:
			var target_skeleton := _resolve_track_target(clip.track_get_path(0))
			if target_skeleton:
				var retargeted := _retarget_clip(clip, target_skeleton)
				if retargeted:
					lib.add_animation(target_name, retargeted)
	source.free()

func _load_extra_animations() -> void:
	var lib: AnimationLibrary
	if anim.has_animation_library(""):
		lib = anim.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		anim.add_animation_library("", lib)

	_merge_external_clip(lib, "HitReact", HIT_REACT_SOURCE)
	anim_hit_react = "HitReact" if anim.has_animation("HitReact") else anim_idle
	_force_loop(anim_hit_react)

	_merge_external_clip(lib, "Land", LAND_SOURCE)
	anim_land = "Land" if anim.has_animation("Land") else anim_hit_react

	_merge_external_clip(lib, "Run", RUN_SOURCE)
	anim_run = "Run" if anim.has_animation("Run") else anim_walk
	_force_loop(anim_run)

	_merge_external_clip(lib, "Shoot", SHOOT_SOURCE)
	if anim.has_animation("Shoot"):
		anim_attack = "Shoot"

func _ready() -> void:
	add_to_group("police")
	health = max_health
	wanted_tier = WantedSystem.get_tier()
	WantedSystem.tier_changed.connect(_on_wanted_tier_changed)
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
		_load_extra_animations()
	_play(anim_idle)
	# See npc.gd's identical fix - multiple cops all spawning on the same
	# frame used to play their idle sway in perfect lockstep.
	if anim and anim.has_animation(anim_idle):
		var idle_clip: Animation = anim.get_animation(anim_idle)
		if idle_clip.length > 0.0:
			anim.seek(randf() * idle_clip.length, true)
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
		# Only imported ArrayMesh surfaces carry names (Skin/Shirt/Pants/etc) -
		# primitive meshes like the Badge/Belt BoxMesh props don't implement
		# surface_get_name at all and would crash here once they're nested
		# under Model (as bone attachments) alongside the real character mesh.
		if mesh and mesh is ArrayMesh:
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

func _on_wanted_tier_changed(tier: int) -> void:
	wanted_tier = tier

func _effective_detection_range() -> float:
	return DETECTION_RANGE + wanted_tier * TIER_RANGE_BONUS

func _effective_engage_range() -> float:
	return ENGAGE_RANGE + wanted_tier * TIER_RANGE_BONUS

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
	hit_stagger_timer = max(0.0, hit_stagger_timer - delta)

	if eject_stun_timer > 0.0:
		eject_stun_timer -= delta
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		_check_vehicle_collisions()
		# Same fix as npc.gd - getting launched by a car used to just freeze
		# whatever anim was already playing while the cop sailed through the
		# air. Airborne tumble while in flight, hard-landing pose once it hits
		# the ground for the rest of the stun window - checked after
		# move_and_slide so is_on_floor() reflects this frame's real result.
		_play(anim_land if is_on_floor() else anim_hit_react)
		return

	if hostile and not siren_audio.playing:
		siren_audio.stream = _make_siren_sound()
		siren_audio.volume_db = -40.0
		siren_audio.play()
		var fade_in := create_tween()
		fade_in.tween_property(siren_audio, "volume_db", SIREN_VOLUME_DB, 0.2)
	elif not hostile and siren_audio.playing:
		var fade_out := create_tween()
		fade_out.tween_property(siren_audio, "volume_db", -40.0, 0.2)
		fade_out.tween_callback(siren_audio.stop)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if hostile and player and is_instance_valid(player):
		# A landed hit briefly freezes movement/firing instead of the cop
		# shrugging it off mid-stride - short enough it's not a real combat
		# advantage, just enough to actually sell the impact.
		if hit_stagger_timer > 0.0:
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			_process_hostile(delta)
	elif alerted and player and is_instance_valid(player):
		_process_investigate(delta)
	else:
		_process_wander(delta)
		_check_proactive_detection()

	move_and_slide()
	_check_vehicle_collisions()

# See npc.gd's register_vehicle_hit() - same split: this catches the cop
# moving into a car, register_vehicle_hit() below also gets called directly
# by parked_car.gd/traffic_car.gd when a driven car rams a stationary cop
# (a StaticBody3D/AnimatableBody3D driven car never pushes a CharacterBody3D
# on its own, unlike car.gd's real RigidBody3D).
func _check_vehicle_collisions() -> void:
	if vehicle_hit_cooldown > 0.0:
		return
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if not collider:
			continue
		var car_speed := _speed_of_vehicle(collider)
		if car_speed < VEHICLE_HIT_MIN_SPEED:
			continue
		register_vehicle_hit(collider, car_speed)
		break

func _speed_of_vehicle(collider: Object) -> float:
	if collider.is_in_group("vehicles"):
		return collider.linear_velocity.length()
	elif collider.is_in_group("traffic_cars"):
		return absf(collider.drive_speed) if collider.driver else collider.speed
	elif collider.is_in_group("parked_vehicles"):
		return absf(collider.drive_speed)
	return -1.0

func register_vehicle_hit(car: Object, car_speed: float) -> void:
	if vehicle_hit_cooldown > 0.0 or car_speed < VEHICLE_HIT_MIN_SPEED:
		return
	vehicle_hit_cooldown = VEHICLE_HIT_COOLDOWN
	killed_by_player = car.get("driver") == player
	take_damage(clamp(car_speed * VEHICLE_HIT_DAMAGE_PER_SPEED, 0.0, VEHICLE_HIT_MAX_DAMAGE))
	if dead:
		return
	var away: Vector3 = global_position - car.global_position
	away.y = 0.0
	var horizontal_dir: Vector3 = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var knockback_speed: float = VEHICLE_HIT_KNOCKBACK_BASE + car_speed * VEHICLE_HIT_KNOCKBACK_PER_SPEED
	launch(horizontal_dir * knockback_speed + Vector3(0, VEHICLE_HIT_LAUNCH_UP, 0), VEHICLE_HIT_STUN_TIME)

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
	if to_player.length() <= _effective_detection_range() and _has_line_of_sight(player.global_position):
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
			and global_position.distance_to(player.global_position) <= _effective_engage_range() \
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
	if not _player_is_unarmed() and to_player.length() <= _effective_detection_range() and _has_line_of_sight(player.global_position):
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
	if dist <= _effective_engage_range() and _has_line_of_sight(player.global_position):
		lost_sight_timer = 0.0
		WantedSystem.report_sighting()
	# SWAT roam further from their spawn point and take longer to give up
	# once they've lost sight - they were called in specifically for this
	# chase, unlike a patrol cop who was just standing post nearby.
	elif global_position.distance_to(home_position) > LEASH_RADIUS * (1.6 if is_swat else 1.0):
		lost_sight_timer += delta
		if lost_sight_timer >= GIVE_UP_TIME * (1.75 if is_swat else 1.0):
			hostile = false
			lost_sight_timer = 0.0
			return

	if dist > STOP_DISTANCE:
		var dir := to_player.normalized()
		velocity.x = dir.x * chase_speed
		velocity.z = dir.z * chase_speed
		_play(anim_run)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if fire_cooldown <= 0.0 and dist <= _effective_engage_range():
			_shoot_at_player()

	if to_player.length() > 0.01:
		var target_yaw := atan2(to_player.x, to_player.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, TURN_SPEED * delta)

func _shoot_at_player() -> void:
	NPC.scare_nearby(get_tree(), global_position)
	fire_cooldown = fire_rate
	_play_once(anim_attack)

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
	# SWAT (see is_swat) shoot noticeably straighter than a regular beat cop -
	# tactical training, not just bigger numbers elsewhere.
	var spread_amount: float = clamp(dist_to_target / ENGAGE_RANGE, 0.0, 1.0) * 1.1 * (0.55 if is_swat else 1.0)
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
		hit_stagger_timer = HIT_STAGGER_TIME
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
	NPC.scare_nearby(get_tree(), global_position)
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
# loops seamlessly while hostile. Narrower sweep and lower ceiling than the
# original (was 650-1000Hz at 0.35 amplitude) so it reads as a wail instead
# of a shrill alarm, and the sweep is phased off the engine clock rather
# than each cop's own play-start time, so several cops going hostile at
# once wail in unison instead of clashing at random offsets.
func _make_siren_sound() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 2.4
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	var start_time := fmod(Time.get_ticks_msec() / 1000.0, duration)
	for i in range(sample_count):
		var t := fmod(start_time + float(i) / mix_rate, duration)
		var lfo: float = (sin(t / duration * TAU) + 1.0) / 2.0
		var freq: float = lerp(600.0, 880.0, lfo)
		phase += freq / mix_rate * TAU
		var sample: float = sin(phase) * 0.28
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = sample_count
	return stream
