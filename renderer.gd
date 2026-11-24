# HUD Plus -- compact, muted top-left overlay.
extends CanvasLayer

var cfg = null
var panel = null
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

func _label(text, min_w=0, alpha=0.9):
	var l = Label.new()
	l.text = text
	l.clip_text = true
	if min_w > 0:
		l.rect_min_size.x = min_w
		l.size_flags_horizontal = Control.SIZE_FILL
	if _font != null:
		l.add_font_override("font", _font)
	l.set_modulate(Color(0.82, 0.86, 0.90, alpha))
	return l

func _build():
	_font = _make_font(9)
	panel = Panel.new()
	panel.name = "HUDPlusPanel"
	panel.rect_min_size = Vector2(292, 70)
	panel.rect_size = Vector2(292, 70)
	panel.rect_clip_content = true
	add_child(panel)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.06, 0.78)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.20, 0.24, 0.28, 0.75)
	sb.set_content_margin_all(4)
	panel.add_stylebox_override("panel", sb)

	var box = VBoxContainer.new()
	box.separation = 0
	panel.add_child(box)
	var header = _label("HUD+", 0, 0.55)
	box.add_child(header)

	for i in range(3):
		var row = HBoxContainer.new()
		row.separation = 3
		row.rect_min_size.y = 11
		var rank = _label(str(i + 1), 10, 0.55)
		var name_l = _label("-", 76)
		var bar_bg = ColorRect.new()
		bar_bg.rect_min_size = Vector2(34, 5)
		bar_bg.rect_size = Vector2(34, 5)
		bar_bg.color = Color(0.14, 0.16, 0.18, 0.9)
		var bar_fill = ColorRect.new()
		bar_fill.rect_min_size = Vector2(0, 5)
		bar_fill.color = Color(0.3, 0.7, 0.4, 0.9)
		bar_bg.add_child(bar_fill)
		var score = _label("0", 16, 0.7)
		var reason = _label("", 128, 0.8)
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

	footer = _label("", 0, 0.55)
	footer.rect_min_size.x = 284
	box.add_child(footer)

func apply_settings():
	if panel == null or cfg == null:
		return
	panel.set_position(Vector2(float(cfg.ui["offset_x"]), float(cfg.ui["offset_y"])))
	var s = clamp(float(cfg.ui["scale"]), 0.7, 1.8)
	panel.set_scale(Vector2(s, s))

func _color_for(score):
	if score >= 70.0:
		return Color(0.30, 0.74, 0.40, 0.95)
	if score >= 40.0:
		return Color(0.88, 0.64, 0.20, 0.95)
	return Color(0.82, 0.30, 0.30, 0.95)

func _short(text, limit):
	if text.length() <= limit:
		return text
	return text.substr(0, limit - 1) + "~"

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
		r.name.text = _short(str(entry.get("name", "?")), 12)
		r.score.text = str(int(s))
		var why = str(entry.get("reason", ""))
		if bool(entry.get("static", false)):
			why = "static " + why
		r.reason.text = _short(why, 26)
		var c = _color_for(s)
		r.fill.color = c
		r.name.set_modulate(c if i == 0 else Color(0.82, 0.86, 0.90, 0.9))
		r.fill.rect_min_size.x = 34.0 * (s / 100.0)
		r.bar.update_minimum_size()

	var bits = []
	bits.append(str(int(result.get("confidence", 0.0))) + "%")
	bits.append(str(result.get("status", "")))
	bits.append(str(result.get("di", "no DI")))
	if bool(result.get("static", false)):
		bits.append("STATIC")
	if result.has("note") and str(result["note"]) != "":
		bits.append(str(result["note"]))
	footer.text = _short(" | ".join(bits), 46)

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
		panel.set_position(mouse - Vector2(8, 8))
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
