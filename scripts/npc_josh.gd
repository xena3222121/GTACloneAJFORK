extends "res://scripts/npc.gd"

# Josh's dance clip (his Model's own native animation, doubling as his idle)
# and his walk each come from separate Mixamo downloads sharing his skeleton -
# same cross-file merge npc_josh needs that player.gd already does for James.
# Copied into the model's own default ("") library under "Idle"/"Walk" so
# npc.gd's existing _find_anim("idle")/_find_anim("walk") keyword lookup
# picks them up with no changes to the shared script.
const JOSH_WALK_SOURCE := "res://assets/characters-josh/Josh_Walk.fbx"
const SOURCE_ANIM_NAME := "mixamo_com"
# No second real dance clip exists anywhere in this project (Josh_Dance.fbx
# is the only "dance"-anything file there is) - a genuinely new move needs a
# new Mixamo download, not something reachable from in here. This is the
# closest achievable stand-in: a retargeted jump read as a hop/beat-drop
# move, cycling in via the same idle-variety system every other NPC uses.
const JUMP_SOURCE := "res://assets/characters-pete/Pete_Jump.fbx"

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

	# His own Dance loop is already far more dynamic than the generic idle-
	# variety pool every other NPC gets (Pete's casual "check phone"/stretch
	# poses) - splicing those in would look like he randomly stopped
	# dancing to check a text. Swap that pool out for a retargeted jump
	# instead, so what cycles in actually reads as another dance beat.
	idle_variants.clear()
	if anim:
		var lib: AnimationLibrary = anim.get_animation_library("")
		_merge_external_clip(lib, "DanceHop", JUMP_SOURCE)
		if anim.has_animation("DanceHop"):
			idle_variants.append("DanceHop")
