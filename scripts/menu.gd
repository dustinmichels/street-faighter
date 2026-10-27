extends Control
## Start menu, the project's main scene. "Singleplayer" starts the local match
## "Multiplayer (online)" opens the online panel: "Host" waits for an opponent
## on `Session.DEFAULT_PORT` (or the entered port), "Join" connects to the address
## typed next to it (IP or IP:port). The `Session` autoload does the networking and
## loads the match once both sides are connected; this only shows its status, and
## why the last session ended when it brings the player back here.

const MATCH_SCENE := "res://scenes/main.tscn"

@onready var _start: Control = %Start
@onready var _singleplayer: Button = %Singleplayer
@onready var _multiplayer: Button = %Multiplayer
@onready var _online: Control = %Online
@onready var _host_port: LineEdit = %HostPort
@onready var _host: Button = %Host
@onready var _address: LineEdit = %Address
@onready var _join: Button = %Join
@onready var _back: Button = %Back
@onready var _status: Label = %Status


## The match renders at the 480x270 base size and is scaled up (`viewport`
## stretch) to keep the pixel art crisp. The menu has no pixel art, so it
## switches to `canvas_items`: the layout stays the same but text is drawn at
## the window's resolution and doesn't look pixelated.
func _enter_tree() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func _exit_tree() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT


func _ready() -> void:
	_singleplayer.pressed.connect(_on_singleplayer_pressed)
	_multiplayer.pressed.connect(_show_online.bind(true))
	_host.pressed.connect(_on_host_pressed)
	_host_port.text_submitted.connect(_on_host_pressed.unbind(1))
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

	_check_cli_args()


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
	var port := Session.DEFAULT_PORT
	var text := _host_port.text.strip_edges()
	if not text.is_empty():
		port = Session.parse_port(text)
		if port < 0:
			_set_status("Invalid port \"%s\": use 1–65535" % text)
			return
	if Session.host(port):
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
	_host_port.editable = not busy
	_join.disabled = busy
	_address.editable = not busy
	_back.text = "Cancel" if busy else "Back"
	if busy:
		_back.grab_focus()

func _set_status(text: String) -> void:
	_status.text = text


func _check_cli_args() -> void:
	var cli_host := false
	var cli_port := Session.DEFAULT_PORT
	var cli_join := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			cli_host = true
		elif arg.begins_with("--port="):
			var p := Session.parse_port(arg.substr(7))
			if p > 0:
				cli_port = p
		elif arg.begins_with("--join="):
			cli_join = arg.substr(7)
	if cli_host:
		_show_online(true)
		_host_port.text = str(cli_port)
		if Session.host(cli_port):
			_set_busy(true)
	elif not cli_join.is_empty():
		_show_online(true)
		_address.text = cli_join
		if Session.join(cli_join):
			_set_busy(true)
