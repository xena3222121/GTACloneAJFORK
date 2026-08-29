extends Area3D

const IDLE_PROMPT := "Press E to save your game"
const SAVED_PROMPT := "Game saved"
const SAVED_PROMPT_TIME := 2.0

var prompt_text := IDLE_PROMPT
var saved_flash_timer := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func _process(delta: float) -> void:
	if saved_flash_timer > 0.0:
		saved_flash_timer -= delta
		if saved_flash_timer <= 0.0:
			prompt_text = IDLE_PROMPT

func interact(player: Node3D) -> void:
	SaveSystem.save_game(player)
	prompt_text = SAVED_PROMPT
	saved_flash_timer = SAVED_PROMPT_TIME
