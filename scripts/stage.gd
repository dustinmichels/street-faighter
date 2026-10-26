class_name Stage
extends Node3D
## The arena: a floor and two walls bounding world X. Each wall is a
## `StaticBody3D` (layer 1, `world`) whose inner face sits at ±`half_width`;
## its block mesh extends `WALL_THICKNESS` outward. The walls are placed from
## `half_width` on ready, so change it here, not by moving the nodes.

## Visible thickness of each wall block (m), outside `half_width`; matches the
## `Mesh_wall` box in `main.tscn`.
const WALL_THICKNESS := 0.5

## Distance from the stage center to each wall's inner face (m). Fighter body
## centers stop one capsule radius (0.3) short of it.
@export var half_width := 6.0

@onready var wall_left: Node3D = $WallLeft
@onready var wall_right: Node3D = $WallRight


func _ready() -> void:
	wall_left.position.x = -half_width
	wall_right.position.x = half_width


## How far from the center the stage is drawn: the walls' outer faces. A
## camera showing no more than this sees no empty space past the walls.
func outer_half_width() -> float:
	return half_width + WALL_THICKNESS
