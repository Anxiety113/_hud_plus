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
	var net = get_node_or_null("/root/Network")
	var id = 1
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
			scorer.begin_pass(sample, game, _me, _opp)
			_pass_done = false
		_next_pass_us = now + int(interval)

	if not _pass_done:
		var done = scorer.step(float(cfg.sim["frame_budget_ms"]))
		if done:
			_pass_done = true
			renderer.show_result(scorer.get_results())

func _exit_tree():
	if scorer != null:
		scorer.reset_match()
