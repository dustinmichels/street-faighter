extends Control
## Start menu, the project's main scene, styled as an arcade attract screen
## (`menu_theme.tres`, pixel font, scrolling grid backdrop, scanlines). It
## steps through screens (`Screen`):
## - `TITLE`: the logo and a blinking "PRESS START"; any key, click or
##   gamepad button continues.
## - `NAME`: the player types a name (`Session.clean_name()`: upper case, up
##   to `Session.MAX_NAME_LENGTH` characters), kept in `Session.player_name`
##   and shown on the HUD next to their health bar.
## - `MODE`: "1 PLAYER VS CPU" opens `CHARACTERS` as the character select
##   (`CharacterScreen.selecting`), whose "FIGHT!" starts the local match;
##   "2 PLAYERS ONLINE" opens `ONLINE`; "CHARACTERS" opens `CHARACTERS`.
## - `ONLINE`: "HOST" waits for an opponent on `Session.DEFAULT_PORT` (or the
##   entered port), "JOIN" connects to the address typed next to it (IP or
##   IP:port). The `Session` autoload does the networking and loads the match
##   once both sides are connected; this only shows its status, and why the
##   last session ended when it brings the player back here. While hosting,
##   the join row gives way to the addresses to give the opponent, each with
##   a "COPY" button (`_show_share()`): this machine's LAN and VPN IPv4
##   addresses, and its public one, looked up at `PUBLIC_IP_URL`, with a line
##   on whether the router forwards the port (`Session.port_mapper`, UPnP).
##   "OPPONENTS:" toggles "Show opponents as default character"
##   (`CharacterLibrary.opponents_default()`).
## - `CHARACTERS`: the custom character screen (`CharacterScreen`), which
##   handles its own pages and Esc until it closes.
## Esc (`ui_cancel`) goes back one screen; on `ONLINE` it acts as "BACK"
## (cancelling a pending host or join). The focused button is framed by
## "> <" arrows; hovering a button focuses it (`FocusArrows`).

enum Screen {
	TITLE,
	NAME,
	MODE,
	ONLINE,
	CHARACTERS,
}

const MATCH_SCENE := "res://match/main.tscn"
## "PRESS START" blink period (s), half on and half off.
const BLINK_SECONDS := 0.9
## Answers a GET with this machine's public IPv4 address as plain text.
const PUBLIC_IP_URL := "https://api.ipify.org"
## Seconds the public address lookup may take before its row is dropped.
const PUBLIC_IP_TIMEOUT := 5.0
## Most local addresses `_show_share()` lists, so the panel fits the screen.
const MAX_LOCAL_ADDRESSES := 3
## Seconds a "COPY" button reads "COPIED" after a click.
const COPIED_SECONDS := 1.5
## Muted label color (`menu.tscn` hints).
const HINT_COLOR := Color(0.6, 0.58, 0.7, 1)

@onready var _press_start: Label = %PressStart
@onready var _name_entry: Control = %NameEntry
@onready var _name_edit: LineEdit = %NameEdit
@onready var _start: Control = %Start
@onready var _singleplayer: Button = %Singleplayer
@onready var _multiplayer: Button = %Multiplayer
@onready var _characters_button: Button = %CharactersButton
@onready var _center: Control = %Center
@onready var _characters: CharacterScreen = %Characters
@onready var _online: Control = %Online
@onready var _host_port: LineEdit = %HostPort
@onready var _host: Button = %Host
@onready var _address: LineEdit = %Address
@onready var _join_row: Control = %JoinRow
@onready var _share: Control = %Share
@onready var _share_rows: Control = %ShareRows
@onready var _router_hint: Label = %RouterHint
@onready var _join: Button = %Join
@onready var _back: Button = %Back
@onready var _opponents_default: Button = %OpponentsDefault
@onready var _status: Label = %Status
@onready var _player_tag: Label = %PlayerTag
@onready var _version: Label = %Version

var _screen := Screen.TITLE
var _blink_time := 0.0
## Looks up the public address for `_show_share()`.
var _public_lookup := HTTPRequest.new()
## The "INTERNET" row's address label while the lookup runs, else null.
var _public_label: Label
## Port of the current hosting, for the shared addresses.
var _share_port := Session.DEFAULT_PORT


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
	_public_lookup.timeout = PUBLIC_IP_TIMEOUT
	_public_lookup.request_completed.connect(_on_public_address)
	add_child(_public_lookup)
	for button: Button in [
		_singleplayer,
		_multiplayer,
		_characters_button,
		_host,
		_join,
		_opponents_default,
		_back,
	]:
		FocusArrows.add(button)
	_opponents_default.set_pressed_no_signal(CharacterLibrary.opponents_default())
	_show_opponents_default()
	_opponents_default.toggled.connect(_on_opponents_default_toggled)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_singleplayer.pressed.connect(_open_characters.bind(true))
	_multiplayer.pressed.connect(_show.bind(Screen.ONLINE))
	_characters_button.pressed.connect(_open_characters.bind(false))
	_characters.closed.connect(_on_characters_closed)
	_characters.fight.connect(_start_singleplayer)
	_host.pressed.connect(_on_host_pressed)
	_host_port.text_submitted.connect(_on_host_pressed.unbind(1))
	_join.pressed.connect(_on_join_pressed)
	_address.text_submitted.connect(_on_join_pressed.unbind(1))
	_back.pressed.connect(_on_back_pressed)
	Session.status_changed.connect(_set_status)
	Session.port_mapper.finished.connect(_on_port_mapped)
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
## typing in a field, and "PRESS START" takes any key. While a popup (pick
## list, color picker) is open, Esc is left to it to close it.
func _input(event: InputEvent) -> void:
	if _screen == Screen.TITLE:
		if _is_start_press(event):
			get_viewport().set_input_as_handled()
			_show(Screen.NAME)
		return
	if not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	if not get_viewport().get_embedded_subwindows().is_empty():
		return
	get_viewport().set_input_as_handled()
	match _screen:
		Screen.NAME:
			_show(Screen.TITLE)
		Screen.MODE:
			_show(Screen.NAME)
		Screen.ONLINE:
			_on_back_pressed()
		Screen.CHARACTERS:
			_characters.go_back()


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
	_center.visible = screen != Screen.CHARACTERS
	_characters.visible = screen == Screen.CHARACTERS
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
		Screen.CHARACTERS:
			_characters.open()


func _open_characters(selecting: bool) -> void:
	_characters.selecting = selecting
	_show(Screen.CHARACTERS)


func _on_characters_closed() -> void:
	_show(Screen.MODE)
	(_singleplayer if _characters.selecting else _characters_button).grab_focus()


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


func _start_singleplayer() -> void:
	get_tree().change_scene_to_file(MATCH_SCENE)


func _on_host_pressed() -> void:
	var port := Session.DEFAULT_PORT
	var text := _host_port.text.strip_edges()
	if not text.is_empty():
		port = Session.parse_port(text)
		if port < 0:
			_set_status("Invalid port \"%s\": use 1–65535" % text)
			return
	_start_hosting(port)


func _start_hosting(port: int) -> void:
	if Session.host(port):
		_set_busy(true)
		_show_share(port)


func _on_join_pressed() -> void:
	if Session.join(_address.text):
		_set_busy(true)


## Replaces the join row with the addresses the opponent can join with: the
## local ones (`share_kind()`) now, the public one when its lookup answers.
func _show_share(port: int) -> void:
	_clear_share()
	_share_port = port
	var listed := PackedStringArray()
	for kind: String in ["LAN", "VPN"]:
		for ip in IP.get_local_addresses():
			if listed.size() < MAX_LOCAL_ADDRESSES and share_kind(ip) == kind and ip not in listed:
				listed.append(ip)
				_add_share_row(kind, join_address(ip, port))
	_public_label = _add_share_row("INTERNET", "...")
	if _public_lookup.request(PUBLIC_IP_URL) != OK:
		_drop_public_row()
	_router_hint.text = (
		"ASKING YOUR ROUTER TO OPEN UDP PORT %d..." % port if Session.port_mapper.enabled else ""
	)
	_join_row.visible = false
	_share.visible = true


func _clear_share() -> void:
	_public_lookup.cancel_request()
	_public_label = null
	for row in _share_rows.get_children():
		row.queue_free()
	_share.visible = false
	_join_row.visible = true


## Adds a row "KIND  address  COPY" and returns its address label. "COPY"
## copies whatever the label shows, and is disabled while it shows "...".
func _add_share_row(kind: String, address: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var kind_label := Label.new()
	kind_label.text = kind
	kind_label.custom_minimum_size.x = 72
	kind_label.add_theme_color_override(&"font_color", HINT_COLOR)
	var address_label := Label.new()
	address_label.text = address
	address_label.custom_minimum_size.x = 176
	var copy := Button.new()
	copy.text = "COPY"
	copy.custom_minimum_size.x = 80
	copy.disabled = address == "..."
	copy.tooltip_text = _share_tooltip(kind)
	FocusArrows.add(copy)
	copy.pressed.connect(
		func() -> void:
			DisplayServer.clipboard_set(address_label.text)
			FocusArrows.set_text(copy, "COPIED")
			copy.create_tween().tween_callback(FocusArrows.set_text.bind(copy, "COPY")) \
					.set_delay(COPIED_SECONDS),
	)
	row.add_child(kind_label)
	row.add_child(address_label)
	row.add_child(copy)
	_share_rows.add_child(row)
	return address_label


func _share_tooltip(kind: String) -> String:
	match kind:
		"LAN":
			return "For an opponent on the same Wi-Fi or wired network."
		"VPN":
			return "For an opponent on the same VPN (Tailscale or similar)."
	return "For an opponent anywhere else. Only works if your router forwards UDP port %d to this computer." % _share_port


func _on_public_address(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if _public_label == null:
		return
	var ip := body.get_string_from_utf8().strip_edges()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not ip.is_valid_ip_address():
		_drop_public_row()
		return
	_public_label.text = join_address(ip, _share_port)
	var copy: Button = _public_label.get_parent().get_child(2)
	copy.disabled = false
	_public_label = null


func _drop_public_row() -> void:
	_public_label.get_parent().queue_free()
	_public_label = null


func _on_port_mapped(port: int, result: PortMapper.Result) -> void:
	if _share.visible and port == _share_port:
		_router_hint.text = router_hint(port, result)


## The line under the shared addresses for the router's answer to forwarding
## UDP `port` (`PortMapper.Result`).
static func router_hint(port: int, result: PortMapper.Result) -> String:
	match result:
		PortMapper.Result.OPENED:
			return "YOUR ROUTER FORWARDS UDP PORT %d: INTERNET SHOULD WORK." % port
		PortMapper.Result.BEHIND_NAT:
			return "YOUR ROUTER ISN'T DIRECTLY ON THE INTERNET (CGNAT OR A SECOND ROUTER): INTERNET LIKELY WON'T WORK. USE A VPN."
		PortMapper.Result.REFUSED:
			return "YOUR ROUTER REFUSED TO FORWARD UDP PORT %d. FOR INTERNET, FORWARD IT YOURSELF." % port
	return "NO UPNP ROUTER FOUND. FOR INTERNET, FORWARD UDP PORT %d YOURSELF." % port


## Which share row a local address belongs to: "LAN" for private IPv4
## (10/8, 172.16/12, 192.168/16), "VPN" for the shared range Tailscale uses
## (100.64/10), "" for the rest (loopback, link-local, IPv6).
static func share_kind(ip: String) -> String:
	var parts := ip.split(".")
	if parts.size() != 4 or not ip.is_valid_ip_address():
		return ""
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	if a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168):
		return "LAN"
	if a == 100 and b >= 64 and b <= 127:
		return "VPN"
	return ""


## `ip` as typed into "JOIN" (`Session.parse_address()` format): the port is
## added only when it isn't `Session.DEFAULT_PORT`.
static func join_address(ip: String, port: int) -> String:
	if port == Session.DEFAULT_PORT:
		return ip
	return "[%s]:%d" % [ip, port] if ip.contains(":") else "%s:%d" % [ip, port]


func _on_opponents_default_toggled(on: bool) -> void:
	CharacterLibrary.set_opponents_default(on)
	_show_opponents_default()


func _show_opponents_default() -> void:
	FocusArrows.set_text(
		_opponents_default,
		"OPPONENTS: DEFAULT" if _opponents_default.button_pressed else "OPPONENTS: AS CHOSEN",
	)


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


## While a session is being set up, only cancelling (and copying a shared
## address) is possible. Leaving that state also hides the shared addresses.
func _set_busy(busy: bool) -> void:
	if not busy:
		_clear_share()
	_host.disabled = busy
	_host_port.editable = not busy
	_join.disabled = busy
	_address.editable = not busy
	_opponents_default.disabled = busy
	FocusArrows.set_text(_back, "CANCEL" if busy else "BACK")
	if busy:
		_back.grab_focus()


func _set_status(text: String) -> void:
	_status.text = text


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
		_start_hosting(cli_port)
	elif not cli_join.is_empty():
		_show(Screen.ONLINE)
		_address.text = cli_join
		if Session.join(cli_join):
			_set_busy(true)
