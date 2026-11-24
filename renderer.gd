# HUD Plus -- module C: a deliberately plain, small top-left CanvasLayer HUD.
extends CanvasLayer

var cfg = null
var panel = null
var header = null
var footer = null
var rows = []
var game_ref = null
var _font = null
var _scale_anchor_y = 0.0
var _last_result = null

func setup(config):
	cfg = config
	layer = 90
	_build()
	apply_settings()

func _make_font(size):
	var probe = Label.new()
	var base = probe.get_font("font")
	probe.free()
	if base is DynamicFont:
		var f = base.duplicate()
		f.size = size
		return f
	return null

func _label(text, min_w=0):
	var l = Label.new()
	l.text = text
	if min_w > 0:
		l.rect_min_size.x = min_w
	if _font != null:
		l.add_font_override("font", _font)
	l.set_modulate(Color(0.88, 0.90, 0.92, 0.95))
	return l

func _build():
	_font = _make_font(11)
	panel = Panel.new()
	panel.name = "HUDPlusPanel"
	add_child(panel)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.055, 0.07, 0.86)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.24, 0.28, 0.34, 0.9)
	sb.set_content_margin_all(6)
	panel.add_stylebox_override("panel", sb)

	var box = VBoxContainer.new()
	box.set_grow_horizontal(Control.GROW_DIRECTION_END)
	panel.add_child(box)
	header = _label("HUD Plus", 0)
	header.set_modulate(Color(0.60, 0.68, 0.76, 0.85))
	box.add_child(header)

	for i in range(3):
		var row = HBoxContainer.new()
		row.name = "Row" + str(i)
		var rank = _label(str(i + 1), 16)
		var name_l = _label("-", 96)
		var bar_bg = ColorRect.new()
		bar_bg.rect_min_size = Vector2(64, 7)
		bar_bg.color = Color(0.16, 0.18, 0.21, 0.9)
		var bar_fill = ColorRect.new()
		bar_fill.rect_min_size = Vector2(0, 7)
		bar_fill.color = Color(0.3, 0.7, 0.4, 0.9)
		bar_bg.add_child(bar_fill)
		var score = _label("0", 26)
		var reason = _label("", 128)
		row.add_child(rank)
		row.add_child(name_l)
		row.add_child(bar_bg)
		row.add_child(score)
		row.add_child(reason)
		box.add_child(row)
		rows.append({
			"root": row, "rank": rank, "name": name_l,
			"bar": bar_bg, "fill": bar_fill, "score": score, "reason": reason,
		})

	footer = _label("", 0)
	footer.set_modulate(Color(0.55, 0.62, 0.70, 0.85))
	box.add_child(footer)
	panel.rect_size = Vector2(340, 96)

func apply_settings():
	if panel == null or cfg == null:
		return
	panel.set_position(Vector2(float(cfg.ui["offset_x"]), float(cfg.ui["offset_y"])))
	var s = clamp(float(cfg.ui["scale"]), 0.7, 1.8)
	panel.set_scale(Vector2(s, s))

func _color_for(score):
	if score >= 70.0:
		return Color(0.32, 0.78, 0.42, 0.95)
	if score >= 40.0:
		return Color(0.92, 0.68, 0.22, 0.95)
	return Color(0.85, 0.32, 0.32, 0.95)

func set_game(g):
	game_ref = g

func show_result(result):
	_last_result = result
	if panel == null or result == null or not bool(result.get("valid", false)):
		return
	var list = result.get("rows", [])
	var verbosity = int(cfg.ui["verbosity"])
	var shown = 3 if verbosity == 0 else 1
	for i in range(rows.size()):
		var r = rows[i]
		if i >= shown or i >= list.size():
			r.root.hide()
			continue
		r.root.show()
		var entry = list[i]
		var s = clamp(float(entry.get("score", 0.0)), 0.0, 100.0)
		r.rank.text = str(i + 1)
		r.name.text = str(entry.get("name", "?"))
		r.score.text = "%d" % int(s)
		r.reason.text = str(entry.get("reason", ""))
		var c = _color_for(s)
		r.fill.color = c
		r.name.set_modulate(c if i == 0 else Color(0.88, 0.90, 0.92, 0.95))
		r.fill.rect_min_size.x = 64.0 * (s / 100.0)
		r.bar.update_minimum_size()
		if bool(entry.get("static", false)):
			r.reason.text = "static: " + r.reason.text
	var confidence = float(result.get("confidence", 0.0))
	var static = bool(result.get("static", false))
	var di = str(result.get("di", "no DI"))
	var txt = "confidence %d%%" % int(confidence)
	if cfg.ui["show_confidence"]:
		txt += "  |  " + str(result.get("status", ""))
	txt += "  |  " + di
	if static:
		txt += "  |  STATIC"
	if result.has("note") and str(result["note"]) != "":
		txt += "  |  " + str(result["note"])
	footer.text = txt

func _match_active():
	if game_ref == null or not is_instance_valid(game_ref):
		return false
	if not bool(game_ref.get("game_started")):
		return false
	if bool(game_ref.get("is_ghost")) or bool(game_ref.get("spectating")):
		return false
	var replay = get_node_or_null("/root/ReplayManager")
	if replay != null and bool(replay.get("playback")):
		return false
	return true

func _process(_delta):
	if panel == null:
		return
	var allowed = cfg != null and bool(cfg.ui["enabled"]) and int(cfg.ui["verbosity"]) != 2 and _match_active()
	panel.visible = allowed
	if not allowed:
		return
	var mouse = get_viewport().get_mouse_position()
	if Input.is_key_pressed(int(cfg.ui["drag_key"])):
		panel.set_position(mouse - Vector2(12, 12))
		cfg.ui["offset_x"] = panel.position.x
		cfg.ui["offset_y"] = panel.position.y
	elif Input.is_key_pressed(int(cfg.ui["scale_key"])):
		var dy = mouse.y - _scale_anchor_y
		var s = clamp(float(cfg.ui["scale"]) + dy * 0.001, 0.7, 1.8)
		cfg.ui["scale"] = s
		panel.set_scale(Vector2(s, s))
	_scale_anchor_y = mouse.y

func _unhandled_input(event):
	if cfg == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code = event.scancode
	if code == int(cfg.ui["toggle_key"]):
		cfg.ui["enabled"] = not bool(cfg.ui["enabled"])
		cfg.save_config()
		get_tree().set_input_as_handled()
	elif code == int(cfg.ui["verbosity_key"]):
		cfg.ui["verbosity"] = (int(cfg.ui["verbosity"]) + 1) % 3
		cfg.save_config()
		if _last_result != null:
			show_result(_last_result)
		get_tree().set_input_as_handled()
