class_name CharacterScreen
extends Control
## The "CHARACTERS" screen of the start menu (`menu.gd`): the character
## library (`CharacterLibrary`) with a turning preview of the selected entry
## (`CharacterPreview`), "CREATE NEW" (the questionnaire, `CharacterWizard`,
## then a review page with the prompt that writes a creator kit, `CreatorKit`)
## and "IMPORT…" (a page listing the validator's errors if the file is
## rejected). The menu shows it with `open()`, forwards Esc to `go_back()`,
## and takes over again on `closed`.
##
## With `selecting` on (singleplayer), it is the character select: the
## library opens on the player's saved choice (`CharacterLibrary.chosen()`),
## and "FIGHT!" (or activating an entry) saves the selected one and emits
## `fight`.

## Emitted when the player leaves the screen (BACK, or Esc on the library).
signal closed
## Emitted by "FIGHT!" after saving the selection as
## `CharacterLibrary.PLAYER_CHOICE`.
signal fight

enum Page { LIBRARY, WIZARD, REVIEW, ERRORS }

## Library page titles, browsing and selecting.
const TITLE := "CHARACTERS"
const SELECT_TITLE := "CHOOSE YOUR FIGHTER"
## Lines scrolled per up/down press on the review and errors pages.
const SCROLL_LINES := 3

## Character select for singleplayer (see the class doc); set before `open()`.
var selecting := false

@onready var _library_page: Control = %LibraryPage
@onready var _library_title: Label = %LibraryTitle
@onready var _fight: Button = %Fight
@onready var _library: ItemList = %Library
@onready var _preview: CharacterPreview = %Preview
@onready var _punch: Button = %Punch
@onready var _reimport: Button = %Reimport
@onready var _delete: Button = %Delete
@onready var _create: Button = %Create
@onready var _import: Button = %Import
@onready var _close: Button = %Close
@onready var _library_status: Label = %LibraryStatus
@onready var _wizard_page: Control = %WizardPage
@onready var _wizard: CharacterWizard = %Wizard
@onready var _review_page: Control = %ReviewPage
@onready var _prompt: TextEdit = %Prompt
@onready var _status: Label = %Status
@onready var _review_back: Button = %ReviewBack
@onready var _copy_prompt: Button = %CopyPrompt
@onready var _save_kit: Button = %SaveKit
@onready var _kit_folder: Button = %KitFolder
@onready var _errors_page: Control = %ErrorsPage
@onready var _errors_title: Label = %ErrorsTitle
@onready var _errors: TextEdit = %Errors
@onready var _errors_status: Label = %ErrorsStatus
@onready var _errors_back: Button = %ErrorsBack
@onready var _copy_errors: Button = %CopyErrors

var _page := Page.LIBRARY
# Entry id armed by a first DELETE press; a second press deletes it.
var _delete_armed := ""


func _ready() -> void:
	for button: Button in [_fight, _punch, _reimport, _delete, _create, _import, _close, _review_back,
			_copy_prompt, _save_kit, _kit_folder, _errors_back, _copy_errors]:
		FocusArrows.add(button)
	_close.pressed.connect(closed.emit)
	_fight.pressed.connect(_on_fight_pressed)
	_library.item_activated.connect(_on_item_activated.unbind(1))
	_create.pressed.connect(_on_create_pressed)
	_wizard.canceled.connect(_open_library)
	_wizard.finished.connect(_open_review)
	_review_back.pressed.connect(_back_to_wizard)
	_copy_prompt.pressed.connect(_on_copy_prompt_pressed)
	_save_kit.pressed.connect(_on_save_kit_pressed)
	_kit_folder.pressed.connect(_on_kit_folder_pressed)
	_import.pressed.connect(_on_import_pressed)
	_reimport.pressed.connect(_on_reimport_pressed)
	_punch.pressed.connect(_preview.punch)
	_delete.pressed.connect(_on_delete_pressed)
	_library.item_selected.connect(_on_selection_changed.unbind(1))
	_errors_back.pressed.connect(_back_to_library)
	_copy_errors.pressed.connect(_on_copy_errors_pressed)
	get_window().files_dropped.connect(_on_files_dropped)


## Up/down on the review and errors pages scroll the text: their buttons are
## one row, so the keys are free, and a gamepad can't focus the text itself.
func _input(event: InputEvent) -> void:
	var text: TextEdit = {Page.REVIEW: _prompt, Page.ERRORS: _errors}.get(_page)
	if text == null or not get_viewport().get_embedded_subwindows().is_empty():
		return
	var lines := 0
	if event.is_action_pressed(&"ui_up", true):
		lines = -SCROLL_LINES
	elif event.is_action_pressed(&"ui_down", true):
		lines = SCROLL_LINES
	if lines != 0:
		text.scroll_vertical += lines
		get_viewport().set_input_as_handled()


## Shows the library page with "CREATE NEW" focused, keeping the selection;
## when `selecting`, on the player's saved choice with "FIGHT!" focused.
func open() -> void:
	_library_title.text = SELECT_TITLE if selecting else TITLE
	_fight.visible = selecting
	_open_library(CharacterLibrary.chosen(CharacterLibrary.PLAYER_CHOICE) if selecting
			else _selected_choice())


# Back on the (refreshed) library page from another page, with `choice`
# selected.
func _open_library(choice := _selected_choice()) -> void:
	_show(Page.LIBRARY)
	_fill_library(choice)
	(_fight if selecting else _create).grab_focus()


## Esc: back one page; on the library, leaves the screen.
func go_back() -> void:
	match _page:
		Page.LIBRARY:
			closed.emit()
		Page.WIZARD:
			_wizard.back()
		Page.REVIEW:
			_back_to_wizard()
		Page.ERRORS:
			_back_to_library()


func _show(page: Page) -> void:
	_page = page
	_library_page.visible = page == Page.LIBRARY
	_wizard_page.visible = page == Page.WIZARD
	_review_page.visible = page == Page.REVIEW
	_errors_page.visible = page == Page.ERRORS


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


func _on_import_pressed() -> void:
	CharacterLibrary.choose_glb(self, _import_file)


## A `.glb` dropped onto the window while this screen is shown is imported
## like one picked with "IMPORT…".
func _on_files_dropped(files: PackedStringArray) -> void:
	if not is_visible_in_tree():
		return
	_open_library()
	var path := CharacterLibrary.first_glb(files)
	if path.is_empty():
		_library_status.text = "ONLY .GLB FILES CAN BE IMPORTED."
		return
	_import_file(path)


## Imports the `.glb` at `path`: back on the library with the entry selected,
## or the errors page if the validator rejects it.
func _import_file(path: String) -> void:
	var result := CharacterLibrary.import_file(path)
	if _show_result(path, result, _import):
		_library_status.text = ("IMPORTED %s." if result.added else "%s IS ALREADY IN THE LIBRARY.") \
				% _entry_name(result.id)


## Re-imports the selected entry from its source file; the new entry (if the
## file changed) replaces it and stays selected.
func _on_reimport_pressed() -> void:
	var id := _selected_id()
	if id.is_empty():
		return
	var source: String = CharacterLibrary.entry(id).get("source", "")
	var result := CharacterLibrary.reimport(id)
	if _show_result(source, result, _reimport):
		_library_status.text = ("RE-IMPORTED %s." if result.id != id else "%s IS UNCHANGED.") \
				% _entry_name(result.id)


## First press arms, second press (same entry) deletes; any other selection
## disarms.
func _on_delete_pressed() -> void:
	var id := _selected_id()
	if id.is_empty():
		return
	if _delete_armed != id:
		_delete_armed = id
		_delete.text = "SURE? DELETE"
		_library_status.text = "PRESS DELETE AGAIN TO REMOVE %s. ITS SOURCE FILE IS KEPT." % _entry_name(id)
		return
	var name := _entry_name(id)
	# Then select the entry below it (or above, if it was the last).
	var index: int = _library.get_selected_items()[0]
	var next := index + 1 if index + 1 < _library.item_count else index - 1
	var next_choice: String = _library.get_item_metadata(next).choice
	CharacterLibrary.delete(id)
	_fill_library(next_choice)
	_library_status.text = "DELETED %s." % name
	_library.grab_focus()


# Shows the errors page, or the library with the entry selected and `focus`
# focused. Returns true on success.
func _show_result(path: String, result: Dictionary, focus: Button) -> bool:
	if not result.errors.is_empty():
		_show_errors(path, result.errors)
		return false
	_open_library(result.id)
	focus.grab_focus()
	return true


func _entry_name(id: String) -> String:
	return CharacterLibrary.entry(id).get("name", "").to_upper()


func _show_errors(path: String, errors: PackedStringArray) -> void:
	_show(Page.ERRORS)
	_errors_title.text = "CAN'T IMPORT %s" % path.get_file().to_upper()
	_errors.text = "The game's validator rejected %s:\n- %s\n" % [path, "\n- ".join(errors)]
	_errors.scroll_vertical = 0
	_errors_status.text = "PASTE THESE TO YOUR AGENT, THEN IMPORT AGAIN."
	_copy_errors.grab_focus()


func _on_copy_errors_pressed() -> void:
	DisplayServer.clipboard_set(_errors.text)
	_errors_status.text = "ERRORS COPIED. PASTE THEM TO YOUR AGENT."


func _back_to_library() -> void:
	_open_library()
	_import.grab_focus()


## Built-in characters first, then the imported ones, selecting `choice` (an
## entry id or a `CharacterLibrary.BUILTIN` name; the first item if absent).
## Item metadata: `{id, choice, model}`, where `id` is "" for built-in ones.
func _fill_library(choice := "") -> void:
	_library.clear()
	var selected := 0
	for name: String in CharacterLibrary.BUILTIN:
		var index := _library.add_item("%s  (BUILT-IN)" % name)
		_library.set_item_metadata(index, {"id": "", "choice": name, "model": CharacterLibrary.BUILTIN[name]})
		if name == choice:
			selected = index
	for info in CharacterLibrary.entries():
		var index := _library.add_item(info.name.to_upper())
		_library.set_item_metadata(index, {"id": info.id, "choice": info.id, "model": CharacterLibrary.glb_path(info.id)})
		_library.set_item_tooltip(index, info.source)
		if info.id == choice:
			selected = index
	_library.select(selected)
	_library.ensure_current_is_visible()
	_on_selection_changed()


# Id of the selected imported entry, or "" (a built-in one).
func _selected_id() -> String:
	var selected := _library.get_selected_items()
	return "" if selected.is_empty() else _library.get_item_metadata(selected[0]).id


# `CharacterLibrary` choice of the selected entry, or "" if none.
func _selected_choice() -> String:
	var selected := _library.get_selected_items()
	return "" if selected.is_empty() else _library.get_item_metadata(selected[0]).choice


## Saves the selected entry as the player's character and emits `fight`.
func _on_fight_pressed() -> void:
	var choice := _selected_choice()
	if choice.is_empty():
		return
	CharacterLibrary.choose(CharacterLibrary.PLAYER_CHOICE, choice)
	fight.emit()


# Enter / double click on an entry: "FIGHT!" while selecting.
func _on_item_activated() -> void:
	if selecting:
		_on_fight_pressed()


func _on_selection_changed() -> void:
	var selected := _library.get_selected_items()
	var model: String = "" if selected.is_empty() else _library.get_item_metadata(selected[0]).model
	if not _preview.show_character(model):
		_library_status.text = "CAN'T SHOW THIS CHARACTER. TRY RE-IMPORT."
	var imported := not _selected_id().is_empty()
	_reimport.disabled = not imported
	_delete.disabled = not imported
	_punch.disabled = _preview.path.is_empty()
	_delete_armed = ""
	_delete.text = "DELETE"
