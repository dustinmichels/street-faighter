class_name PlayerInput
extends InputSource
## Local player: the `move_left`, `move_right`, `jump` and `punch` actions.


func poll() -> int:
	var buttons := 0
	if Input.is_action_pressed(&"move_left"):
		buttons |= LEFT
	if Input.is_action_pressed(&"move_right"):
		buttons |= RIGHT
	if Input.is_action_pressed(&"jump"):
		buttons |= JUMP
	if Input.is_action_pressed(&"punch"):
		buttons |= PUNCH
	return buttons
