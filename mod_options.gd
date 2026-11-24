# Optional settings panel. Only installed when SoupModOptions is present.
# Every value is mirrored to the same user:// config the hardcoded defaults
# use, so the two modes behave identically.
extends "res://SoupModOptions/ModOptions.gd"

var _cfg = null
var _bindings = {}
var _poll = 0.0
var _dirty = false

func _ready():
	var Config = load("res://_hud_plus/scoring_config.gd")
	_cfg = Config.new()
	var menu = generate_menu("_HUDPlusOptions", "HUD Plus")
	menu.add_label("hud_title", "HUD Plus -- combat advisor")
	menu.add_label("hud_note", "Read-only advice. Nothing is submitted automatically.")

	_bindings["dealt"] = menu.add_number_slider("hud_w_dealt", "Weight: Damage Dealt", _cfg.weights["dealt"], { min_value = 0.0, max_value = 3.0, step = 0.05 })
	_bindings["kill"] = menu.add_number_slider("hud_w_kill", "Weight: Kill", _cfg.weights["kill"], { min_value = 0.0, max_value = 20.0, step = 0.5 })
	_bindings["frame_advantage"] = menu.add_number_slider("hud_w_adv", "Weight: Frame Advantage", _cfg.weights["frame_advantage"], { min_value = 0.0, max_value = 2.0, step = 0.05 })
	_bindings["corner_carry"] = menu.add_number_slider("hud_w_corner", "Weight: Corner Carry", _cfg.weights["corner_carry"], { min_value = 0.0, max_value = 2.0, step = 0.05 })
	_bindings["taken"] = menu.add_number_slider("hud_w_taken", "Weight: Damage Taken", _cfg.weights["taken"], { min_value = 0.0, max_value = 3.0, step = 0.05 })
	_bindings["whiff"] = menu.add_number_slider("hud_w_whiff", "Weight: Whiff", _cfg.weights["whiff"], { min_value = 0.0, max_value = 6.0, step = 0.1 })
	_bindings["resource"] = menu.add_number_slider("hud_w_res", "Weight: Resource Cost", _cfg.weights["resource"], { min_value = 0.0, max_value = 3.0, step = 0.05 })
	_bindings["armor_invuln"] = menu.add_number_slider("hud_w_armor", "Weight: Armor / Invuln", _cfg.weights["armor_invuln"], { min_value = 0.0, max_value = 4.0, step = 0.1 })
	_bindings["risk_aversion"] = menu.add_number_slider("hud_risk", "Risk Aversion", _cfg.weights["risk_aversion"], { min_value = 0.0, max_value = 3.0, step = 0.05 })
	menu.add_label("hud_risk_note", "Risk Aversion scales only the damage-taken and whiff penalties.")

	_bindings["tick_depth"] = menu.add_number_spinbox("hud_ticks", "Sim Ticks", _cfg.sim["tick_depth"], { min_value = 6, max_value = 60, step = 1, rounded = true })
	_bindings["candidate_cap"] = menu.add_number_spinbox("hud_caps", "Candidate Cap", _cfg.sim["candidate_cap"], { min_value = 3, max_value = 8, step = 1, rounded = true })
	_bindings["rate_hz"] = menu.add_number_spinbox("hud_hz", "Refresh Hz", _cfg.sim["rate_hz"], { min_value = 6, max_value = 20, step = 1, rounded = true })
	menu.add_label("hud_perf_note", "Work is capped at 4 ms per frame and split across frames.")

	add_menu(menu)

func _has_prop(obj, name):
	if obj == null or not is_instance_valid(obj):
		return false
	for p in obj.get_property_list():
		if str(p.get("name", "")) == name:
			return true
	return false

func _read_number(ctl):
	if ctl == null:
		return null
	for prop in ["value", "spinbox_value", "current_option", "text"]:
		if _has_prop(ctl, prop):
			var v = ctl.get(prop)
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_REAL:
				return float(v)
			if typeof(v) == TYPE_STRING and str(v).is_valid_float():
				return float(str(v))
	return null

func _process(delta):
	_poll += delta
	if _poll < 0.5 or _cfg == null:
		return
	_poll = 0.0
	for key in ["dealt", "kill", "frame_advantage", "corner_carry", "taken", "whiff", "resource", "armor_invuln", "risk_aversion"]:
		var v = _read_number(_bindings.get(key, null))
		if v != null and abs(float(_cfg.weights[key]) - v) > 0.0001:
			_cfg.set_weight(key, v)
			_dirty = true
	for key in ["tick_depth", "candidate_cap", "rate_hz"]:
		var v2 = _read_number(_bindings.get(key, null))
		if v2 != null and int(_cfg.sim[key]) != int(v2):
			_cfg.sim[key] = int(v2)
			_dirty = true
	if _dirty:
		_cfg.save_config()
		_dirty = false
