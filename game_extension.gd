# Extends the live Game script only to attach our read-only controller node.
# We do not override simulation or input methods.
extends "res://game.gd"

var _hud_plus_controller = null

func _ready():
	._ready()
	if is_ghost:
		return
	var script = load("res://_hud_plus/hud_controller.gd")
	if script == null:
		return
	var node = script.new()
	if node == null:
		return
	node.name = "HUDPlusController"
	add_child(node)
	_hud_plus_controller = node
