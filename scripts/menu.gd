extends Control
## Start menu, the project's main scene, styled as an arcade attract screen
## (`menu_theme.tres`, pixel font, scrolling grid backdrop, scanlines). It
## steps through screens (`Screen`):
## - `TITLE`: the logo and a blinking "PRESS START"; any key, click or
##   gamepad button continues.
## - `NAME`: the player types a name (`Session.clean_name()`: upper case, up
##   to `Session.MAX_NAME_LENGTH` characters), kept in `Session.player_name`
##   and shown on the HUD next to their health bar.
## - `MODE`: "1 PLAYER VS CPU" starts the local match; "2 PLAYERS ONLINE"
##   opens `ONLINE`.
## - `ONLINE`: "HOST" waits for an opponent on `Session.DEFAULT_PORT` (or the
##   entered port), "JOIN" connects to the address typed next to it (IP or
##   IP:port). The `Session` autoload does the networking and loads the match
##   once both sides are connected; this only shows its status, and why the
##   last session ended when it brings the player back here.
## Esc (`ui_cancel`) goes back one screen; on `ONLINE` it acts as "BACK"
## (cancelling a pending host or join). The focused button is framed by
## "> <" arrows; hovering a button focuses it.

enum Screen { TITLE, NAME, MODE, ONLINE }

const MATCH_SCENE := "res://scenes/main.tscn"
## "PRESS START" blink period (s), half on and half off.
const BLINK_SECONDS := 0.9

@onready var _press_start: Label = %PressStart
@onready var _name_entry: Control = %NameEntry
@onready var _name_edit: LineEdit = %NameEdit
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
@onready var _player_tag: Label = %PlayerTag
@onready var _version: Label = %Version

var _screen := Screen.TITLE
## Each button's text without the focus arrows (`_set_button_text()`).
var _button_texts := {}
var _blink_time := 0.0


## The match renders at the 480x270 base size and is scaled up (`viewport`
## stretch) to keep the pixel art crisp. The menu switches to `canvas_items`:
## the layout stays the same but text is drawn at the window's resolution,
## so the pixel font stays sharp at any window size.
func _enter_tree() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func _exit_tree() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT


func _ready() -> void:
	_version.text = "VER %s" % Session.game_version()
	for button: Button in [_singleplayer, _multiplayer, _host, _join, _back]:
		_add_focus_arrows(button)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_singleplayer.pressed.connect(_on_singleplayer_pressed)
	_multiplayer.pressed.connect(_show.bind(Screen.ONLINE))
	_host.pressed.connect(_on_host_pressed)
	_host_port.text_submitted.connect(_on_host_pressed.unbind(1))
	_join.pressed.connect(_on_join_pressed)
	_address.text_submitted.connect(_on_join_pressed.unbind(1))
	_back.pressed.connect(_on_back_pressed)
	Session.status_changed.connect(_set_status)
	Session.ended.connect(_on_session_ended)
	var reason := Session.take_end_reason()
	if reason.is_empty():
		_show(Screen.TITLE)
	else:
		# Back from a session that failed or ended: say why, ready to retry.
		_show(Screen.ONLINE)
		_set_status(reason)

	_check_cli_args()


func _process(delta: float) -> void:
	_blink_time = fmod(_blink_time + delta, BLINK_SECONDS)
	_press_start.self_modulate.a = 1.0 if _blink_time < BLINK_SECONDS * 0.5 else 0.0


## Runs before the focused control sees the event, so Esc works even while
## typing in a field, and "PRESS START" takes any key.
func _input(event: InputEvent) -> void:
	if _screen == Screen.TITLE:
		if _is_start_press(event):
			get_viewport().set_input_as_handled()
			_show(Screen.NAME)
		return
	if not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	match _screen:
		Screen.NAME:
			_show(Screen.TITLE)
		Screen.MODE:
			_show(Screen.NAME)
		Screen.ONLINE:
			_on_back_pressed()


static func _is_start_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	return (event is InputEventMouseButton or event is InputEventJoypadButton) and event.pressed


func _show(screen: Screen) -> void:
	_screen = screen
	_press_start.visible = screen == Screen.TITLE
	_name_entry.visible = screen == Screen.NAME
	_start.visible = screen == Screen.MODE
	_online.visible = screen == Screen.ONLINE
	_player_tag.visible = screen == Screen.MODE or screen == Screen.ONLINE
	_player_tag.text = "1UP\n%s" % Session.player_name
	_set_busy(false)
	_set_status("")
	match screen:
		Screen.TITLE:
			_blink_time = 0.0
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null:
				focused.release_focus()
		Screen.NAME:
			_name_edit.text = Session.player_name
			_name_edit.grab_focus()
			_name_edit.edit()
			_name_edit.select_all()
		Screen.MODE:
			_singleplayer.grab_focus()
		Screen.ONLINE:
			_host.grab_focus()


## Keeps the name upper case as it's typed, like an arcade high-score entry.
func _on_name_changed(text: String) -> void:
	var upper := text.to_upper()
	if upper != text:
		var caret := _name_edit.caret_column
		_name_edit.text = upper
		_name_edit.caret_column = caret


func _on_name_submitted(text: String) -> void:
	Session.player_name = Session.clean_name(text)
	_show(Screen.MODE)


func _on_singleplayer_pressed() -> void:
	get_tree().change_scene_to_file(MATCH_SCENE)


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
		_show(Screen.MODE)


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
	_set_button_text(_back, "CANCEL" if busy else "BACK")
	if busy:
		_back.grab_focus()

func _set_status(text: String) -> void:
	_status.text = text


## Frames `button`'s text with "> <" while it has focus, and focuses it on
## hover so mouse and keyboard share one cursor.
func _add_focus_arrows(button: Button) -> void:
	_button_texts[button] = button.text
	button.focus_entered.connect(_update_button_text.bind(button))
	button.focus_exited.connect(_update_button_text.bind(button))
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			button.grab_focus())


func _set_button_text(button: Button, text: String) -> void:
	_button_texts[button] = text
	_update_button_text(button)


func _update_button_text(button: Button) -> void:
	var text: String = _button_texts[button]
	button.text = "> %s <" % text if button.has_focus() else text


## Whether `_check_cli_args()` already ran: the shortcuts apply to the first
## menu only, so a menu reached after a session ends shows why instead of
## hosting or joining again right away.
static var _cli_checked := false


func _check_cli_args() -> void:
	if _cli_checked:
		return
	_cli_checked = true
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
		elif arg.begins_with("--name="):
			Session.player_name = Session.clean_name(arg.substr(7))
	if cli_host:
		_show(Screen.ONLINE)
		_host_port.text = str(cli_port)
		if Session.host(cli_port):
			_set_busy(true)
	elif not cli_join.is_empty():
		_show(Screen.ONLINE)
		_address.text = cli_join
		if Session.join(cli_join):
			_set_busy(true)
