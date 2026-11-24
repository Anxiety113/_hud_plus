# HUD Plus -- version gate and session safety monitor.
# Nothing in this file ever calls a mutating method on a live Fighter.
extends Reference

const EXPECTED_ENGINE = "3.5.1"
const REQUIRED_GAME_METHODS = [
	"copy_to",
	"simulate_one_tick",
	"get_player",
]

var expected_version = ""
var observed_version = ""
var forced_static = false
var kill_switch = false
var downgraded_once = false
var reason = ""
var consecutive_failures = 0
var total_failures = 0
var divergence_count = 0

# Keys are character script paths (or scene paths). Values are true.
var static_characters = {}

func _init(expected = ""):
	expected_version = expected
	_check_engine()

func _check_engine():
	var info = Engine.get_version_info()
	var major = str(info.get("major", 0))
	var minor = str(info.get("minor", 0))
	var patch = str(info.get("patch", 0))
	observed_version = major + "." + minor + "." + patch
	var declared = str(ProjectSettings.get_setting("application/config/version", ""))
	if declared != "":
		observed_version += "/" + declared
	if observed_version.get_slice("/", 0) != EXPECTED_ENGINE:
		forced_static = true
		reason = "engine " + observed_version + " != expected " + EXPECTED_ENGINE
		print("[HUD Plus] static-only: " + reason)

func check_game(game):
	if game == null or not is_instance_valid(game):
		return false
	var missing = []
	for m in REQUIRED_GAME_METHODS:
		if not game.has_method(m):
			missing.append(m)
	if not missing.empty():
		forced_static = true
		reason = "missing game API: " + ", ".join(missing)
		print("[HUD Plus] static-only: " + reason)
		return false
	return true

func simulation_allowed():
	return not forced_static and not kill_switch

func character_key(fighter):
	if fighter == null or not is_instance_valid(fighter):
		return "<none>"
	var script = fighter.get_script()
	if script != null and script.get("resource_path") != null:
		var p = str(script.get("resource_path"))
		if p != "":
			return p
	var filename = str(fighter.get("filename"))
	if filename != "":
		return filename
	return "<unknown>"

func is_static_character(fighter):
	return static_characters.has(character_key(fighter))

func mark_static_character(fighter, why):
	var key = character_key(fighter)
	if not static_characters.has(key):
		static_characters[key] = true
		print("[HUD Plus] character marked static-only (" + key + "): " + why)

func note_clone_result(ok, fighter):
	if ok:
		consecutive_failures = 0
		return
	consecutive_failures += 1
	total_failures += 1
	mark_static_character(fighter, "clone validation failed")
	if consecutive_failures >= 3 and not kill_switch:
		kill_switch = true
		forced_static = true
		reason = "three consecutive simulation failures"
		print("[HUD Plus] simulation kill switch engaged: " + reason)

func note_divergence(fighter):
	# A checksum mismatch is evidence of custom state the clone missed, but a
	# single mismatch can be an artifact of ghost initialization. Require three.
	divergence_count += 1
	if divergence_count >= 3:
		mark_static_character(fighter, "terminal checksum divergence")

func note_success(_fighter):
	consecutive_failures = 0

func capture_checksum(obj):
	if obj == null or not is_instance_valid(obj):
		return -1
	if obj.has_method("get_state_hash"):
		var h = obj.call("get_state_hash")
		if h is int:
			return h
		if h is String:
			return h.hash()
	if obj.has_method("hash"):
		return obj.call("hash")
	return -1

func checksums_compatible(source, clone):
	var a = capture_checksum(source)
	var b = capture_checksum(clone)
	if a == -1 or b == -1:
		# No checksum API: treat as compatible, we cannot judge.
		return true
	return a == b

func status_string():
	if kill_switch:
		return "simulation disabled"
	if forced_static:
		return "static-only"
	return "simulation active"
