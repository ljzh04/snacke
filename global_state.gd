extends Node

const SAVE_PATH = "user://user_data.tres"

var current_profile_name: String = "Guest"
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
				
		save_user_data()  # optional: re-save migrated data
	else:
		user_data = UserData.new()
		user_data.profiles["Guest"] = {"score": 0, "time": 0.0}
		save_user_data()

func save_user_data() -> void:
	ResourceSaver.save(user_data, SAVE_PATH)

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
