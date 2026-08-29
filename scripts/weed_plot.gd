extends Area3D

# Real-time stand-in for "a day" - this project has no day/night cycle yet
# (same trick cook_station.gd uses for its real 8s "cook a batch" timer,
# just a much longer wait to match the GTA-style "plant it, come back later"
# fantasy). Uses wall-clock time rather than a running in-scene timer so the
# plant keeps growing across a save/reload instead of resetting.
const GROW_TIME_SECONDS := 300.0
const YIELD_MIN := 4
const YIELD_MAX := 8

enum State { EMPTY, GROWING, READY }

var state: int = State.EMPTY
var planted_at: int = 0
var prompt_text := "Press E to plant weed seeds"

func _ready() -> void:
	add_to_group("weed_plot")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_refresh()

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func _process(_delta: float) -> void:
	_refresh()

func _elapsed() -> int:
	return Time.get_unix_time_from_system() - planted_at

func _refresh() -> void:
	if state == State.GROWING:
		var remaining: int = int(max(0.0, GROW_TIME_SECONDS - _elapsed()))
		if remaining <= 0:
			state = State.READY
		else:
			prompt_text = "Growing... ready in %dm %ds" % [remaining / 60, remaining % 60]
	if state == State.EMPTY:
		prompt_text = "Press E to plant weed seeds"
	elif state == State.READY:
		prompt_text = "Press E to harvest the weed"

func interact(player: Node3D) -> void:
	match state:
		State.EMPTY:
			state = State.GROWING
			planted_at = Time.get_unix_time_from_system()
		State.READY:
			if player.has_method("add_drugs"):
				player.add_drugs(randi_range(YIELD_MIN, YIELD_MAX))
			state = State.EMPTY
		State.GROWING:
			pass
	_refresh()
