class_name CarPaint
extends RefCounted

# Every FBX car in car-kit-realistic (NormalCar1/2, SUV, Taxi, SportsCar,
# SportsCar2 - used everywhere: traffic, decorative parked cars, and the
# player's own starter car) imported with completely flat default
# materials on every surface: metallic=0, roughness=1, body paint and glass
# and chrome trim all the same dead-matte finish. Only the pack's .glb
# models (Camaro, MazdaRX7, RangeRover) kept their authored PBR values.
#
# Fixed once per car instance at _ready() rather than by hand-editing the
# imported resource, for two reasons: Godot's FBX importer regenerates that
# flat default from the source file, so a hand-edit wouldn't survive a
# re-import; and every traffic/parked car of the same model shares one
# imported Mesh resource, so repainting it in place would give every
# NormalCar1 in the city the exact same recolor instead of each its own.
#
# The "already has real PBR" check below is also what keeps this from ever
# touching Camaro/Mazda/RangeRover - no per-model name-checking needed, a
# material that isn't sitting at the untouched default is left exactly as
# its own artist set it up.

const GLOSS_ROUGHNESS := 0.3
const GLOSS_METALLIC := 0.25
const TRIM_ROUGHNESS := 0.35
const TRIM_METALLIC := 0.55
const GLASS_ROUGHNESS := 0.08
const GLASS_METALLIC := 0.15
const LENS_ROUGHNESS := 0.15
const LENS_METALLIC := 0.2

# The closed set of non-paint surface names actually found across the six
# flat-default FBX cars (Windows/Black/Grey/Headlights/TailLights on all of
# them, "Material.007" a stray trim piece on NormalCar2 only). Anything
# else hitting the untouched-default fingerprint is treated as body paint -
# this is what lets a two-tone car like SportsCar (Orange + DarkOrange)
# recolor both surfaces together rather than needing them named up front.
const TRIM_NAMES := ["Black", "Grey", "Material.007"]
const GLASS_NAMES := ["Windows"]
const LENS_NAMES := ["Headlights", "TailLights"]

# recolor=false keeps every surface's original baked color (just adds
# gloss/metal) - used for the player's own starter car, which shouldn't
# have its paint randomized out from under it the way ambient traffic and
# background parked cars should.
static func apply(model: Node3D, recolor: bool = true) -> void:
	var hue_shift := randf()
	var desaturate := recolor and randf() < 0.45
	_walk(model, hue_shift, desaturate, recolor)

static func _walk(node: Node, hue_shift: float, desaturate: bool, recolor: bool) -> void:
	if node is MeshInstance3D:
		_repaint_mesh(node as MeshInstance3D, hue_shift, desaturate, recolor)
	for child in node.get_children():
		_walk(child, hue_shift, desaturate, recolor)

static func _repaint_mesh(mesh_instance: MeshInstance3D, hue_shift: float, desaturate: bool, recolor: bool) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if not mesh:
		return
	for i in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(i)
		if not (mat is BaseMaterial3D):
			continue
		var base := mat as BaseMaterial3D
		if not (is_equal_approx(base.roughness, 1.0) and is_equal_approx(base.metallic, 0.0)):
			continue
		var surface_name: String = mesh.surface_get_name(i)
		var fixed := StandardMaterial3D.new()
		fixed.albedo_color = base.albedo_color
		fixed.albedo_texture = base.albedo_texture
		if surface_name in GLASS_NAMES:
			fixed.roughness = GLASS_ROUGHNESS
			fixed.metallic = GLASS_METALLIC
		elif surface_name in LENS_NAMES:
			fixed.roughness = LENS_ROUGHNESS
			fixed.metallic = LENS_METALLIC
		elif surface_name in TRIM_NAMES:
			fixed.roughness = TRIM_ROUGHNESS
			fixed.metallic = TRIM_METALLIC
		else:
			fixed.roughness = GLOSS_ROUGHNESS
			fixed.metallic = GLOSS_METALLIC
			if recolor:
				fixed.albedo_color = _tint(base.albedo_color, hue_shift, desaturate)
		mesh_instance.set_surface_override_material(i, fixed)

# One hue_shift/desaturate pair per car (computed once in apply(), threaded
# through every surface) so a two-tone paint job shifts as a unit instead of
# its two surfaces drifting into unrelated colors.
static func _tint(base: Color, hue_shift: float, desaturate: bool) -> Color:
	if desaturate:
		# White/black/grey/silver reads as a believable chunk of real street
		# traffic rather than every car being vividly colorful - randomized
		# lightness (not just one flat grey) covers white through charcoal.
		var value: float = clampf(base.v + randf_range(-0.3, 0.25), 0.08, 0.95)
		return Color.from_hsv(0.0, randf_range(0.0, 0.06), value, base.a)
	var new_hue: float = fmod(base.h + hue_shift, 1.0)
	var new_sat: float = clampf(base.s * randf_range(0.8, 1.3) + 0.1, 0.3, 0.95)
	return Color.from_hsv(new_hue, new_sat, base.v, base.a)
