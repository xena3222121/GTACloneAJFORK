extends Node3D

# Drives the sun position and sky/ambient/fog look from the two global
# clocks (DayNightCycle, Weather) rather than either of those owning any
# rendering state themselves - keeps "what time/weather is it" separate
# from "how does that look".

# Was a clean, saturated postcard-blue sky (0.3, 0.5, 0.85 top / crisp
# near-white horizon) - AJ asked for a GTA IV-esque look, whose Liberty City
# is defined by a hazy, desaturated, slightly warm-gray overcast mood, not
# a bright clear day. Tuned toward that: a muted gray-blue top, a warm smog
# horizon instead of white, and a night horizon with a faint warm glow
# (streetlight light-pollution) instead of clean cool blue.
const DAY_SKY_TOP := Color(0.42, 0.48, 0.55, 1)
const DAY_SKY_HORIZON := Color(0.72, 0.7, 0.65, 1)
const NIGHT_SKY_TOP := Color(0.02, 0.03, 0.08, 1)
const NIGHT_SKY_HORIZON := Color(0.1, 0.08, 0.09, 1)

const DAY_AMBIENT_ENERGY := 0.5
const NIGHT_AMBIENT_ENERGY := 0.12
const DAY_SUN_ENERGY := 0.95
const NIGHT_SUN_ENERGY := 0.05

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var world_env: WorldEnvironment = $WorldEnvironment

# MainMenu.tscn's "Continue" button sets SaveSystem.load_on_next_ready
# before changing to this scene, since it can't load a save into a Player
# that doesn't exist yet - by the time THIS node's _ready() runs, every
# descendant (Player included) has already had its own _ready() called.
func _ready() -> void:
	_setup_urban_grade()
	var player := get_tree().get_first_node_in_group("player")
	if SaveSystem.load_on_next_ready:
		SaveSystem.load_on_next_ready = false
		if player:
			SaveSystem.load_game(player)
	elif player:
		# New Game used to drop the player at whatever spot Player.tscn's
		# own baked transform happened to be (out in the open street) -
		# occasionally right on top of a wandering civilian. Spawning
		# inside the safehouse instead is always clear and matches
		# Continue's own "wake up at the safehouse" spawn.
		_spawn_in_house(player)

# One-time setup for the parts of the GTA IV look that don't need to change
# per-frame the way the day/night lerp below does: color grading (pulled-
# down saturation, a touch more contrast, so nothing reads as postcard-
# bright), a warm-gray fog tint instead of the engine's default blue, and a
# soft glow so streetlights/neon actually bloom at night instead of just
# being flat-lit geometry.
func _setup_urban_grade() -> void:
	var env: Environment = world_env.environment
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.78
	env.adjustment_contrast = 1.08
	env.adjustment_brightness = 0.97
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.fog_light_color = Color(0.55, 0.52, 0.48)
	env.fog_sun_scatter = 0.15
	env.ambient_light_color = Color(0.58, 0.55, 0.5)

	# Ambient occlusion for actual contact shadows/depth where geometry
	# meets (building bases, under cars) instead of everything looking
	# uniformly flat-lit, plus screen-space reflections so glossy car paint
	# and wet rainy streets actually pick up a reflection instead of just
	# being a flat specular highlight.
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.2
	env.ssr_enabled = true
	env.ssr_max_steps = 32

	# Screen-space indirect lighting - bounces light/color off nearby
	# surfaces (a red car casting a faint red tint onto the pavement next to
	# it) instead of every unlit face just falling back to flat ambient.
	# Cheap relative to SSAO/SSR (shares most of the same depth/normal data
	# already being computed for those), reads as a genuinely richer/more
	# "next-gen" look for very little added cost - exactly the kind of
	# thing DLSS's freed-up frame budget is normally spent on, done here
	# without needing DLSS or the performance headroom it buys.
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 1.4

	# ACES is a proper filmic tonemap curve (rolls off highlights instead of
	# hard-clipping them white) - matters now specifically because glow/SSR
	# push more into the bright range than the flat default Linear curve was
	# ever tuned against.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

func _spawn_in_house(player: Node) -> void:
	var house_entrance := get_node_or_null("HouseEntrance")
	if house_entrance and house_entrance.has_method("get_interior_spawn") and player.has_method("enter_building"):
		player.enter_building(house_entrance, house_entrance.global_position)

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
			return 0.002
		Weather.State.RAIN:
			return 0.0045
		_:
			# Was 0.0 (fog fully off on a clear day) - a perfectly crisp sky
			# reads as too clean for the grimy Liberty City look; a faint
			# permanent haze even in "sunny" state is what actually sells it.
			return 0.0008
