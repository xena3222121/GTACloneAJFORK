extends "res://scripts/npc.gd"

# Flair only has one animation clip so far (his own native "mixamo_com" -
# no separate walk file yet, like Josh before his walk was added). Just
# aliases it to "Idle" in the model's own default library so npc.gd's
# existing _find_anim("idle") keyword lookup finds it - no cross-file merge
# needed since, unlike James/Josh/Pete, everything's already in one file.
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

	super._ready()
