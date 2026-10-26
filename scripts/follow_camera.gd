class_name FollowCamera
extends PixelCamera
## Side camera that keeps the midpoint of `fighters` centered along world X,
## clamped so it never shows past the `stage` walls' outer faces. Height and
## depth stay where the scene puts them. Runs on the physics tick after the
## fighters (it comes after them in the tree), so it sees this tick's positions.

## Fighters to keep centered (their midpoint along X).
@export var fighters: Array[Fighter] = []
## Bounds the view; null means no clamping.
@export var stage: Stage


func _ready() -> void:
	super()
	_follow()


func _physics_process(_delta: float) -> void:
	_follow()


## Half the visible width along X (m): orthographic `size` is the height.
func half_view_width() -> float:
	return pixel_size() * get_viewport().get_visible_rect().size.x * 0.5


func _follow() -> void:
	if fighters.is_empty():
		return
	var mid := 0.0
	for f in fighters:
		mid += f.global_position.x
	mid /= fighters.size()
	if stage != null:
		var limit := maxf(stage.outer_half_width() - half_view_width(), 0.0)
		mid = clampf(mid, stage.global_position.x - limit, stage.global_position.x + limit)
	var p := target_position
	p.x = mid
	target_position = p
