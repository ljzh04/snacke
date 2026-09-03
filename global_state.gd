extends Node

const SAVE_PATH = "user://user_data.tres"

var current_profile_name: String = "Guest"
var last_score: int = 0
var last_time: float = 0.0
var user_data: UserData

# The most recently entered profile name (mirrors user_data.last_profile_name
# in memory so the profile screen can pre-fill its name field).
var last_profile_name: String = "Guest"

# Difficulty selection (Easy / Medium / Hard). Defaults to Medium.
var difficulty: String = "Medium"

# Difficulty tuning per GAME_RULES.md.
# multiplier: applied to time-elapsed scoring.
# food_multiplier: applied to each food thrown to the snake.
# initial_speed: snake move duration in seconds (lower = faster).
# speedup: how much the snake speeds up per level-up.
# length_multiplier: applied to the snake's current length for scoring.
const DIFFICULTY_SETTINGS := {
	"Easy":   {"multiplier": 1.0, "food_multiplier": 8,  "initial_speed": 0.16, "speedup": 0.006, "length_multiplier": 1},
	"Medium": {"multiplier": 2.0, "food_multiplier": 15, "initial_speed": 0.11, "speedup": 0.009, "length_multiplier": 2},
	"Hard":   {"multiplier": 3.0, "food_multiplier": 25, "initial_speed": 0.08, "speedup": 0.012, "length_multiplier": 3},
}

func get_difficulty_settings() -> Dictionary:
	return DIFFICULTY_SETTINGS.get(difficulty, DIFFICULTY_SETTINGS["Medium"])

func _ready() -> void:
	load_user_data()

func load_user_data() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		user_data = ResourceLoader.load(SAVE_PATH)
	else:
		user_data = UserData.new()
		user_data.profiles["Guest"] = {"score": 0, "time": 0.0}
		save_user_data()
	_dedupe_leaderboard()
	# Mirror the persisted last name into memory for the profile screen.
	last_profile_name = user_data.last_profile_name

# Stores the most recently entered profile name so the profile screen can
# pre-fill its name field on the next visit. Persisted to disk.
func set_last_profile_name(new_name: String) -> void:
	var trimmed := new_name.strip_edges()
	if trimmed.is_empty():
		trimmed = "Guest"
	last_profile_name = trimmed
	current_profile_name = trimmed
	if is_instance_valid(user_data):
		user_data.last_profile_name = trimmed
		save_user_data()

# Repairs save files written before duplicate-entry saving was fixed:
# removes exact duplicate leaderboard entries (same name, score and time).
func _dedupe_leaderboard() -> void:
	var seen: Dictionary = {}
	var cleaned: Array = []
	for entry in user_data.leaderboard:
		if not (entry is Dictionary and entry.has("name") and entry.has("score") and entry.has("time")):
			continue
		var key := "%s|%s|%s" % [String(entry["name"]), int(entry["score"]), float(entry["time"])]
		if seen.has(key):
			continue
		seen[key] = true
		cleaned.append(entry)
	if cleaned.size() != user_data.leaderboard.size():
		user_data.leaderboard = cleaned
		user_data.leaderboard.sort_custom(Callable(self, "_leaderboard_compare"))
		save_user_data()

func save_user_data() -> void:
	ResourceSaver.save(user_data, SAVE_PATH)

func _leaderboard_compare(a: Dictionary, b: Dictionary) -> bool:
	if a["score"] == b["score"]:
		return String(a["name"]) < String(b["name"])
	return int(a["score"]) > int(b["score"])

func get_leaderboard() -> Array:
	var list: Array = user_data.leaderboard.duplicate()
	list.sort_custom(Callable(self, "_leaderboard_compare"))
	return list

func add_leaderboard_entry(entry_name: String, new_score: int, new_time: float) -> void:
	if entry_name.strip_edges() == "":
		entry_name = "Guest"
	user_data.leaderboard.append({"name": entry_name, "score": new_score, "time": new_time})
	user_data.leaderboard.sort_custom(Callable(self, "_leaderboard_compare"))
	if user_data.leaderboard.size() > 10:
		user_data.leaderboard.resize(10)
	save_user_data()

func get_high_score(profile_name: String) -> Dictionary:
	if user_data.profiles.has(profile_name):
		return user_data.profiles[profile_name]
	return {"score": 0, "time": 0.0}

func update_high_score(profile_name: String, new_score: int, new_time: float) -> void:
	if not user_data.profiles.has(profile_name):
		user_data.profiles[profile_name] = {"score": 0, "time": 0.0}
	
	if new_score > user_data.profiles[profile_name]["score"]:
		user_data.profiles[profile_name] = {"score": new_score, "time": new_time}
		save_user_data()
