extends Node
## First autoload: with `-- --validate-character <file.glb>` (`CreatorKit.VALIDATE_ARG`)
## the game validates the file instead of starting, prints one problem per line
## (warnings prefixed "Warning: ") or `OK`, and exits with 0 (valid) or 1.
##
##   <game> --headless -- --validate-character <file.glb>
##
## An autoload rather than a `-s` script because official export templates
## ignore `-s`. It runs in `_init`, before the later autoloads are even loaded;
## the main scene is still instantiated for the one frame before the quit.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find(CreatorKit.VALIDATE_ARG)
	if at == -1:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if at + 1 >= args.size():
		printerr("Usage: %s <file.glb>" % CreatorKit.VALIDATE_ARG)
		tree.quit(1)
		return
	var validator := CharacterValidator.new()
	var errors := validator.validate(args[at + 1])
	if validator.scene != null:
		validator.scene.free()
	for warning in validator.warnings:
		print("Warning: ", warning)
	for error in errors:
		print(error)
	if errors.is_empty():
		print("OK")
	tree.quit(0 if errors.is_empty() else 1)
