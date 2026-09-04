extends Node

# Music is the one system this project genuinely doesn't have yet. The
# obvious next move would be to synthesize a loop the same way gunshots/
# sirens are synthesized elsewhere in this project - but city_ambience.gd
# already tried exactly that for the city hum/honk and threw it out (see
# that file's own comment): procedural noise read as a crude bass rumble,
# not something that belongs in a soundtrack. Real music needs an actual
# composed/licensed track, not code, so this only wires up the fade/switch
# logic and waits for real files - drop a CC0/CC-BY instrumental loop at
# each path below (opengameart.org and itch.io's game-music packs are a
# good place to start) and it starts playing with zero other code changes.
# Either file is optional - whichever exists plays; if only one exists it
# just stays audible through both states rather than going silent.
const AMBIENT_TRACK_PATH := "res://Audio/Music/ambient.ogg"
const CHASE_TRACK_PATH := "res://Audio/Music/chase.ogg"

const FADE_SPEED := 8.0
const AMBIENT_VOLUME := -16.0
const CHASE_VOLUME := -10.0
const SILENT := -80.0
# Matches WantedSystem's own tier numbering (0..3) - "chase music" kicks in
# from the same heat level that already starts calling in reinforcements
# (see wanted_system.gd's MIN_SPAWN_HEAT/tier 2 territory).
const CHASE_TIER_THRESHOLD := 2

@onready var ambient_player: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var chase_player: AudioStreamPlayer = AudioStreamPlayer.new()

var _has_ambient := false
var _has_chase := false

func _ready() -> void:
	add_child(ambient_player)
	add_child(chase_player)
	ambient_player.bus = "Master"
	chase_player.bus = "Master"
	ambient_player.volume_db = SILENT
	chase_player.volume_db = SILENT

	_has_ambient = ResourceLoader.exists(AMBIENT_TRACK_PATH)
	_has_chase = ResourceLoader.exists(CHASE_TRACK_PATH)
	if _has_ambient:
		_start_looping(ambient_player, AMBIENT_TRACK_PATH)
	if _has_chase:
		_start_looping(chase_player, CHASE_TRACK_PATH)

func _start_looping(player: AudioStreamPlayer, path: String) -> void:
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	player.stream = stream
	player.play()

func _process(delta: float) -> void:
	if not _has_ambient and not _has_chase:
		return
	var chasing: bool = WantedSystem.get_tier() >= CHASE_TIER_THRESHOLD
	var ambient_target: float = SILENT
	var chase_target: float = SILENT
	if _has_ambient and (not chasing or not _has_chase):
		ambient_target = AMBIENT_VOLUME
	if _has_chase and (chasing or not _has_ambient):
		chase_target = CHASE_VOLUME
	ambient_player.volume_db = move_toward(ambient_player.volume_db, ambient_target, FADE_SPEED * delta)
	chase_player.volume_db = move_toward(chase_player.volume_db, chase_target, FADE_SPEED * delta)
