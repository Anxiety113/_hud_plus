# HUD Plus -- default weights, timings and key bindings.
# Plain data + a ConfigFile sink so the mod is fully configured even when
# the optional "Mod Options Menu" library is not installed.
extends Reference

const CONFIG_PATH = "user://hud_plus_config.cfg"

# Scoring terms. Every weight is user-overridable.
var weights = {
	"dealt": 1.0,
	"kill": 8.0,
	"frame_advantage": 0.35,
	"corner_carry": 0.4,
	"taken": 1.0,
	"whiff": 2.5,
	"resource": 0.6,
	"armor_invuln": 1.2,
	# Master slider: scales ONLY the taken and whiff terms.
	"risk_aversion": 1.0,
}

# Search / pacing limits. Hard caps are enforced in scorer.gd too.
var sim = {
	"tick_depth": 24,
	"min_tick_depth": 6,
	"max_tick_depth": 60,
	"candidate_cap": 8,
	"rate_hz": 16,
	"frame_budget_ms": 4.0,
	"wall_budget_ms": 250.0,
}

var ui = {
	"enabled": true,
	# 0 = full, 1 = top only, 2 = off
	"verbosity": 0,
	"toggle_key": KEY_F7,
	"verbosity_key": KEY_F8,
	"drag_key": KEY_F6,
	"scale_key": KEY_F9,
	"offset_x": 14.0,
	"offset_y": 14.0,
	"scale": 1.0,
	"show_confidence": true,
}

func _init():
	load_config()

func _is_number(v):
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_REAL

func _load_section(f, section, target):
	if not f.has_section(section):
		return
	for k in target.keys():
		if not f.has_section_key(section, k):
			continue
		var v = f.get_value(section, k)
		if target[k] is bool:
			if typeof(v) == TYPE_BOOL:
				target[k] = v
		elif _is_number(v):
			target[k] = v

func load_config():
	var f = ConfigFile.new()
	if f.load(CONFIG_PATH) != OK:
		return
	_load_section(f, "weights", weights)
	_load_section(f, "sim", sim)
	_load_section(f, "ui", ui)
	# Clamp everything that could otherwise break the frame budget.
	sim["tick_depth"] = clamp(int(sim["tick_depth"]), int(sim["min_tick_depth"]), int(sim["max_tick_depth"]))
	sim["candidate_cap"] = clamp(int(sim["candidate_cap"]), 3, 8)
	sim["rate_hz"] = clamp(int(sim["rate_hz"]), 6, 20)
	sim["frame_budget_ms"] = clamp(float(sim["frame_budget_ms"]), 1.0, 4.0)
	ui["verbosity"] = clamp(int(ui["verbosity"]), 0, 2)
	ui["scale"] = clamp(float(ui["scale"]), 0.7, 1.8)
	weights["risk_aversion"] = clamp(float(weights["risk_aversion"]), 0.0, 3.0)

func save_config():
	var f = ConfigFile.new()
	for k in weights.keys():
		f.set_value("weights", k, weights[k])
	for k in sim.keys():
		f.set_value("sim", k, sim[k])
	for k in ui.keys():
		f.set_value("ui", k, ui[k])
	f.save(CONFIG_PATH)

func get_weight(key, fallback=0.0):
	if not weights.has(key):
		return fallback
	return float(weights[key])

func set_weight(key, value):
	if weights.has(key) and _is_number(value):
		weights[key] = float(value)

func set_ui(key, value):
	if ui.has(key):
		ui[key] = value
