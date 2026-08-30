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
@onready var save_button: Button = $Panel/VBox/SaveButton
@onready var quit_to_menu_button: Button = $Panel/VBox/QuitToMenuButton
@onready var quit_button: Button = $Panel/VBox/QuitButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	settings_menu.visible = false
	resume_button.pressed.connect(_resume)
	settings_button.pressed.connect(_open_settings)
	save_button.pressed.connect(_on_save_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	quit_button.pressed.connect(func(): get_tree().quit())
	settings_menu.closed.connect(_on_settings_closed)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if visible and settings_menu.visible:
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

func _resume() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_settings() -> void:
	main_panel.visible = false
	settings_menu.visible = true

func _on_settings_closed() -> void:
	settings_menu.visible = false
	main_panel.visible = true

func _on_save_pressed() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		SaveSystem.save_game(player)
		save_button.text = "Saved!"

func _on_quit_to_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
