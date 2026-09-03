extends Node

# Global settings (separate from savegame.json - these aren't "game progress",
# they should survive even a fresh New Game). No settings existed at all
# before this - every audio bus was at whatever hardcoded volume_db each
# script picked, with zero player-facing control.

const SETTINGS_PATH := "user://settings.json"

var master_volume: float = 1.0 # 0..1 linear, applied to the Master bus
var fullscreen: bool = false
# FSR upscaling (Godot's built-in equivalent to DLSS/FSR-on-console - AJ
# asked about "DLSS type shit" specifically; true DLSS needs Nvidia's
# proprietary SDK compiled into the engine itself, not something reachable
# from project/script code, so this is the actual available version of that
# idea). Renders the 3D scene at a lower internal resolution and
# reconstructs it back up to full size - a real performance/sharpness
# tradeoff, which is why it's an opt-in setting rather than just switched on
# silently like the SSAO/SSR/glow upgrades in world_sky.gd.
var performance_mode: bool = false
const FSR_SCALE := 0.77 # roughly FSR's own "Quality" preset ratio

func _ready() -> void:
	_setup_controller_ui_input()
	_load()
	_apply()

# The engine's default ui_up/ui_down already include a d-pad/stick binding,
# but ui_accept and ui_cancel ship with only keyboard events - so a
# controller could navigate between a menu's buttons (see grab_focus calls
# in player.gd/pause_menu.gd) but had no bound button that could actually
# press one. Added once here rather than per-menu since every Control-based
# menu in the game shares these two actions.
func _setup_controller_ui_input() -> void:
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A # X on PlayStation, A on Xbox
	InputMap.action_add_event("ui_accept", accept)

	var cancel := InputEventJoypadButton.new()
	cancel.button_index = JOY_BUTTON_B # Circle on PlayStation, B on Xbox
	InputMap.action_add_event("ui_cancel", cancel)

func _apply() -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	var vp := get_viewport()
	if vp:
		if performance_mode:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = FSR_SCALE
		else:
			vp.scaling_3d_scale = 1.0

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply()
	_save()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply()
	_save()

func set_performance_mode(enabled: bool) -> void:
	performance_mode = enabled
	_apply()
	_save()

func _save() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"master_volume": master_volume,
			"fullscreen": fullscreen,
			"performance_mode": performance_mode,
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
	performance_mode = parsed.get("performance_mode", performance_mode)
	fullscreen = parsed.get("fullscreen", fullscreen)
