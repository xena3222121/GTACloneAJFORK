extends Control

# process_mode is set to ALWAYS in the scene - this is the one node in the
# whole game that needs to keep receiving input and rendering while
# get_tree().paused is true (everything else - player, cops, traffic,
# ambience, the day/night clock - correctly just freezes, which is exactly
# what a real pause should do; none of that needed any special-casing).
#
# All Escape-key handling lives here rather than in player.gd, precisely
# because player.gd's own _unhandled_input stops firing the instant the
# game is paused (it's an ordinary PAUSABLE node) - a handler split between
# the two would mean "press Escape to resume" never reaching anything.

@onready var main_panel: Control = $Panel
@onready var settings_menu: Control = $SettingsMenu
@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var settings_button: Button = $Panel/VBox/SettingsButton
@onready var map_button: Button = $Panel/VBox/MapButton
@onready var save_button: Button = $Panel/VBox/SaveButton
@onready var quit_to_menu_button: Button = $Panel/VBox/QuitToMenuButton
@onready var quit_button: Button = $Panel/VBox/QuitButton
@onready var close_map_button: Button = $CloseMapButton

# Minimap lives as a sibling under HUD (see Player.tscn - HUD/Minimap next
# to HUD/PauseMenu), rendering the same live 3D scene the main camera does
# via a SubViewport with own_world_3d = false. Rather than building a whole
# second map system, the pause map just temporarily blows up that same
# control to fill most of the screen and zooms its camera way out - cheap,
# and it's already centered on the player (MinimapCamera's own _process,
# which follows the player and applies the GTA-style facing rotation,
# freezes the instant the game pauses, same as everything else, so by the
# time this runs the camera is already sitting still exactly where the
# player was) - just fixed back to north-up here since a reference map you
# read while stopped should stay oriented to north, not whatever direction
# you happened to be facing when you paused.
@onready var minimap: Control = get_parent().get_node("Minimap")
@onready var minimap_camera: Camera3D = minimap.get_node("ViewportContainer/SubViewport/MinimapCamera")

const MAP_VIEW_SIZE := 320.0 # Camera3D.size while the full map is open (vs MinimapCamera's own small default)

var minimap_original_anchors: Array = []
var minimap_original_offsets: Array = []
var map_open := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	settings_menu.visible = false
	minimap_original_anchors = [minimap.anchor_left, minimap.anchor_top, minimap.anchor_right, minimap.anchor_bottom]
	minimap_original_offsets = [minimap.offset_left, minimap.offset_top, minimap.offset_right, minimap.offset_bottom]
	resume_button.pressed.connect(_resume)
	settings_button.pressed.connect(_open_settings)
	map_button.pressed.connect(_open_map)
	close_map_button.pressed.connect(_close_map)
	save_button.pressed.connect(_on_save_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	quit_button.pressed.connect(func(): get_tree().quit())
	settings_menu.closed.connect(_on_settings_closed)

func _unhandled_input(event: InputEvent) -> void:
	var is_escape: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	# JOY_BUTTON_START is Godot's generic name for whatever sits in that slot
	# on the physical pad - Options on a PS4/PS5 controller, Menu on Xbox.
	var is_options: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START
	if not (is_escape or is_options):
		return
	if visible and map_open:
		_close_map()
	elif visible and settings_menu.visible:
		_on_settings_closed()
	elif visible:
		_resume()
	else:
		_open()
	get_viewport().set_input_as_handled()

func _open() -> void:
	var player := get_tree().get_first_node_in_group("player")
	# Don't stack the pause menu on top of the Store/NPC menu, or open it
	# over the death screen - both already have their own way out.
	if player and (player.get("menu_open") == true or player.get("dead") == true):
		return
	visible = true
	main_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()

func _resume() -> void:
	if map_open:
		_close_map()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_settings() -> void:
	main_panel.visible = false
	settings_menu.visible = true
	settings_menu.focus_default()

func _on_settings_closed() -> void:
	settings_menu.visible = false
	main_panel.visible = true
	resume_button.grab_focus()

func _open_map() -> void:
	main_panel.visible = false
	close_map_button.visible = true
	map_open = true
	minimap.anchor_left = 0.1
	minimap.anchor_top = 0.1
	minimap.anchor_right = 0.9
	minimap.anchor_bottom = 0.9
	minimap.offset_left = 0.0
	minimap.offset_top = 0.0
	minimap.offset_right = 0.0
	minimap.offset_bottom = 0.0
	minimap_camera.size = MAP_VIEW_SIZE
	minimap_camera.rotation_degrees = Vector3(-90, 0, 0)
	close_map_button.grab_focus()

func _close_map() -> void:
	map_open = false
	close_map_button.visible = false
	main_panel.visible = true
	minimap.anchor_left = minimap_original_anchors[0]
	minimap.anchor_top = minimap_original_anchors[1]
	minimap.anchor_right = minimap_original_anchors[2]
	minimap.anchor_bottom = minimap_original_anchors[3]
	minimap.offset_left = minimap_original_offsets[0]
	minimap.offset_top = minimap_original_offsets[1]
	minimap.offset_right = minimap_original_offsets[2]
	minimap.offset_bottom = minimap_original_offsets[3]
	minimap_camera.size = minimap_camera.MAP_SIZE
	resume_button.grab_focus()

func _on_save_pressed() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		SaveSystem.save_game(player)
		save_button.text = "Saved!"

func _on_quit_to_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
