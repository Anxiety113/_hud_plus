# HUD Plus -- headless self test (section 10 / V3).
# Run from a Godot 3.5 project whose res:// root contains this folder:
#   godot --headless --path <project> --script res://_hud_plus/selftest.gd
# Uses synthetic Fighter/Game doubles; it needs no real match and writes
# nothing to disk.
extends SceneTree

var failures = []

class StubHitbox:
	extends Node
	var position = Vector2(30, 0)
	var rect_size = Vector2(20, 10)
	var start_tick = 4
	var damage = 400
	var plus_frames = 0
	var active = false
	func _init(p=Vector2(30, 0), st=4, d=400, pf=0):
		position = p
		start_tick = st
		damage = d
		plus_frames = pf

class StubState:
	extends Node
	var title = "Move"
	var hitboxes = []
	var selectable = true
	var super_level_ = 0
	var supers_used_ = -1
	var uses_air_movement = false
	var is_brace = false
	func _init(n, hb, super_level=0):
		name = n
		title = n
		hitboxes = [hb]
		super_level_ = super_level

class StubFighter:
	extends Node
	var id = 1
	var hp = 1500
	var MAX_HEALTH = 1500
	var super_meter = 0
	var burst_meter = 0
	var air_movements_left = 2
	var feints = 2
	var sadness_enabled = false
	var minus_frames = 0
	var combo_proration = 0
	var combo_damage = 0
	var queued_action = null
	var current_di = { "x": "0", "y": "0" }
	var hurtbox = null
	var hitboxes = []
	var last_vel = { "x": "0", "y": "0" }
	var invulnerable = false
	var has_hyper_armor = false
	var got_blocked = false
	var got_parried = false
	var clashing = false
	var hit_during_armor = false
	var position = Vector2(0, 0)
	var state = null
	var action_cancels = {}
	func current_state():
		return state
	func get_pos():
		return position
	func get_state_hash():
		return int(hp) * 31 + int(super_meter)

class StubGame:
	extends Node
	var p1 = null
	var p2 = null
	var match_data = { "selected_characters": { 1: { "name": "Stub" }, 2: { "name": "Stub" } }, "seed": 7 }
	var is_ghost = true
	var visible = false
	var _tick = 0
	var _applied = false
	func get_player(id):
		return p1 if id == 1 else p2
	func copy_to(target):
		_copy_fighter(p1, target.p1)
		_copy_fighter(p2, target.p2)
		target._applied = false
		target._tick = 0
	func _copy_fighter(src, dst):
		if src == null or dst == null:
			return
		dst.hp = src.hp
		dst.super_meter = src.super_meter
		dst.minus_frames = src.minus_frames
		dst.position = src.position
		dst.queued_action = src.queued_action
		dst.current_di = src.current_di.duplicate()
	func simulate_one_tick():
		_tick += 1
		if _applied:
			return
		if p1 == null or p2 == null:
			return
		var act = str(p1.queued_action)
		if act != "" and act != "Continue":
			var dmg = 0
			for st in p1.action_cancels.get("Normal", []):
				if st.name == act and st.hitboxes.size() > 0:
					dmg = st.hitboxes[0].damage
			p2.hp = max(0, p2.hp - dmg)
			p1.minus_frames = -2
			_applied = true
	func should_game_end():
		return p1.hp <= 0 or p2.hp <= 0

func _assert(condition, message):
	if condition:
		print("  PASS  " + message)
	else:
		failures.append(message)
		print("  FAIL  " + message)

func _finite(v):
	return not is_nan(float(v)) and not is_inf(float(v))

func _setup_fighters():
	var jab = StubState.new("Jab", StubHitbox.new(Vector2(30, 0), 4, 400, 2))
	var punch = StubState.new("Punch", StubHitbox.new(Vector2(70, 0), 8, 700, 0))
	var super_move = StubState.new("Super", StubHitbox.new(Vector2(120, 0), 12, 1600, -4), 1)
	var armor = StubState.new("Armor", StubHitbox.new(Vector2(50, 0), 10, 500, 1))
	var me = StubFighter.new()
	me.id = 1
	me.position = Vector2(-60, 0)
	me.action_cancels = { "Normal": [jab, punch, super_move, armor] }
	me.state = jab
	var opp = StubFighter.new()
	opp.id = 2
	opp.position = Vector2(60, 0)
	opp.queued_action = "Continue"
	opp.state = punch
	return [me, opp]

func _run_mode(label, cfg, guard, statics, sampler, sample, game, me, opp, ghost):
	print("--- " + label + " ---")
	var scorer = load("res://_hud_plus/scorer.gd").new()
	scorer.setup(cfg, guard, statics)
	if ghost != null:
		scorer.ghost_override = ghost
	scorer.begin_pass(sample, game, me, opp)
	var guard_count = 0
	while not scorer.step(4.0):
		guard_count += 1
		if guard_count > 200:
			break
	var result = scorer.get_results()
	_assert(bool(result.get("valid", false)), label + ": result is valid")
	var rows = result.get("rows", [])
	_assert(rows.size() >= 3, label + ": at least three ranked rows (got " + str(rows.size()) + ")")
	for r in rows:
		_assert(_finite(r.get("score", 0.0)), label + ": finite score for " + str(r.get("name", "?")))
		_assert(str(r.get("reason", "")) != "", label + ": reason for " + str(r.get("name", "?")))
	print("  confidence=" + str(result.get("confidence", 0.0)) + "  di=" + str(result.get("di", "?")))
	for r in rows:
		print("   " + str(r.get("name", "?")) + "  " + str(int(r.get("score", 0.0))) + "  " + str(r.get("reason", "")))
	return result

func _initialize():
	print("=========================================")
	print("HUD Plus selftest -- Godot " + str(Engine.get_version_info().get("string", "?")))
	print("=========================================")
	var cfg = load("res://_hud_plus/scoring_config.gd").new()
	var guard = load("res://_hud_plus/guard.gd").new()
	var statics = load("res://_hud_plus/static_heuristics.gd").new()
	var sampler = load("res://_hud_plus/sampler.gd").new()
	var pair = _setup_fighters()
	var me = pair[0]
	var opp = pair[1]

	var candidates = sampler.collect_candidates(me)
	_assert(candidates.size() >= 3, "sampler: at least three candidates (got " + str(candidates.size()) + ")")
	var sample = sampler.sample(me, opp)
	_assert(bool(sample.get("valid", false)), "sampler: sample is valid")
	_assert(float(sample.get("distance", 0.0)) > 0.0, "sampler: distance computed")

	# Static path (no Game at all).
	_run_mode("STATIC", cfg, guard, statics, sampler, sample, null, me, opp, null)

	# Simulation path using a synthetic Game double.
	var ghost = StubGame.new()
	ghost.p1 = StubFighter.new()
	ghost.p1.id = 1
	ghost.p1.position = Vector2(-60, 0)
	ghost.p1.action_cancels = me.action_cancels
	ghost.p1.state = me.state
	ghost.p2 = StubFighter.new()
	ghost.p2.id = 2
	ghost.p2.position = Vector2(60, 0)
	ghost.p2.action_cancels = opp.action_cancels
	ghost.p2.state = opp.state
	var live_game = StubGame.new()
	live_game.p1 = me
	live_game.p2 = opp
	_run_mode("SIMULATED", cfg, guard, statics, sampler, sample, live_game, me, opp, ghost)

	if failures.empty():
		print("SELFTEST RESULT: PASS")
		quit(0)
	else:
		print("SELFTEST RESULT: FAIL (" + str(failures.size()) + " failures)")
		quit(1)
