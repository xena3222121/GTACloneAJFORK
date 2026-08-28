extends CharacterBody3D

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const JUMP_VELOCITY := 5.5
const MOUSE_SENSITIVITY := 0.003
const GUN_DAMAGE := 25.0
const INTERACT_RANGE := 3.0
const FIRE_COOLDOWN := 0.12
const MUZZLE_FLASH_TIME := 0.08
const MAX_HEALTH := 100.0
# Verified by rendering a sweep of values, not assumed: the SpringArm3D
# orbits the character rather than doing a true free-look, so pitch stops
# framing cleanly past the normal gameplay clamp range in either direction.
# -1.2 (the existing minimum from normal gameplay) gives a clean top-down
# view of the body without pushing into that unstable territory.
const DEATH_CAM_PITCH := -1.2
const DEATH_CAM_PAN_TIME := 1.8
const DEATH_TEXT_DELAY := 1.0
const DEATH_TEXT_FADE_TIME := 0.8
# spring_arm.collision_mask is 0 (collision avoidance disabled), so
# spring_length grows freely without ever getting clipped by geometry -
# safe to just keep raising it forever for the "reveal the whole city"
# pull-back, capped only so it can't run away to something absurd if the
# player leaves the death screen open for a very long time.
const DEATH_CAM_ZOOM_SPEED := 2.5
const DEATH_CAM_ZOOM_MAX := 300.0

const IMPACT_EFFECT := preload("res://scenes/ImpactEffect.tscn")
const IMPACT_HIT := preload("res://scenes/ImpactHit.tscn")
const PISTOL_ANIM_SOURCE := "res://assets/animations/UAL1_Standard.glb"
# "Idle"/"Walk" (unarmed-looking but same rig/wrist convention as the Pistol_*
# set) are used for the relaxed base pose instead of the character's own
# bundled Man_Idle/Man_Walk, which come from a differently-rigged pack whose
# wrist rotation doesn't match — mixing them made the gun's fixed hand offset
# look wrong (pointing sideways/up) whenever those animations were active.
const PISTOL_ANIMS := ["Pistol_Idle", "Pistol_Shoot", "Pistol_Reload", "Pistol_Aim_Neutral", "Idle", "Walk"]

const MAG_SIZE := 12
const STARTING_RESERVE_AMMO := 36
const RELOAD_TIME := 1.6
const RECOIL_KICK := 0.05
const RECOIL_RECOVERY := 9.0
const TURN_SPEED := 12.0
const AIM_TURN_SPEED := 20.0
const RAY_LENGTH := 1000.0
const LOCO_BLEND_SPEED := 6.0
const AIM_BLEND_SPEED := 8.0

# Bones driven by the upper-body layer (aim pose / shoot / reload) so the
# lower body always keeps following the Idle/Walk locomotion animation
# underneath, no matter what the arms are doing. Always kept as one whole
# unit (never split between two different clips) — bone rotations are
# parent-relative, so a hand spliced in from a different clip than its own
# arm produces a kinematically-incoherent pose (the gun ends up pointing the
# wrong way).
const UPPER_BODY_BONES := [
	"Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"index_01_l", "index_02_l", "index_03_l",
	"middle_01_l", "middle_02_l", "middle_03_l",
	"pinky_01_l", "pinky_02_l", "pinky_03_l",
	"ring_01_l", "ring_02_l", "ring_03_l",
	"thumb_01_l", "thumb_02_l", "thumb_03_l",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"index_01_r", "index_02_r", "index_03_r", "index_04_leaf_r",
	"middle_01_r", "middle_02_r", "middle_03_r", "middle_04_leaf_r",
	"pinky_01_r", "pinky_02_r", "pinky_03_r", "pinky_04_leaf_r",
	"ring_01_r", "ring_02_r", "ring_03_r", "ring_04_leaf_r",
	"thumb_01_r", "thumb_02_r", "thumb_03_r",
]

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var gun_viewmodel: Node3D = $Model/HumanArmature/GeneralSkeleton/BoneAttachment3D/GunViewmodel
@onready var muzzle_point: Marker3D = $Model/HumanArmature/GeneralSkeleton/BoneAttachment3D/GunViewmodel/MuzzlePoint
@onready var muzzle_flash: MeshInstance3D = $Model/HumanArmature/GeneralSkeleton/BoneAttachment3D/GunViewmodel/MuzzlePoint/MuzzleFlash
@onready var muzzle_light: OmniLight3D = $Model/HumanArmature/GeneralSkeleton/BoneAttachment3D/GunViewmodel/MuzzlePoint/MuzzleLight
@onready var gunshot_player: AudioStreamPlayer = $GunshotPlayer
@onready var crosshair: Control = $HUD/Crosshair
@onready var ammo_label: Label = $HUD/AmmoLabel
@onready var model: Node3D = $Model
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
@onready var anim_tree: AnimationTree = $AnimTree
@onready var death_screen: Control = $HUD/DeathScreen
@onready var health_bar: ProgressBar = $HUD/HealthBar
@onready var restart_button: Button = $HUD/DeathScreen/ButtonRow/RestartButton
@onready var quit_button: Button = $HUD/DeathScreen/ButtonRow/QuitButton
@onready var money_label: Label = $HUD/MoneyLabel
@onready var reserve_ammo_label: Label = $HUD/ReserveAmmoLabel

# The RightHand bone's local Y axis is "along the forearm" in both poses
# (points down when the arm hangs relaxed, forward when raised to aim), so
# both orientations below use it as the barrel axis. But the same secondary
# (grip-roll) axis can't serve both: the one that keeps the barrel pointed
# straight down at rest holds the gun upside-down once raised to aim, and
# vice versa. So the gun's attachment blends between two authored
# orientations using the same aim_blend the animation tree already tracks.
const GUN_SCALE := 0.84
const GUN_ORIGIN := Vector3(0, 0.22, 0.05)
# Basis.slerp() requires pure (unscaled) rotation matrices, so scale is kept
# separate here and reapplied after blending rather than baked into these.
var gun_rot_idle := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))
var gun_rot_aim := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera_pitch := 0.0
var driving: Car = null
var fire_cooldown := 0.0

var anim_idle := ""
var anim_walk := ""
var anim_aim := ""
var anim_die := ""
var aiming := false
var health := MAX_HEALTH
var dead := false
var death_cam_zooming := false
var recoil_pitch := 0.0
var ammo_in_mag := MAG_SIZE
var reserve_ammo := STARTING_RESERVE_AMMO
var money := 0
var reload_timer := 0.0
var loco_blend := 0.0
var aim_blend := 0.0
var has_shoot_anim := false
var has_reload_anim := false

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

# Cycle animations (walk, held aim pose) import with loop_mode NONE, so once
# played to the end they freeze on the last frame instead of restarting —
# the character keeps moving via velocity while its legs stay frozen mid-step,
# looking like it's gliding/skating, permanently, once the clip first ends.
func _force_loop(anim_name: String) -> void:
	if anim and anim.has_animation(anim_name):
		anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

func _load_pistol_animations() -> void:
	var packed: PackedScene = load(PISTOL_ANIM_SOURCE)
	var source: Node3D = packed.instantiate()
	var source_anim: AnimationPlayer = source.find_child("AnimationPlayer", true, false)
	if not source_anim:
		source.free()
		return

	var lib: AnimationLibrary
	if anim.has_animation_library("pistol"):
		lib = anim.get_animation_library("pistol")
	else:
		lib = AnimationLibrary.new()
		anim.add_animation_library("pistol", lib)

	for anim_name in PISTOL_ANIMS:
		if source_anim.has_animation(anim_name) and not lib.has_animation(anim_name):
			lib.add_animation(anim_name, source_anim.get_animation(anim_name))

	source.free()

# Builds a blend tree where the upper body (arms/torso, via UPPER_BODY_BONES)
# can independently follow the aim pose / shoot / reload animations while the
# lower body always keeps following Idle/Walk locomotion underneath.
func _setup_animation_tree() -> void:
	has_shoot_anim = anim.has_animation("pistol/Pistol_Shoot")
	has_reload_anim = anim.has_animation("pistol/Pistol_Reload")

	var bt := AnimationNodeBlendTree.new()

	var n_idle := AnimationNodeAnimation.new()
	n_idle.animation = anim_idle
	bt.add_node("Idle", n_idle)

	var n_walk := AnimationNodeAnimation.new()
	n_walk.animation = anim_walk
	bt.add_node("Walk", n_walk)

	# The walk cycle is authored for one specific travel speed (WALK_SPEED);
	# without this, sprinting covers ground faster than the animation's foot
	# plants account for, so the feet visibly slide/glide across the ground.
	var walk_speed_scale := AnimationNodeTimeScale.new()
	bt.add_node("WalkSpeed", walk_speed_scale)
	bt.connect_node("WalkSpeed", 0, "Walk")

	var n_aim := AnimationNodeAnimation.new()
	n_aim.animation = anim_aim
	bt.add_node("Aim", n_aim)

	var loco := AnimationNodeBlend2.new()
	bt.add_node("Locomotion", loco)
	bt.connect_node("Locomotion", 0, "Idle")
	bt.connect_node("Locomotion", 1, "WalkSpeed")

	# The whole arm (shoulder through fingers) must come from a single
	# coherent clip: bone rotations are relative to their parent, so a hand
	# spliced in from a different clip than its own arm produces a broken,
	# kinematically-incoherent pose (the gun ends up pointing the wrong way).
	# So the arm+hand blends as one unit between the relaxed Locomotion pose
	# and the Aim pose, never split.
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	for bone_name in UPPER_BODY_BONES:
		upper.set_filter_path(NodePath("%GeneralSkeleton:" + bone_name), true)
	bt.add_node("UpperAim", upper)
	bt.connect_node("UpperAim", 0, "Locomotion")
	bt.connect_node("UpperAim", 1, "Aim")

	var last_output := "UpperAim"

	if has_shoot_anim:
		var n_shoot := AnimationNodeAnimation.new()
		n_shoot.animation = "pistol/Pistol_Shoot"
		bt.add_node("Shoot", n_shoot)
		var shoot_shot := AnimationNodeOneShot.new()
		shoot_shot.filter_enabled = true
		for bone_name in UPPER_BODY_BONES:
			shoot_shot.set_filter_path(NodePath("%GeneralSkeleton:" + bone_name), true)
		shoot_shot.fadein_time = 0.02
		shoot_shot.fadeout_time = 0.15
		bt.add_node("ShootShot", shoot_shot)
		bt.connect_node("ShootShot", 0, last_output)
		bt.connect_node("ShootShot", 1, "Shoot")
		last_output = "ShootShot"

	if has_reload_anim:
		var n_reload := AnimationNodeAnimation.new()
		n_reload.animation = "pistol/Pistol_Reload"
		bt.add_node("Reload", n_reload)
		var reload_shot := AnimationNodeOneShot.new()
		reload_shot.filter_enabled = true
		for bone_name in UPPER_BODY_BONES:
			reload_shot.set_filter_path(NodePath("%GeneralSkeleton:" + bone_name), true)
		reload_shot.fadein_time = 0.05
		reload_shot.fadeout_time = 0.2
		bt.add_node("ReloadShot", reload_shot)
		bt.connect_node("ReloadShot", 0, last_output)
		bt.connect_node("ReloadShot", 1, "Reload")
		last_output = "ReloadShot"

	bt.connect_node("output", 0, last_output)

	anim_tree.anim_player = anim_tree.get_path_to(anim)
	anim_tree.tree_root = bt
	anim_tree.active = true

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if anim:
		_strip_armature_root_tracks()
		_load_pistol_animations()
		# The base resting stance stays relaxed (gun down, not pointed forward);
		# Pistol_Idle already holds the gun up/forward, which is what the
		# UpperAim layer should only bring in while aiming or shooting. Use
		# "pistol/Idle" and "pistol/Walk" (same rig as the Pistol_* set) rather
		# than the character's own Man_Idle/Man_Walk, which is a differently
		# rigged pack that holds the wrist at an incompatible angle for the gun.
		anim_idle = "pistol/Idle" if anim.has_animation("pistol/Idle") else _find_anim("idle")
		anim_walk = "pistol/Walk" if anim.has_animation("pistol/Walk") else _find_anim("walk")
		anim_aim = "pistol/Pistol_Aim_Neutral" if anim.has_animation("pistol/Pistol_Aim_Neutral") else anim_idle
		anim_die = _find_anim("death")
		_force_loop(anim_walk)
		_force_loop(anim_aim)
		_force_loop(anim_idle)
		_setup_animation_tree()
	gunshot_player.stream = _make_gunshot_sound()
	_update_ammo_label()
	_update_reserve_ammo_label()
	_update_money_label()
	health_bar.max_value = MAX_HEALTH
	health_bar.value = health
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.2, 0.8)

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not driving and fire_cooldown <= 0.0 and reload_timer <= 0.0:
			if ammo_in_mag > 0:
				shoot()
				fire_cooldown = FIRE_COOLDOWN
			else:
				_play_empty_click()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		aiming = event.pressed and not driving and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		crosshair.aiming = aiming

	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if not driving:
			reload()

	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		if driving:
			exit_vehicle()
		else:
			try_enter_vehicle()

func _physics_process(delta: float) -> void:
	if dead:
		# Hand off spring_arm.rotation.x to the death-cam tween entirely -
		# this line normally re-asserts it from camera_pitch every frame,
		# which would fight the tween if it kept running.
		return

	fire_cooldown = max(0.0, fire_cooldown - delta)
	recoil_pitch = lerp(recoil_pitch, 0.0, min(1.0, RECOIL_RECOVERY * delta))
	spring_arm.rotation.x = camera_pitch + recoil_pitch
	if reload_timer > 0.0:
		reload_timer = max(0.0, reload_timer - delta)

	if driving:
		# Follow the car's driver seat while inside it; the car handles its own physics.
		global_position = driving.driver_seat.global_position
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	var speed := SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	var forward := camera_pivot.global_transform.basis.z
	var right := camera_pivot.global_transform.basis.x
	var move_dir := (right * input_dir.x + forward * input_dir.y)
	move_dir.y = 0
	move_dir = move_dir.normalized() if move_dir.length() > 0.01 else Vector3.ZERO

	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

	var moving := move_dir.length() > 0.01
	if aiming:
		# Camera3D looks down -Z, so the direction the camera is actually facing
		# (and where the reticle points) is offset by PI from camera_pivot's yaw.
		var aim_yaw := camera_pivot.rotation.y + PI
		model.rotation.y = lerp_angle(model.rotation.y, aim_yaw, AIM_TURN_SPEED * delta)
	elif moving:
		var target_yaw := atan2(move_dir.x, move_dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, TURN_SPEED * delta)

	# The lower body always follows Idle/Walk based on actual movement, and the
	# upper body independently blends toward the aim pose — so the legs keep
	# walking under an aiming (or shooting/reloading) upper body.
	loco_blend = move_toward(loco_blend, 1.0 if moving else 0.0, LOCO_BLEND_SPEED * delta)
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, AIM_BLEND_SPEED * delta)
	anim_tree["parameters/Locomotion/blend_amount"] = loco_blend
	anim_tree["parameters/UpperAim/blend_amount"] = aim_blend
	anim_tree["parameters/WalkSpeed/scale"] = speed / WALK_SPEED

	gun_viewmodel.transform.basis = gun_rot_idle.slerp(gun_rot_aim, aim_blend).scaled(Vector3.ONE * GUN_SCALE)
	gun_viewmodel.transform.origin = GUN_ORIGIN

	move_and_slide()

func shoot() -> void:
	gunshot_player.play()
	_flash_muzzle()

	ammo_in_mag -= 1
	_update_ammo_label()

	recoil_pitch += RECOIL_KICK

	if has_shoot_anim:
		anim_tree["parameters/ShootShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE

	# Hip-fire travels along the character's own facing direction, not wherever
	# the orbiting third-person camera happens to be looking. While aiming,
	# the character is camera-locked and the reticle is screen-centered, so
	# the shot must be cast from the camera itself to actually land on it.
	var origin: Vector3
	var forward: Vector3
	if aiming:
		origin = camera.global_position
		forward = -camera.global_transform.basis.z.normalized()
	else:
		origin = muzzle_point.global_position
		forward = model.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * RAY_LENGTH)
	query.exclude = [self.get_rid()]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)

	if result:
		var point: Vector3 = result.position
		var hit: Object = result.collider
		var is_damageable: bool = hit and hit.has_method("take_damage")

		var fx: Node3D = IMPACT_HIT.instantiate() if is_damageable else IMPACT_EFFECT.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = point

		if is_damageable:
			hit.take_damage(GUN_DAMAGE, point)
			crosshair.flash_hit()

func reload() -> void:
	if reload_timer > 0.0 or ammo_in_mag >= MAG_SIZE or reserve_ammo <= 0:
		return
	reload_timer = RELOAD_TIME
	if has_reload_anim:
		anim_tree["parameters/ReloadShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	await get_tree().create_timer(RELOAD_TIME).timeout
	var needed: int = MAG_SIZE - ammo_in_mag
	var taken: int = min(needed, reserve_ammo)
	ammo_in_mag += taken
	reserve_ammo -= taken
	_update_ammo_label()
	_update_reserve_ammo_label()

func _update_ammo_label() -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [ammo_in_mag, MAG_SIZE]

func _update_reserve_ammo_label() -> void:
	if reserve_ammo_label:
		reserve_ammo_label.text = "Ammo: %d" % reserve_ammo

func _update_money_label() -> void:
	if money_label:
		money_label.text = "$%d" % money

func add_money(amount: int) -> void:
	money += amount
	_update_money_label()

func add_ammo(amount: int) -> void:
	reserve_ammo += amount
	_update_reserve_ammo_label()

func _play_empty_click() -> void:
	var stream := _make_click_sound()
	gunshot_player.stream = stream
	gunshot_player.play()
	gunshot_player.stream = _make_gunshot_sound()

func _flash_muzzle() -> void:
	muzzle_flash.visible = true
	muzzle_flash.scale = Vector3.ONE * 1.3
	muzzle_light.light_energy = 5.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(muzzle_flash, "scale", Vector3.ONE * 0.2, MUZZLE_FLASH_TIME).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(muzzle_light, "light_energy", 0.0, MUZZLE_FLASH_TIME).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	muzzle_flash.visible = false

func _make_gunshot_sound() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.16
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
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

func _make_click_sound() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.045
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(sample_count):
		var t := float(i) / sample_count
		var envelope: float = pow(1.0 - t, 6.0)
		var noise := rng.randf_range(-1.0, 1.0)
		var sample: float = clamp(noise * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func try_enter_vehicle() -> void:
	var nearest: Car = null
	var nearest_dist := INTERACT_RANGE
	for car in get_tree().get_nodes_in_group("vehicles"):
		var dist: float = global_position.distance_to(car.global_position)
		if dist < nearest_dist:
			nearest = car
			nearest_dist = dist
	if nearest:
		enter_vehicle(nearest)

func enter_vehicle(car: Car) -> void:
	driving = car
	aiming = false
	crosshair.aiming = false
	visible = false
	collision.disabled = true
	camera.current = false
	car.driver_enter(self)

func exit_vehicle() -> void:
	if not driving:
		return
	var car := driving
	driving = null
	visible = true
	collision.disabled = false
	global_position = car.exit_point.global_position
	camera.current = true
	car.driver_exit()

func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	health -= amount
	health_bar.value = health
	if health <= 0.0:
		die()

func die() -> void:
	if dead:
		return
	dead = true
	collision.disabled = true

	if anim:
		# The AnimationTree normally drives every pose each frame; switch it
		# off so a direct play() on the death clip isn't immediately
		# overwritten, same as how NPCs (which have no blend tree at all)
		# just play their death clip straight.
		anim_tree.active = false
		if anim_die != "":
			anim.play(anim_die)

	_play_death_camera()

func _play_death_camera() -> void:
	var tween := create_tween()
	tween.tween_property(spring_arm, "rotation:x", DEATH_CAM_PITCH, DEATH_CAM_PAN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Starts immediately (not after the pan finishes) so the pull-back and
	# the swing-to-top-down happen together rather than one after the other.
	death_cam_zooming = true
	await get_tree().create_timer(DEATH_TEXT_DELAY).timeout
	_show_death_text()

func _show_death_text() -> void:
	death_screen.visible = true
	death_screen.modulate.a = 0.0
	# The buttons need a visible, usable cursor - normal gameplay keeps the
	# mouse captured/hidden for looking around, which would otherwise leave
	# Restart/Quit unclickable.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tween := create_tween()
	tween.tween_property(death_screen, "modulate:a", 1.0, DEATH_TEXT_FADE_TIME)

# Runs every rendered frame regardless of _physics_process's early-return
# once dead, so the "reveal the whole city" pull-back keeps going for as
# long as the death screen is up.
func _process(delta: float) -> void:
	if death_cam_zooming:
		spring_arm.spring_length = min(spring_arm.spring_length + DEATH_CAM_ZOOM_SPEED * delta, DEATH_CAM_ZOOM_MAX)
