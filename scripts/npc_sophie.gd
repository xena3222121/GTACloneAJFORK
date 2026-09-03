extends "res://scripts/npc.gd"

# Ch02.fbx - Mixamo keeps its own generic internal "Ch##" node naming
# regardless of what a character was actually named when customized/exported
# (confirmed by inspecting Megan_Model.tscn's own node tree: internally
# "Ch22" despite the file being named for Megan - same project, same
# pattern), so there's no way to positively confirm this is "Sophie" from
# the file alone. It's the one clearly female, unused character sitting in
# assets/characters-female-tmp/ with no NPC ever built for it - if this
# isn't actually her, it's a one-line swap of IDLE_SOURCE etc. below plus a
# new Model ext_resource in NPC_Sophie.tscn.
#
# Unlike James/Josh/Pete's own per-character downloads, this file ships only
# a single-frame T-pose ("mixamo_com" here is degenerate - length 0.033s,
# not a real clip; confirmed by sampling a hand bone's position across the
# whole clip and finding it doesn't move at all). Every locomotion animation
# is borrowed and retargeted from elsewhere via npc.gd's existing
# cross-character retarget system (_merge_external_clip/_retarget_clip) -
# the same mechanism every NPC already uses for HitReact/Run/Land, just
# also covering Idle/Walk/Death here since nothing native exists to fall
# back on.
const IDLE_SOURCE := "res://assets/characters-pete/Pete_Idle.fbx"
const WALK_SOURCE := "res://assets/characters-pete/Pete_Walk.fbx"
const DEATH_SOURCE := "res://assets/characters-female-tmp/Megan_Death.fbx"

func _ready() -> void:
	if anim:
		var lib: AnimationLibrary
		if anim.has_animation_library(""):
			lib = anim.get_animation_library("")
		else:
			lib = AnimationLibrary.new()
			anim.add_animation_library("", lib)
		# Merged under these target names (containing "idle"/"walk"/"death")
		# BEFORE super._ready() runs, so its own _find_anim() keyword lookup
		# picks them up with no other changes needed.
		_merge_external_clip(lib, "Idle", IDLE_SOURCE)
		_merge_external_clip(lib, "Walk", WALK_SOURCE)
		_merge_external_clip(lib, "Death", DEATH_SOURCE)

	super._ready()
