extends Node
## Match root. The `restart` action (R) reloads the whole scene, resetting
## fighters, health and camera; it works at any time, not only after a KO.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart") and not event.is_echo():
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
