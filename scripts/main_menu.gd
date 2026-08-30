extends Control

# The game used to boot straight into World.tscn with no menu at all - no
# way to see if a save existed, no clean way to quit. This is now
# run/main_scene (see project.godot).

@onready var main_buttons: VBoxContainer = $VBox
@onready var continue_button: Button = $VBox/ContinueButton
@onready var new_game_button: Button = $VBox/NewGameButton
@onready var settings_button: Button = $VBox/SettingsButton
@onready var quit_button: Button = $VBox/QuitButton
@onready var settings_menu: Control = $SettingsMenu

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	continue_button.visible = SaveSystem.has_save()
	continue_button.pressed.connect(_on_continue_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_menu.visible = false
	settings_menu.closed.connect(_on_settings_closed)

func _on_continue_pressed() -> void:
	SaveSystem.load_on_next_ready = true
	get_tree().change_scene_to_file("res://scenes/World.tscn")

func _on_new_game_pressed() -> void:
	SaveSystem.load_on_next_ready = false
	get_tree().change_scene_to_file("res://scenes/World.tscn")

func _on_settings_pressed() -> void:
	main_buttons.visible = false
	settings_menu.visible = true

func _on_settings_closed() -> void:
	settings_menu.visible = false
	main_buttons.visible = true

func _on_quit_pressed() -> void:
	get_tree().quit()
