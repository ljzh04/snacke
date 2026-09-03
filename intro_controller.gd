extends Node

const ZOOM_START := 4.0
const ZOOM_END := 1.0
const FADE_IN := 0.2
const ZOOM_DURATION := 0.7
const FADE_OUT := 0.2
const HOLD := 0.35

@onready var camera: Camera2D = get_parent().get_node("Camera2D")
@onready var survive_label: Label = get_parent().get_node("IntroUI/SurviveLabel")
@onready var mouse_hint: Label = get_parent().get_node("IntroUI/MouseHint")
@onready var player: CharacterBody2D = get_parent().get_node("Player")
@onready var snake_head: Area2D = get_parent().get_node("Snake/SnakeHead")
@onready var game_manager: GameManager = get_parent().get_node("GameManager")
@onready var hud: CanvasLayer = get_parent().get_node("CanvasLayer")

func _ready() -> void:
	# Camera starts zoomed in on the player position.
	camera.global_position = player.global_position
	camera.zoom = Vector2(ZOOM_START, ZOOM_START)

	# Position the intro overlays in screen space, just above the on-screen player.
	var screen_size := Vector2(get_viewport().get_visible_rect().size)
	survive_label.position = screen_size * 0.5 - survive_label.size * 0.5 + Vector2(0, -90)
	mouse_hint.position = screen_size * 0.5 - mouse_hint.size * 0.5 + Vector2(0, 90)
	survive_label.modulate.a = 0.0
	mouse_hint.modulate.a = 0.0

	# Lock gameplay during the intro so the snake can't lunge / player can't move.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	snake_head.process_mode = Node.PROCESS_MODE_DISABLED

	# Hide the HUD (score / time / pause button) until the zoom-out has
	# finished and the player actually has control.
	hud.visible = false

	# Wait for any incoming bite-wipe transition to finish (including its
	# bite_out) before starting the intro cutscene, so the intro isn't hidden
	# behind the wipe.
	await _wait_for_bite_wipe()

	_play_intro()

func _wait_for_bite_wipe() -> void:
	var bite = get_tree().get_root().get_node_or_null("BiteWipe")
	if not is_instance_valid(bite):
		return
	var bite_anim := bite.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if bite_anim and bite_anim.is_playing():
		await bite_anim.animation_finished
	# Give the bite scene a moment to free itself after the wipe completes.
	await get_tree().process_frame

func _play_intro() -> void:
	# Fade in SURVIVE and the mouse hint.
	var fade_in := create_tween()
	fade_in.tween_property(survive_label, "modulate:a", 1.0, FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_in.parallel().tween_property(mouse_hint, "modulate:a", 0.85, FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await fade_in.finished

	# Hold the zoomed shot briefly.
	await get_tree().create_timer(HOLD).timeout

	# Zoom out to the full arena.
	var zoom_tween := create_tween()
	zoom_tween.set_parallel(true)
	zoom_tween.tween_property(camera, "zoom", Vector2(ZOOM_END, ZOOM_END), ZOOM_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	zoom_tween.tween_property(camera, "global_position", Vector2(400, 320), ZOOM_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await zoom_tween.finished

	# Fade out the intro overlays.
	var fade_out := create_tween()
	fade_out.tween_property(survive_label, "modulate:a", 0.0, FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_out.parallel().tween_property(mouse_hint, "modulate:a", 0.0, FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await fade_out.finished

	# Reveal the HUD and start the survival clock at the exact moment the
	# player gains control, so score and time begin at zero on the first
	# controllable frame.
	hud.visible = true
	game_manager.start_run()

	# Hand control back.
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.enable_input_after_intro()
	snake_head.process_mode = Node.PROCESS_MODE_INHERIT
