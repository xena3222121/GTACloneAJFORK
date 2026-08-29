extends Node

# Global clock. AJ asked for a full day/night cycle where one full day takes
# 24 real minutes (1 in-game hour per 1 real minute), so it roughly mirrors
# a real day's pacing while staying short enough to actually see change in
# a play session. Other systems (world_sky.gd, weather.gd) read time_of_day
# / sun_altitude() rather than owning any clock logic themselves.

const DAY_LENGTH_SECONDS := 24.0 * 60.0
const HOURS_PER_SECOND := 24.0 / DAY_LENGTH_SECONDS
const NIGHT_START := 20.0
const NIGHT_END := 6.0

signal hour_changed(hour: int)

var time_of_day := 8.0 # start mid-morning
var _last_hour := 8

func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + HOURS_PER_SECOND * delta, 24.0)
	var h := int(time_of_day)
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)

func is_night() -> bool:
	return time_of_day >= NIGHT_START or time_of_day < NIGHT_END

# Smooth 0..1 day/night brightness curve (peaks at solar noon, bottoms at
# midnight) rather than a hard on/off cut, so dawn/dusk actually transition.
func sun_altitude() -> float:
	return (sin((time_of_day / 24.0 - 0.25) * TAU) + 1.0) / 2.0
