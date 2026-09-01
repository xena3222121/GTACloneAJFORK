extends Node3D

# The city-kit GLB models (building-a/b/c) render with no color at all - a
# flat, blank white - regardless of which building they're used for. Rather
# than depend on fixing whatever's wrong with that import, this just paints
# the whole model with a real material the same way job_board.gd tints a
# contract target: recursive material_override down every MeshInstance3D.
# Was a clean warm tan (0.75, 0.72, 0.66) - darkened and desaturated a
# notch, plus a bit more roughness, for the grimier GTA IV concrete/brick
# look AJ asked for. Buildings with their own per-instance albedo override
# (see World.tscn's Downtown) are untouched - this only shifts the default
# any building falls back to.
@export var albedo := Color(0.66, 0.62, 0.56)
@export var roughness := 0.9
@export var metallic := 0.0

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	_tint_recursive(self, mat)

func _tint_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_recursive(child, mat)
