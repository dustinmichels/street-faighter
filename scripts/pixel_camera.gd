class_name PixelCamera
extends Camera3D
## Orthographic camera that stays on the pixel grid so the low-res image doesn't
## shimmer as it moves. Move it via `target_position`, not `position`.
## Models should snap their visual root with `snap()` (keep physics bodies unsnapped).

## Logical (unsnapped) camera position; the actual position is its snapped version.
var target_position: Vector3:
	set(value):
		target_position = value
		if is_inside_tree():
			global_position = snap(value)


func _ready() -> void:
	target_position = global_position


## World-space size of one screen pixel (orthographic, keep-height aspect).
func pixel_size() -> float:
	return size / get_viewport().get_visible_rect().size.y


## Rounds `world_pos` to the pixel grid along the camera's right/up axes,
## keeping its depth along the view axis.
func snap(world_pos: Vector3) -> Vector3:
	var b := global_basis.orthonormalized()
	var px := pixel_size()
	var right := snappedf(world_pos.dot(b.x), px)
	var up := snappedf(world_pos.dot(b.y), px)
	return b.x * right + b.y * up + b.z * world_pos.dot(b.z)
