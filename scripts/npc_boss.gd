extends "res://scripts/npc.gd"

# Same cross-file animation merge as npc_remy.gd/npc_pete.gd - The Boss's
# Mixamo "Male Locomotion Pack" clips are lightweight skeleton+curve-only
# exports with no mesh at all, only Boss_Model.fbx (his own standalone
# character export) carries the actual mesh. The pack shipped a real Run
# clip for him too, so it's merged directly rather than borrowed from Pete.
const BOSS_IDLE_SOURCE := "res://assets/characters-boss/Boss_Idle.fbx"
const BOSS_WALK_SOURCE := "res://assets/characters-boss/Boss_Walk.fbx"
const BOSS_RUN_SOURCE := "res://assets/characters-boss/Boss_Run.fbx"
const SOURCE_ANIM_NAME := "mixamo_com"

func _merge_clip(lib: AnimationLibrary, target_name: String, source_path: String) -> void:
	if lib.has_animation(target_name):
		return
	var packed: PackedScene = load(source_path)
	var source := packed.instantiate()
	var source_ap: AnimationPlayer = source.find_child("AnimationPlayer", true, false)
	if source_ap and source_ap.has_animation(SOURCE_ANIM_NAME):
		lib.add_animation(target_name, source_ap.get_animation(SOURCE_ANIM_NAME))
	source.free()

func _ready() -> void:
	var m: Node = find_child("Model", false, false)
	var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false) if m else null
	if ap:
		var lib: AnimationLibrary
		if ap.has_animation_library(""):
			lib = ap.get_animation_library("")
		else:
			lib = AnimationLibrary.new()
			ap.add_animation_library("", lib)

		_merge_clip(lib, "Idle", BOSS_IDLE_SOURCE)
		_merge_clip(lib, "Walk", BOSS_WALK_SOURCE)
		_merge_clip(lib, "Run", BOSS_RUN_SOURCE)

	super._ready()
