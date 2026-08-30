extends Area3D

# A vending-style shelf at the Convenience Store - press E, pay, get 1 unit.
# Generic over which ingredient: ingredient_key must match one of the
# match cases in player.gd's add_ingredient() ("blue_oyster_dust" or
# "horse_semen"), display_name is just for the prompt text.
@export var ingredient_key: String = ""
@export var display_name: String = ""
@export var price: int = 20

var prompt_text := ""

func _ready() -> void:
	prompt_text = "Press E to buy %s - $%d" % [display_name, price]
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func interact(player: Node3D) -> void:
	if player.get("money") == null or player.money < price:
		return
	player.add_money(-price)
	if player.has_method("add_ingredient"):
		player.add_ingredient(ingredient_key, 1)
