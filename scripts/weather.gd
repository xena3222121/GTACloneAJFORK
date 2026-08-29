extends Node

# Global weather state. AJ asked for random weather, weighted mostly sunny
# with a low chance of rain - re-rolled periodically rather than fixed for
# the whole session. Other systems (world_sky.gd, player.gd's rain emitter,
# city_ambience.gd's rain layer) react to state_changed rather than owning
# any weather logic themselves.

enum State { SUNNY, CLOUDY, RAIN }

const CHECK_INTERVAL := 180.0 # reroll roughly every 3 real minutes
const WEIGHTS := {
	State.SUNNY: 0.7,
	State.CLOUDY: 0.2,
	State.RAIN: 0.1,
}

signal state_changed(state: int)

var state: int = State.SUNNY
var _timer := 0.0

func _ready() -> void:
	_timer = CHECK_INTERVAL

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_INTERVAL
		_reroll()

func _reroll() -> void:
	var total := 0.0
	for w in WEIGHTS.values():
		total += w
	var roll := randf() * total
	var acc := 0.0
	var new_state: int = State.SUNNY
	for s in WEIGHTS:
		acc += WEIGHTS[s]
		if roll <= acc:
			new_state = s
			break
	if new_state != state:
		state = new_state
		state_changed.emit(state)

func is_raining() -> bool:
	return state == State.RAIN
