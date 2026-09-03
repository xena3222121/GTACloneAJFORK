extends "res://scripts/npc.gd"

# Ch28.fbx - found unused alongside Ch02.fbx (see npc_sophie.gd's identical
# note on this). Nobody asked for a specific new male character, so "Derek"
# is just a placeholder name picked to have something other than "Ch28" in
# the UI - rename npc_derek.gd/NPC_Derek.tscn freely if a different name is
# wanted, nothing else depends on it.
#
# Same situation as Sophie: only a single-frame T-pose stub natively (no
# real "mixamo_com" clip - confirmed the same way, a hand bone that never
# moves across the reported 0.033s clip), so Idle/Walk/Death are all
# borrowed and retargeted from elsewhere via npc.gd's existing cross-
# character retarget system.
const IDLE_SOURCE := "res://assets/characters-pete/Pete_Idle.fbx"
const WALK_SOURCE := "res://assets/characters-pete/Pete_Walk.fbx"
const DEATH_SOURCE := "res://assets/characters-james/James_Death.fbx"

func _ready() -> void:
	if anim:
		var lib: AnimationLibrary
		if anim.has_animation_library(""):
			lib = anim.get_animation_library("")
		else:
			lib = AnimationLibrary.new()
			anim.add_animation_library("", lib)
		_merge_external_clip(lib, "Idle", IDLE_SOURCE)
		_merge_external_clip(lib, "Walk", WALK_SOURCE)
		_merge_external_clip(lib, "Death", DEATH_SOURCE)

	super._ready()
