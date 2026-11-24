# HUD Plus -- module A: cheap, read-only snapshot of the live match.
# Every read goes through _get/_call, which check object validity and the
# actual property/method list before touching anything. No simulation here.
extends Reference

var _readable = {}
var _sample = {}
var _cached_me = null
var _cached_opp = null

func _obj_key(obj):
	if obj == null or not is_instance_valid(obj):
		return "<invalid>"
	var s = obj.get_script()
	if s != null and s.get("resource_path") != null and str(s.get("resource_path")) != "":
		return str(s.get("resource_path"))
	# Inner classes / scripts without a resource path all report get_class() ==
	# "Node"; use the instance id so their property lists never collide.
	return str(obj.get_instance_id())

func _get(obj, prop, default=null):
	if obj == null or not is_instance_valid(obj) or prop == "":
		return default
	var key = _obj_key(obj)
	if not _readable.has(key):
		var names = {}
		for p in obj.get_property_list():
			names[str(p.get("name", ""))] = true
		_readable[key] = names
	if not _readable[key].has(str(prop)):
		return default
	var v = obj.get(prop)
	if v == null:
		return default
	return v

func _call(obj, method, args=[]):
	if obj == null or not is_instance_valid(obj):
		return null
	if not obj.has_method(method):
		return null
	return obj.callv(method, args)

func _num(v, fallback=0.0):
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_REAL:
		return float(v)
	if typeof(v) == TYPE_STRING:
		if str(v).is_valid_float():
			return float(str(v))
	return fallback

func _vec2(v):
	if v is Vector2:
		return v
	if v is Dictionary:
		return Vector2(_num(v.get("x", 0.0)), _num(v.get("y", 0.0)))
	return Vector2.ZERO

func current_state(fighter):
	return _call(fighter, "current_state", [])

func refresh(me, opp):
	_cached_me = me
	_cached_opp = opp

func refs_valid(me, opp):
	return me != null and is_instance_valid(me) and opp != null and is_instance_valid(opp)

# ---- candidate enumeration from the LIVE moveset -----------------------

func _candidate_name(c, state):
	var n = _get(c, "state_name", "")
	if n is String and n != "":
		return n
	n = _get(state, "title", "")
	if n is String and n != "":
		return n
	if state != null and is_instance_valid(state):
		return str(state.name)
	return "?"

func _hitboxes_of(state):
	if state == null or not is_instance_valid(state):
		return []
	# This build exposes hitboxes through all_hitbox_nodes, not a plain
	# "hitboxes" array. Fall back to children that look like hitboxes.
	var hb = _get(state, "all_hitbox_nodes", [])
	if hb is Array and not hb.empty():
		return hb
	hb = _get(state, "hitboxes", [])
	if hb is Array and not hb.empty():
		return hb
	var found = []
	if state is Node:
		for child in state.get_children():
			if _get(child, "start_tick", null) != null or _get(child, "damage", null) != null:
				found.append(child)
	return found

func _startup_of(state, boxes):
	var starts = _get(state, "hitbox_start_frames", [])
	if starts is Array:
		for v in starts:
			var n = int(_num(v, -1.0))
			if n >= 0:
				return n
	var earliest = _get(state, "earliest_hitbox", null)
	if typeof(earliest) == TYPE_INT or typeof(earliest) == TYPE_REAL:
		var n = int(_num(earliest, -1.0))
		if n >= 0:
			return n
	elif earliest != null and is_instance_valid(earliest):
		var n = int(_num(_get(earliest, "start_tick", -1.0), -1.0))
		if n >= 0:
			return n
	var best = -1
	for box in boxes:
		if box == null or not is_instance_valid(box):
			continue
		var n = int(_num(_get(box, "start_tick", -1.0), -1.0))
		if n >= 0 and (best < 0 or n < best):
			best = n
	return best

func _box_geometry(box):
	# CollisionBox in this build uses x/y/width/height (also exposed as
	# pos_x/pos_y). get_rect_float() is the generic fallback.
	var bx = _get(box, "x", null)
	if bx == null:
		bx = _get(box, "pos_x", null)
	var bw = _get(box, "width", null)
	var reach = -1.0
	if bx != null and bw != null:
		reach = abs(_num(bx)) + abs(_num(bw)) * 0.5
	if reach < 0.0 and box is Node and box.has_method("get_rect_float"):
		var r = box.call("get_rect_float")
		if r is Rect2:
			reach = abs(r.position.x) + r.size.x * 0.5
		elif r is Dictionary:
			reach = abs(_num(r.get("x", 0.0))) + _num(r.get("width", 0.0)) * 0.5
	if reach < 0.0:
		return { "reach": -1.0, "start": -1, "damage": -1, "plus": 0 }
	return {
		"reach": reach,
		"start": int(_num(_get(box, "start_tick", -1.0), -1.0)),
		"damage": int(_num(_get(box, "damage", -1.0), -1.0)),
		"plus": int(_num(_get(box, "plus_frames", 0.0), 0.0)),
	}

func make_candidate(c, fighter):
	var state = c
	if not (c is Node) and c is Dictionary:
		state = c.get("state", null)
	var boxes = _hitboxes_of(state)
	var startup = _startup_of(state, boxes)
	var reach = -1.0
	var damage = -1
	var plus = 0
	for box in boxes:
		if box == null or not is_instance_valid(box):
			continue
		var g = _box_geometry(box)
		if g.start >= 0 and (startup < 0 or g.start < startup):
			startup = g.start
		if g.reach >= 0.0 and g.reach > reach:
			reach = g.reach
		if g.damage >= 0 and g.damage > damage:
			damage = g.damage
		if abs(g.plus) > abs(plus):
			plus = g.plus
	var armor = bool(_get(fighter, "has_hyper_armor", false)) or bool(_get(state, "is_brace", false))
	var invuln = bool(_get(fighter, "invulnerable", false)) or bool(_get(fighter, "projectile_invulnerable", false))
	var cost = max(0.0, _num(_get(state, "super_level_", 0.0), 0.0)) + max(0.0, _num(_get(state, "supers_used_", 0.0), 0.0))
	if bool(_get(state, "uses_air_movement", false)):
		cost += 0.25
	var name = _candidate_name(c, state)
	if damage < 0:
		damage = int(_num(_get(state, "damage", -1.0), -1.0))
	var damage_known = damage >= 0
	return {
		"name": name,
		"state": state,
		"data": null,
		"startup": startup,
		"reach": reach,
		"damage": max(damage, 0),
		"plus_frames": plus,
		"armor": armor,
		"invuln": invuln,
		"cost": cost,
		"unknown": startup < 0 or not damage_known or reach < 0.0,
		"damage_known": damage_known,
	}

func _append_unique(out, seen, c, fighter):
	if c == null:
		return
	var probe = c
	if c is Dictionary:
		probe = c.get("state", null)
	if probe == null or not is_instance_valid(probe):
		return
	var cand = make_candidate(c, fighter)
	var key = cand.name
	if key == "" or seen.has(key):
		return
	# "Continue" is a legal option but it is not a distinct move to advise.
	if key == "Continue":
		return
	seen[key] = true
	out.append(cand)

func _category_priority(category):
	var n = str(category).to_lower()
	if n.findn("attack") >= 0:
		return 0
	if n.findn("throw") >= 0:
		return 1
	if n.findn("super") >= 0:
		return 2
	if n.findn("movement") >= 0:
		return 3
	if n.findn("special") >= 0:
		return 4
	if n.findn("defen") >= 0 or n.findn("parry") >= 0 or n.findn("burst") >= 0 or n.findn("counter") >= 0:
		return 8
	return 6

func _sort_categories(a, b):
	if int(a["prio"]) != int(b["prio"]):
		return int(a["prio"]) < int(b["prio"])
	return int(a["order"]) < int(b["order"])

func collect_candidates(fighter, cap=8):
	var out = []
	var seen = {}
	if fighter == null or not is_instance_valid(fighter):
		return out
	var cancels = _get(fighter, "action_cancels", {})
	var entries = []
	if cancels is Dictionary:
		var order = 0
		for category in cancels.keys():
			var arr = cancels[category]
			if arr is Array:
				for c in arr:
					entries.append({ "c": c, "prio": _category_priority(category), "order": order })
			order += 1
		entries.sort_custom(self, "_sort_categories")
	var attacks_added = 0
	for e in entries:
		# Keep the list useful but varied: at most five attacks before filling
		# the remaining slots with throws, supers, movement and defense.
		if int(e["prio"]) == 0 and attacks_added >= 5:
			continue
		var before = out.size()
		_append_unique(out, seen, e["c"], fighter)
		if out.size() > before and int(e["prio"]) == 0:
			attacks_added += 1
		if out.size() >= cap:
			break
	# Fallback for modded characters that expose moves only through the state
	# machine. Still no hardcoded names: selectable states are the source.
	if out.size() < 3:
		var sm = _get(fighter, "state_machine", null)
		var map = _get(sm, "states_map", {})
		if map is Dictionary:
			for k in map.keys():
				var st = map[k]
				if st == null or not is_instance_valid(st):
					continue
				if not bool(_get(st, "selectable", true)):
					continue
				_append_unique(out, seen, st, fighter)
				if out.size() >= cap:
					break
	return out

# ---- static threat picture ---------------------------------------------

func _active_boxes(fighter):
	var info = []
	var boxes = _get(fighter, "hitboxes", [])
	if boxes is Array:
		for b in boxes:
			if b == null or not is_instance_valid(b):
				continue
			if bool(_get(b, "active", false)):
				info.append(_box_geometry(b))
	return info

func sample(me, opp):
	var s = _sample
	s.clear()
	if not refs_valid(me, opp):
		s["valid"] = false
		return s

	var mp = _vec2(_call(me, "get_pos", []))
	var op = _vec2(_call(opp, "get_pos", []))
	var delta = op - mp
	var distance = delta.length()

	var me_state = current_state(me)
	var opp_state = current_state(opp)
	var my_candidates = collect_candidates(me, 8)

	var my_startup = -1
	for c in my_candidates:
		var st = int(c.get("startup", -1))
		if st >= 0 and (my_startup < 0 or st < my_startup):
			my_startup = st
	var opp_boxes = _hitboxes_of(opp_state)
	var opp_startup = _startup_of(opp_state, opp_boxes)
	var opp_reach = -1.0
	for b in opp_boxes:
		if b == null or not is_instance_valid(b):
			continue
		var g = _box_geometry(b)
		if g.start >= 0 and (opp_startup < 0 or g.start < opp_startup):
			opp_startup = g.start
		if g.reach > opp_reach:
			opp_reach = g.reach

	var opp_queued = _get(opp, "queued_action", null)
	var committed = opp_queued != null and str(opp_queued) != "Continue"
	var active_opp = _active_boxes(opp)
	if not active_opp.empty():
		committed = true

	s["valid"] = true
	s["tick"] = OS.get_ticks_msec()
	s["distance"] = distance
	s["delta_x"] = delta.x
	s["direction"] = -1.0 if delta.x < 0.0 else 1.0
	s["me_pos"] = mp
	s["opp_pos"] = op
	s["me_vel"] = _vec2(_get(me, "last_vel", null))
	s["opp_vel"] = _vec2(_get(opp, "last_vel", null))
	s["me_hp"] = int(_num(_get(me, "hp", 0.0), 0.0))
	s["opp_hp"] = int(_num(_get(opp, "hp", 0.0), 0.0))
	s["me_max_hp"] = int(_num(_get(me, "MAX_HEALTH", 1500.0), 1500.0))
	s["opp_max_hp"] = int(_num(_get(opp, "MAX_HEALTH", 1500.0), 1500.0))
	s["me_proration"] = int(_num(_get(me, "combo_proration", 0.0), 0.0))
	s["opp_proration"] = int(_num(_get(opp, "combo_proration", 0.0), 0.0))
	s["me_combo_damage"] = int(_num(_get(me, "combo_damage", 0.0), 0.0))
	s["me_super"] = int(_num(_get(me, "super_meter", 0.0), 0.0))
	s["me_burst"] = int(_num(_get(me, "burst_meter", 0.0), 0.0))
	s["me_air_left"] = int(_num(_get(me, "air_movements_left", 0.0), 0.0))
	s["me_feints"] = int(_num(_get(me, "feints", 0.0), 0.0))
	s["me_sadness"] = bool(_get(me, "sadness_enabled", false))
	s["me_minus_frames"] = int(_num(_get(me, "minus_frames", 0.0), 0.0))
	s["opp_minus_frames"] = int(_num(_get(opp, "minus_frames", 0.0), 0.0))
	s["me_plus"] = s["me_minus_frames"] <= 0
	s["opp_queued_action"] = str(opp_queued) if opp_queued != null else ""
	s["opp_di"] = _get(opp, "current_di", null)
	s["me_state"] = str(me_state.name) if me_state != null and is_instance_valid(me_state) else ""
	s["opp_state"] = str(opp_state.name) if opp_state != null and is_instance_valid(opp_state) else ""
	s["opp_startup"] = opp_startup
	s["opp_reach"] = opp_reach
	s["my_fastest_startup"] = my_startup
	s["committed"] = committed
	s["me_hurtbox"] = _get(me, "hurtbox", null)
	s["opp_hurtbox"] = _get(opp, "hurtbox", null)
	s["me_active_boxes"] = _active_boxes(me)
	s["opp_active_boxes"] = active_opp
	s["threat"] = {
		"in_reach": opp_reach >= 0.0 and distance <= opp_reach + 2.0,
		"faster": opp_startup >= 0 and my_startup >= 0 and opp_startup < my_startup,
		"punishable": s["me_minus_frames"] > 0,
		"committed": committed,
	}
	s["candidates"] = my_candidates
	return s
