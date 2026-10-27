extends SceneTree

func _initialize() -> void:
	var main: Node = load("res://match/main.tscn").instantiate()
	root.add_child(main)
	for i in 240:
		await process_frame
	var view := main.get_node("GameView") as CanvasItem
	for lv in [12.0, 16.0]:
		(view.material as ShaderMaterial).set_shader_parameter(&"levels", lv)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/levels_%d.png" % int(lv))
	quit()
