class_name PlayerInput
extends InputSource
## Local player: the `move_left`, `move_right`, `jump`, `punch`, `block`,
## `crouch` and `special` actions (keyboard and gamepad, see `project.godot`).


func poll(_tick: int) -> int:
	var buttons := 0
	if Input.is_action_pressed(&"move_left"):
		buttons |= LEFT
	if Input.is_action_pressed(&"move_right"):
		buttons |= RIGHT
	if Input.is_action_pressed(&"jump"):
		buttons |= JUMP
	if Input.is_action_pressed(&"punch"):
		buttons |= PUNCH
	if Input.is_action_pressed(&"block"):
		buttons |= BLOCK
	if Input.is_action_pressed(&"crouch"):
		buttons |= CROUCH
	if Input.is_action_pressed(&"special"):
		buttons |= SPECIAL
	return buttons
