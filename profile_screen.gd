extends Control

@onready var name_edit: LineEdit = %LineEdit
@onready var play_button: Button = %Button
@onready var exit_button: Button = %ExitButton
@onready var menu_button: Button = %MenuButton
@onready var difficulty_label: Label = %DifficultyLabel
@onready var score_label: Label = %ScoreLabel
@onready var time_label: Label = %TimeLabel
@onready var high_score_label: Label = %HighScoreLabel
@onready var best_label: Label = %BestLabel
@onready var leaderboard_entries: VBoxContainer = %LeaderboardEntries
@onready var title_label: Label = %TitleLabel
var placeholder_label: Label = null
var placeholder_index: int = -1
# Guards against saving the placeholder leaderboard entry more than once
# per visit (e.g. button handler + _exit_tree both firing on scene change).
var _leaderboard_saved: bool = false
@export var bite_wipe_scene: PackedScene

const SCROLLING_PATTERN_SCENE := preload("res://ScrollingPattern.tscn")

const TITLE_GLOW_DIM := Color(1.0, 0.15, 0.15, 1.0)
const TITLE_GLOW_HOT := Color(1.0, 0.55, 0.55, 1.0)

func _get_entered_name() -> String:
	var profile_name := name_edit.text.strip_edges()
	if profile_name.is_empty():
		profile_name = "Guest"
	return profile_name


func _truncate_name(entry_name: String, max_len: int) -> String:
	if entry_name.length() > max_len:
		return entry_name.substr(0, max_len - 3) + "..."
	return entry_name

func _ready() -> void:
	randomize()
	_leaderboard_saved = false
	_setup_background()
	# Keep the title hidden until its slam-in entrance reveals it (after any
	# incoming bite-wipe has finished revealing the scene).
	title_label.modulate.a = 0.0
	_start_title_idle()
	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	for button in [play_button, exit_button, menu_button]:
		_wire_button_squash(button)
	name_edit.text_changed.connect(_on_name_text_changed)
	# Pre-fill the name field with the last-entered name (persisted across
	# visits) instead of always clearing it. The player can change or clear
	# it as usual; the new value is remembered for the next visit.
	name_edit.text = GlobalState.last_profile_name
	_populate_leaderboard()
	_update_session_stats()
	_update_difficulty_label()
	name_edit.grab_focus()
	name_edit.select_all()
	AudioManager.play_music_after_transitions(AudioManager.Music.PROFILE)



func _setup_background() -> void:
	var diag: int = randi() % ScrollingPattern.DiagonalDirection.size()

	var base := SCROLLING_PATTERN_SCENE.instantiate()
	base.density = 0.35
	base.base_scroll_speed = 0.01
	base.background_color = Color(0, 0, 0, 0)
	base.shape_color = Color(0.55, 0.55, 0.85, 0.50)
	base.shape_size = 0.14
	base.shape_type = ScrollingPattern.ShapeType.STAR
	base.pattern_seed = 0.0
	base.diagonal_direction = diag
	add_child(base)

	var accent := SCROLLING_PATTERN_SCENE.instantiate()
	accent.density = 0.12
	accent.base_scroll_speed = 0.02
	accent.background_color = Color(0, 0, 0, 0)
	accent.shape_color = Color(0.65, 0.65, 0.95, 0.30)
	accent.shape_size = 0.20
	accent.shape_type = ScrollingPattern.ShapeType.STAR
	accent.pattern_seed = 0.5
	# Small-shapes layer always counter-scrolls against the big-shapes layer
	# (reversed x, inverted y: fully opposite diagonal).
	accent.invert_y = true
	accent.diagonal_direction = base.reversed_direction()
	add_child(accent)

	move_child(base, 1)
	move_child(accent, 2)

func _update_difficulty_label() -> void:
	difficulty_label.text = "Difficulty: %s" % [GlobalState.difficulty]

func _populate_leaderboard() -> void:
	var entries := GlobalState.get_leaderboard()
	placeholder_label = null
	placeholder_index = -1
	var insert_idx := entries.size()
	for i in range(min(entries.size(), 10)):
		if GlobalState.last_score > entries[i]["score"]:
			insert_idx = i
			break

	var display := entries.duplicate()
	if insert_idx < 10:
		display.insert(insert_idx, {"name": _get_entered_name(), "score": GlobalState.last_score})

	for i in range(leaderboard_entries.get_child_count()):
		var label = leaderboard_entries.get_child(i)
		if i < 10 and i < display.size() and display[i] is Dictionary:
			var entry = display[i]
			var display_name = _truncate_name(entry["name"], 11)
			label.text = "%d. %s - %d" % [i + 1, display_name, entry["score"]]
			if i == insert_idx:
				placeholder_label = label
				placeholder_index = i
				_update_placeholder_text()
				_start_placeholder_animation()
		else:
			label.text = "%d. ---" % [i + 1]

	_animate_leaderboard_rows()

func _animate_leaderboard_rows() -> void:
	# Staggered slide-in for the leaderboard rows. Wait for any incoming
	# bite-wipe to finish revealing the scene first, so the slide-in isn't
	# spent hidden behind the wipe. Then wait one frame so the VBoxContainer
	# has laid the rows out (position is container-driven).
	await _wait_for_bite_wipe()
	await get_tree().process_frame
	var idx := 0
	for row in leaderboard_entries.get_children():
		if not (row is Control):
			idx += 1
			continue
		var target_x: float = row.position.x
		row.position.x = target_x + 24.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(row, "position:x", target_x, 0.3) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
			.set_delay(idx * 0.05)
		# The placeholder row's modulate is owned by its color-cycling
		# animation, so only slide it; fade the rest in from transparent.
		if row != placeholder_label:
			row.modulate.a = 0.0
			tw.tween_property(row, "modulate:a", 1.0, 0.3) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
				.set_delay(idx * 0.05)
		idx += 1

func _update_session_stats() -> void:
	var last_score = GlobalState.last_score
	var last_time = GlobalState.last_time
	time_label.text = "Time Survived: %.2fs" % [last_time]
	var leaderboard = GlobalState.get_leaderboard()
	var current_high = 0
	if leaderboard.size() > 0:
		current_high = leaderboard[0]["score"]
	# Count the two score stats up from zero for a little arcade flair. Wait
	# for any incoming bite-wipe to finish revealing the scene first, so the
	# count-up isn't spent hidden behind the wipe. Both count-ups share this
	# single wait so they animate together after the reveal.
	await _wait_for_bite_wipe()
	_tween_count_up(score_label, "Last Score: %d", last_score)
	_tween_count_up(high_score_label, "High Score: %d", current_high)
	best_label.text = "All Time Best: %d" % [current_high]

func _tween_count_up(label: Label, format: String, target: int) -> void:
	label.text = format % 0
	var tw := create_tween()
	tw.tween_method(_set_count_text.bind(label, format), 0, target, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _set_count_text(value: int, label: Label, format: String) -> void:
	label.text = format % value

func _on_name_text_changed(_new_text: String) -> void:
	_update_placeholder_text()
	# Remember the name as the player types so the next visit pre-fills it.
	GlobalState.set_last_profile_name(_new_text)
	var leaderboard = GlobalState.get_leaderboard()
	var current_high = leaderboard[0]["score"] if leaderboard.size() > 0 else 0
	high_score_label.text = "High Score: %d" % [current_high]
	best_label.text = "All Time Best: %d" % [current_high]

func _update_placeholder_text() -> void:
	if placeholder_label:
		var entered_name = _truncate_name(_get_entered_name(), 11)
		placeholder_label.text = "%d. %s - %d" % [placeholder_index + 1, entered_name, GlobalState.last_score]

func _start_placeholder_animation() -> void:
	if not placeholder_label:
		return
	_anim_loop()

func _anim_loop() -> void:
	var colors = [Color(1, 0.5, 0.5, 1), Color(0.5, 1, 0.5, 1), Color(0.5, 0.5, 1, 1)]
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
	AudioManager.play(AudioManager.SFX.CLICK)
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
	AudioManager.play(AudioManager.SFX.CLICK)
	get_tree().quit()

func _on_menu_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	var bite = bite_wipe_scene.instantiate()
	var bite_anim := bite.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if bite_wipe_scene:
		get_tree().get_root().add_child(bite)
		if bite_anim and bite_anim.has_animation("bite"):
			bite_anim.play("bite")
			await bite_anim.animation_finished
	get_tree().change_scene_to_file("res://Main_Menu.tscn")
	if bite_anim and bite_anim.has_animation("bite_out"):
		bite_anim.play("bite_out")
		await bite_anim.animation_finished
	bite.queue_free()

func _save_placeholder_to_leaderboard() -> void:
	if _leaderboard_saved:
		return
	_leaderboard_saved = true
	var entered_name = _get_entered_name()
	GlobalState.add_leaderboard_entry(entered_name, GlobalState.last_score, GlobalState.last_time)

func _wire_button_squash(button: Button) -> void:
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))

func _on_button_down(button: Button) -> void:
	button.pivot_offset = button.size / 2.0
	var tw := create_tween()
	tw.tween_property(button, "scale", Vector2(0.92, 0.92), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_button_up(button: Button) -> void:
	var tw := create_tween()
	tw.tween_property(button, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _exit_tree() -> void:
	_save_placeholder_to_leaderboard()

# Waits for any incoming bite-wipe overlay to finish revealing this scene.
# The wipe's AnimationPlayer is guaranteed to be mid-"bite_out" by the time
# _ready runs (change_scene_to_file is deferred) - the same assumption made
# by AudioManager.play_music_after_transitions and intro_controller.gd.
#
# We wait a fixed duration matching the bite_out animation (1.0s) rather than
# awaiting the animation_finished signal, because on repeat visits a stale
# BiteWipe from a previous transition can be grabbed by name, and the signal
# can race (already emitted before the await is set up), which would hang the
# coroutine and skip the title entrance entirely.
func _wait_for_bite_wipe() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.9).timeout

# --- GAME OVER title juice ---------------------------------------------------
# One-shot slam-in entrance, then a looping idle animation: heartbeat scale
# pulse, gentle rocking wobble and a breathing red glow on the font color.
func _start_title_idle() -> void:
	# Wait for any incoming bite-wipe transition (e.g. the game-over wipe)
	# to finish revealing this scene before running the entrance + idle loop,
	# so the animations are not spent hidden behind the wipe.
	await _wait_for_bite_wipe()
	# Wait a frame so the label has its final layout size before centering
	# the pivot used for scaling/rotation.
	await get_tree().process_frame
	if not is_instance_valid(title_label):
		return
	title_label.pivot_offset = title_label.size / 2.0
	title_label.resized.connect(
		func(): title_label.pivot_offset = title_label.size / 2.0)
	# Entrance: slam in from oversized + transparent with a back-ease overshoot.
	title_label.scale = Vector2(2.4, 2.4)
	title_label.modulate.a = 0.0
	var intro := create_tween().set_parallel()
	intro.tween_property(title_label, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(title_label, "modulate:a", 1.0, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Idle: heartbeat double-thump pulse.
	var pulse := create_tween().set_loops()
	pulse.tween_interval(0.9)
	pulse.tween_property(title_label, "scale", Vector2(1.08, 1.08), 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse.tween_property(title_label, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse.tween_property(title_label, "scale", Vector2(1.05, 1.05), 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse.tween_property(title_label, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Idle: gentle rocking wobble.
	var wobble := create_tween().set_loops()
	wobble.tween_property(title_label, "rotation_degrees", 2.0, 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	wobble.tween_property(title_label, "rotation_degrees", -2.0, 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Idle: breathing red glow (a modulate tint would be invisible against the
	# already-pure-red font, so tween the font color override instead).
	var glow := create_tween().set_loops()
	glow.tween_property(title_label, "theme_override_colors/font_color", TITLE_GLOW_HOT, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	glow.tween_property(title_label, "theme_override_colors/font_color", TITLE_GLOW_DIM, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
