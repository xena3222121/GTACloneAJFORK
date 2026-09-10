extends "res://scripts/police.gd"

# A rival crew's soldier, holding down a district for whoever owns it (see
# faction_system.gd). Deliberately a SUBCLASS of police.gd rather than a
# second combat AI written from scratch: the cop already wanders a post,
# spots the player with line-of-sight checks, trades fire, staggers when
# hit, gets launched by cars, drops loot and dies properly. Only the parts
# that are specifically POLICE get replaced here - the radio heat, the
# siren, the badge, the "this is the police" line, and the rule that a cop
# only aggros on a player who is already wanted.

# Gunfire is still gunfire - a shootout between crews draws some police
# attention, just nowhere near what shooting an actual officer does.
const CREW_HEAT_SCALE := 0.25
# An enforcer is standing on his own crew's corner, so he is looking for
# trouble in a way a patrolling cop isn't.
const TURF_DETECTION_BONUS := 5.0

# Set by faction_system.gd before the node enters the tree, so _ready()'s
# tint pass (inherited from police.gd) already has the crew's colors.
var faction_id := ""
var faction_name := ""
var faction_color := Color(0.75, 0.15, 0.18)
var district_name := ""

func _ready() -> void:
	super()
	# WantedSystem drives the "police" group directly - it alerts every
	# member when a crime is reported and stands them all down when the
	# player escapes. An enforcer must not be part of the police response,
	# so it leaves that group and gets its own.
	remove_from_group("police")
	add_to_group("gang_enforcers")
	# Police.tscn's gold badge prop is bone-attached to the shared model.
	# Nothing else in that scene reads as "cop" once the uniform is retinted.
	var badge := get_node_or_null("Model/Skeleton3D/BadgeAttachment/Badge")
	if badge:
		badge.visible = false
	# police.gd's _physics_process starts a siren the moment it goes hostile.
	# There's no separate "hostile gangster" audio to swap in, so the sound
	# is simply taken out rather than left blaring off a street thug.
	siren_audio.volume_db = -80.0

# Crew colors instead of navy/black. Called by police.gd's own _ready() via
# normal virtual dispatch, so the base class needs no knowledge of factions.
func _tint_uniform() -> void:
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = faction_color
	var pants := StandardMaterial3D.new()
	pants.albedo_color = faction_color.darkened(0.7)
	_tint_surfaces(model, {"Shirt": shirt, "Pants": pants, "Details": shirt})

func _report_crime(amount: float) -> void:
	WantedSystem.add_heat(amount * CREW_HEAT_SCALE, global_position)

func _report_sighting() -> void:
	# A rival watching the player is not a police sighting, and must not keep
	# an unrelated wanted level from decaying.
	pass

func _engage() -> void:
	# Same one-shot engagement latch as the cop's (see police.gd) minus the
	# "this is the police" voice line - AJ records these himself and there
	# are no crew lines yet, so an enforcer engages silently.
	if hostile:
		return
	hostile = true
	alerted = false

func _check_proactive_detection() -> void:
	# The cop version only joins an incident already in progress
	# (WantedSystem.heat > 0). On rival turf, the player being there IS the
	# incident. Holstering everything still reads as "not a threat" - the
	# same signal police.gd honors - so a district can be walked through
	# unarmed without starting a fight.
	if not player or not is_instance_valid(player):
		return
	if _player_is_unarmed():
		return
	var to_player := player.global_position - global_position
	if to_player.length() <= _effective_detection_range() + TURF_DETECTION_BONUS \
			and _has_line_of_sight(player.global_position):
		_engage()

func die(by_player: bool = false) -> void:
	super(by_player)
	FactionSystem.report_enforcer_killed(self, by_player)
