extends SceneTree


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var world: Match = current_scene.get_node("GameView/GameViewport/World")
	world.set_physics_process(false)
	var p: Fighter = world.fighters[0]
	var ai: Fighter = world.fighters[1]
	for i in 400:
		world.step(PackedInt32Array([InputSource.LEFT, InputSource.RIGHT]))
	print("separation held: p=", p.pos_x, " ai=", ai.pos_x, " limit=", p.wall_limit)
	for i in 600:
		world.step(PackedInt32Array([InputSource.RIGHT, InputSource.RIGHT]))
	print("wall: p=", p.pos_x, " ai=", ai.pos_x)
	world.step(PackedInt32Array([InputSource.JUMP, 0]))
	var peak := 0
	var air := 0
	for i in 80:
		world.step(PackedInt32Array([0, 0]))
		peak = maxi(peak, p.pos_y)
		air += int(p.pos_y > 0)
	print("jump peak=", peak, " air ticks=", air, " state=", Fighter.State.keys()[p.state])
	quit()
