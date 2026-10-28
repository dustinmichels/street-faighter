class_name CharacterWizard
extends VBoxContainer
## The "CREATE NEW" questionnaire of `CharacterScreen`: five short pages
## (`PAGES`) sized for the 480x270 menu, built in code. Every input is a
## focusable control, so keyboard (arrows/Tab, Enter, Esc), gamepad (d-pad,
## A, B) and mouse all work; only the text fields need typing. The outfit
## fields, notes and special move are optional; whatever is left blank is up
## to the agent, and a blank special move keeps the standard throw.
## `answers()` returns the answers in the `CreatorKit` format.

## The player moved past the last page.
signal finished
## The player went back from the first page.
signal canceled

enum Page {
	IDENTITY,
	LOOK,
	OUTFIT,
	NOTES,
	SPECIAL,
}

const PAGES := {
	Page.IDENTITY: "WHO IS IT?",
	Page.LOOK: "LOOK",
	Page.OUTFIT: "OUTFIT",
	Page.NOTES: "ANYTHING ELSE?",
	Page.SPECIAL: "SPECIAL MOVE",
}
## The OUTFIT page's fields: `CreatorKit.OPTIONAL_KEYS` key → label and
## placeholder.
const OUTFIT := {
	"headgear": ["HEADGEAR", "red headband"],
	"shirt": ["SHIRT", "sleeveless gi top"],
	"pants": ["PANTS", "baggy black gi pants"],
	"accessories": ["ACCESSORIES", "gold chain, taped fists"],
}
## Pick-list entry that leaves the answer to the agent (empty answer).
const ANY := "ANY"
const ARCHETYPES := [
	ANY,
	"BRAWLER",
	"MARTIAL ARTIST",
	"WRESTLER",
	"BOXER",
	"ROBOT",
	"MONSTER",
	"STREET PUNK",
	"KNIGHT",
	"NINJA",
	"ANIMAL",
]
const BUILDS := ["SLIM", "ATHLETIC", "HEAVY", "HUGE"]
## Palette keys in `CreatorKit` order, with their swatch labels.
const PALETTE_KEYS := { "main": "MAIN", "secondary": "2ND", "accent": "ACCENT", "base": "SKIN" }
## Palettes to pick from (sRGB); the first one fills a new questionnaire.
const PRESETS := {
	"STREET": ["#c02a20", "#2a2f45", "#f2c230", "#d9a07a"],
	"NEON": ["#19d9ff", "#1a1030", "#ff3fa4", "#c8b6ff"],
	"STEEL": ["#8a96a8", "#3a3f4a", "#ff7a1a", "#c9ced6"],
	"JUNGLE": ["#4f7a2a", "#6b4a2a", "#f2e2a0", "#8a5a3a"],
}
## The palette choice that unlocks the swatches for editing.
const CUSTOM := "CUSTOM"
const HINT_COLOR := Color(0.6, 0.58, 0.7, 1)
const LABEL_COLOR := Color(0.1, 0.85, 1, 1)
const ERROR_COLOR := Color(1, 0.55, 0.35, 1)
const FIELD_WIDTH := 200.0

var _page := Page.IDENTITY
var _pages: Array[Control] = []
var _step: Label
var _title: Label
var _body: Control
var _error: Label
var _back: Button
var _next: Button

var _name: LineEdit
var _slug: Label
var _concept: LineEdit
var _archetype: OptionButton
var _build: OptionButton
var _colors := { } # palette key → ColorPickerButton
var _palettes := { } # PRESETS key or CUSTOM → its toggle Button
var _palette := "" # the shown PRESETS key or CUSTOM
var _custom: Array[Color] = [] # the CUSTOM colors, kept while a preset is shown
var _outfit := { } # OUTFIT key → its LineEdit
var _notes: LineEdit
var _special: LineEdit


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(400, 0)
	_step = _label("", HINT_COLOR)
	_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_step)
	_title = _label("", Color(0.98, 0.82, 0.2, 1))
	_title.add_theme_font_size_override("font_size", 16)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(0, 150)
	add_child(_body)
	_error = _label("", ERROR_COLOR)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_error)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 24)
	add_child(footer)
	_back = _button("BACK", footer)
	_back.pressed.connect(back)
	_next = _button("NEXT", footer)
	_next.pressed.connect(_on_next_pressed)
	var hint := _label("ENTER: OK    ESC: BACK", HINT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	for page: Page in PAGES:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.visible = false
		_body.add_child(box)
		_pages.append(box)
		_build_page(page, box)
	reset()


## A blank questionnaire (first palette preset), on the first page.
func reset() -> void:
	for edit: LineEdit in [_name, _concept, _notes, _special] + _outfit.values():
		edit.text = ""
	_archetype.select(0)
	_build.select(1)
	_select_palette(PRESETS.keys()[0])
	_custom.clear()
	_update_slug("")
	_show_page(Page.IDENTITY)


## Shows the last page again (back from the review).
func resume() -> void:
	_show_page(PAGES.size() - 1 as Page)


## Esc or BACK: the previous page, or `canceled` on the first.
func back() -> void:
	if _page == Page.IDENTITY:
		canceled.emit()
	else:
		_show_page(_page - 1 as Page)


## The answers in the `CreatorKit` format. `ANY` gives an empty archetype.
func answers() -> Dictionary:
	var palette := { }
	for key: String in _colors:
		palette[key] = "#" + _colors[key].color.to_html(false)
	var out := {
		"name": _name.text.strip_edges(),
		"concept": _concept.text.strip_edges(),
		"archetype": _pick(_archetype),
		"build": _pick(_build),
		"palette": palette,
		"notes": _notes.text.strip_edges(),
		"special": _special.text.strip_edges(),
	}
	for key: String in _outfit:
		out[key] = _outfit[key].text.strip_edges()
	return out


static func _pick(option: OptionButton) -> String:
	var item := option.get_item_text(option.selected)
	return "" if item == ANY else item.to_lower()


func _build_page(page: Page, box: Control) -> void:
	match page:
		Page.IDENTITY:
			_name = _field(box, "NAME (REQUIRED)", "BIG TONY", CreatorKit.max_length("name"))
			_name.text_changed.connect(_update_slug)
			_slug = _label("", HINT_COLOR)
			box.add_child(_slug)
			_concept = _field(
				box,
				"CONCEPT IN ONE SENTENCE",
				"a retired sumo wrestler turned subway busker",
				CreatorKit.max_length("concept"),
			)
			_concept.custom_minimum_size.x = 380
		Page.LOOK:
			_archetype = _choice(box, "TYPE", ARCHETYPES)
			_build = _choice(box, "BUILD", BUILDS)
			var palettes := _row(box, "COLORS")
			var group := ButtonGroup.new()
			for palette: String in PRESETS.keys() + [CUSTOM]:
				var button := _button(palette, palettes)
				button.toggle_mode = true
				button.button_group = group
				button.pressed.connect(_select_palette.bind(palette))
				_palettes[palette] = button
			# Left/right stay in the row: geometrically the swatches below can
			# be nearer than the next preset.
			var buttons := palettes.get_children().filter(
				func(node: Node) -> bool:
					return node is Button,
			)
			for i in buttons.size():
				buttons[i].focus_neighbor_left = buttons[maxi(i - 1, 0)].get_path()
				buttons[i].focus_neighbor_right = buttons[mini(i + 1, buttons.size() - 1)].get_path()
			var swatches := _row(box, "")
			swatches.add_theme_constant_override("separation", 8)
			for key: String in PALETTE_KEYS:
				var swatch := VBoxContainer.new()
				swatch.add_theme_constant_override("separation", 0)
				swatches.add_child(swatch)
				var label := _label(PALETTE_KEYS[key], HINT_COLOR)
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				swatch.add_child(label)
				var picker := ColorPickerButton.new()
				picker.custom_minimum_size = Vector2(48, 14)
				picker.edit_alpha = false
				_setup_picker(picker.get_picker())
				swatch.add_child(picker)
				_colors[key] = picker
		Page.OUTFIT:
			for key: String in OUTFIT:
				var edit := _line_edit(OUTFIT[key][1], CreatorKit.max_length(key))
				_row(box, OUTFIT[key][0]).add_child(edit)
				_outfit[key] = edit
			box.add_child(_note("All optional. Blank ones are up to the agent."))
		Page.NOTES:
			_notes = _field(
				box,
				"HAIR, FACE, EXTRAS (OPTIONAL)",
				"slicked-back pompadour, a scar over the left eye",
				CreatorKit.max_length("notes"),
			)
			_notes.custom_minimum_size.x = 380
			box.add_child(_note("Leave it blank and the agent designs the rest from your concept."))
		Page.SPECIAL:
			_special = _field(
				box,
				"YOUR SPECIAL THROW (OPTIONAL)",
				"a death roll that spins them and slams them down",
				CreatorKit.max_length("special"),
			)
			_special.custom_minimum_size.x = 380
			box.add_child(
				_note(
					"The agent animates it on both fighters. It looks different, but works like the standard throw. Leave it blank to keep the standard one."
				)
			)


func _show_page(page: Page) -> void:
	_page = page
	for i in _pages.size():
		_pages[i].visible = i == page
	_step.text = "NEW CHARACTER  %d/%d" % [page + 1, PAGES.size()]
	_title.text = PAGES[page]
	_error.text = ""
	FocusArrows.set_text(_next, "REVIEW" if page == PAGES.size() - 1 else "NEXT")
	var first := _first_focusable(_pages[page])
	if first != null:
		first.grab_focus()


func _on_next_pressed() -> void:
	if _page == Page.IDENTITY and _name.text.strip_edges().is_empty():
		_error.text = "A NAME IS REQUIRED"
		_name.grab_focus()
		return
	if _page == PAGES.size() - 1:
		finished.emit()
	else:
		_show_page(_page + 1 as Page)


func _update_slug(text: String) -> void:
	_slug.text = "FILE NAME: %s.glb" % CreatorKit.slug(text) if not text.strip_edges().is_empty() else ""


## Shows palette `name` (a `PRESETS` key or `CUSTOM`). Only `CUSTOM` makes the
## swatches editable; it starts from the shown preset and keeps its edits
## while a preset is shown.
func _select_palette(name: String) -> void:
	if _palette == CUSTOM:
		_custom.assign(
			_colors.values().map(
				func(p: ColorPickerButton) -> Color:
					return p.color,
			)
		)
	_palette = name
	_palettes[name].set_pressed(true) # unpresses the others; emits only `toggled`
	var custom := name == CUSTOM
	var i := 0
	for picker: ColorPickerButton in _colors.values():
		if not custom:
			picker.color = Color.html(PRESETS[name][i])
		elif not _custom.is_empty():
			picker.color = _custom[i]
		picker.disabled = not custom
		picker.focus_mode = Control.FOCUS_ALL if custom else Control.FOCUS_NONE
		i += 1


## A compact picker that fits the 480x270 menu: sliders and hex only.
static func _setup_picker(picker: ColorPicker) -> void:
	picker.picker_shape = ColorPicker.SHAPE_NONE
	picker.presets_visible = false
	picker.sampler_visible = false
	picker.color_modes_visible = false
	picker.can_add_swatches = false
	picker.edit_intensity = false


static func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and child.visible:
			if child.focus_mode == Control.FOCUS_ALL:
				return child
			var inner := _first_focusable(child)
			if inner != null:
				return inner
	return null


## A row: a fixed-width label (blank for "", to line up with labeled rows),
## then the controls added to it.
func _row(box: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var label := _label(text, LABEL_COLOR)
	label.custom_minimum_size.x = 96
	row.add_child(label)
	return row


## A labeled text field (see `_line_edit()`).
func _field(box: Control, text: String, placeholder: String, limit: int) -> LineEdit:
	var edit := _line_edit(placeholder, limit)
	box.add_child(_label(text, LABEL_COLOR))
	box.add_child(edit)
	return edit


## A text field taking at most `limit` characters (the `CreatorKit.sanitize()`
## cap, so nothing typed is cut off later); Enter moves on to the next control.
func _line_edit(placeholder: String, limit: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = limit
	edit.custom_minimum_size.x = FIELD_WIDTH
	edit.context_menu_enabled = false
	edit.text_submitted.connect(
		func(_t: String) -> void:
			_focus_next(edit),
	)
	return edit


func _focus_next(from: Control) -> void:
	var next := from.find_next_valid_focus()
	if next != null and next != _back:
		next.grab_focus()
	else:
		_next.grab_focus()


## A labeled pick list.
func _choice(box: Control, text: String, items: Array) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.x = 160
	option.fit_to_longest_item = false
	for item: String in items:
		option.add_item(item)
	_row(box, text).add_child(option)
	return option


func _button(text: String, parent: Control) -> Button:
	var button := Button.new()
	button.text = text
	parent.add_child(button)
	FocusArrows.add(button)
	return button


static func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label


static func _note(text: String) -> Label:
	var label := _label(text, HINT_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 380
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
