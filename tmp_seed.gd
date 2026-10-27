extends SceneTree


func run(match_seed: int) -> Array:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var world: Match = scene.get_node("GameView/GameViewport/World")
	world.rng_seed = match_seed
	world.fighters[0].input = AIInput.new()
	root.add_child(scene)
	world.set_physics_process(false)
	print('start ', world.fighters[0].pos_x, ' ', world.fighters[1].pos_x, ' ', world.fighters[0].position, ' ', world.fighters[1].input, ' ', world.fighters[1].input._fighter, ' ', world.fighters[1].input._rng.seed)
	var trace := []
	for i in 1200:
		if i < 6: print(i, ' ', world.fighters[0].input.poll(), ' ', world.fighters[1].input.poll(), ' ', world.fighters[0].state, ' ', world.fighters[1].state)
		world.step(PackedInt32Array([world.fighters[0].input.poll(), world.fighters[1].input.poll()]))
		trace.append([world.fighters[0].pos_x, world.fighters[1].pos_x, world.fighters[0].health, world.fighters[1].health])
	scene.free()
	return trace


func _initialize() -> void:
	var a := run(1)
	var b := run(1)
	for i in a.size():
		if a[i] != b[i]:
			print("diverge at ", i, " ", a[max(i-1,0)], " ", a[i], " vs ", b[i])
			break
	quit()
