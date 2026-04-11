extends Node

const SAVE_PATH = "user://user_data.tres"

var current_profile_name: String = "Guest"
var last_score: int = 0
var last_time: float = 0.0
var user_data: UserData

func _ready() -> void:
	load_user_data()

func load_user_data() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		user_data = ResourceLoader.load(SAVE_PATH)
		

		for profile in user_data.profiles.keys():
			var data = user_data.profiles[profile]
			if typeof(data) == TYPE_INT:
				user_data.profiles[profile] = {"score": data, "time": 0.0}
		# if leaderboard is empty, migrate profiles into leaderboard array
		if not user_data.leaderboard or user_data.leaderboard.size() == 0:
			for profile in user_data.profiles.keys():
				var data2 = user_data.profiles[profile]
				var score = data2 if typeof(data2) == TYPE_INT else data2.get("score", 0)
				var time = 0.0
				if typeof(data2) == TYPE_DICTIONARY and data2.has("time"):
					time = data2["time"]
				user_data.leaderboard.append({"name": profile, "score": score, "time": time})
			user_data.leaderboard.sort_custom(Callable(self, "_leaderboard_compare"))
		
			save_user_data()  # optional: re-save migrated data
	else:
		user_data = UserData.new()
		user_data.profiles["Guest"] = {"score": 0, "time": 0.0}
		save_user_data()

func save_user_data() -> void:
	ResourceSaver.save(user_data, SAVE_PATH)

func _leaderboard_compare(a: Dictionary, b: Dictionary) -> bool:
	if a["score"] == b["score"]:
		return String(a["name"]) < String(b["name"])
	return int(a["score"]) > int(b["score"])

func get_leaderboard() -> Array:
	var list: Array = []
	if user_data.leaderboard and user_data.leaderboard.size() > 0:
		list = user_data.leaderboard.duplicate()
	else:
		for profile in user_data.profiles.keys():
			var data = user_data.profiles[profile]
			var score = data if typeof(data) == TYPE_INT else data.get("score", 0)
			var time = 0.0
			if typeof(data) == TYPE_DICTIONARY and data.has("time"):
				time = data["time"]
			list.append({"name": profile, "score": score, "time": time})
	list.sort_custom(Callable(self, "_leaderboard_compare"))
	return list

func add_leaderboard_entry(entry_name: String, new_score: int, new_time: float) -> void:
	if entry_name.strip_edges() == "":
		entry_name = "Guest"
	user_data.leaderboard.append({"name": entry_name, "score": new_score, "time": new_time})
	user_data.leaderboard.sort_custom(Callable(self, "_leaderboard_compare"))
	if user_data.leaderboard.size() > 20:
		user_data.leaderboard.resize(20)
	save_user_data()

func get_high_score(profile_name: String) -> Dictionary:
	if user_data.profiles.has(profile_name):
		var data = user_data.profiles[profile_name]
		if typeof(data) == TYPE_DICTIONARY:
			return data
		else:
			return {"score": data, "time": 0.0}
	return {"score": 0, "time": 0.0}
func update_high_score(profile_name: String, new_score: int, new_time: float) -> void:
	if not user_data.profiles.has(profile_name):
		user_data.profiles[profile_name] = {"score": 0, "time": 0.0}
	
	var current_high_score_data = user_data.profiles[profile_name]
	
	if typeof(current_high_score_data) == TYPE_INT:
		current_high_score_data = {"score": current_high_score_data, "time": 0.0}
	
	if new_score > current_high_score_data["score"]:
		user_data.profiles[profile_name] = {"score": new_score, "time": new_time}
		save_user_data()
