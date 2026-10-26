extends SceneTree

class Scripted extends InputSource:
	var script_fn: Callable
	var t := 0
	func poll() -> int:
		t += 1
		return script_fn.call(t)

var f1: Fighter
var f2: Fighter
var tick := 0
var src := Scripted.new()
var log_on := true


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	f1 = main.get_node("GameView/GameViewport/World/Fighter1")
	f2 = main.get_node("GameView/GameViewport/World/Fighter2")
	f1.position.x = 0.0
	# Jump toward f2 at t=2, attack at t=20 (mid-air, on the way up), mash attack again at t=30.
	src.script_fn = func(t: int) -> int:
		var b := 0
		if t >= 2 and t <= 4:
			b |= InputSource.JUMP | InputSource.RIGHT
		if (t >= 20 and t <= 21) or (t >= 30 and t <= 31):
			b |= InputSource.PUNCH
		return b
	f1.input = src
	physics_frame.connect(_tick)


func _tick() -> void:
	tick += 1
	var phase: String = Fighter.JumpPhase.keys()[f1.jump_phase] if f1.state == Fighter.State.JUMP else "-"
	print("%3d %-6s %-8s y=%.2f x=%.2f clip=%s hb=%s hbpos=%s f2=%d f2state=%s" % [
		tick, Fighter.State.keys()[f1.state], phase, f1.position.y, f1.position.x,
		f1.anim.current_animation, f1.is_hitbox_active(), f1.hitbox.position, f2.health,
	if tick == 30 or tick == 45:
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/kick_%d.png" % tick)
	if tick >= 50:
		quit()
