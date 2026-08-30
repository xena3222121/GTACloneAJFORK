extends Node

# Second autoload (after WantedSystem). No save/load system existed at all
# before this - every stat reset to defaults on every launch. Plain JSON in
# user:// rather than a Resource/.tres save, since the state here is just a
# flat bag of numbers - no need for Godot's class-serialization machinery.

const SAVE_PATH := "user://savegame.json"

# Set by MainMenu.tscn's "Continue" button before changing scene to
# World.tscn, then consumed (and cleared) by world_sky.gd's _ready() once
# the fresh scene (and its Player) actually exists to load into.
var load_on_next_ready := false

# Fallback only, if HouseEntrance somehow isn't found (see load_game below) -
# its exterior door position, at actual ground height rather than the
# door trigger's own chest-height y.
const LOAD_SPAWN_POSITION := Vector3(7.3, 0.1, 0.0)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func _find_weed_plot(player: Node) -> Node:
	return player.get_tree().get_first_node_in_group("weed_plot")

# Not its own group - there's only ever one, and job_board.gd already finds
# it the same way (filtering "civilians" by is_dealer) rather than adding a
# dedicated group for a single node.
func _find_dealer(player: Node) -> Node:
	for npc in player.get_tree().get_nodes_in_group("civilians"):
		if npc.get("is_dealer") == true:
			return npc
	return null

func save_game(player: Node) -> void:
	var weed := _find_weed_plot(player)
	var dealer := _find_dealer(player)
	var data := {
		"money": player.money,
		"drugs": player.drugs,
		"health": player.health,
		"current_weapon": player.current_weapon,
		"has_shotgun": player.has_shotgun,
		"has_mac10": player.has_mac10,
		"pistol_ammo_in_mag": player.pistol_ammo_in_mag,
		"pistol_reserve_ammo": player.pistol_reserve_ammo,
		"shotgun_ammo_in_mag": player.shotgun_ammo_in_mag,
		"shotgun_reserve_ammo": player.shotgun_reserve_ammo,
		"mac10_ammo_in_mag": player.mac10_ammo_in_mag,
		"mac10_reserve_ammo": player.mac10_reserve_ammo,
		"weed_state": weed.state if weed else 0,
		"weed_planted_at": weed.planted_at if weed else 0,
		"dealer_hired": dealer.hired if dealer else false,
		"outfit_tint": player.outfit_tint.to_html(true),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

# Returns true on success. Deliberately does NOT restore world/wanted state
# (heat resets to 0, NPCs/police/loot are wherever the fresh scene puts
# them) - only carries over the player's own stats, matching how "continue"
# already behaves after a restart in most GTA-likes.
func load_game(player: Node) -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed

	player.money = data.get("money", player.money)
	player.drugs = data.get("drugs", player.drugs)
	player.health = data.get("health", player.health)
	player.has_shotgun = data.get("has_shotgun", player.has_shotgun)
	player.has_mac10 = data.get("has_mac10", player.has_mac10)
	player.pistol_ammo_in_mag = data.get("pistol_ammo_in_mag", player.pistol_ammo_in_mag)
	player.pistol_reserve_ammo = data.get("pistol_reserve_ammo", player.pistol_reserve_ammo)
	player.shotgun_ammo_in_mag = data.get("shotgun_ammo_in_mag", player.shotgun_ammo_in_mag)
	player.shotgun_reserve_ammo = data.get("shotgun_reserve_ammo", player.shotgun_reserve_ammo)
	player.mac10_ammo_in_mag = data.get("mac10_ammo_in_mag", player.mac10_ammo_in_mag)
	player.mac10_reserve_ammo = data.get("mac10_reserve_ammo", player.mac10_reserve_ammo)
	player.current_weapon = data.get("current_weapon", player.current_weapon)

	var weed := _find_weed_plot(player)
	if weed:
		weed.state = data.get("weed_state", weed.state)
		weed.planted_at = data.get("weed_planted_at", weed.planted_at)

	var dealer := _find_dealer(player)
	if dealer and data.get("dealer_hired", false):
		dealer.hire()

	var outfit_html: String = data.get("outfit_tint", "")
	if outfit_html != "" and player.has_method("_set_outfit_tint"):
		var tint := Color.html(outfit_html)
		if tint.a > 0.0:
			player._set_outfit_tint(tint)

	# Wake up inside the safehouse itself (classic GTA "you wake up at the
	# safehouse" behavior) rather than preserving exact mid-street
	# position/orientation across a session boundary - going through
	# enter_building() (instead of a bare position assignment) is what
	# actually sets current_interior/exterior_return_position too, so
	# pressing E to leave works immediately rather than the player being
	# visually inside but the game still thinking they're outside.
	var house_entrance := player.get_tree().current_scene.get_node_or_null("HouseEntrance")
	if house_entrance and house_entrance.has_method("get_interior_spawn") and player.has_method("enter_building"):
		player.enter_building(house_entrance, house_entrance.global_position)
	else:
		player.global_position = LOAD_SPAWN_POSITION
	return true
