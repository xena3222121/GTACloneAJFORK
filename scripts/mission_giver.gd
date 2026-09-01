extends Area3D

# The Fixer - a fixed point near the safehouse that hands out MissionSystem's
# ordered story jobs one at a time. Same body_entered/interact plumbing as
# job_board.gd; the actual target-picking and completion checking lives in
# the MissionSystem autoload since a mission can outlive the player walking
# away from this kiosk (e.g. driving a stolen car clear across town).

var prompt_text := "Press E to talk to the Fixer"

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	MissionSystem.mission_started.connect(_on_mission_started)
	MissionSystem.mission_completed.connect(_on_mission_ended)
	MissionSystem.mission_aborted.connect(_on_mission_ended)
	_update_prompt()

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)

func interact(player: Node3D) -> void:
	if MissionSystem.active_mission:
		return
	MissionSystem.start_mission(player)

func _on_mission_started(_mission: Dictionary) -> void:
	_update_prompt()

func _on_mission_ended(_arg = null) -> void:
	_update_prompt()

func _update_prompt() -> void:
	if MissionSystem.active_mission:
		prompt_text = "Mission in progress - check your objective"
	elif MissionSystem.has_next_mission():
		prompt_text = "Press E to talk to the Fixer"
	else:
		prompt_text = "The Fixer has no more work for you"
