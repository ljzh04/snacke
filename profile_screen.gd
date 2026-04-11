extends Control

@onready var name_edit: LineEdit = %LineEdit
@onready var play_button: Button = %Button
@onready var exit_button: Button = %ExitButton
@onready var score_label: Label = %ScoreLabel
@onready var time_label: Label = %TimeLabel
@onready var high_score_label: Label = %HighScoreLabel
@onready var best_label: Label = %BestLabel
@onready var leaderboard_entries: VBoxContainer = %LeaderboardEntries
var placeholder_label: Label = null
var placeholder_index: int = -1
@export var bite_wipe_scene: PackedScene

func _get_entered_name() -> String:
	var profile_name := name_edit.text.strip_edges()
	if profile_name.is_empty():
		profile_name = "Guest"
	return profile_name

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	name_edit.text_changed.connect(_on_name_text_changed)
	name_edit.text = ""
	_populate_leaderboard()
	_update_session_stats()
	name_edit.grab_focus()
	name_edit.select_all()

func _populate_leaderboard() -> void:
	var entries := GlobalState.get_leaderboard()
	placeholder_label = null
	placeholder_index = -1
	# find insertion index for the current session score (higher scores rank earlier)
	var insert_idx := entries.size()
	for i in range(entries.size()):
		if GlobalState.last_score > entries[i]["score"]:
			insert_idx = i
			break

	var display := entries.duplicate()
	# only insert placeholder if it will be visible in the current leaderboard display
	if insert_idx < leaderboard_entries.get_child_count():
		display.insert(insert_idx, {"name": _get_entered_name(), "score": GlobalState.last_score})

	for i in range(leaderboard_entries.get_child_count()):
		var label = leaderboard_entries.get_child(i)
		if i < display.size():
			var entry = display[i]
			label.text = "%d. %s - %d" % [i + 1, entry["name"], entry["score"]]
			if i == insert_idx:
				placeholder_label = label
				placeholder_index = i
				_update_placeholder_text()
				_start_placeholder_animation()
		else:
			label.text = "%d. ---" % [i + 1]

func _compare_leaderboard(a: Dictionary, b: Dictionary) -> bool:
	if a["score"] == b["score"]:
		return String(a["name"]) < String(b["name"])
	return int(a["score"]) > int(b["score"])

func _update_session_stats() -> void:
	var last_score = GlobalState.last_score
	var last_time = GlobalState.last_time
	score_label.text = "Last Score: %d" % [last_score]
	time_label.text = "Time Survived: %.2fs" % [last_time]
	var leaderboard = GlobalState.get_leaderboard()
	var current_high = 0
	if leaderboard.size() > 0:
		current_high = leaderboard[0]["score"]
	high_score_label.text = "High Score: %d" % [current_high]
	best_label.text = "All Time Best: %d" % [current_high]

func _on_name_text_changed(_new_text: String) -> void:
	_update_placeholder_text()
	# keep overall high displayed
	var leaderboard = GlobalState.get_leaderboard()
	var current_high = leaderboard[0]["score"] if leaderboard.size() > 0 else 0
	high_score_label.text = "High Score: %d" % [current_high]
	best_label.text = "All Time Best: %d" % [current_high]

func _update_placeholder_text() -> void:
	if placeholder_label:
		var entered_name = _get_entered_name()
		placeholder_label.text = "%d. %s - %d" % [placeholder_index + 1, entered_name, GlobalState.last_score]

func _start_placeholder_animation() -> void:
	if not placeholder_label:
		return
	# smoothly cycle modulate through red -> green -> blue indefinitely
	_anim_loop()

func _anim_loop() -> void:
	var colors = [Color(1, 0.5, 0.5, 1), Color(0.5, 1, 0.5, 1), Color(0.5, 0.5, 1, 1)]
	# start at red for a consistent ramp
	if is_instance_valid(placeholder_label):
		placeholder_label.modulate = colors[0]
	var idx := 0
	while is_instance_valid(placeholder_label):
		var next_idx := (idx + 1) % colors.size()
		var t = placeholder_label.create_tween()
		t.tween_property(placeholder_label, "modulate", colors[next_idx], 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await t.finished
		idx = next_idx

func _on_play_pressed() -> void:
	_save_placeholder_to_leaderboard()
	# Play bite-in wipe, then change to main so main can play the bite-out/reveal.
	var bite = bite_wipe_scene.instantiate()
	var bite_anim := bite.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if bite_wipe_scene:
		get_tree().get_root().add_child(bite)
		if bite_anim and bite_anim.has_animation("bite"):
			bite_anim.play("bite")
			await bite_anim.animation_finished
	get_tree().change_scene_to_file("res://Main.tscn")
	bite_anim.play("bite_out")
	await bite_anim.animation_finished
	bite.queue_free()

func _on_exit_pressed() -> void:
	_save_placeholder_to_leaderboard()
	get_tree().quit()

func _save_placeholder_to_leaderboard() -> void:
	var entered_name = _get_entered_name()
	# if there's already an entry with the same name and a lower score, we still add — treat as leaderboard
	GlobalState.add_leaderboard_entry(entered_name, GlobalState.last_score, GlobalState.last_time)

func _exit_tree() -> void:
	# Try to persist the current placeholder if the scene is torn down unexpectedly
	_save_placeholder_to_leaderboard()
