extends Control

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var exit_button: Button = %ExitButton
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel

@export var bite_wipe_scene: PackedScene

const SCROLLING_PATTERN_SCENE := preload("res://ScrollingPattern.tscn")

static var _has_booted := false


func _ready() -> void:
	randomize()
	_setup_background()
	_set_bg_transparent()
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	play_button.grab_focus()
	AudioManager.play_music_after_transitions(AudioManager.Music.MENU)
	await _play_boot_bite_out()
	_animate_title()
	_animate_buttons()


func _play_boot_bite_out() -> void:
	if _has_booted:
		return
	_has_booted = true
	if not bite_wipe_scene:
		return
	var bite = bite_wipe_scene.instantiate()
	get_tree().get_root().add_child.call_deferred(bite)
	var bite_anim := bite.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if bite_anim and bite_anim.has_animation("bite_out"):
		bite_anim.play("bite_out")
		await bite_anim.animation_finished
	bite.queue_free()


func _setup_background() -> void:
	var diag: int = randi() % ScrollingPattern.DiagonalDirection.size()

	var base := SCROLLING_PATTERN_SCENE.instantiate()
	base.density = 0.35
	base.base_scroll_speed = 0.01
	base.background_color = Color(0, 0, 0, 0)
	base.shape_color = Color(0.55, 0.55, 0.85, 0.50)
	base.shape_size = 0.14
	base.shape_type = ScrollingPattern.ShapeType.SQUARE
	base.pattern_seed = 0.0
	base.diagonal_direction = diag
	add_child(base)

	var accent := SCROLLING_PATTERN_SCENE.instantiate()
	accent.density = 0.12
	accent.base_scroll_speed = 0.02
	accent.background_color = Color(0, 0, 0, 0)
	accent.shape_color = Color(0.65, 0.65, 0.95, 0.30)
	accent.shape_size = 0.20
	accent.shape_type = ScrollingPattern.ShapeType.SQUARE
	accent.pattern_seed = 0.5
	# Small-shapes layer always counter-scrolls against the big-shapes layer
	# (reversed x, inverted y: fully opposite diagonal).
	accent.invert_y = true
	accent.diagonal_direction = base.reversed_direction()
	add_child(accent)

	move_child(base, 1)
	move_child(accent, 2)


func _set_bg_transparent() -> void:
	var bg = get_node_or_null("ColorRect") as ColorRect
	if bg:
		bg.color.a = 1.0


func _animate_title() -> void:
	# Gentle idle motion on the main title so it never sits still.
	var base_pos := title_label.position
	var base_rot: float = title_label.rotation_degrees

	var bob := create_tween().set_loops()
	bob.tween_property(title_label, "position:y", base_pos.y + 4.0, 1.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(title_label, "position:y", base_pos.y, 1.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var breath := create_tween().set_loops()
	breath.tween_property(title_label, "scale", Vector2(1.03, 1.03), 1.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property(title_label, "scale", Vector2.ONE, 1.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var shimmer := create_tween().set_loops()
	shimmer.tween_property(title_label, "modulate", Color(1.0, 0.96, 0.86, 1.0), 2.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	shimmer.tween_property(title_label, "modulate", Color.WHITE, 2.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var sway := create_tween().set_loops()
	sway.tween_property(title_label, "rotation_degrees", base_rot + 1.3, 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(title_label, "rotation_degrees", base_rot - 1.3, 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(title_label, "rotation_degrees", base_rot, 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)





func _animate_buttons() -> void:
	# Juice lives in the shared ButtonJuice helper so the pause modal (and
	# any future menu) gets the exact same feel as the title screen.
	var buttons: Array[Button] = [play_button, settings_button, exit_button]
	for button in buttons:
		ButtonJuice.attach(button)


func _play_bite_transition(target_scene: String) -> void:
	var bite = bite_wipe_scene.instantiate()
	get_tree().get_root().add_child(bite)
	var bite_anim := bite.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if bite_anim and bite_anim.has_animation("bite"):
		bite_anim.play("bite")
		await bite_anim.animation_finished
	get_tree().change_scene_to_file(target_scene)
	if bite_anim and bite_anim.has_animation("bite_out"):
		bite_anim.play("bite_out")
		await bite_anim.animation_finished
	bite.queue_free()


func _on_play_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	await _play_bite_transition("res://Main.tscn")


func _on_settings_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	await _play_bite_transition("res://Settings.tscn")


func _on_exit_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	get_tree().quit()
