extends Node3D

# Purely atmospheric background dressing - flies a straight line across the
# sky at a fixed altitude and wraps back around, matching the primitive/
# no-external-asset style already used for the alley dumpsters/park fences.
@export var speed: float = 18.0
@export var travel_min: float = -220.0
@export var travel_max: float = 220.0

func _process(delta: float) -> void:
	position.x += speed * delta
	if position.x > travel_max:
		position.x = travel_min
