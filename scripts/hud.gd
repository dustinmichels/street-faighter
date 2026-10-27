class_name Hud
extends Control
## Fight overlay drawn at the internal 480×270 resolution, on top of the game
## view (and outside its quantize shader). Health bars sit in the top corners;
## each fills from its outer edge, so lost health shows up next to the center.
## Once either fighter is knocked down, a centered "K.O." and a hint appear:
## offline the restart (`main.gd`), online the rematch status (`ko_hint()`).
## A "Controls" button in the bottom-right corner, or the `controls` action
## (Esc), toggles a panel listing the key bindings, read live from the
## InputMap. Before `Match.start_tick`
## a centered countdown (3, 2, 1) shows, then "FIGHT!" for `FIGHT_TICKS`;
## both come from the simulation tick, so peers show them on the same tick.

const BAR_SIZE := Vector2(200, 8)
## Gap between a bar and the screen's top and side edges (px).
const BAR_MARGIN := Vector2(12, 10)
const BORDER := 1
const BORDER_COLOR := Color(0.08, 0.06, 0.1)
const LOST_COLOR := Color(0.55, 0.1, 0.1)
const HEALTH_COLOR := Color(0.98, 0.82, 0.2)
const KO_COLOR := Color(0.95, 0.2, 0.15)
const COUNTDOWN_COLOR := Color.WHITE
## How long "FIGHT!" stays up after the countdown (ticks).
const FIGHT_TICKS := 45
## Actions listed in the controls panel, in display order, with their labels.
const CONTROLS: Array[Array] = [
	[&"move_left", "Move left"],
	[&"move_right", "Move right"],
	[&"jump", "Jump (hold to repeat)"],
	[&"punch", "Punch / air kick"],
	[&"block", "Block (hold)"],
	[&"restart", "Restart"],
	[&"controls", "Show controls"],
]
const CONTROLS_FONT_SIZE := 10

## Shown on the left bar.
@export var left_fighter: Fighter
## Shown on the right bar.
@export var right_fighter: Fighter
## Its `tick` and `start_tick` drive the countdown.
@export var fight: Match

var _left_fill: ColorRect
var _right_fill: ColorRect
## "K.O." plus `_ko_hint`, hidden until a knockdown.
var _ko: VBoxContainer
var _ko_hint: Label
## Key-binding list, hidden until the controls button is toggled on.
var _controls: PanelContainer
## Bottom-right toggle; its pressed state is the panel's visibility.
var _controls_button: Button
## Centered countdown / "FIGHT!", empty (hidden) otherwise.
var _countdown: Label


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_left_fill = _make_bar(false)
	_right_fill = _make_bar(true)
	_ko = _make_ko()
	_countdown = _make_label("", 48, COUNTDOWN_COLOR)
	_countdown.mouse_filter = MOUSE_FILTER_IGNORE
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_countdown)
	_countdown.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_controls = _make_controls_panel()
	_controls_button = _make_controls_button()
	_update()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"controls") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_controls_button.button_pressed = not _controls_button.button_pressed


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	_set_fill(_left_fill, left_fighter, false)
	_set_fill(_right_fill, right_fighter, true)
	_ko.visible = _is_down(left_fighter) or _is_down(right_fighter)
	if _ko.visible:
		_ko_hint.text = ko_hint(Session.is_online(), Session.rematch_requested, Session.peer_rematch_requested)
	if fight != null:
		_countdown.text = countdown_text(fight.tick, fight.start_tick)


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
			code = DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
		names.append(OS.get_keycode_string(code))
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
