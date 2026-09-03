extends CharacterBody2D

@export var move_delay := 0.05
# How many cell steps the logic may run ahead of the sprite's glide. Small
# values keep the visual tightly synced with gameplay; larger values let the
# sprite queue more of the A* route before the animation catches up.
@export var max_queued_steps := 2
var tile_size := 32
var current_cell: Vector2i = Vector2i.ZERO

@export var game_manager: GameManager
var half_size := tile_size * 0.5
@onready var animation_player = $AnimationPlayer

var _waiting_for_mouse := true
var _anchor_mouse_cell: Vector2i = Vector2i.ZERO
var _input_enabled := false

func _ready():
	add_to_group("Player")
	if game_manager:
		current_cell = game_manager.grid.world_to_grid(global_position)
		_anchor_mouse_cell = current_cell
	call_deferred("_animate_player_spawn")

func _process(_delta: float) -> void:
	if not _input_enabled:
		return
	if not is_instance_valid(game_manager) or game_manager.is_game_over:
		return

	var mouse_pos = get_global_mouse_position()
	var target_cell = game_manager.grid.world_to_grid(mouse_pos)

	if _waiting_for_mouse:
		if target_cell == _anchor_mouse_cell:
			return
		_waiting_for_mouse = false

	# The logic (grid position) may run a few cells ahead of the sprite, but
	# never more than max_queued_steps: each requested step is appended to
	# the glide queue in game_manager, and the sprite consumes it at a
	# constant one-cell-per-move_delay speed along the real cardinal path.
	# This decouples speed from frame rate and path length — the sprite
	# always visibly travels the route, never teleporting from A to B.
	var max_steps_per_frame = 60

	# Ask A* ONCE per frame for the full route from the current cell to the
	# mouse cell, with snake body cells treated as unpassable (4-directional
	# only, no diagonals). If the snake slides onto a waypoint before it is
	# consumed, request_player_move_to refuses the step and we stop; the
	# next frame recomputes a fresh path around the snake's new position.
	# When no path exists (mouse on/behind the snake, or walled off), the
	# waypoint list stays empty and the greedy fallback inside
	# request_player_move_to takes over — it still refuses to enter snake
	# cells, so the player just stops adjacent to the blocking body.
	var path: Array[Vector2i] = []
	if game_manager.grid.is_cell_inside(target_cell):
		path = game_manager.find_player_path(current_cell, target_cell)

	for i in range(max_steps_per_frame):
		if game_manager.is_game_over:
			break

		if target_cell == current_cell:
			break

		# Don't enqueue new steps while the glide queue is full — keeps the
		# sprite tightly synced with gameplay and mouse retargets responsive.
		if game_manager.player_move_queue_count() >= max_queued_steps:
			break

		if game_manager.grid.is_cell_inside(target_cell):
			# Follow the A* route when one exists; otherwise aim straight
			# at the target and let request_player_move_to's greedy
			# one-axis step handle it.
			var step_target: Vector2i = target_cell
			if not path.is_empty():
				step_target = path[0]

			if game_manager.request_player_move_to(step_target):
				current_cell = game_manager.player_cell
				if not path.is_empty():
					path.remove_at(0)
			else:
				break
		else:
			break

func _animate_player_spawn():
	var anim_sprite = get_node("AnimatedSprite2D") as AnimatedSprite2D
	anim_sprite.play("player_wake_up")
	await anim_sprite.animation_finished
	anim_sprite.play("player_idle")

func enable_input_after_intro() -> void:
	# Called once the intro zoom-out has finished; the player should only begin
	# following the mouse after the user actually moves it from its current cell,
	# so we re-arm the wait and anchor at wherever the mouse is right now.
	if game_manager:
		_anchor_mouse_cell = game_manager.grid.world_to_grid(get_global_mouse_position())
	else:
		_anchor_mouse_cell = current_cell
	_waiting_for_mouse = true
	_input_enabled = true
	set_process(true)

func play_surprise_animation():
	animation_player.play("player_dead")

func disable_input():
	_input_enabled = false
	set_process(false)
