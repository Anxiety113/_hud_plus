# HUD Plus -- module B: amortized candidate scoring.
# All simulation happens on a hidden ghost Game (throwaway clones).
# Live Fighters are read only. Work is split across frames by step().
extends Reference

var cfg = null
var guard = null
var statics = null

var _pending = []
var _results = []
var _index = 0
var _pass_active = false
var _pass_start_us = 0
var _sim_mode = false
var _effective_ticks = 24
var _shrunk = false
var _last_sample = null
var _last_game = null
var _last_me = null
var _last_opp = null
var _ghost = null
var _ghost_ready = false
var _ghost_match_key = ""
var _props = {}

# Test hook: a synthetic Game substitute can be injected for headless tests.
# Never set by the running mod.
var ghost_override = null

var _di_dirs = [Vector2(0, 0), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, -1)]
var _di_names = ["no DI", "DI left", "DI right", "DI down", "DI up"]
var _di_index = 0
var _di_needed = false
var _di_initialized = false
var _di_finalized = false
var _di_taken = []
var _di_result = "no DI"

func setup(config, safety, static_ranker):
	cfg = config
	guard = safety
	statics = static_ranker
	_effective_ticks = int(cfg.sim["tick_depth"])

func _set(obj, prop, value):
	if obj != null and is_instance_valid(obj):
		obj.set(prop, value)

func _get(obj, prop, default=null):
	if obj == null or not is_instance_valid(obj):
		return default
	return obj.get(prop)

func _num(v, fallback=0.0):
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_REAL:
		return float(v)
	if typeof(v) == TYPE_STRING and str(v).is_valid_float():
		return float(str(v))
	return fallback

func _vec2(v):
	if v is Vector2:
		return v
	if v is Dictionary:
		return Vector2(_num(v.get("x", 0.0)), _num(v.get("y", 0.0)))
	return Vector2.ZERO

func _find_viewport(game):
	var tree = game.get_tree()
	if tree == null:
		return null
	var root = tree.get_root()
	if root == null:
		return null
	var vp = root.find_node("GhostViewport", true, false)
	if vp != null:
		return vp
	return root

func _match_key(game):
	var md = _get(game, "match_data", null)
	if md is Dictionary:
		var names = str(md.get("selected_characters", ""))
		var seed_value = str(md.get("seed", ""))
		return names + "|" + seed_value
	return str(game.get_instance_id())

func _ensure_ghost(game):
	if game == null or not is_instance_valid(game):
		return false
	var key = _match_key(game)
	if _ghost != null and is_instance_valid(_ghost) and _ghost_match_key == key:
		return true
	if ghost_override != null and is_instance_valid(ghost_override):
		_ghost = ghost_override
		_ghost_match_key = key
		_ghost_ready = true
		return true
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_ready = false
	var scene = load("res://Game.tscn")
	if scene == null:
		return false
	var host = _find_viewport(game)
	if host == null:
		return false
	var g = scene.instance()
	if g == null:
		return false
	_set(g, "is_ghost", true)
	g.visible = false
	host.add_child(g)
	var md = _get(game, "match_data", null)
	if md is Dictionary and g.has_method("start_game"):
		g.call("start_game", true, md)
	_set(g, "ghost_speed", 100)
	_set(g, "ghost_freeze", false)
	if g.get("ai_skip_show_state") != null:
		_set(g, "ai_skip_show_state", true)
	_ghost = g
	_ghost_match_key = key
	_ghost_ready = true
	return true

func _prepare_ghost(g):
	# Mirror the same runtime baseline the game uses for ghost simulations.
	_set(g, "visible", false)
	_set(g, "is_ghost", true)
	_set(g, "is_afterimage", false)
	_set(g, "ghost_hidden", false)
	_set(g, "ghost_speed", 100)
	_set(g, "ghost_tick", 0)
	_set(g, "ghost_freeze", false)
	_set(g, "ghost_simulated_ticks", 0)
	_set(g, "ghost_actionable_freeze_ticks", 0)
	_set(g, "ghost_p1_actionable", false)
	_set(g, "ghost_p2_actionable", false)
	_set(g, "p1_ghost_ready_tick", null)
	_set(g, "p2_ghost_ready_tick", null)
	_set(g, "current_tick", -1)
	_set(g, "real_tick", 0)
	_set(g, "game_end_tick", 0)
	_set(g, "frame_passed", false)
	_set(g, "game_finished", false)
	_set(g, "parry_freeze", false)
	_set(g, "game_paused", false)
	_set(g, "buffer_playback", false)
	_set(g, "buffer_edit", false)
	_set(g, "advance_frame_input", false)
	_set(g, "simulated_once", false)
	_set(g, "super_freeze_ticks", 0)
	_set(g, "super_active", false)
	_set(g, "hit_freeze", false)
	_set(g, "prediction_effect", false)
	_set(g, "player_actionable", false)
	_set(g, "p1_turn", false)
	_set(g, "p2_turn", false)

func _player(g, id):
	if g == null:
		return null
	if g.has_method("get_player"):
		return g.call("get_player", id)
	if id == 1:
		return _get(g, "p1", null)
	return _get(g, "p2", null)

func _copy_live_to_ghost(game, g):
	if game.has_method("copy_to"):
		game.call("copy_to", g)
		return true
	# Minimal fallback if Game.copy_to is unavailable.
	var gp1 = _player(g, 1)
	var gp2 = _player(g, 2)
	var lp1 = _player(game, 1)
	var lp2 = _player(game, 2)
	if lp1 == null or lp2 == null or gp1 == null or gp2 == null:
		return false
	if not (lp1.has_method("copy_to") and lp2.has_method("copy_to")):
		return false
	lp1.call("copy_to", gp1)
	lp2.call("copy_to", gp2)
	if gp1.has_method("update_data"):
		gp1.call("update_data")
	if gp2.has_method("update_data"):
		gp2.call("update_data")
	return true

func _queue(f, action, data, extra, di=null):
	if f == null or not is_instance_valid(f):
		return
	_set(f, "is_ghost", true)
	_set(f, "queued_action", action)
	_set(f, "queued_data", data)
	_set(f, "queued_extra", extra)
	_set(f, "state_interruptable", false)
	_set(f, "dummy_interruptable", false)
	_set(f, "state_hit_cancellable", false)
	_set(f, "busy_interrupt", false)
	if di != null:
		_set(f, "current_di", di)

func _di_value(dir):
	# current_di is a dictionary of fixed-point strings in this build.
	return { "x": str(dir.x), "y": str(dir.y) }

func _simulate(cand, sample, game, di=null):
	if not _ensure_ghost(game):
		return null
	var g = _ghost
	if not _copy_live_to_ghost(game, g):
		return null
	_prepare_ghost(g)
	var me = _player(g, int(_last_me.get("id", 1)) if _last_me != null else 1)
	var opp = _player(g, int(_last_opp.get("id", 2)) if _last_opp != null else 2)
	if me == null or opp == null or not is_instance_valid(me) or not is_instance_valid(opp):
		guard.note_clone_result(false, _last_me)
		return null
	var divergent = not guard.checksums_compatible(_last_me, me)
	if divergent:
		# Keep simulating, but remember the divergence. After three occurrences
		# this character is forced to static-only for the rest of the session.
		guard.note_divergence(_last_me)

	var opp_action = str(sample.get("opp_queued_action", ""))
	if opp_action == "" or opp_action == "Continue":
		opp_action = "Continue"
	_queue(me, cand.name, cand.get("data", null), { "DI": Vector2(1, 0), "feint": false, "prediction": -1, "reverse": false }, di)
	_queue(opp, opp_action, null, { "DI": Vector2(-1, 0), "feint": false, "prediction": -1, "reverse": false })

	var hp_me_before = _num(_get(me, "hp", 0.0))
	var hp_opp_before = _num(_get(opp, "hp", 0.0))
	var pos_before = _vec2(opp.call("get_pos") if opp.has_method("get_pos") else null)
	var super_before = _num(_get(me, "super_meter", 0.0))
	var ticks = _effective_ticks
	for i in range(ticks):
		g.call("simulate_one_tick")
		if g.has_method("should_game_end") and g.call("should_game_end"):
			break

	var hp_me_after = _num(_get(me, "hp", 0.0))
	var hp_opp_after = _num(_get(opp, "hp", 0.0))
	var pos_after = _vec2(opp.call("get_pos") if opp.has_method("get_pos") else null)
	var dealt = max(0.0, hp_opp_before - hp_opp_after)
	var taken = max(0.0, hp_me_before - hp_me_after)
	var kill = hp_opp_after <= 0.0 and hp_opp_before > 0.0
	var whiff = 1.0 if dealt <= 0.0 and int(cand.get("damage", 0)) > 0 else 0.0
	var blocked = bool(_get(opp, "got_blocked", false)) or bool(_get(opp, "blocked_last_hit", false))
	var parried = bool(_get(me, "got_parried", false))
	var clashed = bool(_get(me, "clashing", false))
	var armor_used = bool(_get(me, "hit_during_armor", false)) or bool(_get(me, "has_hyper_armor", false))
	var invuln_used = bool(_get(me, "invulnerable", false)) and taken <= 0.0
	var end_minus = _num(_get(me, "minus_frames", 0.0))
	var end_adv = -end_minus
	var corner = abs(pos_after.x) - abs(pos_before.x)
	corner = clamp(corner, -80.0, 80.0)
	var resource_delta = max(0.0, _num(_get(me, "super_meter", 0.0)) - super_before)
	var cost = _num(cand.get("cost", 0.0))

	guard.note_success(_last_me)
	return {
		"name": cand.name,
		"dealt": dealt,
		"taken": taken,
		"kill": kill,
		"whiff": whiff,
		"blocked": blocked,
		"parried": parried,
		"clashed": clashed,
		"armor": armor_used,
		"invuln": invuln_used,
		"end_adv": end_adv,
		"corner": corner,
		"resource_delta": resource_delta,
		"resource_cost": cost,
		"startup": int(cand.get("startup", -1)),
		"opp_startup": int(sample.get("opponent_startup", -1)),
		"reach": _num(cand.get("reach", -1.0), -1.0),
		"damage": int(cand.get("damage", 0)),
		"static": false,
		"divergent": divergent,
		"unknown": bool(cand.get("unknown", false)),
		"ticks": ticks,
	}

func _reason(r):
	var parts = []
	if r.kill:
		parts.append("kills")
	elif r.dealt > 0.0:
		parts.append("hits for %d" % int(r.dealt))
	if r.taken > 0.0:
		parts.append("takes %d" % int(r.taken))
	if r.whiff > 0.5:
		parts.append("whiffs at this range")
	if r.blocked:
		parts.append("blocked")
	if r.parried:
		parts.append("parried")
	if r.clashed:
		parts.append("clashes")
	if r.armor:
		parts.append("armor absorbs hit")
	if r.invuln:
		parts.append("invulnerable")
	if int(r.startup) >= 0 and int(r.opp_startup) >= 0 and int(r.startup) < int(r.opp_startup):
		parts.append("beats %dF startup" % int(r.opp_startup))
	if r.end_adv > 0.0:
		parts.append("+%d frame advantage" % int(r.end_adv))
	if r.resource_cost > 0.0:
		parts.append("spends resource")
	if bool(r.unknown):
		parts.append("unknown frame data")
	if parts.empty():
		parts.append("no clear advantage")
	var trimmed = []
	for p in parts:
		if trimmed.size() >= 3:
			break
		trimmed.append(p)
	return trimmed

func _score(r):
	var w = cfg.weights
	var risk = float(w["risk_aversion"])
	var dmg_unit = 100.0
	var s = float(w["dealt"]) * (r.dealt / dmg_unit) \
		+ float(w["kill"]) * (1.0 if r.kill else 0.0) \
		+ float(w["frame_advantage"]) * r.end_adv \
		+ float(w["corner_carry"]) * (r.corner / 10.0) \
		+ float(w["armor_invuln"]) * ((1.0 if r.armor else 0.0) + (1.0 if r.invuln else 0.0)) \
		- risk * float(w["taken"]) * (r.taken / dmg_unit) \
		- risk * float(w["whiff"]) * r.whiff \
		- float(w["resource"]) * r.resource_cost
	if is_nan(s) or is_inf(s):
		s = 0.0
	return s

# ---- public pass interface ---------------------------------------------

func _signature(c):
	# String key: arrays as Dictionary keys are not reliably hashable in GDScript 3.
	return str(int(c.get("startup", -1))) + "|" + str(int(c.get("reach", -10))) + "|" \
		+ str(int(c.get("damage", 0))) + "|" + str(bool(c.get("armor", false))) + "|" \
		+ str(bool(c.get("invuln", false))) + "|" + str(int(c.get("cost", 0.0)))

func begin_pass(sample, game, me, opp):
	_last_sample = sample
	_last_game = game
	_last_me = me
	_last_opp = opp
	_results = []
	_pending = []
	_index = 0
	_pass_active = false
	_di_index = 0
	_di_needed = false
	_di_initialized = false
	_di_finalized = false
	_di_taken = []
	_di_result = "no DI"
	_effective_ticks = clamp(int(cfg.sim["tick_depth"]), int(cfg.sim["min_tick_depth"]), int(cfg.sim["max_tick_depth"]))
	_shrunk = false
	if sample == null or not bool(sample.get("valid", false)):
		return

	var candidates = sample.get("candidates", [])
	var cap = int(cfg.sim["candidate_cap"])
	var seen = {}
	for c in candidates:
		if _pending.size() >= cap:
			break
		var sig = _signature(c)
		if seen.has(sig):
			continue
		seen[sig] = true
		_pending.append(c)

	_sim_mode = guard.simulation_allowed() and game != null and guard.check_game(game) and not guard.is_static_character(me)
	if not _sim_mode and game != null:
		if guard.check_game(game) and not _ensure_ghost(game):
			_sim_mode = false
	_pass_active = not _pending.empty()
	_pass_start_us = OS.get_ticks_usec()

func _best_result():
	var best = null
	var best_score = -1e30
	for r in _results:
		var s = float(r.get("raw_score", 0.0))
		if s > best_score:
			best_score = s
			best = r
	return best

func _finalize_di():
	if _di_taken.empty():
		_di_result = "no DI"
		return
	var best_i = 0
	var best_t = float(_di_taken[0])
	for i in range(1, _di_taken.size()):
		if float(_di_taken[i]) < best_t:
			best_t = float(_di_taken[i])
			best_i = i
	# A direction that does not reduce damage is not a recommendation.
	var no_better = false
	if best_i == 0 and _di_taken.size() > 1 and best_t >= float(_di_taken[1]) - 0.01:
		no_better = true
	if best_t >= 1e29 or no_better:
		_di_result = "no DI"
	else:
		_di_result = _di_names[best_i]

func step(budget_ms=4.0):
	if not _pass_active:
		return true
	var deadline = OS.get_ticks_usec() + int(budget_ms * 1000.0)
	# Static mode is one cheap batch; simulation is one candidate per call.
	if not _sim_mode:
		var ranked = statics.rank(_pending, _last_sample, cfg)
		for r in ranked:
			r["raw_score"] = _score_static_like(r)
			r["reason"] = r.get("reason", "")
		_results = ranked
		_pass_active = false
		return true

	if _index < _pending.size():
		var cand = _pending[_index]
		_index += 1
		var outcome = null
		var can_sim = not guard.is_static_character(_last_me)
		if can_sim:
			outcome = _simulate(cand, _last_sample, _last_game)
		if outcome == null:
			outcome = _static_result_for(cand, _last_sample)
			guard.note_clone_result(false, _last_me)
		outcome["raw_score"] = _score(outcome)
		outcome["reason"] = ", ".join(_reason(outcome))
		_results.append(outcome)

	var elapsed_ms = float(OS.get_ticks_usec() - _pass_start_us) / 1000.0
	if elapsed_ms > float(cfg.sim["wall_budget_ms"]) and not _shrunk:
		_shrunk = true
		_effective_ticks = max(int(cfg.sim["min_tick_depth"]), int(_effective_ticks * 0.6))
		print("[HUD Plus] reducing search depth to " + str(_effective_ticks) + " ticks (wall budget)")

	if _index < _pending.size():
		return false
	if OS.get_ticks_usec() >= deadline:
		return false

	# DI search is amortized the same way: one extra rollout per frame.
	if not _di_initialized:
		_di_initialized = true
		var best = _best_result()
		_di_needed = best != null and float(best.get("taken", 0.0)) > 0.0
		if not _di_needed:
			_di_finalized = true
	if not _di_finalized:
		if _di_index < _di_dirs.size():
			var r = _simulate(_pending[0], _last_sample, _last_game, _di_value(_di_dirs[_di_index]))
			_di_taken.append(float(r.get("taken", 1e30)) if r != null else 1e30)
			_di_index += 1
			if OS.get_ticks_usec() >= deadline or _di_index < _di_dirs.size():
				return false
		_finalize_di()
		_di_finalized = true
	_pass_active = false
	return true

func _score_static_like(r):
	return float(r.get("raw_score", 0.0))

func _static_result_for(cand, sample):
	var r = statics.rank([cand], sample, cfg)
	if r.empty():
		return {
			"name": str(cand.get("name", "?")), "dealt": 0.0, "taken": 0.0,
			"kill": false, "whiff": 1.0, "blocked": false, "parried": false,
			"clashed": false, "armor": false, "invuln": false,
			"end_adv": 0.0, "corner": 0.0, "resource_delta": 0.0,
			"resource_cost": _num(cand.get("cost", 0.0)),
			"startup": int(cand.get("startup", -1)),
			"opp_startup": int(sample.get("opponent_startup", -1)),
			"reach": _num(cand.get("reach", -1.0), -1.0),
			"damage": int(cand.get("damage", 0)),
			"static": true, "unknown": bool(cand.get("unknown", false)), "ticks": 0,
		}
	var first = r[0]
	return {
		"name": first.name,
		"dealt": 0.0,
		"taken": 0.0,
		"kill": false,
		"whiff": 1.0 if first.components.get("whiff", 0.0) > 0.5 else 0.0,
		"blocked": false,
		"parried": false,
		"clashed": false,
		"armor": bool(cand.get("armor", false)),
		"invuln": bool(cand.get("invuln", false)),
		"end_adv": 0.0,
		"corner": 0.0,
		"resource_delta": 0.0,
		"resource_cost": _num(cand.get("cost", 0.0)),
		"startup": int(cand.get("startup", -1)),
		"opp_startup": int(sample.get("opponent_startup", -1)),
		"reach": _num(cand.get("reach", -1.0), -1.0),
		"damage": int(cand.get("damage", 0)),
		"static": true,
		"unknown": bool(cand.get("unknown", false)),
		"ticks": 0,
	}

func get_results():
	var ranked = _results.duplicate(true)
	if ranked.empty():
		return {
			"rows": [], "confidence": 0.0, "static": not _sim_mode,
			"di": "no DI", "status": guard.status_string(), "valid": false,
		}
	ranked.sort_custom(self, "_sort_by_score")
	var lo = float(ranked[ranked.size() - 1].get("raw_score", 0.0))
	var hi = float(ranked[0].get("raw_score", 0.0))
	var span = hi - lo
	for i in range(ranked.size()):
		var display = 60.0
		if span > 0.0001:
			display = 20.0 + 80.0 * (float(ranked[i].get("raw_score", 0.0)) - lo) / span
		ranked[i]["score"] = clamp(display, 0.0, 100.0)

	var top = float(ranked[0].get("raw_score", 0.0))
	var second = float(ranked[1].get("raw_score", 0.0)) if ranked.size() > 1 else 0.0
	var spread = abs(top - second) / max(1.0, abs(top))
	var confidence = clamp(spread * 120.0, 0.0, 100.0)
	var any_static = false
	for r in ranked:
		if bool(r.get("static", false)):
			any_static = true
			break
	if any_static or not _sim_mode:
		confidence *= 0.55
	confidence = clamp(confidence, 0.0, 100.0)

	var di = _di_result if _sim_mode else "no DI"

	var label = "close call -- low confidence" if confidence < 30.0 else ""
	return {
		"rows": ranked,
		"confidence": confidence,
		"static": any_static or not _sim_mode,
		"di": di,
		"status": guard.status_string(),
		"note": label,
		"valid": true,
	}

func _sort_by_score(a, b):
	return float(a.get("raw_score", 0.0)) > float(b.get("raw_score", 0.0))

func reset_match():
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_ready = false
	_ghost_match_key = ""
	_pending = []
	_results = []
	_pass_active = false
