extends Node
## Pause overlay controller. Freezes the whole scene tree and shows a modal
## with Back (resume), Restart and Exit (to main menu). Lives on
## PROCESS_MODE_ALWAYS so its input handling and buttons keep working while
## the rest of the game is paused.

@export var game_manager: GameManager

@onready var pause_button: Button = %PauseButton
@onready var modal: Control = %PauseModal
@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var exit_button: Button = %ExitButton

func _ready() -> void:
	# The pause UI must keep processing while the tree is paused, or its
	# buttons (and the resume path) would be frozen along with the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_button.pressed.connect(_on_pause_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	modal.visible = false

	# Same button juice as the title screen: hover brighten, press squash,
	# gentle idle brightness pulse. The pause button pulses during gameplay
	# as a soft affordance; pass `false` to ButtonJuice.attach to turn the
	# idle pulse off for any button.
	ButtonJuice.attach(pause_button)
	ButtonJuice.attach(resume_button)
	ButtonJuice.attach(restart_button)
	ButtonJuice.attach(exit_button)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if modal.visible:
			_on_resume_pressed()
		elif _can_pause():
			_on_pause_pressed()
		get_viewport().set_input_as_handled()

# Pausing is only meaningful while a run is live: block it during the intro
# (the hidden modal would freeze the game with nothing on screen) and during
# the game-over sequence / profile transition.
func _can_pause() -> bool:
	return is_instance_valid(game_manager) and not game_manager.is_game_over \
			and game_manager.run_started

func _on_pause_pressed() -> void:
	if get_tree().paused or not _can_pause():
		return
	AudioManager.play(AudioManager.SFX.CLICK)
	get_tree().paused = true
	modal.visible = true
	pause_button.disabled = true
	resume_button.grab_focus()

func _on_resume_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	modal.visible = false
	pause_button.disabled = false
	get_tree().paused = false

func _on_restart_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	# Unpause BEFORE touching the tree: a paused tree freezes the scene
	# transition, and the fresh scene must come up unpaused.
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_exit_pressed() -> void:
	AudioManager.play(AudioManager.SFX.CLICK)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Main_Menu.tscn")
