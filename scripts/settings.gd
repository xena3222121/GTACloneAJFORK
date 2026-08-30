extends Node

# Global settings (separate from savegame.json - these aren't "game progress",
# they should survive even a fresh New Game). No settings existed at all
# before this - every audio bus was at whatever hardcoded volume_db each
# script picked, with zero player-facing control.

const SETTINGS_PATH := "user://settings.json"

var master_volume: float = 1.0 # 0..1 linear, applied to the Master bus
var fullscreen: bool = false

func _ready() -> void:
	_load()
	_apply()

func _apply() -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply()
	_save()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply()
	_save()

func _save() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"master_volume": master_volume,
			"fullscreen": fullscreen,
		}))
		file.close()

func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	master_volume = parsed.get("master_volume", master_volume)
	fullscreen = parsed.get("fullscreen", fullscreen)
