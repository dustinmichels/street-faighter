extends Control
## Start menu, the project's main scene. "Singleplayer" starts the local match
## (`main.tscn`: you control fighter 1, fighter 2 stands idle). "Multiplayer
## (online)" stays disabled until online play exists (`docs/todo/multiplayer.md`).

const MATCH_SCENE := "res://scenes/main.tscn"

@onready var _singleplayer: Button = %Singleplayer


func _ready() -> void:
	_singleplayer.pressed.connect(_on_singleplayer_pressed)
	_singleplayer.grab_focus()


func _on_singleplayer_pressed() -> void:
	get_tree().change_scene_to_file(MATCH_SCENE)
