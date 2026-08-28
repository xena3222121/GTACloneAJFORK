extends CharacterBody3D

const WALK_SPEED := 1.8
const WANDER_RADIUS := 3.0
const ARRIVE_DIST := 0.6
const IDLE_TIME_MIN := 1.5
const IDLE_TIME_MAX := 4.0
const MAX_HEALTH := 150.0

const BLOOD_POOL := preload("res://scenes/BloodPool.tscn")

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

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var home_position: Vector3
var target_position: Vector3
var idle_timer := 0.0
var health := MAX_HEALTH
var dead := false

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

func _pick_new_target() -> void:
	var angle := randf() * TAU
	var dist := randf() * WANDER_RADIUS
	target_position = home_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func _physics_process(delta: float) -> void:
	if dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

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

	move_and_slide()

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
	_play(anim_die)
	_spawn_blood_pool()

func _spawn_blood_pool() -> void:
	var pool: Node3D = BLOOD_POOL.instantiate()
	get_tree().current_scene.add_child(pool)
	pool.global_position = Vector3(global_position.x, 0.02, global_position.z)
	pool.rotation.y = randf() * TAU
	pool.scale = Vector3.ONE * randf_range(0.8, 1.3)
