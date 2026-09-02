extends "res://scripts/npc.gd"

# Josh's dance clip (his Model's own native animation, doubling as his idle)
# and his walk each come from separate Mixamo downloads sharing his skeleton -
# same cross-file merge npc_josh needs that player.gd already does for James.
# Copied into the model's own default ("") library under "Idle"/"Walk" so
# npc.gd's existing _find_anim("idle")/_find_anim("walk") keyword lookup
# picks them up with no changes to the shared script.
const JOSH_WALK_SOURCE := "res://assets/characters-josh/Josh_Walk.fbx"
const SOURCE_ANIM_NAME := "mixamo_com"

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

		if ap.has_animation(SOURCE_ANIM_NAME) and not lib.has_animation("Idle"):
			lib.add_animation("Idle", ap.get_animation(SOURCE_ANIM_NAME))

		if not lib.has_animation("Walk"):
			var packed: PackedScene = load(JOSH_WALK_SOURCE)
			var source := packed.instantiate()
			var source_ap: AnimationPlayer = source.find_child("AnimationPlayer", true, false)
			if source_ap and source_ap.has_animation(SOURCE_ANIM_NAME):
				lib.add_animation("Walk", source_ap.get_animation(SOURCE_ANIM_NAME))
			source.free()

	super._ready()
