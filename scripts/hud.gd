class_name Hud
extends Control
## Fight overlay drawn at the internal 480×270 resolution, on top of the game
## view (and outside its quantize shader). Health bars sit in the top corners;
## each fills from its outer edge, so lost health shows up next to the center.
## Under each bar, aligned to its outer edge, its fighter's name
## (`left_name` / `right_name`, set by `main.gd`) in the arcade font, and at
## the bar's inner end a pulsing star while that fighter's special is ready
## (`Fighter.special_ready()`).
## Once either fighter is knocked down, a centered "K.O." and a hint appear:
## offline the restart (`main.gd`), online the rematch status (`ko_hint()`).
## A "Controls" button in the bottom-right corner, or the `controls` action
## (Esc), toggles a panel listing the key bindings, read live from the
## InputMap. Before `Match.start_tick`
## a centered countdown (3, 2, 1) shows, then "FIGHT!" for `FIGHT_TICKS`;
## both come from the simulation tick, so peers show them on the same tick.
## `show_notice()` replaces both, and the K.O., with a centered message
## (online: why the match ended). Online (`net` set), the bottom-left corner
## shows the ping and this side's input delay (`net_status_text()`). The
## `net_debug` action (F3) toggles a debug overlay under the left name:
## ticks, rollbacks, stalls and packet loss (`net_debug_text()`). Offline,
## `debug_text` (set by `main.gd`, e.g. a non-default CPU difficulty) shows in
## the bottom-left corner instead. `show_warning()` puts a short message
## (e.g. a character that fell back to the default) under the name row for
## `WARNING_SECONDS`.

const BAR_SIZE := Vector2(200, 8)
## Gap between a bar and the screen's top and side edges (px).
const BAR_MARGIN := Vector2(12, 10)
const BORDER := 1
const BORDER_COLOR := Color(0.08, 0.06, 0.1)
const LOST_COLOR := Color(0.55, 0.1, 0.1)
const HEALTH_COLOR := Color(0.98, 0.82, 0.2)
const KO_COLOR := Color(0.95, 0.2, 0.15)
const COUNTDOWN_COLOR := Color.WHITE
const NOTICE_COLOR := Color(1.0, 0.55, 0.35)
## How long "FIGHT!" stays up after the countdown (ticks).
const FIGHT_TICKS := 45
## How long a `show_warning()` message stays up (seconds, wall clock).
const WARNING_SECONDS := 6.0
const WARNING_FONT_SIZE := 10
## Top of the warning line, below the names and special stars.
const WARNING_TOP := 40
## Actions listed in the controls panel, in display order, with their labels.
const CONTROLS: Array[Array] = [
	[&"move_left", "Move left"],
	[&"move_right", "Move right"],
	[&"jump", "Jump (hold to repeat)"],
	[&"punch", "Punch / air kick"],
	[&"block", "Block (hold)"],
	[&"crouch", "Crouch (hold, ducks punches; + punch: sweep)"],
	[&"special", "Special throw (after 3 hits in a row)"],
	[&"restart", "Restart"],
	[&"controls", "Show controls"],
	[&"net_debug", "Network debug overlay"],
	[&"ai_difficulty", "CPU difficulty: default / easy (debug)"],
]
const CONTROLS_FONT_SIZE := 10
## Fighter names under the bars: the menu's pixel font at its native size,
## `NAME_GAP` px below the bar's border.
const NAME_FONT: Font = preload("res://assets/fonts/PressStart2P-Regular.ttf")
const NAME_FONT_SIZE := 8
const NAME_GAP := 3
const NAME_COLOR := Color.WHITE
## Special-ready star: outer radius (px), color, pulse rate (Hz).
const STAR_RADIUS := 6.0
const STAR_COLOR := Color(1.0, 0.92, 0.3)
const STAR_PULSE_HZ := 2.0

## Shown on the left bar.
@export var left_fighter: Fighter
## Shown on the right bar.
@export var right_fighter: Fighter
## Its `tick` and `start_tick` drive the countdown.
@export var fight: Match
## Shown under the left / right bar.
var left_name := ""
var right_name := ""
## Online: the match's input exchange, for the ping and input delay. null
## offline (no network line).
var net: InputSync
## Offline debug line in the bottom-left corner; hidden while empty.
var debug_text := ""

var _left_fill: ColorRect
var _right_fill: ColorRect
var _left_name: Label
var _right_name: Label
var _left_star: Control
var _right_star: Control
## "K.O." plus `_ko_hint`, hidden until a knockdown.
var _ko: VBoxContainer
var _ko_hint: Label
## Key-binding list, hidden until the controls button is toggled on.
var _controls: PanelContainer
## Bottom-right toggle; its pressed state is the panel's visibility.
var _controls_button: Button
## Centered countdown / "FIGHT!", empty (hidden) otherwise.
var _countdown: Label
## Centered message from `show_notice()`, hidden until then.
var _notice: Label
## Bottom-left ping / input delay line, hidden offline.
var _net_status: Label
## Debug overlay under the left name, hidden until `net_debug` toggles it.
var _net_debug: Label
## Message from `show_warning()`, hidden while empty.
var _warning: Label


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_left_fill = _make_bar(false)
	_right_fill = _make_bar(true)
	_left_name = _make_name(false)
	_right_name = _make_name(true)
	_left_star = _make_star(false)
	_right_star = _make_star(true)
	_ko = _make_ko()
	_countdown = _make_label("", 48, COUNTDOWN_COLOR)
	_countdown.mouse_filter = MOUSE_FILTER_IGNORE
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_countdown)
	_countdown.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_notice = _make_label("", 16, NOTICE_COLOR)
	_notice.mouse_filter = MOUSE_FILTER_IGNORE
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice.visible = false
	add_child(_notice)
	_notice.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_controls = _make_controls_panel()
	_controls_button = _make_controls_button()
	_net_status = _make_label("", CONTROLS_FONT_SIZE, Color.WHITE)
	_net_status.mouse_filter = MOUSE_FILTER_IGNORE
	_net_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_net_status)
	_net_status.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT, PRESET_MODE_MINSIZE, int(BAR_MARGIN.y))
	_net_debug = _make_label("", CONTROLS_FONT_SIZE, Color.WHITE)
	_net_debug.mouse_filter = MOUSE_FILTER_IGNORE
	_net_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_net_debug.position = Vector2(BAR_MARGIN.x, _name_top() + NAME_FONT_SIZE + 4)
	_net_debug.visible = false
	add_child(_net_debug)
	_warning = _make_label("", WARNING_FONT_SIZE, NOTICE_COLOR)
	_warning.mouse_filter = MOUSE_FILTER_IGNORE
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.visible = false
	add_child(_warning)
	_warning.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	_warning.offset_left = BAR_MARGIN.x
	_warning.offset_right = -BAR_MARGIN.x
	_warning.offset_top = WARNING_TOP
	_update()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"controls") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_controls_button.button_pressed = not _controls_button.button_pressed
	elif event.is_action_pressed(&"net_debug") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_net_debug.visible = not _net_debug.visible


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	_set_fill(_left_fill, left_fighter, false)
	_set_fill(_right_fill, right_fighter, true)
	_left_name.text = left_name
	_right_name.text = right_name
	_left_star.visible = left_fighter != null and left_fighter.special_ready()
	_right_star.visible = right_fighter != null and right_fighter.special_ready()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * STAR_PULSE_HZ)
	for star: Control in [_left_star, _right_star]:
		star.modulate.a = lerpf(0.6, 1.0, pulse)
	_ko.visible = _is_down(left_fighter) or _is_down(right_fighter)
	if _ko.visible:
		var session := get_node_or_null("/root/Session")
		var online: bool = session != null and bool(session.is_online())
		var req: bool = session != null and bool(session.rematch_requested)
		var peer_req: bool = session != null and bool(session.peer_rematch_requested)
		_ko_hint.text = ko_hint(online, req, peer_req)
	if fight != null:
		_countdown.text = countdown_text(fight.tick, fight.start_tick)
	_net_status.visible = net != null or debug_text != ""
	if net != null:
		_net_status.text = net_status_text(net.ping_ms(), net.local.delay if net.local != null else 0)
	else:
		_net_status.text = debug_text
	if _net_debug.visible:
		_net_debug.text = net_debug_text(fight, net)
	if _notice.visible:
		_ko.visible = false
		_countdown.text = ""


## Shows `text` centered over the fight, hiding the countdown and K.O.
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = true
	_update()


## Shows `text` under the name row for `WARNING_SECONDS`, replacing any
## earlier warning. The fight stays visible.
func show_warning(text: String) -> void:
	_warning.text = text
	_warning.visible = not text.is_empty()
	get_tree().create_timer(WARNING_SECONDS).timeout.connect(func() -> void:
		if _warning.text == text:
			_warning.visible = false)


## The debug overlay's lines for `world` and, online, its `sync`: this
## side's tick and last confirmed tick, the peer's last reported tick and
## this side's lead (`InputSync.lead()`), rollbacks / re-simulated ticks /
## window, frames stalled and skipped (tick sync), the peer's packets
## received and lost, with the loss of the last `InputSync.LOSS_WINDOW`, and
## the simulated network conditions, if any.
static func net_debug_text(world: Match, sync: InputSync) -> String:
	if world == null:
		return ""
	var lines := PackedStringArray([
		"Tick %d  confirmed %d" % [world.tick, world.confirmed_tick],
	])
	if sync == null:
		lines.append("Offline")
		return "\n".join(lines)
	lines.append_array([
		"Remote tick %d  lead %+.1f" % [sync.remote_tick, sync.lead()],
		"Rollbacks %d (%d ticks)  window %d" % [world.rollbacks, world.resimulated_ticks, world.max_rollback],
		"Stalled %d  skipped %d frames" % [world.stalled_frames, world.skipped_frames],
		"Packets %d in, %d lost  loss %d%%" % [sync.packets_received, sync.packets_lost, roundi(sync.packet_loss * 100.0)],
	])
	if sync.is_simulating():
		lines.append("Simulated +%d ms (+0-%d) each way, %d%% loss" % [sync.sim_latency_ms, sync.sim_jitter_ms, roundi(sync.sim_loss * 100.0)])
	return "\n".join(lines)


## What the countdown shows at the start of `tick` for a fight starting at
## `start_tick`: whole seconds left ("3", "2", "1"), then "FIGHT!" for
## `FIGHT_TICKS`, then "" (also when there is no countdown).
static func countdown_text(tick: int, start_tick: int) -> String:
	if start_tick <= 0 or tick >= start_tick + FIGHT_TICKS:
		return ""
	if tick >= start_tick:
		return "FIGHT!"
	var ticks_left := start_tick - tick
	return str(ceili(float(ticks_left) / Fighter.TICK_RATE))


## The online status line: round trip `rtt_ms` ("?" while unknown, 0) and
## the input delay of this side's `LocalInput`, in ticks and ms.
static func net_status_text(rtt_ms: int, delay_ticks: int) -> String:
	var ping := "%d ms" % rtt_ms if rtt_ms > 0 else "? ms"
	return "Ping %s   Input delay %d (%d ms)" % [ping, delay_ticks, roundi(delay_ticks * 1000.0 / Fighter.TICK_RATE)]


## The line under "K.O.": the restart key offline; online, what the rematch
## is waiting for (`requested`: this player asked, `peer_requested`: the
## opponent did).
static func ko_hint(online: bool, requested: bool, peer_requested: bool) -> String:
	if not online:
		return "Press R to restart"
	if requested:
		return "Waiting for the opponent to accept the rematch..."
	if peer_requested:
		return "Opponent wants a rematch: press R to accept"
	return "Press R for a rematch"


static func _is_down(fighter: Fighter) -> bool:
	return fighter != null and fighter.state == Fighter.State.KNOCKED_DOWN


## Builds the hidden, screen-centered KO message.
func _make_ko() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	box.add_child(_make_label("K.O.", 48, KO_COLOR))
	_ko_hint = _make_label("", 16, Color.WHITE)
	box.add_child(_ko_hint)
	box.visible = false
	add_child(box)
	return box


## Adds the bottom-right toggle that shows/hides the controls panel. It never
## takes focus, so Space (jump) can't press it.
func _make_controls_button() -> Button:
	var button := Button.new()
	button.text = "Controls"
	button.toggle_mode = true
	button.focus_mode = FOCUS_NONE
	button.add_theme_font_size_override(&"font_size", CONTROLS_FONT_SIZE)
	button.toggled.connect(func(on: bool) -> void: _controls.visible = on)
	add_child(button)
	button.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT, PRESET_MODE_MINSIZE, int(BAR_MARGIN.y))
	return button


## Builds the hidden, screen-centered table of actions and their keys.
func _make_controls_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BORDER_COLOR, 0.85)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override(&"panel", style)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 12)
	for entry in CONTROLS:
		var action := _make_label(entry[1], CONTROLS_FONT_SIZE, HEALTH_COLOR)
		action.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(action)
		var keys := _make_label(_keys_for(entry[0]), CONTROLS_FONT_SIZE, Color.WHITE)
		keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(keys)
	panel.add_child(grid)
	panel.visible = false
	add_child(panel)
	panel.set_anchors_and_offsets_preset(PRESET_CENTER, PRESET_MODE_MINSIZE)
	return panel


## Key names bound to `action`, joined with " / ", as labeled on the player's
## keyboard layout (bindings are physical keys).
static func _keys_for(action: StringName) -> String:
	var names: PackedStringArray = []
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		var code := key.keycode
		if key.physical_keycode != KEY_NONE:
			if DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			else:
				code = key.physical_keycode
	return " / ".join(names)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", BORDER_COLOR)
	label.add_theme_constant_override(&"outline_size", maxi(font_size / 6, 2))
	return label


## Top of the name labels: `NAME_GAP` px under the bars' bottom border.
static func _name_top() -> float:
	return BAR_MARGIN.y + BAR_SIZE.y + BORDER + NAME_GAP


## Adds the name label under the left (or right) bar, aligned to its outer edge.
func _make_name(right: bool) -> Label:
	var label := _make_label("", NAME_FONT_SIZE, NAME_COLOR)
	label.add_theme_font_override(&"font", NAME_FONT)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.offset_top = _name_top()
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.anchor_left = 1.0
		label.anchor_right = 1.0
		label.offset_left = -BAR_MARGIN.x - BAR_SIZE.x
		label.offset_right = -BAR_MARGIN.x
	else:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.offset_left = BAR_MARGIN.x
		label.offset_right = BAR_MARGIN.x + BAR_SIZE.x
	add_child(label)
	return label


## Adds the special-ready star (hidden) on the name row at the inner end of
## the left (or right) bar.
func _make_star(right: bool) -> Control:
	var star := Control.new()
	star.mouse_filter = MOUSE_FILTER_IGNORE
	var side := STAR_RADIUS * 2.0
	# The inner end of the bar, measured from the screen edge it hangs off.
	var inner_edge := BAR_MARGIN.x + BAR_SIZE.x
	star.offset_top = _name_top() - 2.0
	star.offset_bottom = star.offset_top + side
	if right:
		star.anchor_left = 1.0
		star.anchor_right = 1.0
		star.offset_left = -inner_edge
		star.offset_right = -inner_edge + side
	else:
		star.offset_left = inner_edge - side
		star.offset_right = inner_edge
	star.draw.connect(_draw_star.bind(star))
	star.visible = false
	add_child(star)
	return star


## Draws a five-pointed star filling `star`, outlined like the labels.
static func _draw_star(star: Control) -> void:
	var center := star.size / 2.0
	var points := PackedVector2Array()
	for i in 10:
		var r := STAR_RADIUS if i % 2 == 0 else STAR_RADIUS * 0.45
		var angle := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	star.draw_colored_polygon(points, STAR_COLOR)
	points.append(points[0])
	star.draw_polyline(points, BORDER_COLOR, 1.0)


## Adds a bordered bar in the top-left (or top-right) corner and returns its fill.
func _make_bar(right: bool) -> ColorRect:
	var border := ColorRect.new()
	border.color = BORDER_COLOR
	border.size = BAR_SIZE + Vector2(BORDER, BORDER) * 2.0
	border.position = BAR_MARGIN - Vector2(BORDER, BORDER)
	if right:
		border.anchor_left = 1.0
		border.anchor_right = 1.0
		border.offset_left = -BAR_MARGIN.x - BAR_SIZE.x - BORDER
		border.offset_right = -BAR_MARGIN.x + BORDER
	border.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(border)
	var lost := ColorRect.new()
	lost.color = LOST_COLOR
	lost.position = Vector2(BORDER, BORDER)
	lost.size = BAR_SIZE
	lost.mouse_filter = MOUSE_FILTER_IGNORE
	border.add_child(lost)
	var fill := ColorRect.new()
	fill.color = HEALTH_COLOR
	fill.size = BAR_SIZE
	fill.mouse_filter = MOUSE_FILTER_IGNORE
	lost.add_child(fill)
	return fill


## Sizes `fill` to `fighter`'s health in whole pixels, anchored left, or right
## when `from_right`. No fighter reads as empty.
func _set_fill(fill: ColorRect, fighter: Fighter, from_right: bool) -> void:
	var ratio := float(fighter.health) / Fighter.MAX_HEALTH if fighter != null else 0.0
	var width := roundf(BAR_SIZE.x * ratio)
	fill.size.x = width
	fill.position.x = BAR_SIZE.x - width if from_right else 0.0
