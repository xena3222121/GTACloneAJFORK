extends Node3D

# Drives the sun position and sky/ambient/fog look from the two global
# clocks (DayNightCycle, Weather) rather than either of those owning any
# rendering state themselves - keeps "what time/weather is it" separate
# from "how does that look".

const DAY_SKY_TOP := Color(0.3, 0.5, 0.85, 1)
const DAY_SKY_HORIZON := Color(0.75, 0.85, 0.95, 1)
const NIGHT_SKY_TOP := Color(0.02, 0.03, 0.08, 1)
const NIGHT_SKY_HORIZON := Color(0.05, 0.07, 0.15, 1)

const DAY_AMBIENT_ENERGY := 0.6
const NIGHT_AMBIENT_ENERGY := 0.12
const DAY_SUN_ENERGY := 1.1
const NIGHT_SUN_ENERGY := 0.05

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var world_env: WorldEnvironment = $WorldEnvironment

func _process(_delta: float) -> void:
	var t: float = DayNightCycle.time_of_day
	var angle: float = (t / 24.0 - 0.25) * TAU
	sun.rotation.x = -angle
	sun.rotation.y = 0.3

	var brightness: float = clamp(DayNightCycle.sun_altitude(), 0.0, 1.0)
	var weather_dim: float = _weather_dim()

	sun.light_energy = lerp(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, brightness) * weather_dim

	var env: Environment = world_env.environment
	env.ambient_light_energy = lerp(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, brightness) * weather_dim

	var sky_mat: ProceduralSkyMaterial = env.sky.sky_material
	sky_mat.sky_top_color = NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, brightness)
	sky_mat.sky_horizon_color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, brightness)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color

	var fog_density: float = _fog_density()
	env.fog_enabled = fog_density > 0.0
	env.fog_density = fog_density

func _weather_dim() -> float:
	match Weather.state:
		Weather.State.CLOUDY:
			return 0.7
		Weather.State.RAIN:
			return 0.5
		_:
			return 1.0

func _fog_density() -> float:
	match Weather.state:
		Weather.State.CLOUDY:
			return 0.0015
		Weather.State.RAIN:
			return 0.004
		_:
			return 0.0
