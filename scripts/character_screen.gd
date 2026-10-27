class_name CharacterScreen
extends Control
## The "CHARACTERS" screen of the start menu (`menu.gd`): the character
## library, "CREATE NEW" (the questionnaire, `CharacterWizard`, that writes a
## creator kit, `CreatorKit`) and "IMPORT…". The menu shows it with `open()`,
## forwards Esc to `go_back()`, and takes over again on `closed`.

## Emitted when the player leaves the screen (BACK, or Esc on the library).
signal closed

enum Page { LIBRARY, WIZARD }

## Characters that ship with the game: display name → model.
const BUILTIN := {"DEFAULT": "res://characters/default/default.glb"}

@onready var _library_page: Control = %LibraryPage
@onready var _library: ItemList = %Library
@onready var _create: Button = %Create
@onready var _import: Button = %Import
@onready var _close: Button = %Close
@onready var _wizard_page: Control = %WizardPage
@onready var _wizard: CharacterWizard = %Wizard

var _page := Page.LIBRARY


func _ready() -> void:
	for button: Button in [_create, _import, _close]:
		FocusArrows.add(button)
	_close.pressed.connect(closed.emit)
	_create.pressed.connect(_on_create_pressed)
	_wizard.canceled.connect(open)
	_fill_library()


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


func _show(page: Page) -> void:
	_page = page
	_library_page.visible = page == Page.LIBRARY
	_wizard_page.visible = page == Page.WIZARD


func _on_create_pressed() -> void:
	_show(Page.WIZARD)
	_wizard.reset()


func _fill_library() -> void:
	_library.clear()
	for name: String in BUILTIN:
		_library.add_item("%s  (BUILT-IN)" % name)
