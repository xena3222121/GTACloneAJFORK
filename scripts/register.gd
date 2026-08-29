extends Area3D

const COOLDOWN := 60.0
const PAYOUT_MIN := 80
const PAYOUT_MAX := 150
const ROBBERY_HEAT := 25.0
const IDLE_PROMPT := "Press E to rob the register"
const EMPTY_PROMPT := "Register's empty - come back later"

var prompt_text := IDLE_PROMPT
var cooldown_timer := 0.0

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
	if cooldown_timer > 0.0:
		cooldown_timer = max(0.0, cooldown_timer - delta)
		prompt_text = EMPTY_PROMPT
	else:
		prompt_text = IDLE_PROMPT

func interact(player: Node3D) -> void:
	if cooldown_timer > 0.0:
		return
	cooldown_timer = COOLDOWN
	if player.has_method("add_money"):
		player.add_money(randi_range(PAYOUT_MIN, PAYOUT_MAX))
	WantedSystem.add_heat(ROBBERY_HEAT, global_position)
