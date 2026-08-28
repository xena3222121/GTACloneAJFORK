extends Control

const HIT_FLASH_DURATION := 0.15
const HIT_MARKER_DURATION := 0.25

var hit_flash_timer := 0.0
var hit_marker_timer := 0.0
var aiming := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func flash_hit() -> void:
	hit_flash_timer = HIT_FLASH_DURATION
	hit_marker_timer = HIT_MARKER_DURATION

func _draw() -> void:
	# Use the viewport rect directly rather than this Control's own `size`:
	# as a top-level Control under a CanvasLayer, `size` doesn't reliably
	# resolve to the viewport size even with full-rect anchors.
	var center: Vector2 = get_viewport_rect().size / 2.0
	var color: Color = Color(1, 0.2, 0.15, 0.9) if hit_flash_timer > 0.0 else Color(1, 1, 1, 0.85)

	if aiming:
		var gap := 4.0
		var tick := 6.0
		var outline := Color(0, 0, 0, 0.6)
		var dirs: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
		for d in dirs:
			draw_line(center + d * gap, center + d * (gap + tick), outline, 3.0)
		for d in dirs:
			draw_line(center + d * gap, center + d * (gap + tick), color, 1.5)
		draw_circle(center, 1.5, outline)
		draw_circle(center, 1.0, color)

	if hit_marker_timer > 0.0:
		var t: float = 1.0 - (hit_marker_timer / HIT_MARKER_DURATION)
		var scale_amt: float = lerp(16.0, 11.0, t)
		var alpha: float = lerp(1.0, 0.0, t)
		var mcolor: Color = Color(1, 0.85, 0.2, alpha)
		var offsets: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		for o in offsets:
			var inner: Vector2 = center + o * (scale_amt * 0.45)
			var outer: Vector2 = center + o * scale_amt
			draw_line(inner, outer, mcolor, 2.0)

func _process(delta: float) -> void:
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
	if hit_marker_timer > 0.0:
		hit_marker_timer -= delta
	queue_redraw()
