extends "res://scripts/npc.gd"

# Same cross-file animation merge as npc_josh.gd, but Pete's asset pack is
# shaped differently from James/Josh's: it's Mixamo's bundled "Action
# Adventure Pack" zip, where the 22 individual animation clips (idle,
# walking, running, cover/sneak, etc.) are lightweight skeleton+curve-only
# exports with NO mesh at all - only Pete_Model.fbx (the pack's one full
# character export) carries the actual mesh, so Model must point there, not
# at Pete_Idle.fbx (confirmed by inspecting both - Pete_Idle.fbx's node tree
# has zero MeshInstance3D children). Idle/Walk are still pulled from their
# own dedicated clip files rather than Pete_Model's own native animation,
# for the same real-Idle-pose-vs-rest-pose reason as James/Josh.
const PETE_IDLE_SOURCE := "res://assets/characters-pete/Pete_Idle.fbx"
const PETE_WALK_SOURCE := "res://assets/characters-pete/Pete_Walk.fbx"
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

		_merge_clip(lib, "Idle", PETE_IDLE_SOURCE)
		_merge_clip(lib, "Walk", PETE_WALK_SOURCE)

	super._ready()
