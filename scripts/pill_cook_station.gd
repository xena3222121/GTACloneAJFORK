extends Area3D

# Same cook-a-batch-over-time pattern as cook_station.gd, but gated on 2
# ingredients (bought at the Convenience Store's ingredient_shelf.gd)
# consumed per batch instead of being free/unlimited like weed.
const COOK_TIME := 8.0
const YIELD_MIN := 2
const YIELD_MAX := 4
const IDLE_PROMPT := "Press E to cook boner pills (needs 1 Blue Oyster Dust + 1 Horse Semen)"
const MISSING_PROMPT := "Need 1 Blue Oyster Dust + 1 Horse Semen to cook"

var prompt_text := IDLE_PROMPT
var cooking := false
var cook_timer := 0.0
var cooking_player: Node3D = null

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
	if not cooking:
		return
	cook_timer -= delta
	if cook_timer <= 0.0:
		cooking = false
		if cooking_player and is_instance_valid(cooking_player) and cooking_player.has_method("add_pills"):
			cooking_player.add_pills(randi_range(YIELD_MIN, YIELD_MAX))
		cooking_player = null
		prompt_text = IDLE_PROMPT

func interact(player: Node3D) -> void:
	if cooking:
		return
	if player.get("blue_oyster_dust") == null or player.blue_oyster_dust <= 0 \
			or player.get("horse_semen") == null or player.horse_semen <= 0:
		prompt_text = MISSING_PROMPT
		return
	player.blue_oyster_dust -= 1
	player.horse_semen -= 1
	cooking = true
	cook_timer = COOK_TIME
	cooking_player = player
	prompt_text = "Cooking..."
