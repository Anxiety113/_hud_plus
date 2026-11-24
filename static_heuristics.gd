# HUD Plus -- static fallback ranking.
# Used when simulation is unavailable (version mismatch, kill switch, a
# character whose clone diverges, or a candidate that cannot be simulated).
# It reads only live moveset metadata and is deliberately independent of
# any per-character table.
extends Reference

func _num(v, fallback):
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_REAL:
		return float(v)
	return fallback

func _reason_for(c, sample):
	var reasons = []
	var distance = _num(sample.get("distance", 0.0), 0.0)
	var reach = _num(c.get("reach", -1.0), -1.0)
	var startup = int(_num(c.get("startup", -1.0), -1.0))
	var opp_startup = int(_num(sample.get("opponent_startup", -1.0), -1.0))
	var damage = int(_num(c.get("damage", 0.0), 0.0))
	var cost = _num(c.get("cost", 0.0), 0.0)
	var plus = int(_num(c.get("plus_frames", 0.0), 0.0))

	if reach >= 0.0 and reach + 2.0 < distance:
		reasons.append("whiffs at this range")
	if startup >= 0 and opp_startup >= 0 and startup < opp_startup:
		reasons.append("beats %dF startup" % opp_startup)
	elif startup >= 0 and opp_startup >= 0 and startup > opp_startup:
		reasons.append("loses to %dF startup" % opp_startup)
	if damage >= 1500:
		reasons.append("kills")
	if bool(c.get("armor", false)):
		reasons.append("armored")
	if bool(c.get("invuln", false)):
		reasons.append("invulnerable")
	if plus > 0 and reach >= 0.0 and reach + 2.0 >= distance:
		reasons.append("safe, +%d on block" % plus)
	if cost > 0.0:
		reasons.append("spends resource")
	if bool(c.get("unknown", false)):
		reasons.append("unknown frame data")
	if reasons.empty():
		if damage > 0:
			reasons.append("reaches, %d damage" % damage)
		else:
			reasons.append("no frame data")
	return reasons

func rank(candidates, sample, cfg):
	var out = []
	var distance = _num(sample.get("distance", 0.0), 0.0)
	var opp_startup = int(_num(sample.get("opponent_startup", -1.0), -1.0))
	var me_minus = int(_num(sample.get("me_minus_frames", 0.0), 0.0))

	for c in candidates:
		var damage = int(_num(c.get("damage", 0.0), 0.0))
		var startup = int(_num(c.get("startup", -1.0), -1.0))
		var reach = _num(c.get("reach", -1.0), -1.0)
		var cost = _num(c.get("cost", 0.0), 0.0)
		var armor = bool(c.get("armor", false))
		var invuln = bool(c.get("invuln", false))
		var unknown = bool(c.get("unknown", false))

		var in_range = 0.0
		if reach < 0.0:
			in_range = 0.0
		elif reach + 2.0 >= distance:
			in_range = 1.0
		else:
			in_range = -1.6

		var speed_edge = 0.0
		if startup >= 0 and opp_startup >= 0 and me_minus <= 0:
			speed_edge = clamp(float(opp_startup - startup) * 0.06, -0.6, 0.6)

		var kill_bonus = 8.0 if damage >= 1500 else 0.0
		var defense_bonus = (0.5 if armor else 0.0) + (0.5 if invuln else 0.0)
		var raw = 0.5 + (float(damage) / 300.0) + speed_edge + in_range \
			+ kill_bonus + defense_bonus - (cost * 0.6)
		if unknown:
			raw -= 0.15
		# Static mode is a safety net, not a fortune teller: keep scores finite.
		if is_nan(raw) or is_inf(raw):
			raw = 0.0

		var result = {
			"name": str(c.get("name", "?")),
			"raw_score": raw,
			"reason": ", ".join(_reason_for(c, sample)),
			"static": true,
			"unknown": unknown,
			"startup": startup,
			"reach": reach,
			"damage": damage,
			"cost": cost,
			"components": {
				"dealt": float(damage),
				"kill": kill_bonus,
				"whiff": 1.0 if in_range < 0.0 else 0.0,
				"resource": cost,
				"armor_invuln": defense_bonus,
				"speed": speed_edge,
			},
		}
		out.append(result)

	out.sort_custom(self, "_sort_by_raw")
	return out

func _sort_by_raw(a, b):
	return float(a.get("raw_score", 0.0)) > float(b.get("raw_score", 0.0))
