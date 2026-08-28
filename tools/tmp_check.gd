extends SceneTree
var t := 0
var world: Node
var debug_cam: Camera3D
var light: DirectionalLight3D

func _initialize():
	var world_packed: PackedScene = load("res://scenes/World.tscn")
	world = world_packed.instantiate()
	root.add_child(world)
	current_scene = world

func _process(delta: float) -> bool:
	t += 1
	if t == 60:
		var img: Image = root.get_texture().get_image()
		img.save_png("res://tools/tmp_wide.png")

		var player: Node = world.find_child("Player", true, false)
		var hand: Node3D = player.get_node("Model/HumanArmature/GeneralSkeleton/BoneAttachment3D")
		var hp: Vector3 = hand.global_position

		light = DirectionalLight3D.new()
		root.add_child(light)
		light.light_energy = 1.5
		light.global_position = hp + Vector3(0, 2, 0)
		light.look_at(hp, Vector3.RIGHT)

		debug_cam = Camera3D.new()
		root.add_child(debug_cam)
		debug_cam.fov = 40
		debug_cam.global_position = hp + Vector3(0.4, 0.2, 0.4)
		debug_cam.look_at(hp, Vector3.UP)
		debug_cam.current = true
		return false
	if t == 63:
		var img2: Image = root.get_texture().get_image()
		img2.save_png("res://tools/tmp_close.png")
		print("done")
		quit()
		return true
	return false
