extends "res://scripts/npc.gd"

# Same cross-file animation merge as npc_pete.gd - Remy's Mixamo "Male
# Locomotion Pack" clips are lightweight skeleton+curve-only exports with no
# mesh at all, only Remy_Model.fbx (Remy's own standalone character export)
# carries the actual mesh. Unlike Pete, the pack shipped a real Run clip for
# Remy himself, so it's merged directly here rather than falling back to
# npc.gd's generic borrowed-from-Pete retarget.
const REMY_IDLE_SOURCE := "res://assets/characters-remy/Remy_Idle.fbx"
const REMY_WALK_SOURCE := "res://assets/characters-remy/Remy_Walk.fbx"
const REMY_RUN_SOURCE := "res://assets/characters-remy/Remy_Run.fbx"
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

		_merge_clip(lib, "Idle", REMY_IDLE_SOURCE)
		_merge_clip(lib, "Walk", REMY_WALK_SOURCE)
		_merge_clip(lib, "Run", REMY_RUN_SOURCE)

	super._ready()
