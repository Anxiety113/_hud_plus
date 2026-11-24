extends Node

var _installed = false

# The YOMI mod loader normally passes itself as the argument. If it does not,
# resolve the autoload from the running SceneTree instead. This avoids a hard
# compile-time reference to the ModLoader identifier.
func _init(modLoader = null):
	if modLoader == null:
		var loop = Engine.get_main_loop()
		if loop is SceneTree and loop.root != null:
			modLoader = loop.root.get_node_or_null("ModLoader")
	_install(modLoader)

func _ready():
	# Last-resort fallback for loaders that instantiate before the tree exists.
	var loader = get_node_or_null("/root/ModLoader")
	if loader != null:
		_install(loader)

func _install(modLoader):
	if _installed or modLoader == null or not modLoader.has_method("installScriptExtension"):
		return
	_installed = true
	modLoader.installScriptExtension("res://_hud_plus/game_extension.gd")
	# Soft dependency: only wire the options panel if the library exists.
	if ResourceLoader.exists("res://SoupModOptions/ModOptions.gd") and ResourceLoader.exists("res://_hud_plus/mod_options.gd"):
		modLoader.installScriptExtension("res://_hud_plus/mod_options.gd")
