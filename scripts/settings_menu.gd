extends Control

# Reusable settings panel - instanced from both MainMenu.tscn and the
# in-game PauseMenu so there's one shared implementation instead of two
# copies drifting apart.

signal closed

@onready var volume_slider: HSlider = $Panel/VBox/VolumeSlider
@onready var fullscreen_check: CheckButton = $Panel/VBox/FullscreenCheck
@onready var performance_check: CheckButton = $Panel/VBox/PerformanceCheck
@onready var back_button: Button = $Panel/VBox/BackButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	volume_slider.value = Settings.master_volume
	fullscreen_check.button_pressed = Settings.fullscreen
	performance_check.button_pressed = Settings.performance_mode
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	performance_check.toggled.connect(_on_performance_toggled)
	back_button.pressed.connect(_on_back_pressed)

func _on_volume_changed(value: float) -> void:
	Settings.set_master_volume(value)

func _on_fullscreen_toggled(enabled: bool) -> void:
	Settings.set_fullscreen(enabled)

func _on_performance_toggled(enabled: bool) -> void:
	Settings.set_performance_mode(enabled)

func _on_back_pressed() -> void:
	closed.emit()

# Called by whichever menu (MainMenu/PauseMenu) just made this visible -
# nothing had focus by default, so a controller had no control to
# navigate from or press.
func focus_default() -> void:
	volume_slider.grab_focus()
