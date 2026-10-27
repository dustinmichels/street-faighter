extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session: Node = root.get_node_or_null("Session")
	print("autoload: ", session)
	for a in ["1.2.3.4", "1.2.3.4:9000", "host.example:1", "[::1]:7000", "[::1]", "::1", "", "a:b", "a:70000", " 10.0.0.2 :7777"]:
		print(a, " -> ", session.parse_address(a))
	change_scene_to_file("res://scenes/menu.tscn")
	await process_frame
	await process_frame
	var menu := current_scene
	print("start visible ", menu.get_node("%Start").visible, " online ", menu.get_node("%Online").visible)
	menu.get_node("%Multiplayer").pressed.emit()
	print("after Multiplayer: start ", menu.get_node("%Start").visible, " online ", menu.get_node("%Online").visible)
	menu.get_node("%Address").text = "nope:xx"
	menu.get_node("%Join").pressed.emit()
	print("status: ", menu.get_node("%Status").text, " join disabled ", menu.get_node("%Join").disabled)
	menu.get_node("%Host").pressed.emit()
	print("status: ", menu.get_node("%Status").text, " host disabled ", menu.get_node("%Host").disabled, " back ", menu.get_node("%Back").text, " mode ", session.mode)
	menu.get_node("%Back").pressed.emit()
	print("status: ", menu.get_node("%Status").text, " mode ", session.mode, " back ", menu.get_node("%Back").text)
	menu.get_node("%Back").pressed.emit()
	print("after back: start ", menu.get_node("%Start").visible)
	quit(0)
