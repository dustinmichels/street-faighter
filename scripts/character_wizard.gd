class_name CharacterWizard
extends VBoxContainer
## The "CREATE NEW" questionnaire of `CharacterScreen`: short pages of
## questions (`PAGES`) sized for the 480x270 menu, built in code. Every input
## is a focusable control, so keyboard (arrows/Tab, Enter, Esc), gamepad
## (d-pad, A, B) and mouse all work; only the text fields need typing.
## `answers()` returns the answers in the `CreatorKit` format.

## The player moved past the last page.
signal finished
## The player went back from the first page.
signal canceled

enum Page { IDENTITY, ARCHETYPE, BUILD, HEAD, OUTFIT, PALETTE, ACCESSORIES, NOTES }

const PAGES := {
	Page.IDENTITY: "WHO IS IT?",
	Page.ARCHETYPE: "ARCHETYPE",
	Page.BUILD: "BUILD",
	Page.HEAD: "HEAD",
	Page.OUTFIT: "OUTFIT",
	Page.PALETTE: "PALETTE",
	Page.ACCESSORIES: "ACCESSORIES",
	Page.NOTES: "ANYTHING ELSE?",
}
## Pick-list entry whose answer is only the free text next to it.
const OTHER := "OTHER"
const ARCHETYPES := ["BRAWLER", "MARTIAL ARTIST", "WRESTLER", "BOXER", "ROBOT", "MONSTER",
		"STREET PUNK", "KNIGHT", "NINJA", "ANIMAL", OTHER]
const BUILDS := ["SLIM", "ATHLETIC", "HEAVY", "HUGE"]
const HEADS := ["HUMAN", "HELMET", "MASK", "ANIMAL", "ROBOT"]
const TOPS := ["T-SHIRT", "TANK TOP", "GI JACKET", "LEATHER JACKET", "HOODIE", "BARE CHEST",
		"ARMOR", OTHER]
const BOTTOMS := ["JEANS", "GI PANTS", "SHORTS", "CARGO PANTS", "TIGHTS", "ARMOR", OTHER]
const FOOTWEAR := ["SNEAKERS", "BOOTS", "BAREFOOT", "SANDALS", "ARMORED BOOTS", OTHER]
const ACCESSORIES := ["BELT", "GLOVES", "SHOULDER PADS", "SCARF", "BACKPACK", "TAIL",
		"CAPE", "KNEE PADS", "HEADBAND", "SUNGLASSES", "CHAIN", "WRIST WRAPS"]
## Palette keys in `CreatorKit` order, with their labels.
const PALETTE_KEYS := {"main": "MAIN", "secondary": "SECONDARY", "accent": "ACCENT", "base": "SKIN / BASE"}
## Starting palettes (sRGB); the first one fills a new questionnaire.
const PRESETS := {
	"STREET": ["#c02a20", "#2a2f45", "#f2c230", "#d9a07a"],
	"NEON": ["#19d9ff", "#1a1030", "#ff3fa4", "#c8b6ff"],
	"STEEL": ["#8a96a8", "#3a3f4a", "#ff7a1a", "#c9ced6"],
	"JUNGLE": ["#4f7a2a", "#6b4a2a", "#f2e2a0", "#8a5a3a"],
}
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
var _archetype_other: LineEdit
var _build: OptionButton
var _head: OptionButton
var _headwear: LineEdit
var _outfit := {}  # key → [OptionButton, LineEdit]
var _colors := {}  # palette key → ColorPickerButton
var _accessories: Array[Button] = []
var _notes: LineEdit


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
	for edit: LineEdit in [_name, _concept, _archetype_other, _headwear, _notes]:
		edit.text = ""
	for pair: Array in _outfit.values():
		pair[0].select(0)
		pair[1].text = ""
	_archetype.select(0)
	_build.select(1)
	_head.select(0)
	_apply_preset(PRESETS.keys()[0])
	for button in _accessories:
		button.button_pressed = false
	_update_slug("")
	_update_other(_archetype.selected)
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


## The answers in the `CreatorKit` format. A pick with free text gives
## "pick, text", `OTHER` gives the text alone.
func answers() -> Dictionary:
	var palette := {}
	for key: String in _colors:
		palette[key] = "#" + _colors[key].color.to_html(false)
	var picked: Array[String] = []
	for button in _accessories:
		if button.button_pressed:
			picked.append(str(button.get_meta(&"item")).to_lower())
	return {
		"name": _name.text.strip_edges(),
		"concept": _concept.text.strip_edges(),
		"archetype": _pick(_archetype, _archetype_other),
		"build": _pick(_build, null),
		"head": _pick(_head, null),
		"headwear": _headwear.text.strip_edges(),
		"top": _pick(_outfit.top[0], _outfit.top[1]),
		"bottom": _pick(_outfit.bottom[0], _outfit.bottom[1]),
		"footwear": _pick(_outfit.footwear[0], _outfit.footwear[1]),
		"palette": palette,
		"accessories": picked,
		"notes": _notes.text.strip_edges(),
	}


static func _pick(option: OptionButton, detail: LineEdit) -> String:
	var item := option.get_item_text(option.selected)
	var text := detail.text.strip_edges() if detail != null else ""
	if item == OTHER:
		return text
	item = item.to_lower()
	return item if text.is_empty() else "%s, %s" % [item, text]

func _build_page(page: Page, box: Control) -> void:
	match page:
		Page.IDENTITY:
			_name = _field(box, "NAME (REQUIRED)", "BIG TONY")
			_name.text_changed.connect(_update_slug)
			_slug = _label("", HINT_COLOR)
			box.add_child(_slug)
			_concept = _field(box, "CONCEPT IN ONE SENTENCE", "a retired sumo wrestler turned subway busker")
			_concept.custom_minimum_size.x = 380
		Page.ARCHETYPE:
			_archetype = _choice(box, "TYPE", ARCHETYPES)
			_archetype.item_selected.connect(_update_other)
			_archetype_other = _field(_row(box, "OTHER"), "", "")
		Page.BUILD:
			_build = _choice(box, "BUILD", BUILDS)
			box.add_child(_note("The joints are fixed: the build changes how bulky the parts are, not the length of the limbs."))
		Page.HEAD:
			_head = _choice(box, "HEAD", HEADS)
			_headwear = _field(_row(box, "HAIR/HAT"), "", "topknot, red bandana")
		Page.OUTFIT:
			for row: Array in [["top", "TOP", TOPS], ["bottom", "BOTTOM", BOTTOMS], ["footwear", "FOOTWEAR", FOOTWEAR]]:
				var option := _choice(box, row[1], row[2])
				var detail := _field(option.get_parent(), "", "details")
				detail.custom_minimum_size.x = 140
				_outfit[row[0]] = [option, detail]
		Page.PALETTE:
			var presets := HBoxContainer.new()
			presets.alignment = BoxContainer.ALIGNMENT_CENTER
			presets.add_theme_constant_override("separation", 8)
			box.add_child(presets)
			for preset: String in PRESETS:
				_button(preset, presets).pressed.connect(_apply_preset.bind(preset))
			for key: String in PALETTE_KEYS:
				var row := _row(box, PALETTE_KEYS[key])
				var picker := ColorPickerButton.new()
				picker.custom_minimum_size = Vector2(FIELD_WIDTH, 14)
				picker.edit_alpha = false
				_setup_picker(picker.get_picker())
				row.add_child(picker)
				_colors[key] = picker
		Page.ACCESSORIES:
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 4)
			grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(grid)
			for item: String in ACCESSORIES:
				var button := _button("", grid)
				button.toggle_mode = true
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.custom_minimum_size.x = 128
				button.set_meta(&"item", item)
				button.toggled.connect(_update_accessory.bind(button))
				_update_accessory(false, button)
				_accessories.append(button)
		Page.NOTES:
			_notes = _field(box, "ANYTHING ELSE THE AGENT SHOULD KNOW?", "a scar over the left eye")
			_notes.custom_minimum_size.x = 380
			box.add_child(_note("Next: review the prompt for your AI agent and save the creator kit."))


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


## The free-text "other" only takes input when OTHER is picked.
func _update_other(index: int) -> void:
	var other := _archetype.get_item_text(index) == OTHER
	_archetype_other.editable = other
	_archetype_other.focus_mode = Control.FOCUS_ALL if other else Control.FOCUS_NONE
	_archetype_other.placeholder_text = "describe it" if other else "pick OTHER to describe your own"


func _update_accessory(on: bool, button: Button) -> void:
	FocusArrows.set_text(button, "[%s] %s" % ["X" if on else " ", button.get_meta(&"item")])


func _apply_preset(preset: String) -> void:
	var colors: Array = PRESETS[preset]
	var i := 0
	for key: String in _colors:
		_colors[key].color = Color.html(colors[i])
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


## A row: a fixed-width label, then the controls added to it.
func _row(box: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	if not text.is_empty():
		var label := _label(text, LABEL_COLOR)
		label.custom_minimum_size.x = 96
		row.add_child(label)
	return row


## A labeled text field; Enter moves on to the next control.
func _field(box: Control, text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size.x = FIELD_WIDTH
	edit.context_menu_enabled = false
	edit.text_submitted.connect(func(_t: String) -> void: _focus_next(edit))
	if text.is_empty():
		box.add_child(edit)
	else:
		var label := _label(text, LABEL_COLOR)
		box.add_child(label)
		box.add_child(edit)
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
