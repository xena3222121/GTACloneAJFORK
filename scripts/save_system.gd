extends Node

# Second autoload (after WantedSystem). No save/load system existed at all
# before this - every stat reset to defaults on every launch. Plain JSON in
# user:// rather than a Resource/.tres save, since the state here is just a
# flat bag of numbers - no need for Godot's class-serialization machinery.

const SAVE_PATH := "user://savegame.json"

# Where the player lands on a loaded game - just outside the safehouse door
# (HouseEntrance's own position in World.tscn), matching classic GTA "you
# wake up at the safehouse" behavior rather than trying to preserve exact
# mid-street position/orientation across a session boundary.
const LOAD_SPAWN_POSITION := Vector3(7.3, 1.0, 0.0)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(player: Node) -> void:
	var weed := player.get_tree().get_first_node_in_group("weed_plot")
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

	var weed := player.get_tree().get_first_node_in_group("weed_plot")
	if weed:
		weed.state = data.get("weed_state", weed.state)
		weed.planted_at = data.get("weed_planted_at", weed.planted_at)

	player.global_position = LOAD_SPAWN_POSITION
	return true
