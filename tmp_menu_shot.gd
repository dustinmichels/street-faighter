extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file("res://scenes/menu.tscn")
	for i in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/menu_start.png")
	current_scene.get_node("%Multiplayer").pressed.emit()
	current_scene.get_node("%Address").text = "192.168.1.20:7777"
	current_scene.get_node("%Status").text = "Rejected by the host: Game version mismatch (this game: 0.1.0, other: 0.2.0)"
	for i in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/menu_online.png")
	quit(0)
