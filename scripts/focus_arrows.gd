class_name FocusArrows
extends RefCounted
## Menu button cursor shared by the menu screens: the focused button's text is
## framed by "> <", and hovering a button focuses it, so mouse, keyboard and
## gamepad share one cursor. The text without arrows is kept in the button's
## `META` metadata.

const META := &"focus_arrows_text"


static func add(button: Button) -> void:
	button.set_meta(META, button.text)
	button.focus_entered.connect(_update.bind(button))
	button.focus_exited.connect(_update.bind(button))
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			button.grab_focus())


## Changes `button`'s text (without arrows) after `add()`.
static func set_text(button: Button, text: String) -> void:
	button.set_meta(META, text)
	_update(button)


static func _update(button: Button) -> void:
	var text: String = button.get_meta(META)
	button.text = "> %s <" % text if button.has_focus() else text
