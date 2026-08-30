extends CharacterBody3D

enum Weapon { KNIFE, PISTOL, SHOTGUN, MAC10, UNARMED }

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const JUMP_VELOCITY := 5.5
const MOUSE_SENSITIVITY := 0.003
const JOY_LOOK_SENSITIVITY := 3.0
const JOY_DEADZONE := 0.2
const PISTOL_DAMAGE := 25.0
const INTERACT_RANGE := 3.0
const PISTOL_FIRE_COOLDOWN := 0.12
const MUZZLE_FLASH_TIME := 0.08
const MAX_HEALTH := 100.0
const VEHICLE_HIT_MIN_SPEED := 2.0
const VEHICLE_HIT_DAMAGE_PER_SPEED := 4.0
const VEHICLE_HIT_MAX_DAMAGE := 80.0
const VEHICLE_HIT_KNOCKBACK := 6.0
const VEHICLE_HIT_COOLDOWN := 0.6

const SELL_RANGE := 3.0
const SELL_PRICE_MIN := 15
const SELL_PRICE_MAX := 45
const SNITCH_CHANCE := 0.10 # was 0.15 - AJ asked for a flat 10% undercover-buyer chance
const SNITCH_HEAT := 20.0

const AMMO_PRICE := 20
const AMMO_BUY_AMOUNT := 60
const SHOTGUN_PRICE := 50
const SHOTGUN_BUY_AMOUNT := 16
const MAC10_PRICE := 80
const MAC10_BUY_AMOUNT := 90
const OUTFIT_PRICE := 30

const CAMARO_PRICE := 2500
const MAZDA_PRICE := 2200
const RANGEROVER_PRICE := 3200
const CAMARO_SCENE := preload("res://scenes/ParkedCar_Camaro.tscn")
const MAZDA_SCENE := preload("res://scenes/ParkedCar_MazdaRX7.tscn")
const RANGEROVER_SCENE := preload("res://scenes/ParkedCar_RangeRover.tscn")
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

const COPS_INCOMING_LINE := "res://Audio/Arnold/Player Cops Incoming/Oh my fucking god bro here comes the fucking police.wav"
const PLAYER_KILL_LINES := [
	"res://Audio/Arnold/Player Shot Someone/Oh my fucking god I shot that guys dick clean off.wav",
	"res://Audio/Arnold/Player Shot Someone/Fuck bro I shot you right in the dick my bad bro.wav",
]
const PLAYER_KILL_LINE_CHANCE := 0.6
const PLAYER_HURT_LINE := "res://Audio/Arnold/Random Lines/I havent felt this sad and pathetic since band camp.wav"
const PLAYER_HURT_LINE_CHANCE := 0.3

const IMPACT_EFFECT := preload("res://scenes/ImpactEffect.tscn")
const IMPACT_HIT := preload("res://scenes/ImpactHit.tscn")
const PISTOL_ANIM_SOURCE := "res://assets/animations/UAL1_Standard.glb"
# "Idle"/"Walk" (unarmed-looking but same rig/wrist convention as the Pistol_*
# set) are used for the relaxed base pose instead of the character's own
# bundled Man_Idle/Man_Walk, which come from a differently-rigged pack whose
# wrist rotation doesn't match — mixing them made the gun's fixed hand offset
# look wrong (pointing sideways/up) whenever those animations were active.
const PISTOL_ANIMS := ["Pistol_Idle", "Pistol_Shoot", "Pistol_Reload", "Pistol_Aim_Neutral", "Idle", "Walk", "Punch_Cross"]

const PISTOL_MAG_SIZE := 12
const STARTING_RESERVE_AMMO := 36
const PISTOL_RELOAD_TIME := 1.6
const RECOIL_KICK := 0.05

const MELEE_RANGE := 2.6
const MELEE_HITBOX_RADIUS := 1.3
const MELEE_DAMAGE := 90.0 # 2 solid hits kill anything (Police=120hp, NPC=150hp) - a knife needing 4-5 hits while standing next to an armed enemy wasn't a real weapon
const MELEE_COOLDOWN := 0.85 # Punch_Cross is ~1s long; this lets the swing mostly play out before it can be re-triggered
const MELEE_RECOIL_KICK := 0.12

# The shotgun and Mac-10 both reuse the pistol's viewmodel and animations
# (there's no separate weapon model in the project's assets) - each is given
# a different tint on pickup as the only visual differentiator, and is
# differentiated for real by its fire behavior/ammo pool instead.
const SHOTGUN_PELLET_DAMAGE := 9.0
const SHOTGUN_PELLET_COUNT := 8
const SHOTGUN_SPREAD_DEGREES := 6.0
const SHOTGUN_FIRE_COOLDOWN := 0.9
const SHOTGUN_MAG_SIZE := 6
const SHOTGUN_RELOAD_TIME := 2.2
const SHOTGUN_PICKUP_AMMO := 16

const MAC10_DAMAGE := 14.0
const MAC10_FIRE_COOLDOWN := 0.08
const MAC10_MAG_SIZE := 30
const MAC10_RELOAD_TIME := 1.8
const MAC10_PICKUP_AMMO := 60

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
@onready var rain: GPUParticles3D = $CameraPivot/Rain
@onready var pistol_viewmodel: Node3D = $Model/HumanArmature/GeneralSkeleton/BoneAttachment3D/PistolViewmodel
@onready var shotgun_viewmodel: Node3D = $Model/HumanArmature/GeneralSkeleton/BoneAttachment3D/ShotgunViewmodel
@onready var mac10_viewmodel: Node3D = $Model/HumanArmature/GeneralSkeleton/BoneAttachment3D/Mac10Viewmodel
@onready var knife_viewmodel: Node3D = $Model/HumanArmature/GeneralSkeleton/BoneAttachment3D/KnifeViewmodel
# Each real gun model (from styloo's guns pack) replaced one shared,
# re-tinted Pistol_2.glb doing duty as all 3 guns - keyed by Weapon so
# _current_gun_viewmodel()/_current_muzzle_point() below can look up
# whichever one is actually equipped instead of a single fixed node.
@onready var gun_viewmodels := {
	Weapon.PISTOL: pistol_viewmodel,
	Weapon.SHOTGUN: shotgun_viewmodel,
	Weapon.MAC10: mac10_viewmodel,
}
@onready var gunshot_player: AudioStreamPlayer = $GunshotPlayer
@onready var voice_line_player: AudioStreamPlayer = $VoiceLinePlayer
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
@onready var wanted_label: Label = $HUD/WantedLabel
@onready var drugs_label: Label = $HUD/DrugsLabel
@onready var interact_prompt_label: Label = $HUD/InteractPromptLabel
@onready var drunk_overlay: ColorRect = $HUD/DrunkOverlay
@onready var store_menu: Control = $HUD/StoreMenu
@onready var buy_ammo_button: Button = $HUD/StoreMenu/Panel/VBox/BuyAmmoButton
@onready var buy_shotgun_button: Button = $HUD/StoreMenu/Panel/VBox/BuyShotgunButton
@onready var buy_mac10_button: Button = $HUD/StoreMenu/Panel/VBox/BuyMac10Button
@onready var buy_red_outfit_button: Button = $HUD/StoreMenu/Panel/VBox/BuyRedOutfitButton
@onready var buy_black_outfit_button: Button = $HUD/StoreMenu/Panel/VBox/BuyBlackOutfitButton
@onready var close_store_button: Button = $HUD/StoreMenu/Panel/VBox/CloseStoreButton
@onready var dealer_menu: Control = $HUD/DealerMenu
@onready var buy_camaro_button: Button = $HUD/DealerMenu/Panel/VBox/BuyCamaroButton
@onready var buy_mazda_button: Button = $HUD/DealerMenu/Panel/VBox/BuyMazdaButton
@onready var buy_rangerover_button: Button = $HUD/DealerMenu/Panel/VBox/BuyRangeRoverButton
@onready var close_dealer_button: Button = $HUD/DealerMenu/Panel/VBox/CloseDealerButton
@onready var reserve_ammo_label: Label = $HUD/ReserveAmmoLabel
@onready var npc_menu: Control = $HUD/NPCMenu
@onready var npc_menu_title: Label = $HUD/NPCMenu/Panel/VBox/Title
@onready var talk_button: Button = $HUD/NPCMenu/Panel/VBox/TalkButton
@onready var sell_drugs_button: Button = $HUD/NPCMenu/Panel/VBox/SellDrugsButton
@onready var hire_button: Button = $HUD/NPCMenu/Panel/VBox/HireButton
@onready var close_npc_button: Button = $HUD/NPCMenu/Panel/VBox/CloseNPCButton

# The RightHand bone's local Y axis is "along the forearm" in both poses
# (points down when the arm hangs relaxed, forward when raised to aim), so
# both orientations below use it as the barrel axis. But the same secondary
# (grip-roll) axis can't serve both: the one that keeps the barrel pointed
# straight down at rest holds the gun upside-down once raised to aim, and
# vice versa. So the gun's attachment blends between two authored
# orientations using the same aim_blend the animation tree already tracks.
const GUN_SCALE := 0.84
const GUNS_PACK_VIEWMODEL_SCALE := 3.0
const GUN_ORIGIN := Vector3(0, 0.22, 0.05)
# Basis.slerp() requires pure (unscaled) rotation matrices, so scale is kept
# separate here and reapplied after blending rather than baked into these.
var gun_rot_idle := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))
var gun_rot_aim := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera_pitch := 0.0
var driving: Node3D = null
var fire_cooldown := 0.0
var vehicle_hit_cooldown := 0.0
var joy_fire_prev := false
var joy_reload_prev := false
var joy_interact_prev := false
var joy_dpad_left_prev := false
var joy_dpad_right_prev := false

var anim_idle := ""
var anim_walk := ""
var anim_aim := ""
var anim_die := ""
var aiming := false
var health := MAX_HEALTH
var dead := false
var played_cops_incoming_line := false
var death_cam_zooming := false
var recoil_pitch := 0.0
var current_weapon: int = Weapon.UNARMED
# Alpha 0 means "stock outfit, no tint bought" - distinguishes that from a
# legitimately dark purchased color when deciding whether to persist/reapply
# an outfit on save/load.
var outfit_tint := Color(0, 0, 0, 0)
var has_shotgun := false
var has_mac10 := false
var pistol_ammo_in_mag := PISTOL_MAG_SIZE
var pistol_reserve_ammo := STARTING_RESERVE_AMMO
var shotgun_ammo_in_mag := 0
var shotgun_reserve_ammo := 0
var mac10_ammo_in_mag := 0
var mac10_reserve_ammo := 0
var money := 0
var drugs := 0
var drunk_timer := 0.0
var drunk_sway_time := 0.0
var drunk_pitch_sway := 0.0
var menu_open := false
var nearby_interactable: Node = null
var current_npc: Node3D = null
var current_interior: Node = null
var current_dealer: Node = null
var exterior_return_position := Vector3.ZERO
var reload_timer := 0.0
var loco_blend := 0.0
var aim_blend := 0.0
var has_shoot_anim := false
var has_reload_anim := false
var has_punch_anim := false

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
	has_punch_anim = anim.has_animation("pistol/Punch_Cross")

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

	if has_punch_anim:
		var n_punch := AnimationNodeAnimation.new()
		n_punch.animation = "pistol/Punch_Cross"
		bt.add_node("Punch", n_punch)
		var punch_shot := AnimationNodeOneShot.new()
		punch_shot.filter_enabled = true
		for bone_name in UPPER_BODY_BONES:
			punch_shot.set_filter_path(NodePath("%GeneralSkeleton:" + bone_name), true)
		punch_shot.fadein_time = 0.03
		punch_shot.fadeout_time = 0.2
		bt.add_node("PunchShot", punch_shot)
		bt.connect_node("PunchShot", 0, last_output)
		bt.connect_node("PunchShot", 1, "Punch")
		last_output = "PunchShot"

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
	if SaveSystem.has_save():
		SaveSystem.load_game(self)
		_update_gun_viewmodel_visibility()
		knife_viewmodel.visible = current_weapon == Weapon.KNIFE
	_update_ammo_label()
	_update_reserve_ammo_label()
	_update_money_label()
	_update_drugs_label()
	health_bar.max_value = MAX_HEALTH
	health_bar.value = health
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	WantedSystem.tier_changed.connect(_on_wanted_tier_changed)
	_on_wanted_tier_changed(0)
	buy_ammo_button.pressed.connect(_buy_ammo)
	buy_shotgun_button.pressed.connect(_buy_shotgun)
	buy_mac10_button.pressed.connect(_buy_mac10)
	buy_red_outfit_button.pressed.connect(_buy_red_outfit)
	buy_black_outfit_button.pressed.connect(_buy_black_outfit)
	close_store_button.pressed.connect(close_store_menu)
	buy_camaro_button.pressed.connect(_buy_camaro)
	buy_mazda_button.pressed.connect(_buy_mazda)
	buy_rangerover_button.pressed.connect(_buy_rangerover)
	close_dealer_button.pressed.connect(close_dealer_menu)
	talk_button.pressed.connect(_on_npc_talk_pressed)
	sell_drugs_button.pressed.connect(_on_npc_sell_pressed)
	hire_button.pressed.connect(_on_npc_hire_pressed)
	close_npc_button.pressed.connect(close_npc_menu)

func _on_wanted_tier_changed(tier: int) -> void:
	wanted_label.text = "★".repeat(tier)

func _on_restart_pressed() -> void:
	WantedSystem.reset()
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.2, 0.8)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not driving and fire_cooldown <= 0.0 and reload_timer <= 0.0:
			_try_fire()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		aiming = event.pressed and not driving and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		crosshair.aiming = aiming

	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if not driving:
			reload()

	if event is InputEventKey and event.pressed and event.keycode == KEY_1:
		if not driving:
			switch_weapon(Weapon.KNIFE)
	if event is InputEventKey and event.pressed and event.keycode == KEY_2:
		if not driving:
			switch_weapon(Weapon.PISTOL)
	if event is InputEventKey and event.pressed and event.keycode == KEY_3:
		if not driving:
			switch_weapon(Weapon.SHOTGUN)
	if event is InputEventKey and event.pressed and event.keycode == KEY_4:
		if not driving:
			switch_weapon(Weapon.MAC10)
	if event is InputEventKey and event.pressed and event.keycode == KEY_0:
		if not driving:
			switch_weapon(Weapon.UNARMED)

	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		_interact()

func _interact() -> void:
	if menu_open:
		return
	if driving:
		exit_vehicle()
	elif nearby_interactable:
		# Checked before current_interior: standing at the StoreCounter/
		# Register with a nearby_interactable set means E should open that
		# menu, not exit the building - current_interior used to be checked
		# first, so pressing E at the counter always bailed out to the
		# street instead of shopping (the "kicks you out immediately" bug).
		nearby_interactable.interact(self)
	elif current_interior:
		exit_building()
	elif not try_enter_vehicle():
		try_sell_drugs_to_nearby_npc()

func _physics_process(delta: float) -> void:
	if dead:
		# Hand off spring_arm.rotation.x to the death-cam tween entirely -
		# this line normally re-asserts it from camera_pitch every frame,
		# which would fight the tween if it kept running.
		return

	if menu_open:
		return

	fire_cooldown = max(0.0, fire_cooldown - delta)
	vehicle_hit_cooldown = max(0.0, vehicle_hit_cooldown - delta)
	drunk_timer = max(0.0, drunk_timer - delta)
	# Getting drunk (bar_drink.gd) used to be completely invisible to the
	# player - it only quietly nudged one aggro-chance roll in npc.gd. A
	# gentle camera sway (roll for the "tipsy" wobble, a little pitch drift)
	# plus a HUD tint gives it an actual felt effect.
	var drunk_target_roll: float = sin(drunk_sway_time * 1.3) * 0.06 if drunk_timer > 0.0 else 0.0
	var drunk_target_pitch: float = sin(drunk_sway_time * 1.7) * 0.04 if drunk_timer > 0.0 else 0.0
	if drunk_timer > 0.0:
		drunk_sway_time += delta
	spring_arm.rotation.z = lerp(spring_arm.rotation.z, drunk_target_roll, 3.0 * delta)
	drunk_pitch_sway = lerp(drunk_pitch_sway, drunk_target_pitch, 3.0 * delta)
	if drunk_overlay:
		drunk_overlay.modulate.a = clamp(drunk_timer, 0.0, 3.0) / 3.0 * 0.3

	recoil_pitch = lerp(recoil_pitch, 0.0, min(1.0, RECOIL_RECOVERY * delta))
	spring_arm.rotation.x = camera_pitch + recoil_pitch + drunk_pitch_sway
	if reload_timer > 0.0:
		reload_timer = max(0.0, reload_timer - delta)

	# Right stick look and the vehicle-interact button both need to keep
	# working while driving too (mirroring mouse-look, which runs from
	# _unhandled_input and isn't gated by this function's early return
	# below), so they're polled here rather than down with fire/reload/etc.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-_joy_axis(JOY_AXIS_RIGHT_X) * JOY_LOOK_SENSITIVITY * delta)
		camera_pitch = clamp(camera_pitch - _joy_axis(JOY_AXIS_RIGHT_Y) * JOY_LOOK_SENSITIVITY * delta, -1.2, 0.8)

	var joy_interact_down := Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
	if joy_interact_down and not joy_interact_prev:
		_interact()
	joy_interact_prev = joy_interact_down

	if nearby_interactable:
		interact_prompt_label.text = nearby_interactable.prompt_text
		interact_prompt_label.visible = true
	else:
		interact_prompt_label.visible = false

	if driving:
		# Follow the car's driver seat while inside it; the car handles its own physics.
		global_position = driving.driver_seat.global_position
		velocity = Vector3.ZERO
		return

	# Mac-10 is full-auto: keeps firing while held, unlike the click-to-fire
	# pistol/shotgun/knife (handled in _unhandled_input on the press event,
	# and below for the controller's edge-triggered equivalent).
	var joy_fire_down := Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	if current_weapon == Weapon.MAC10 and fire_cooldown <= 0.0 and reload_timer <= 0.0 \
			and ((Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) \
				or joy_fire_down):
		_try_fire()
	elif joy_fire_down and not joy_fire_prev and fire_cooldown <= 0.0 and reload_timer <= 0.0:
		_try_fire()
	joy_fire_prev = joy_fire_down

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
		crosshair.aiming = aiming

	var joy_reload_down := Input.is_joy_button_pressed(0, JOY_BUTTON_X)
	if joy_reload_down and not joy_reload_prev:
		reload()
	joy_reload_prev = joy_reload_down

	var joy_dpad_left_down := Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT)
	if joy_dpad_left_down and not joy_dpad_left_prev:
		_cycle_weapon(-1)
	joy_dpad_left_prev = joy_dpad_left_down

	var joy_dpad_right_down := Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT)
	if joy_dpad_right_down and not joy_dpad_right_prev:
		_cycle_weapon(1)
	joy_dpad_right_prev = joy_dpad_right_down

	if not is_on_floor():
		velocity.y -= gravity * delta

	if (Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)) and is_on_floor():
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
	input_dir.x += _joy_axis(JOY_AXIS_LEFT_X)
	input_dir.y += _joy_axis(JOY_AXIS_LEFT_Y)
	input_dir = input_dir.normalized() if input_dir.length() > 1.0 else input_dir

	var speed := SPRINT_SPEED if (Input.is_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)) else WALK_SPEED
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

	# All 3 gun models share one idle/aim sway ROTATION - only one is ever
	# visible at a time, but updating all 3 (plus the knife) unconditionally
	# is simpler than tracking which one and means no re-sync is needed the
	# moment you switch weapons. Scale is per-weapon though: Pistol_2.glb
	# (assets/weapons/) has a 100x correction baked into its own mesh
	# transform from whatever DCC tool exported it, so GUN_SCALE=0.84 nets
	# out to a normal-looking pistol; the guns-pack models (mac10/shotgun,
	# added this session) have no such correction and are already authored
	# at real-world meter scale, so they need a much bigger multiplier here
	# to read as anything but a tiny sliver in the character's hand -
	# confirmed empirically via screenshot, not calculated, since the two
	# packs' internal scale conventions don't match.
	var gun_rot: Basis = gun_rot_idle.slerp(gun_rot_aim, aim_blend)
	pistol_viewmodel.transform.basis = gun_rot.scaled(Vector3.ONE * GUN_SCALE)
	pistol_viewmodel.transform.origin = GUN_ORIGIN
	shotgun_viewmodel.transform.basis = gun_rot.scaled(Vector3.ONE * GUNS_PACK_VIEWMODEL_SCALE)
	shotgun_viewmodel.transform.origin = GUN_ORIGIN
	mac10_viewmodel.transform.basis = gun_rot.scaled(Vector3.ONE * GUNS_PACK_VIEWMODEL_SCALE)
	mac10_viewmodel.transform.origin = GUN_ORIGIN
	# Knife has no separate idle/aim pose of its own - it just rides along in
	# the same hand position/orientation the gun would otherwise be in.
	knife_viewmodel.transform.basis = gun_rot.scaled(Vector3.ONE * GUN_SCALE)
	knife_viewmodel.transform.origin = GUN_ORIGIN

	move_and_slide()
	_check_vehicle_collisions()

# Cars never used to check for the player at all (no contact_monitor, no
# body_entered signal on any of car.gd/traffic_car.gd/parked_car.gd), so
# getting run over did nothing. Doing this on the player's side instead
# means it works against every vehicle type for free via move_and_slide's
# own collision results, with no changes needed to the car scripts beyond
# tagging traffic cars into a group to identify them here.
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
		var away: Vector3 = global_position - collider.global_position
		away.y = 0.0
		velocity += (away.normalized() if away.length() > 0.01 else -collision.get_normal()) * VEHICLE_HIT_KNOCKBACK
		break

func _mag_size() -> int:
	match current_weapon:
		Weapon.SHOTGUN: return SHOTGUN_MAG_SIZE
		Weapon.MAC10: return MAC10_MAG_SIZE
		_: return PISTOL_MAG_SIZE

func _fire_cooldown_time() -> float:
	match current_weapon:
		Weapon.SHOTGUN: return SHOTGUN_FIRE_COOLDOWN
		Weapon.MAC10: return MAC10_FIRE_COOLDOWN
		_: return PISTOL_FIRE_COOLDOWN

func _reload_time_for_current() -> float:
	match current_weapon:
		Weapon.SHOTGUN: return SHOTGUN_RELOAD_TIME
		Weapon.MAC10: return MAC10_RELOAD_TIME
		_: return PISTOL_RELOAD_TIME

func _current_ammo_in_mag() -> int:
	match current_weapon:
		Weapon.SHOTGUN: return shotgun_ammo_in_mag
		Weapon.MAC10: return mac10_ammo_in_mag
		_: return pistol_ammo_in_mag

func _set_current_ammo_in_mag(value: int) -> void:
	match current_weapon:
		Weapon.SHOTGUN: shotgun_ammo_in_mag = value
		Weapon.MAC10: mac10_ammo_in_mag = value
		_: pistol_ammo_in_mag = value

func _current_reserve_ammo() -> int:
	match current_weapon:
		Weapon.SHOTGUN: return shotgun_reserve_ammo
		Weapon.MAC10: return mac10_reserve_ammo
		_: return pistol_reserve_ammo

func _set_current_reserve_ammo(value: int) -> void:
	match current_weapon:
		Weapon.SHOTGUN: shotgun_reserve_ammo = value
		Weapon.MAC10: mac10_reserve_ammo = value
		_: pistol_reserve_ammo = value

func is_unarmed() -> bool:
	return current_weapon == Weapon.UNARMED

func _has_weapon(weapon: int) -> bool:
	match weapon:
		Weapon.SHOTGUN: return has_shotgun
		Weapon.MAC10: return has_mac10
		_: return true

# PS4/Xbox-style gamepad, device 0 only - this is a single-player game with
# no split-screen/second-controller concept anywhere else in the codebase.
func _joy_axis(axis: JoyAxis) -> float:
	var v := Input.get_joy_axis(0, axis)
	return v if absf(v) > JOY_DEADZONE else 0.0

const WEAPON_ORDER := [Weapon.UNARMED, Weapon.KNIFE, Weapon.PISTOL, Weapon.SHOTGUN, Weapon.MAC10]

func _cycle_weapon(direction: int) -> void:
	if driving:
		return
	var idx := WEAPON_ORDER.find(current_weapon)
	for i in range(1, WEAPON_ORDER.size() + 1):
		var next_idx := ((idx + direction * i) % WEAPON_ORDER.size() + WEAPON_ORDER.size()) % WEAPON_ORDER.size()
		var candidate: int = WEAPON_ORDER[next_idx]
		if _has_weapon(candidate):
			switch_weapon(candidate)
			return

func switch_weapon(weapon: int) -> void:
	if weapon == current_weapon or not _has_weapon(weapon):
		return
	if reload_timer > 0.0:
		return
	current_weapon = weapon
	_update_gun_viewmodel_visibility()
	knife_viewmodel.visible = weapon == Weapon.KNIFE
	_update_ammo_label()
	_update_reserve_ammo_label()

# Each gun is now a distinct real model (see gun_viewmodels), not one
# shared Pistol_2.glb re-tinted per weapon - so this just shows the one
# matching current_weapon and hides the other two, no material_override
# recoloring needed anymore.
func _update_gun_viewmodel_visibility() -> void:
	pistol_viewmodel.visible = current_weapon == Weapon.PISTOL
	shotgun_viewmodel.visible = current_weapon == Weapon.SHOTGUN
	mac10_viewmodel.visible = current_weapon == Weapon.MAC10

# Knife/unarmed have no gun of their own to fire from, so this falls back
# to the pistol's muzzle point as a generic "hand position" reference -
# matching the previous behavior where muzzle_point was always the one
# shared gun's, regardless of which weapon was actually equipped.
func _current_muzzle_point() -> Marker3D:
	var vm: Node3D = gun_viewmodels.get(current_weapon)
	if vm:
		return vm.get_node("MuzzlePoint")
	return pistol_viewmodel.get_node("MuzzlePoint")

func _current_muzzle_flash() -> MeshInstance3D:
	return _current_muzzle_point().get_node("MuzzleFlash")

func _current_muzzle_light() -> OmniLight3D:
	return _current_muzzle_point().get_node("MuzzleLight")

# Dispatches the left-click / auto-fire action for whichever weapon is
# currently equipped: melee for the knife (no ammo), otherwise fire if the
# mag has rounds, otherwise a dry-fire click.
func _try_fire() -> void:
	if current_weapon == Weapon.UNARMED:
		return
	if current_weapon == Weapon.KNIFE:
		melee_attack()
		fire_cooldown = MELEE_COOLDOWN
		return
	if _current_ammo_in_mag() > 0:
		shoot()
		fire_cooldown = _fire_cooldown_time()
	else:
		_play_empty_click()
		fire_cooldown = _fire_cooldown_time()

func _spread_direction(forward: Vector3, max_degrees: float) -> Vector3:
	var basis := Basis.looking_at(forward, Vector3.UP) if forward != Vector3.UP and forward != -Vector3.UP else Basis()
	var yaw_deg := randf_range(-max_degrees, max_degrees)
	var pitch_deg := randf_range(-max_degrees, max_degrees)
	var spread_basis := basis.rotated(basis.y, deg_to_rad(yaw_deg))
	spread_basis = spread_basis.rotated(spread_basis.x, deg_to_rad(pitch_deg))
	return -spread_basis.z.normalized()

func _fire_ray(origin: Vector3, forward: Vector3, damage: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * RAY_LENGTH)
	query.exclude = [self.get_rid()]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)

	if result:
		var point: Vector3 = result.position
		var hit: Object = result.collider
		var is_damageable: bool = hit and hit.has_method("take_damage")
		# Cars/traffic cars have take_damage too (they explode after enough
		# hits), but they're not alive - only CharacterBody3D targets
		# (Player/NPC/Police) should spray blood; everything else sparks.
		var is_person: bool = is_damageable and hit is CharacterBody3D

		var fx: Node3D = IMPACT_HIT.instantiate() if is_person else IMPACT_EFFECT.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = point

		if is_damageable:
			hit.take_damage(damage, point)
			crosshair.flash_hit()
			_maybe_play_kill_line(hit, is_person)

func shoot() -> void:
	gunshot_player.play()
	_flash_muzzle()

	_set_current_ammo_in_mag(_current_ammo_in_mag() - 1)
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
		origin = _current_muzzle_point().global_position
		forward = model.global_transform.basis.z.normalized()

	if current_weapon == Weapon.SHOTGUN:
		for i in range(SHOTGUN_PELLET_COUNT):
			_fire_ray(origin, _spread_direction(forward, SHOTGUN_SPREAD_DEGREES), SHOTGUN_PELLET_DAMAGE)
	elif current_weapon == Weapon.MAC10:
		_fire_ray(origin, forward, MAC10_DAMAGE)
	else:
		_fire_ray(origin, forward, PISTOL_DAMAGE)

func reload() -> void:
	if reload_timer > 0.0 or current_weapon == Weapon.KNIFE or current_weapon == Weapon.UNARMED:
		return
	if _current_ammo_in_mag() >= _mag_size() or _current_reserve_ammo() <= 0:
		return
	reload_timer = _reload_time_for_current()
	if has_reload_anim:
		anim_tree["parameters/ReloadShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	await get_tree().create_timer(reload_timer).timeout
	var needed: int = _mag_size() - _current_ammo_in_mag()
	var taken: int = min(needed, _current_reserve_ammo())
	_set_current_ammo_in_mag(_current_ammo_in_mag() + taken)
	_set_current_reserve_ammo(_current_reserve_ammo() - taken)
	_update_ammo_label()
	_update_reserve_ammo_label()

func _update_ammo_label() -> void:
	if ammo_label:
		ammo_label.text = "-- / --" if current_weapon == Weapon.KNIFE or current_weapon == Weapon.UNARMED else "%d / %d" % [_current_ammo_in_mag(), _mag_size()]

func _update_reserve_ammo_label() -> void:
	if reserve_ammo_label:
		if current_weapon == Weapon.KNIFE:
			reserve_ammo_label.text = "Knife"
		elif current_weapon == Weapon.UNARMED:
			reserve_ammo_label.text = "Unarmed"
		else:
			reserve_ammo_label.text = "Ammo: %d" % _current_reserve_ammo()

func _update_money_label() -> void:
	if money_label:
		money_label.text = "$%d" % money

func add_money(amount: int) -> void:
	money += amount
	_update_money_label()

func _update_drugs_label() -> void:
	if drugs_label:
		drugs_label.visible = drugs > 0
		drugs_label.text = "Drugs: %d" % drugs

func add_drugs(amount: int) -> void:
	drugs += amount
	_update_drugs_label()

func get_drunk(duration: float) -> void:
	drunk_timer = duration

# Called by any Area3D-based interactable (building_entrance.gd,
# cook_station.gd, store_counter.gd, register.gd, bar_drink.gd) on
# body_entered/exited - "last one entered wins" is fine here since none of
# their trigger volumes are meant to overlap.
func set_nearby_interactable(interactable: Node) -> void:
	nearby_interactable = interactable

func clear_nearby_interactable(interactable: Node) -> void:
	if nearby_interactable == interactable:
		nearby_interactable = null

# Interiors physically live far away in World.tscn (see the *Interior
# groups) rather than being a separate scene or a hide/show toggle on the
# whole exterior - same "just teleport, keep the one Player node alive"
# spirit as the existing vehicle enter/exit, so money/ammo/health/etc. all
# carry over automatically with no save-state plumbing needed.
func enter_building(entrance: Node, exterior_position: Vector3) -> void:
	if current_interior or driving:
		return
	current_interior = entrance
	exterior_return_position = exterior_position
	var spawn: Marker3D = entrance.get_interior_spawn()
	global_position = spawn.global_position
	rotation.y = spawn.rotation.y
	velocity = Vector3.ZERO
	nearby_interactable = null
	interact_prompt_label.visible = false

func exit_building() -> void:
	if not current_interior:
		return
	global_position = exterior_return_position
	velocity = Vector3.ZERO
	current_interior = null

func open_store_menu() -> void:
	menu_open = true
	store_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_store_menu() -> void:
	menu_open = false
	store_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# nearby_interactable is still the DealerCounter that triggered this call
# (interact() runs via nearby_interactable.interact(self) - see _interact()),
# so grabbing it here is how _buy_car() below later finds the right
# showroom's spawn marker without the counter having to pass itself as an arg.
func open_dealer_menu() -> void:
	current_dealer = nearby_interactable
	menu_open = true
	dealer_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_dealer_menu() -> void:
	current_dealer = null
	menu_open = false
	dealer_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func open_npc_menu(npc: Node3D) -> void:
	current_npc = npc
	menu_open = true
	npc_menu_title.text = npc.name
	var is_dealer: bool = npc.get("is_dealer") == true
	var hired: bool = npc.get("hired") == true
	# The dealer is someone you hire to sell FOR you, not a regular
	# civilian - talking/selling to them directly doesn't fit, so they get
	# a dedicated single-button menu instead of the normal talk/sell one.
	talk_button.visible = not is_dealer
	sell_drugs_button.visible = not is_dealer
	sell_drugs_button.disabled = drugs <= 0
	hire_button.visible = is_dealer
	if is_dealer:
		if hired:
			hire_button.text = "Already hired - selling for you"
			hire_button.disabled = true
		else:
			hire_button.text = "Hire - $200"
			hire_button.disabled = money < 200
	npc_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_npc_menu() -> void:
	current_npc = null
	menu_open = false
	npc_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_npc_talk_pressed() -> void:
	if current_npc and is_instance_valid(current_npc) and current_npc.has_method("say_hello"):
		current_npc.say_hello()
	close_npc_menu()

func _on_npc_sell_pressed() -> void:
	if current_npc and is_instance_valid(current_npc):
		_sell_drugs_to(current_npc)
	close_npc_menu()

func _on_npc_hire_pressed() -> void:
	if current_npc and is_instance_valid(current_npc) and current_npc.has_method("hire") and money >= 200:
		money -= 200
		_update_money_label()
		current_npc.hire()
	close_npc_menu()

func _buy_ammo() -> void:
	if money >= AMMO_PRICE:
		money -= AMMO_PRICE
		add_ammo(AMMO_BUY_AMOUNT, "pistol")
		_update_money_label()

func _buy_shotgun() -> void:
	if money >= SHOTGUN_PRICE:
		money -= SHOTGUN_PRICE
		add_ammo(SHOTGUN_BUY_AMOUNT, "shotgun")
		_update_money_label()

func _buy_mac10() -> void:
	if money >= MAC10_PRICE:
		money -= MAC10_PRICE
		add_ammo(MAC10_BUY_AMOUNT, "mac10")
		_update_money_label()

func _buy_red_outfit() -> void:
	if money >= OUTFIT_PRICE:
		money -= OUTFIT_PRICE
		_set_outfit_tint(Color(0.55, 0.12, 0.1))
		_update_money_label()

func _buy_black_outfit() -> void:
	if money >= OUTFIT_PRICE:
		money -= OUTFIT_PRICE
		_set_outfit_tint(Color(0.08, 0.08, 0.09))
		_update_money_label()

func _buy_camaro() -> void:
	_buy_car(CAMARO_PRICE, CAMARO_SCENE)

func _buy_mazda() -> void:
	_buy_car(MAZDA_PRICE, MAZDA_SCENE)

func _buy_rangerover() -> void:
	_buy_car(RANGEROVER_PRICE, RANGEROVER_SCENE)

# Spawns a real, drivable ParkedCar_* at the showroom's own SpawnPoint marker
# (the display models out front are plain scenery with no script, so they
# can't just be "unlocked" - buying hands you a separate car instead) rather
# than teleporting one in on top of the player, which could clip a wall.
func _buy_car(price: int, scene: PackedScene) -> void:
	if money < price:
		return
	if not current_dealer or not is_instance_valid(current_dealer):
		return
	add_money(-price)
	var car: Node3D = scene.instantiate()
	get_tree().current_scene.add_child(car)
	var spawn: Marker3D = current_dealer.get_spawn_marker()
	car.global_position = spawn.global_position
	car.rotation.y = spawn.rotation.y

# Purely cosmetic - same recursive material_override trick police.gd's
# _tint_uniform() uses to fake a uniform on the shared civilian model.
func _set_outfit_tint(color: Color) -> void:
	outfit_tint = color
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_tint_outfit_recursive(model, mat)

func _tint_outfit_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_outfit_recursive(child, mat)

func try_sell_drugs_to_nearby_npc() -> void:
	if drugs <= 0:
		return
	var nearest: Node3D = null
	var nearest_dist := SELL_RANGE
	for npc in get_tree().get_nodes_in_group("civilians"):
		if not is_instance_valid(npc) or npc.dead:
			continue
		var dist: float = global_position.distance_to(npc.global_position)
		if dist < nearest_dist:
			nearest = npc
			nearest_dist = dist
	if not nearest:
		return
	_sell_drugs_to(nearest)

# Shared by the blind nearest-NPC fallback above and the explicit "Sell
# Drugs" button in the NPC talk menu - same undercover-buyer risk either way.
func _sell_drugs_to(npc: Node3D) -> void:
	if drugs <= 0 or npc.get("dead") == true:
		return
	drugs -= 1
	_update_drugs_label()
	add_money(randi_range(SELL_PRICE_MIN, SELL_PRICE_MAX))
	if randf() < SNITCH_CHANCE:
		WantedSystem.add_heat(SNITCH_HEAT, global_position)

# weapon: "pistol" (default), "shotgun", or "mac10". Picking up a weapon for
# the first time grants it and auto-equips it; later pickups just add ammo.
func add_ammo(amount: int, weapon: String = "pistol") -> void:
	match weapon:
		"shotgun":
			var first_pickup := not has_shotgun
			has_shotgun = true
			if first_pickup:
				# Load the mag straight away so a freshly picked-up weapon is
				# immediately ready to fire instead of needing a manual reload first.
				var to_mag: int = min(amount, SHOTGUN_MAG_SIZE)
				shotgun_ammo_in_mag = to_mag
				shotgun_reserve_ammo += amount - to_mag
				switch_weapon(Weapon.SHOTGUN)
			else:
				shotgun_reserve_ammo += amount
		"mac10":
			var first_pickup := not has_mac10
			has_mac10 = true
			if first_pickup:
				var to_mag: int = min(amount, MAC10_MAG_SIZE)
				mac10_ammo_in_mag = to_mag
				mac10_reserve_ammo += amount - to_mag
				switch_weapon(Weapon.MAC10)
			else:
				mac10_reserve_ammo += amount
		_:
			pistol_reserve_ammo += amount
	_update_ammo_label()
	_update_reserve_ammo_label()

func _play_empty_click() -> void:
	var stream := _make_click_sound()
	gunshot_player.stream = stream
	gunshot_player.play()
	gunshot_player.stream = _make_gunshot_sound()

# The knife (weapon slot 1) - no ammo cost, short range, fires via the same
# left-click input as the guns (see _try_fire).
func melee_attack() -> void:
	var stream := _make_punch_sound()
	gunshot_player.stream = stream
	gunshot_player.play()
	gunshot_player.stream = _make_gunshot_sound()

	recoil_pitch += MELEE_RECOIL_KICK

	if has_punch_anim:
		anim_tree["parameters/PunchShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE

	# Always swings toward where the camera/crosshair is actually pointing,
	# unlike hip-fire's character-facing fallback (fine for guns at range,
	# but at knife range even a small facing/look mismatch was an outright
	# whiff). A sphere-shape query centered in front of the player instead
	# of a hairline ray is the actual "bigger hitbox" - it catches anything
	# overlapping a real volume rather than needing to land one exact pixel.
	#
	# The origin has to be the player's own body (muzzle_point), not the
	# camera: this is a third-person over-the-shoulder camera pulled back
	# several units behind the player by the SpringArm, so a cast from
	# camera.global_position at only MELEE_RANGE barely reaches the
	# player's own position, let alone an adjacent enemy - confirmed by
	# direct measurement, not assumed. The camera is still what supplies
	# the aim *direction*, matching the crosshair.
	var origin: Vector3 = _current_muzzle_point().global_position
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()

	var space_state := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = MELEE_HITBOX_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), origin + forward * MELEE_RANGE)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [self.get_rid()]

	# Prefer a person (CharacterBody3D - Player/NPC/Police) over any inanimate
	# object even if it's farther away. Picking whichever's merely CLOSEST let
	# a car parked between the player and their actual target eat the knife
	# hit instead - one solid stab was enough to blow the car up, and its
	# blast radius then killed the person who was never actually hit.
	var hit: Object = null
	var hit_dist := INF
	var hit_is_person := false
	for result in space_state.intersect_shape(query, 8):
		var collider: Object = result.get("collider")
		if not collider or not collider.has_method("take_damage"):
			continue
		var is_person: bool = collider is CharacterBody3D
		if hit_is_person and not is_person:
			continue
		var dist: float = origin.distance_to((collider as Node3D).global_position)
		if is_person and not hit_is_person:
			hit = collider
			hit_dist = dist
			hit_is_person = true
			continue
		if dist < hit_dist:
			hit_dist = dist
			hit = collider

	if hit:
		var point: Vector3 = (hit as Node3D).global_position
		var is_person: bool = hit is CharacterBody3D

		var fx: Node3D = IMPACT_HIT.instantiate() if is_person else IMPACT_EFFECT.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = point

		hit.take_damage(MELEE_DAMAGE, point)
		crosshair.flash_hit()
		_maybe_play_kill_line(hit, is_person)

func _flash_muzzle() -> void:
	var muzzle_flash: MeshInstance3D = _current_muzzle_flash()
	var muzzle_light: OmniLight3D = _current_muzzle_light()
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

func _make_punch_sound() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.09
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var filtered := 0.0
	for i in range(sample_count):
		var t := float(i) / sample_count
		var envelope: float = pow(1.0 - t, 3.0)
		var noise := rng.randf_range(-1.0, 1.0)
		# Heavier low-pass than the gunshot's for a dull thud instead of a crack.
		filtered = filtered * 0.75 + noise * 0.25
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

func try_enter_vehicle() -> bool:
	var nearest: Node3D = null
	var nearest_dist := INTERACT_RANGE
	# "vehicles" (the original drivable Car), "traffic_cars" (patrolling
	# cars - stealable, with an implied driver to throw out), and
	# "parked_vehicles" (stationary until stolen, no driver to eject) are
	# three separate groups because the car-vs-pedestrian damage code
	# elsewhere keys off "vehicles" vs "traffic_cars" to know which speed
	# property to read (RigidBody3D linear_velocity vs a plain speed var) -
	# entry just needs to search all three together.
	for group in ["vehicles", "traffic_cars", "parked_vehicles"]:
		for car in get_tree().get_nodes_in_group(group):
			var dist: float = global_position.distance_to(car.global_position)
			if dist < nearest_dist:
				nearest = car
				nearest_dist = dist
	if nearest:
		enter_vehicle(nearest)
		return true
	return false

func enter_vehicle(car: Node3D) -> void:
	driving = car
	aiming = false
	crosshair.aiming = false
	visible = false
	collision.disabled = true
	# Only the original Car has its own camera to hand off to - stolen
	# traffic/parked cars have none, so the player's own third-person
	# camera just stays active and keeps following (global_position is
	# synced to driver_seat every frame below regardless of vehicle type).
	if car.has_node("CameraPivot"):
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

# Generic version of the pattern above for one-off location voice lines
# (see building_entrance.gd's voice_clips_dir) - scans the folder at
# call time instead of a hardcoded file list, so dropping more .wav files
# in later (some run long, e.g. a ~20s one) just works with no code
# change. Guarded by voice_line_player.playing exactly like the other
# lines here so a long clip can't get cut off by a second entry, and
# can't cut off/overlap whatever line is already playing.
func play_random_voice_clip(dir_path: String) -> void:
	if voice_line_player.playing:
		return
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	var clips: Array = []
	for file_name in dir.get_files():
		if file_name.get_extension().to_lower() == "wav":
			clips.append(dir_path.path_join(file_name))
	if clips.is_empty():
		return
	voice_line_player.stream = load(clips[randi() % clips.size()])
	voice_line_player.play()

func play_cops_incoming_line() -> void:
	if played_cops_incoming_line:
		return
	played_cops_incoming_line = true
	voice_line_player.stream = load(COPS_INCOMING_LINE)
	voice_line_player.play()

# Called right after landing a killing blow on an NPC/Police (never on
# cars/objects) - random pick, chance-gated so it doesn't fire on every
# single kill, and skipped if a voice line is already playing so it can't
# cut itself (or the cops-incoming line) off mid-sentence.
func _maybe_play_kill_line(hit: Object, is_person: bool) -> void:
	if not is_person or voice_line_player.playing:
		return
	if not ("dead" in hit) or not hit.dead:
		return
	if randf() > PLAYER_KILL_LINE_CHANCE:
		return
	voice_line_player.stream = load(PLAYER_KILL_LINES[randi() % PLAYER_KILL_LINES.size()])
	voice_line_player.play()

func take_damage(amount: float, _hit_point: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	health -= amount
	health_bar.value = health
	if health <= 0.0:
		die()
	elif not voice_line_player.playing and randf() < PLAYER_HURT_LINE_CHANCE:
		voice_line_player.stream = load(PLAYER_HURT_LINE)
		voice_line_player.play()

func die() -> void:
	if dead:
		return
	dead = true
	collision.disabled = true

	# A stray hit while browsing either menu (take_damage isn't gated by
	# menu_open) used to leave it stuck on screen over the death screen
	# until restart, since neither menu was ever force-closed here.
	if menu_open:
		close_store_menu()
		close_npc_menu()
		close_dealer_menu()

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
	rain.emitting = Weather.is_raining()
