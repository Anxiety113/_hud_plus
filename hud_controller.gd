# HUD Plus -- orchestrator. Added as a child of the live Game node by the
# game script extension. Owns all four modules and never mutates game state.
extends Node

var cfg = null
var guard = null
var statics = null
var sampler = null
var scorer = null
var renderer = null
var game = null

var _me = null
var _opp = null
var _my_id = 1
var _next_pass_us = 0
var _pass_done = true
var _last_state_key = ""
var _active = false
var _debug_passes = 0
var _debug_results = 0

func _ready():
	set_process(true)
	var Config = load("res://_hud_plus/scoring_config.gd")
	var Guard = load("res://_hud_plus/guard.gd")
	var Statics = load("res://_hud_plus/static_heuristics.gd")
	var Sampler = load("res://_hud_plus/sampler.gd")
	var Scorer = load("res://_hud_plus/scorer.gd")
	var Renderer = load("res://_hud_plus/renderer.gd")
	cfg = Config.new()
	guard = Guard.new(str(ProjectSettings.get_setting("application/config/version", "")))
	statics = Statics.new()
	sampler = Sampler.new()
	scorer = Scorer.new()
	renderer = Renderer.new()
	add_child(renderer)
	scorer.setup(cfg, guard, statics)
	renderer.setup(cfg)
	game = get_parent()
	guard.check_game(game)
	print("[HUD Plus] loaded; " + guard.status_string())

func _player(g, id):
	if g == null or not is_instance_valid(g):
		return null
	if g.has_method("get_player"):
		return g.call("get_player", id)
	if id == 1:
		return g.get("p1")
	return g.get("p2")

func _resolve_players():
	if game == null or not is_instance_valid(game):
		_active = false
		return
	# Fighter.is_you() is authoritative about which side the local player owns.
	var p1 = _player(game, 1)
	var p2 = _player(game, 2)
	var id = 1
	if p1 != null and is_instance_valid(p1) and p1.has_method("is_you") and bool(p1.call("is_you", false)):
		id = 1
	elif p2 != null and is_instance_valid(p2) and p2.has_method("is_you") and bool(p2.call("is_you", false)):
		id = 2
	else:
		var net = get_node_or_null("/root/Network")
		if net != null:
			var candidate = net.get("player_id")
			if typeof(candidate) == TYPE_INT and (candidate == 1 or candidate == 2):
				id = int(candidate)
	_my_id = id
	var me = _player(game, id)
	var opp = _player(game, 3 - id)
	if me == null or opp == null or not is_instance_valid(me) or not is_instance_valid(opp):
		_active = false
		return
	_me = me
	_opp = opp
	sampler.refresh(me, opp)
	_active = true

func _match_active():
	if game == null or not is_instance_valid(game):
		return false
	if not bool(game.get("game_started")):
		return false
	if bool(game.get("is_ghost")) or bool(game.get("spectating")):
		return false
	var replay = get_node_or_null("/root/ReplayManager")
	if replay != null and (bool(replay.get("playback")) or bool(replay.get("resimulating"))):
		return false
	return true

func _state_key():
	var st = sampler.current_state(_me)
	if st == null or not is_instance_valid(st):
		return ""
	return str(st.name)

func _debug_dump(sample):
	if _debug_passes >= 2:
		return
	_debug_passes += 1
	print("[HUD Plus DBG] pass ", _debug_passes, " state=", sample.get("me_state", "?"),
		" dist=", int(sample.get("distance", 0.0)), " opp_action=", sample.get("opp_queued_action", ""),
		" opp_state=", sample.get("opp_state", "?"))
	var cancels = _me.get("action_cancels")
	if cancels is Dictionary:
		for k in cancels.keys():
			var v = cancels[k]
			var names = []
			if v is Array:
				for c in v:
					var st = c
					if c is Dictionary:
						st = c.get("state", null)
					if st != null and is_instance_valid(st):
						names.append(str(st.name))
					if names.size() >= 12:
						break
			print("[HUD Plus DBG] cancel category '", k, "' count=", (v.size() if v is Array else -1), " names=", ", ".join(names))
	else:
		print("[HUD Plus DBG] action_cancels is ", typeof(cancels))
	for c in sample.get("candidates", []):
		var st = c.get("state", null)
		var props = []
		if st != null and is_instance_valid(st):
			for p in st.get_property_list():
				var n = str(p.get("name", ""))
				if n.findn("hit") >= 0 or n.findn("damage") >= 0 or n == "title":
					props.append(n)
		print("[HUD Plus DBG] cand ", c.get("name", "?"), " startup=", c.get("startup", -1),
			" reach=", c.get("reach", -1.0), " dmg=", c.get("damage", 0),
			" unknown=", c.get("unknown", false), " state_props=", ", ".join(props))
		if _debug_passes == 1 and c == sample.get("candidates", [])[0]:
			var nodes = st.get("all_hitbox_nodes") if st != null else null
			print("[HUD Plus DBG] first state all_hitbox_nodes=", (nodes.size() if nodes is Array else str(typeof(nodes))),
				" has_hitboxes=", (st.get("has_hitboxes") if st != null else "?"),
				" hitbox_start_frames=", (st.get("hitbox_start_frames") if st != null else "?"))
			if nodes is Array and not nodes.empty():
				var hb = nodes[0]
				print("[HUD Plus DBG] first box ", hb.name, " x=", hb.get("x"), " width=", hb.get("width"),
					" damage=", hb.get("damage"), " start=", hb.get("start_tick"),
					" rect=", (hb.call("get_rect_float") if hb.has_method("get_rect_float") else "?"))

func _process(_delta):
	if cfg == null or renderer == null:
		return
	if not _match_active():
		_pass_done = true
		return
	if _me == null or _opp == null or not is_instance_valid(_me) or not is_instance_valid(_opp):
		_resolve_players()
	renderer.set_game(game)
	if not _active:
		return

	var key = _state_key()
	if key != _last_state_key:
		_last_state_key = key
		_pass_done = true

	var now = OS.get_ticks_usec()
	var interval = 1000000.0 / max(1, int(cfg.sim["rate_hz"]))
	if _pass_done and now >= _next_pass_us:
		var sample = sampler.sample(_me, _opp)
		if bool(sample.get("valid", false)):
			_debug_dump(sample)
			scorer.begin_pass(sample, game, _me, _opp)
			_pass_done = false
		_next_pass_us = now + int(interval)

	if not _pass_done:
		var done = scorer.step(float(cfg.sim["frame_budget_ms"]))
		if done:
			_pass_done = true
			var result = scorer.get_results()
			if _debug_results < 2:
				_debug_results += 1
				for r in result.get("rows", []):
					print("[HUD Plus DBG] result ", r.get("name", "?"), " score=", int(r.get("score", 0.0)),
						" reason=", r.get("reason", ""), " static=", r.get("static", false))
			renderer.show_result(result)

func _exit_tree():
	if scorer != null:
		scorer.reset_match()
