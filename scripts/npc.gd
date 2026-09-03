class_name NPC
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

# The city used to feel like a shooting gallery - civilians stood around
# wandering their own idle loop no matter how much gunfire or how many car
# bombs went off next to them. scare_nearby() is called from player.gd's
# shoot() and from car.gd/parked_car.gd's explode() so any civilian in
# earshot breaks off whatever they were doing and runs.
const PANIC_RADIUS := 14.0
const PANIC_SPEED := 3.4
const PANIC_DURATION := 3.5
# How far a newly-panicking civilian's own scream spooks whoever's standing
# right next to them - smaller than PANIC_RADIUS so it doesn't just
# rebroadcast the original blast/gunshot radius from every panicking body,
# but enough for panic to ripple further through a clustered crowd (Prism's
# patrons, the Downtown plaza) than the original source alone could reach.
const RIPPLE_RADIUS := 6.0
const PANIC_AUDIO_CLIPS := [
	"res://Audio/Arnold/NPC Getting attacked/ahhhhhhhh.wav",
	"res://Audio/Arnold/NPC Getting attacked/oh fml im getting attacked.wav",
	"res://Audio/Arnold/NPC Getting attacked/Oh No This Guys Crazy.wav",
]

const VEHICLE_HIT_MIN_SPEED := 2.0
const VEHICLE_HIT_DAMAGE_PER_SPEED := 4.0
const VEHICLE_HIT_MAX_DAMAGE := 80.0
# A flat knockback added straight to velocity used to get stomped the very
# next physics tick by _process_wander/_process_hostile setting
# velocity.x/z outright - looked like a shove, not a hit. Routed through
# launch() (below) instead, same as the stolen-car-eject impulse, so the
# stun timer actually blocks normal movement AI from overwriting it and
# gravity carries the arc through properly.
const VEHICLE_HIT_KNOCKBACK_BASE := 5.0
const VEHICLE_HIT_KNOCKBACK_PER_SPEED := 0.55
const VEHICLE_HIT_LAUNCH_UP := 4.5
const VEHICLE_HIT_STUN_TIME := 1.4
const VEHICLE_HIT_COOLDOWN := 0.6

const BLOOD_POOL := preload("res://scenes/BloodPool.tscn")
const MONEY_PICKUP := preload("res://scenes/MoneyPickup.tscn")

# Extra Mixamo clips pulled in on top of whatever the character's own model
# ships with, same cross-file retarget trick npc_pete.gd/npc_josh.gd/player.gd
# already use (every Mixamo download shares the same skeleton/bone names, so
# a clip exported for one character's rig plays back correctly on any other).
# Sourced from Pete's own "Action Adventure Pack" (assets/characters-pete/)
# since it's the one download in this project with real variety already sitting
# unused - Pete himself gets perfect-fidelity playback since these ARE his own
# files; every other character gets the same clips retargeted onto their rig.
const EXTRA_ANIM_SOURCE_NAME := "mixamo_com"
const HIT_REACT_SOURCE := "res://assets/characters-pete/Pete_FallingIdle.fbx"
const RUN_SOURCE := "res://assets/characters-pete/Pete_Run.fbx"
const IDLE_VARIANT_SOURCES := [
	"res://assets/characters-pete/Pete_Idle2.fbx",
	"res://assets/characters-pete/Pete_Idle3.fbx",
	"res://assets/characters-pete/Pete_Idle4.fbx",
	"res://assets/characters-pete/Pete_Idle5.fbx",
]

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
# Overrides CHATTER_AUDIO_CLIPS with a folder scan instead - e.g. Prism's
# patrons (World.tscn) get "NPC Random In Gay Club" set here so they bark
# club-appropriate lines instead of generic street chatter. Scanned at
# call time (not cached) so dropping more .wav files in later just works.
@export var chatter_clips_dir: String = ""
const CHATTER_CHANCE := 0.12

# Swaps hit/panic AND chatter audio together to an alternate voice pack -
# e.g. "res://Audio/Female" for the female NPC variants, which mirrors
# Audio/Arnold's own "NPC Getting attacked"/"Random Lines" subfolder layout.
# Leave empty to keep the default Arnold-voiced consts. chatter_clips_dir
# above still wins if BOTH are set (e.g. a female club patron keeps the
# club-specific chatter, but still screams in her own voice when hit).
@export var voice_pack_dir: String = ""

# A dealer NPC (see is_dealer below) sells drugs out in the world for the
# player once hired. A second "street" body (see _spawn_street_dealer)
# spawns near the player's house door and visibly wanders while THIS NPC -
# the one actually standing in the house, who the player talks to - keeps
# the sell timer/payout/catch logic, so hiring or bailing out never depends
# on chasing down wherever the street body has wandered off to.
const HIRE_COST := 200
const DEALER_SELL_INTERVAL := 45.0
const DEALER_SALE_PRICE := 50
const DEALER_CUT := 10 # the dealer's pay - player nets SALE_PRICE - CUT per sale
const DEALER_CATCH_CHANCE := 0.05
const DEALER_BRIBE_COST := 50
# load(), not preload() - NPC_A.tscn's own script IS npc.gd, so a preload
# here is a circular dependency (this file depends on a scene that depends
# on this file). The editor tolerates it, but it broke resource loading
# for this whole script in an actual exported build (confirmed via a real
# export - a huge cascade of "can't load dependency" errors traced back to
# exactly this line) - not just this one constant failing, the entire
# script failed to load, which then affects everything else in the
# exported game.
static var _street_dealer_scene: PackedScene
static func _get_street_dealer_scene() -> PackedScene:
	if not _street_dealer_scene:
		_street_dealer_scene = load("res://scenes/NPC_A.tscn")
	return _street_dealer_scene

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
# Only set true on Prism's 6 patrons (World.tscn's NightClubInterior) -
# read by player.gd's _sell_drugs_to() so pill sales to an actual club
# patron never risk a snitch, per AJ (nobody in the club is undercover).
@export var is_club_patron := false
var hostile := false
var attack_cooldown := 0.0

# Only meaningful when is_dealer is true (an opt-in per-instance flag, same
# pattern as is_bar_patron above) - a hireable civilian who, once paid,
# quietly sells the player's drugs for them over time instead of the player
# walking it to a stranger themselves.
@export var is_dealer := false
# Fixture NPCs stuffed into a small, fully-furnished interior room (the
# house's dealer, standing behind a counter, etc.) have nowhere to actually
# wander - WANDER_RADIUS routinely picks a point past that room's walls,
# and with no obstacle avoidance the NPC just walks into the wall forever
# and never arrives, looking permanently stuck. Set false to have them
# stand in place instead.
@export var wanders := true
var panicking := false
var panic_timer := 0.0
var flee_dir := Vector3.ZERO
var hired := false
# Set by player.gd's _rob_npc - one attempt per person, so reopening the
# same NPC's menu can't just be farmed for infinite money.
var robbed := false
var jailed := false
var street_dealer: Node3D = null
# True only on the wandering street body _spawn_street_dealer() creates -
# it's just a visible proxy the player can see out dealing; without this
# guard its own is_dealer/hired (set so ITS menu also reads "already
# hired") would make _physics_process run a second, duplicate sell timer.
var is_street_proxy := false
var dealer_sell_timer := 0.0
var patron_aggro_timer := 0.0
var player: Node3D = null
var vehicle_hit_cooldown := 0.0
var eject_stun_timer := 0.0
# Set right before take_damage() by whatever actually dealt the hit, so
# die() only raises the player's wanted heat when the player caused it -
# a civilian run over by ambient AI traffic (or another car's driver)
# used to blame the player just because they died near one.
var killed_by_player := false
var chatter_audio: AudioStreamPlayer3D
var chatter_timer := 0.0
var interact_zone: Area3D
var prompt_text := "Press E to talk"

var anim_idle := ""
var anim_walk := ""
var anim_die := ""
var anim_run := ""
var anim_hit_react := ""
var idle_variants: Array = []

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

# Unlike _play() above, always restarts from frame 0 even if this is already
# the current animation - needed for a one-off reaction (getting launched by
# a car) that has to replay in full each time it's triggered, not silently
# no-op because the last stun already left current_animation on this name.
func _play_once(anim_name: String) -> void:
	if anim and anim_name != "":
		anim.stop()
		anim.play(anim_name)

func _merge_external_clip(lib: AnimationLibrary, target_name: String, source_path: String) -> void:
	if lib.has_animation(target_name):
		return
	var packed: PackedScene = load(source_path)
	if not packed:
		return
	var source := packed.instantiate()
	var source_ap: AnimationPlayer = source.find_child("AnimationPlayer", true, false)
	if source_ap and source_ap.has_animation(EXTRA_ANIM_SOURCE_NAME):
		lib.add_animation(target_name, source_ap.get_animation(EXTRA_ANIM_SOURCE_NAME))
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

	_merge_external_clip(lib, "Run", RUN_SOURCE)
	anim_run = "Run" if anim.has_animation("Run") else anim_walk
	_force_loop(anim_run)

	for i in range(IDLE_VARIANT_SOURCES.size()):
		var target_name := "Idle%d" % (i + 2)
		_merge_external_clip(lib, target_name, IDLE_VARIANT_SOURCES[i])
		if anim.has_animation(target_name):
			idle_variants.append(target_name)

# Called from the idle branch of _process_wander/_process_panic settling back
# down - mostly the plain looping idle, but occasionally one of Pete's other
# idle poses (checking phone, stretching, etc.) so a street full of civilians
# doesn't read as the same handful of characters stuck in the same loop.
func _pick_idle_anim() -> String:
	if idle_variants.is_empty() or randf() > 0.4:
		return anim_idle
	return idle_variants[randi() % idle_variants.size()]

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
		_load_extra_animations()
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

	if is_dealer:
		prompt_text = "Press E to talk to the dealer"

func _pick_new_target() -> void:
	var angle := randf() * TAU
	var dist := randf() * WANDER_RADIUS
	target_position = home_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

# Called from wherever violence happens (player.gd's shoot(), car.gd/
# parked_car.gd's explode()) rather than civilians polling for danger every
# frame - a one-shot broadcast to whoever's in earshot is cheaper and reacts
# the instant the gun goes off instead of on the next check interval.
static func scare_nearby(tree: SceneTree, source_position: Vector3, radius: float = PANIC_RADIUS) -> void:
	for body in tree.get_nodes_in_group("civilians"):
		if is_instance_valid(body) and body.global_position.distance_to(source_position) <= radius:
			body.panic(source_position)
	# Same broadcast also panic-brakes nearby ambient traffic (see
	# traffic_car.gd's panic_brake) - one shared "something scary just
	# happened here" call instead of every gunfire/explosion/death site
	# needing to separately notify both civilians and traffic.
	for car in tree.get_nodes_in_group("traffic_cars"):
		if is_instance_valid(car) and car.has_method("panic_brake") and car.global_position.distance_to(source_position) <= radius:
			car.panic_brake()

# Functional civilians (a hired dealer, their visible street proxy) keep
# doing their job instead of running off - and anyone already fighting
# (hostile) or already fleeing ignores a second, weaker scare.
func panic(source_position: Vector3) -> void:
	if dead or hostile or panicking or is_dealer or is_street_proxy:
		return
	panicking = true
	panic_timer = PANIC_DURATION
	var away := global_position - source_position
	away.y = 0.0
	flee_dir = away.normalized() if away.length() > 0.01 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
	if not chatter_audio.playing:
		# voice_pack_dir NPCs reuse their (already varied) hit-clip pool for
		# panic too, rather than needing a second, smaller recorded set.
		var clips: Array = _hit_clips() if voice_pack_dir != "" else PANIC_AUDIO_CLIPS
		if not clips.is_empty():
			chatter_audio.stream = load(clips[randi() % clips.size()])
			chatter_audio.play()
	NPC.scare_nearby(get_tree(), global_position, RIPPLE_RADIUS)

func _physics_process(delta: float) -> void:
	if dead:
		return

	if is_dealer and hired and not is_street_proxy:
		_process_dealer(delta)

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
		# Getting launched by a car used to just freeze whatever anim was
		# already playing (idle/walk) while the body sailed through the air -
		# looked like a glitch, not a hit. This sells the airborne
		# tumble/bounce for the whole stun window instead.
		_play(anim_hit_react)
		move_and_slide()
		_check_vehicle_collisions()
		return

	if hostile and player and is_instance_valid(player):
		_process_hostile(delta)
	elif panicking:
		_process_panic(delta)
	else:
		if wanders:
			_process_wander(delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
		_check_ambient_chatter(delta)
		if is_bar_patron:
			_check_patron_aggro(delta)

	move_and_slide()
	_check_vehicle_collisions()

# Called by traffic_car.gd when this NPC gets thrown out of a stolen car.
func launch(impulse: Vector3, stun_duration: float = 1.1) -> void:
	velocity = impulse
	eject_stun_timer = stun_duration

# Pedestrian-initiated side: cars never used to look for pedestrians
# themselves, so this runs from the pedestrian's own move_and_slide()
# results. Only catches a car that the NPC itself moved into/through -
# see register_vehicle_hit() for the car-initiated side (a moving car
# ramming a stationary NPC, which never shows up in this NPC's own slide
# collisions since the NPC never moved).
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

# Called either from _check_vehicle_collisions above (this NPC moved into a
# car) or directly by parked_car.gd/traffic_car.gd when THEIR own
# move_and_collide rams a stationary NPC - a StaticBody3D/AnimatableBody3D
# driven car never pushes a CharacterBody3D the way a real RigidBody3D
# (car.gd) does, so without this direct call a standing-still NPC getting
# rammed would just silently block the car and take no hit at all.
func register_vehicle_hit(car: Object, car_speed: float) -> void:
	if dead or vehicle_hit_cooldown > 0.0 or car_speed < VEHICLE_HIT_MIN_SPEED:
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

func _process_wander(delta: float) -> void:
	var to_target := target_position - global_position
	to_target.y = 0

	if idle_timer > 0.0:
		idle_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
	elif to_target.length() < ARRIVE_DIST:
		idle_timer = randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)
		_play(_pick_idle_anim())
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

# Called by player.gd's _on_npc_hire_pressed after it's already deducted
# HIRE_COST - this NPC doesn't need to know the price, just that it's paid.
func hire() -> void:
	hired = true
	jailed = false
	dealer_sell_timer = DEALER_SELL_INTERVAL
	prompt_text = "Your dealer - selling for you"
	_spawn_street_dealer()

# Called by player.gd's _on_dealer_bribe_pressed after it's already deducted
# DEALER_BRIBE_COST.
func bail_out() -> void:
	jailed = false
	dealer_sell_timer = DEALER_SELL_INTERVAL
	prompt_text = "Your dealer - selling for you"
	_spawn_street_dealer()

# The visible half of "hire a dealer" - a body that actually walks out the
# door and wanders the block near the player's house, so hiring reads as
# more than just a number ticking up. Spawned fresh each time (on hire and
# again after a bail-out) since the previous one gets queue_free'd on
# getting caught.
func _spawn_street_dealer() -> void:
	if street_dealer and is_instance_valid(street_dealer):
		return
	var world := get_tree().current_scene
	var door := world.get_node_or_null("HouseEntrance")
	# Exterior ground level is y=0.1 (see any street NPC's transform) -
	# HouseEntrance itself sits at y=1, the door-trigger's chest height, so
	# spawning directly at its position would drop the dealer in mid-air.
	var spawn_pos: Vector3 = Vector3(door.global_position.x, 0.1, door.global_position.z) if door else global_position
	var body: Node3D = _get_street_dealer_scene().instantiate()
	# Position set before add_child (matches wanted_system.gd's reinforcement
	# spawner) - _ready() runs the instant it enters the tree and latches
	# home_position from wherever it's standing then, so setting position
	# after add_child would have it wander around the scene's default
	# instantiate spot instead of near the house.
	body.position = spawn_pos
	body.wanders = true
	body.is_dealer = true
	body.hired = true
	body.is_street_proxy = true
	world.add_child(body)
	street_dealer = body

# Passive income once hired: periodically sells one unit of the player's
# drugs on their behalf (no need to actually path to a buyer - the street
# body wandering around already sells the idea), same undercover-buyer
# risk framing as selling in person, just now with a flat chance the
# dealer gets caught in the act instead of a snitch raising the player's
# own heat - selling pauses until the player bails them out.
func _process_dealer(delta: float) -> void:
	if jailed:
		return
	dealer_sell_timer -= delta
	if dealer_sell_timer > 0.0:
		return
	dealer_sell_timer = DEALER_SELL_INTERVAL
	var player := get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player) or player.get("drugs") == null or player.drugs <= 0:
		return
	player.add_drugs(-1)
	player.add_money(DEALER_SALE_PRICE - DEALER_CUT)
	if randf() < DEALER_CATCH_CHANCE:
		_get_caught()

func _get_caught() -> void:
	jailed = true
	prompt_text = "Your dealer got busted - pay $%d to bail them out" % DEALER_BRIBE_COST
	if street_dealer and is_instance_valid(street_dealer):
		street_dealer.queue_free()
	street_dealer = null

# Reuses the ambient-chatter clip pool (see CHATTER_AUDIO_CLIPS) - only one
# line exists to draw from right now, same limitation as the ambient bark.
func say_hello() -> void:
	if chatter_audio.playing:
		return
	var clips: Array = _get_chatter_clips()
	if clips.is_empty():
		return
	chatter_audio.stream = load(clips[randi() % clips.size()])
	chatter_audio.play()

# Folder scan when chatter_clips_dir is set (per-instance override, e.g.
# club patrons) or voice_pack_dir names an alternate voice's "Random Lines"
# subfolder, otherwise the shared default list.
func _get_chatter_clips() -> Array:
	if chatter_clips_dir != "":
		return _scan_wav_folder(chatter_clips_dir)
	if voice_pack_dir != "":
		return _scan_wav_folder(voice_pack_dir.path_join("Random Lines"))
	return CHATTER_AUDIO_CLIPS

func _hit_clips() -> Array:
	if voice_pack_dir == "":
		return HIT_AUDIO_CLIPS
	return _scan_wav_folder(voice_pack_dir.path_join("NPC Getting attacked"))

func _scan_wav_folder(folder_path: String) -> Array:
	var clips: Array = []
	var dir := DirAccess.open(folder_path)
	if dir:
		for file_name in dir.get_files():
			# Exported builds list "name.wav.import" here instead of
			# "name.wav" (the real audio data moves under .godot/imported/
			# at export time) - strip that suffix before checking the
			# extension, or this always comes back empty in an exported
			# build and no voice line ever plays.
			var real_name: String = file_name.trim_suffix(".import")
			if real_name.get_extension().to_lower() != "wav":
				continue
			var full_path: String = folder_path.path_join(real_name)
			if not clips.has(full_path):
				clips.append(full_path)
	return clips

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
		var clips: Array = _get_chatter_clips()
		if clips.is_empty():
			return
		chatter_audio.stream = load(clips[randi() % clips.size()])
		chatter_audio.play()

# Runs flat-out away from wherever the scare came from for PANIC_DURATION,
# no pathing or obstacle-avoidance (same simple direct-velocity approach as
# _process_wander) - then drops back to normal wandering from wherever it
# ended up.
func _process_panic(delta: float) -> void:
	panic_timer -= delta
	if panic_timer <= 0.0:
		panicking = false
		_pick_new_target()
		return
	velocity.x = flee_dir.x * PANIC_SPEED
	velocity.z = flee_dir.z * PANIC_SPEED
	var target_yaw := atan2(flee_dir.x, flee_dir.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 8.0 * delta)
	_play(anim_run)

func _process_hostile(delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0
	var dist := to_player.length()

	if dist > MELEE_RANGE:
		var dir := to_player.normalized()
		velocity.x = dir.x * CHASE_SPEED
		velocity.z = dir.z * CHASE_SPEED
		_play(anim_run)
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
	# Consumed immediately so an unrelated later hit (e.g. car-explosion
	# blast damage, which never sets this) can't inherit a stale true from
	# whatever last set it.
	var by_player := killed_by_player
	killed_by_player = false
	_play_hit_audio()
	health -= amount
	if health <= 0.0:
		die(by_player)

func _play_hit_audio() -> void:
	if hit_audio.playing:
		return
	var clips: Array = _hit_clips()
	if clips.is_empty():
		return
	hit_audio.stream = load(clips[randi() % clips.size()])
	hit_audio.play()

func die(by_player: bool = false) -> void:
	dead = true
	collision.disabled = true
	interact_zone.monitoring = false
	var p := get_tree().get_first_node_in_group("player")
	if p and p.get("nearby_interactable") == self:
		p.clear_nearby_interactable(self)
	_play(anim_die)
	_spawn_blood_pool()
	_maybe_drop_money()
	# scare_nearby is also called directly from gunfire/explosions (see
	# player.gd/car.gd), but a knife kill or a run-over is silent - this is
	# what makes THOSE scatter a crowd too, not just louder deaths.
	NPC.scare_nearby(get_tree(), global_position)
	if by_player:
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
