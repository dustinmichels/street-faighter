extends SceneTree

class Puncher extends InputSource:
	var me: Fighter
	var t := 0
	func bind(f: Fighter) -> void:
		me = f
	func poll() -> int:
		t += 1
		var dx := me.opponent.pos_x - me.pos_x
		if absi(dx) > 9000:
			return RIGHT if dx > 0 else LEFT
		if t % 90 < 10:
			return JUMP | (RIGHT if dx > 0 else LEFT)
		return PUNCH if t % 24 == 0 else 0


func run(n: int) -> Dictionary:
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var world: Match = current_scene.get_node("GameView/GameViewport/World")
	var p: Fighter = world.fighters[0]
	var ai: Fighter = world.fighters[1]
	p.input = Puncher.new()
	world.set_physics_process(false)
	var counts := {}
	var trace := []
	var ko := -1
	var maxy := 0
	for i in n:
		world.step(PackedInt32Array([p.input.poll(), ai.input.poll()]))
		var s: String = Fighter.State.keys()[ai.state] + "/" + Fighter.State.keys()[p.state]
		counts[s] = counts.get(s, 0) + 1
		maxy = maxi(maxy, p.pos_y)
		trace.append([p.pos_x, p.pos_y, p.state, ai.pos_x, ai.state, p.health, ai.health])
		if ko < 0 and (p.health == 0 or ai.health == 0):
			ko = world.tick
	return {"tick": world.tick, "p_hp": p.health, "ai_hp": ai.health, "ko": ko, "maxy": maxy, "px": p.pos_x, "aix": ai.pos_x, "hash": hash(trace), "n_states": counts.size()}


func _initialize() -> void:
	var a: Dictionary = await run(1800)
	print(a)
	var b: Dictionary = await run(1800)
	print(b)
	print("same: ", a.hash == b.hash)
	quit()
