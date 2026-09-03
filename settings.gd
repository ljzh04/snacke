extends Control

@onready var master_slider: HSlider = %MasterSlider
@onready var mute_button: Button = %MuteButton
@onready var back_button: Button = %BackButton
@onready var volume_label: Label = %VolumeLabel
@onready var easy_button: Button = %EasyButton
@onready var medium_button: Button = %MediumButton
@onready var hard_button: Button = %HardButton
@onready var difficulty_selector: Panel = %DifficultySelector
@onready var reset_button: Button = %ResetButton
@onready var reset_confirmation: ConfirmationDialog = %ResetConfirmation
@onready var fullscreen_button: Button = %FullscreenButton
@onready var title_label: Label = %TitleLabel

@export var button_muted_icon: CompressedTexture2D
@export var button_sound_icon: CompressedTexture2D
@export var bite_wipe_scene: PackedScene

const SCROLLING_PATTERN_SCENE := preload("res://ScrollingPattern.tscn")

const MASTER_BUS := "Master"

func _ready() -> void:
	randomize()
	_setup_background()
	master_slider.value_changed.connect(_on_master_slider_changed)
	mute_button.pressed.connect(_on_mute_pressed)
	easy_button.pressed.connect(_on_easy_pressed)
	medium_button.pressed.connect(_on_medium_pressed)
	hard_button.pressed.connect(_on_hard_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	reset_confirmation.confirmed.connect(_on_reset_confirmed)
	back_button.pressed.connect(_on_back_pressed)
	fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	for button in [mute_button, easy_button, medium_button, hard_button, fullscreen_button, reset_button, back_button]:
		_wire_button_squash(button)
	_load_current_volume()
	call_deferred("_update_difficulty_buttons")
	back_button.grab_focus()
	_animate_title_after_transition()



func _setup_background() -> void:
	var diag: int = randi() % ScrollingPattern.DiagonalDirection.size()

	var base := SCROLLING_PATTERN_SCENE.instantiate()
	base.density = 0.35
	base.base_scroll_speed = 0.01
	base.background_color = Color(0, 0, 0, 0)
	base.shape_color = Color(0.55, 0.55, 0.85, 0.50)
	base.shape_size = 0.14
	base.shape_type = ScrollingPattern.ShapeType.DIAMOND
	base.pattern_seed = 0.0
	base.diagonal_direction = diag
	add_child(base)

	var accent := SCROLLING_PATTERN_SCENE.instantiate()
	accent.density = 0.12
	accent.base_scroll_speed = 0.02
	accent.background_color = Color(0, 0, 0, 0)
	accent.shape_color = Color(0.65, 0.65, 0.95, 0.30)
	accent.shape_size = 0.20
	accent.shape_type = ScrollingPattern.ShapeType.DIAMOND
	accent.pattern_seed = 0.5
	# Small-shapes layer always counter-scrolls against the big-shapes layer
	# (reversed x, inverted y: fully opposite diagonal).
	accent.invert_y = true
	accent.diagonal_direction = base.reversed_direction()
	add_child(accent)

	move_child(base, 1)
	move_child(accent, 2)


func _animate_title_after_transition() -> void:
	# Wait for the incoming bite-out transition to finish revealing the scene
	# before starting the title's impact animation. _ready() fires as soon as
	# the scene is instantiated, while the bite wipe is still covering the
	# screen — so without this wait the animation would play behind the wipe
	# and be over by the time the scene is revealed.
	#
	# We wait a fixed duration matching the bite_out animation (1.0s) rather
	# than awaiting the animation_finished signal, because on repeat visits a
	# stale BiteWipe from a previous transition can be grabbed by name, and
	# the signal can race (already emitted before the await is set up), which
	# would hang the coroutine and skip the title animation entirely.
	await get_tree().process_frame
	await get_tree().create_timer(0.9).timeout
	_animate_title_intro()


func _animate_title_intro() -> void:
	if not is_instance_valid(title_label):
		return

	var title_size := title_label.size

	# Remaining nail is on the left-middle edge.
	title_label.pivot_offset = Vector2(
		0.0,
		title_size.y * 0.5
	)

	var base_position := title_label.position

	# Cancel anything left over from a previous scene visit.
	title_label.scale = Vector2.ONE
	title_label.rotation_degrees = 0.0
	title_label.position = base_position
	title_label.modulate.a = 1.0


	var tw := create_tween()


	tw.tween_property(
		title_label,
		"rotation_degrees",
		13.0,
		0.24
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


	tw.tween_property(
		title_label,
		"rotation_degrees",
		5.2,
		0.12
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


	# Tiny settling correction.
	tw.tween_property(
		title_label,
		"rotation_degrees",
		4.4,
		0.08
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


	# Final resting angle.
	tw.tween_property(
		title_label,
		"rotation_degrees",
		5.0,
		0.10
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)




func _load_current_volume() -> void:
	var bus_idx := AudioServer.get_bus_index(MASTER_BUS)
	if bus_idx == -1:
		return
	var db := AudioServer.get_bus_volume_db(bus_idx)
	var linear := db_to_linear(db)
	master_slider.value = linear
	_update_volume_label(linear)
	_update_mute_button(AudioServer.is_bus_mute(bus_idx))

func _on_master_slider_changed(value: float) -> void:
	var bus_idx := AudioServer.get_bus_index(MASTER_BUS)
	if bus_idx == -1:
		return
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
	AudioServer.set_bus_mute(bus_idx, value <= 0.0)
	_update_volume_label(value)
	_update_mute_button(value <= 0.0)

func _on_mute_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	var bus_idx := AudioServer.get_bus_index(MASTER_BUS)
	if bus_idx == -1:
		return
	var muted := not AudioServer.is_bus_mute(bus_idx)
	AudioServer.set_bus_mute(bus_idx, muted)
	_update_mute_button(muted)

func _update_volume_label(value: float) -> void:
	volume_label.text = "Volume: %d%%" % int(round(value * 100.0))

func _update_mute_button(muted: bool) -> void:
	mute_button.icon = button_muted_icon if muted else button_sound_icon

func _on_easy_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	GlobalState.difficulty = "Easy"
	_update_difficulty_buttons()

func _on_medium_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	GlobalState.difficulty = "Medium"
	_update_difficulty_buttons()

func _on_hard_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	GlobalState.difficulty = "Hard"
	_update_difficulty_buttons()

func _update_difficulty_buttons() -> void:
	var current = GlobalState.difficulty
	var selected_button: Button
	match current:
		"Easy": selected_button = easy_button
		"Hard": selected_button = hard_button
		_: selected_button = medium_button

	easy_button.disabled = current == "Easy"
	medium_button.disabled = current == "Medium"
	hard_button.disabled = current == "Hard"

	# Match the selector's size to the selected button's actual laid-out size.
	# The buttons live in an HBoxContainer, so their width is container-driven
	# and can differ from the size captured at _ready time — read it fresh each
	# update so the overlay always covers the button exactly. The selector is
	# top_level, so use the button's global rect for both size and position.
	# Wait a frame so the container has finished laying out the buttons.
	await get_tree().process_frame
	if not is_instance_valid(selected_button):
		return
	var target_rect := selected_button.get_global_rect()
	difficulty_selector.size = target_rect.size
	var tween := create_tween()
	tween.tween_property(difficulty_selector, "position", target_rect.position, 0.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_back_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	var bite = bite_wipe_scene.instantiate()
	get_tree().get_root().add_child(bite)
	var bite_anim := bite.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if bite_anim and bite_anim.has_animation("bite"):
		bite_anim.play("bite")
		await bite_anim.animation_finished
	get_tree().change_scene_to_file("res://Main_Menu.tscn")
	if bite_anim and bite_anim.has_animation("bite_out"):
		bite_anim.play("bite_out")
		await bite_anim.animation_finished
	await bite.get_tree().create_timer(1.0).timeout
	bite.queue_free()

func _on_reset_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	reset_confirmation.popup_centered()

func _on_reset_confirmed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	var save_path = GlobalState.SAVE_PATH
	if ResourceLoader.exists(save_path):
		DirAccess.remove_absolute(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	GlobalState.user_data = UserData.new()
	GlobalState.user_data.profiles["Guest"] = {"score": 0, "time": 0.0}
	GlobalState.difficulty = "Medium"
	var bus_idx := AudioServer.get_bus_index(MASTER_BUS)
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(1.0))
		AudioServer.set_bus_mute(bus_idx, false)
	_load_current_volume()
	_update_difficulty_buttons()
	reset_button.disabled = true
	reset_button.modulate = Color(1, 1, 1, 0.5)


func _on_fullscreen_pressed() -> void:
	audio_manager_play_click()
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(800, 640))
		# Center the windowed window on the current screen.
		var screen := DisplayServer.window_get_current_screen()
		var screen_size := DisplayServer.screen_get_size(screen)
		var screen_pos := DisplayServer.screen_get_position(screen)
		var window_size := DisplayServer.window_get_size()
		var centered := screen_pos + (screen_size - window_size) / 2
		DisplayServer.window_set_position(centered)
	else:
		# Keep the internal resolution at 800x640 so the UI layout stays
		# exactly as designed. The canvas_items + integer stretch mode scales
		# the fixed viewport up to the screen with crisp nearest-neighbor
		# pixel scaling, so nothing reflows or re-anchors.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	# Defer the label update so the mode change has time to settle.
	_update_fullscreen_button.call_deferred()


func _update_fullscreen_button() -> void:
	var mode := DisplayServer.window_get_mode()
	var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	fullscreen_button.text = "ON" if is_fullscreen else "OFF"


func audio_manager_play_click() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)


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
