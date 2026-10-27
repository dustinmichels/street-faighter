class_name CharacterScreen
extends Control
## The "CHARACTERS" screen of the start menu (`menu.gd`): the character
## library, "CREATE NEW" (the questionnaire, `CharacterWizard`, then a review
## page with the prompt that writes a creator kit, `CreatorKit`) and
## "IMPORT…". The menu shows it with `open()`, forwards Esc to `go_back()`,
## and takes over again on `closed`.

## Emitted when the player leaves the screen (BACK, or Esc on the library).
signal closed

enum Page { LIBRARY, WIZARD, REVIEW }

## Characters that ship with the game: display name → model.
const BUILTIN := {"DEFAULT": "res://characters/default/default.glb"}
## Lines scrolled per up/down press on the review page.
const SCROLL_LINES := 3

@onready var _library_page: Control = %LibraryPage
@onready var _library: ItemList = %Library
@onready var _create: Button = %Create
@onready var _import: Button = %Import
@onready var _close: Button = %Close
@onready var _wizard_page: Control = %WizardPage
@onready var _wizard: CharacterWizard = %Wizard
@onready var _review_page: Control = %ReviewPage
@onready var _prompt: TextEdit = %Prompt
@onready var _status: Label = %Status
@onready var _review_back: Button = %ReviewBack
@onready var _copy_prompt: Button = %CopyPrompt
@onready var _save_kit: Button = %SaveKit
@onready var _kit_folder: Button = %KitFolder

var _page := Page.LIBRARY


func _ready() -> void:
	for button: Button in [_create, _import, _close, _review_back, _copy_prompt, _save_kit, _kit_folder]:
		FocusArrows.add(button)
	_close.pressed.connect(closed.emit)
	_create.pressed.connect(_on_create_pressed)
	_wizard.canceled.connect(open)
	_wizard.finished.connect(_open_review)
	_review_back.pressed.connect(_back_to_wizard)
	_copy_prompt.pressed.connect(_on_copy_prompt_pressed)
	_save_kit.pressed.connect(_on_save_kit_pressed)
	_kit_folder.pressed.connect(_on_kit_folder_pressed)
	_fill_library()


## Up/down on the review page scroll the prompt: its buttons are one row, so
## the keys are free, and a gamepad can't focus the text itself.
func _input(event: InputEvent) -> void:
	if _page != Page.REVIEW or not get_viewport().get_embedded_subwindows().is_empty():
		return
	var lines := 0
	if event.is_action_pressed(&"ui_up", true):
		lines = -SCROLL_LINES
	elif event.is_action_pressed(&"ui_down", true):
		lines = SCROLL_LINES
	if lines != 0:
		_prompt.scroll_vertical += lines
		get_viewport().set_input_as_handled()


## Shows the library page with "CREATE NEW" focused.
func open() -> void:
	_show(Page.LIBRARY)
	_create.grab_focus()


## Esc: back one page; on the library, leaves the screen.
func go_back() -> void:
	match _page:
		Page.LIBRARY:
			closed.emit()
		Page.WIZARD:
			_wizard.back()
		Page.REVIEW:
			_back_to_wizard()


func _show(page: Page) -> void:
	_page = page
	_library_page.visible = page == Page.LIBRARY
	_wizard_page.visible = page == Page.WIZARD
	_review_page.visible = page == Page.REVIEW


func _on_create_pressed() -> void:
	_show(Page.WIZARD)
	_wizard.reset()


func _open_review() -> void:
	_show(Page.REVIEW)
	_prompt.text = CreatorKit.prompt(_wizard.answers())
	_prompt.scroll_vertical = 0
	_show_kit_dir()
	_save_kit.grab_focus()


func _back_to_wizard() -> void:
	_show(Page.WIZARD)
	_wizard.resume()


func _on_copy_prompt_pressed() -> void:
	DisplayServer.clipboard_set(_prompt.text)
	_status.text = "PROMPT COPIED. SAVE THE KIT TOO: YOUR AGENT WORKS IN ITS FOLDER."


func _on_save_kit_pressed() -> void:
	var folder := CreatorKit.write(CreatorKit.saved_dir(), _wizard.answers())
	if folder.is_empty():
		_status.text = "COULD NOT SAVE THE KIT TO %s. TRY ANOTHER FOLDER." % CreatorKit.saved_dir()
		return
	_status.text = CreatorKit.hand_off(folder)


func _on_kit_folder_pressed() -> void:
	CreatorKit.choose_dir(self, func(_dir: String) -> void:
		_show_kit_dir()
		_save_kit.grab_focus())


func _show_kit_dir() -> void:
	_status.text = "KITS ARE SAVED IN %s" % CreatorKit.saved_dir()


func _fill_library() -> void:
	_library.clear()
	for name: String in BUILTIN:
		_library.add_item("%s  (BUILT-IN)" % name)
