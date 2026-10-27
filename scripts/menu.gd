extends Control
## Start menu, the project's main scene. "Singleplayer" starts the local match
## (`main.tscn`: you control fighter 1, `AIInput` drives fighter 2).
## "Multiplayer (online)" opens the online panel: "Host" waits for an opponent
## on `Session.DEFAULT_PORT`, "Join" connects to the address typed next to it
## (IP or IP:port). The `Session` autoload does the networking and loads the
## match once both sides are connected; this only shows its status, and why
## the last session ended when it brings the player back here.

const MATCH_SCENE := "res://scenes/main.tscn"

@onready var _start: Control = %Start
@onready var _singleplayer: Button = %Singleplayer
@onready var _multiplayer: Button = %Multiplayer
@onready var _online: Control = %Online
@onready var _host: Button = %Host
@onready var _address: LineEdit = %Address
@onready var _join: Button = %Join
@onready var _back: Button = %Back
@onready var _status: Label = %Status


func _ready() -> void:
	_singleplayer.pressed.connect(_on_singleplayer_pressed)
	_multiplayer.pressed.connect(_show_online.bind(true))
	_host.pressed.connect(_on_host_pressed)
	_join.pressed.connect(_on_join_pressed)
	_address.text_submitted.connect(_on_join_pressed.unbind(1))
	_back.pressed.connect(_on_back_pressed)
	Session.status_changed.connect(_set_status)
	Session.ended.connect(_on_session_ended)
	var reason := Session.take_end_reason()
	if reason.is_empty():
		_show_online(false)
	else:
		# Back from a session that failed or ended: say why, ready to retry.
		_show_online(true)
		_set_status(reason)


func _on_singleplayer_pressed() -> void:
	get_tree().change_scene_to_file(MATCH_SCENE)


func _show_online(online: bool) -> void:
	_start.visible = not online
	_online.visible = online
	_set_busy(false)
	_set_status("")
	if online:
		_host.grab_focus()
	else:
		_singleplayer.grab_focus()


func _on_host_pressed() -> void:
	if Session.host():
		_set_busy(true)


func _on_join_pressed() -> void:
	if Session.join(_address.text):
		_set_busy(true)


## Back from the online panel; while hosting or connecting it cancels instead.
func _on_back_pressed() -> void:
	if Session.is_online():
		Session.close()
		_set_busy(false)
		_set_status("Cancelled")
	else:
		_show_online(false)


func _on_session_ended(reason: String) -> void:
	Session.take_end_reason()
	_set_busy(false)
	_set_status(reason)


## While a session is being set up, only cancelling is possible.
func _set_busy(busy: bool) -> void:
	_host.disabled = busy
	_join.disabled = busy
	_address.editable = not busy
	_back.text = "Cancel" if busy else "Back"
	if busy:
		_back.grab_focus()


func _set_status(text: String) -> void:
	_status.text = text
