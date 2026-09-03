class_name GameManager
extends Node

signal score_updated(new_score: int)
signal time_updated(time_string: String)
signal level_changed(level: int) 

class Grid:
	var rect: Rect2
	var tile_size: int
	var columns: int
	var rows: int
	var board: Array = []

	func _init(_rect: Rect2, _tile_size: int):
		rect = _rect
		tile_size = _tile_size
		columns = int(rect.size.x / tile_size)
		rows = int(rect.size.y / tile_size)
		initialize_board()

	func initialize_board():
		board.clear()
		for y in range(rows):
			var row := []
			for x in range(columns):
				row.append(0)
			board.append(row)

	func world_to_grid(world_pos: Vector2) -> Vector2i:
		var half_size = tile_size * 0.5
		var local_pos = world_pos - rect.position
		var grid_x = int(floor((local_pos.x - half_size) / tile_size))
		var grid_y = int(floor((local_pos.y - half_size) / tile_size))
		return Vector2i(grid_x, grid_y)

	func grid_to_world(grid_pos: Vector2i) -> Vector2:
		var half_size = tile_size * 0.5
		return rect.position + Vector2(grid_pos.x * tile_size, grid_pos.y * tile_size) + Vector2(half_size, half_size)

	func is_cell_inside(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < columns and cell.y >= 0 and cell.y < rows

	func get_cell(cell: Vector2i) -> int:
		if not is_cell_inside(cell): return 0
		return board[cell.y][cell.x]

	func set_cell(cell: Vector2i, value: int):
		if is_cell_inside(cell):
			board[cell.y][cell.x] = value

# Impact hit effect shown when the snake catches the player.
const HIT_EFFECT_SCENE := preload("res://Hit_Effect.tscn")
# Sparkle burst shown when a powerup is collected.
const PICKUP_EFFECT_SCENE := preload("res://PickUp_Effect.tscn")
# Small pop shown when the snake eats food.
const EAT_EFFECT_SCENE := preload("res://Eat_Effect.tscn")
# Font used by the floating "+N" score text.
const FLOAT_FONT := preload("res://PeaberryBase.ttf")

@export var snake_head: Area2D
@export var snake_segment: PackedScene
@export var corner_piece: PackedScene
@export var food_spawner: Node
@export var powerup_spawner: Node
@export var initial_snake_length := 3
@export var bite_wipe_scene: PackedScene
@export var player: CharacterBody2D
@export var play_area_rect := Rect2(32, 64, 736, 544)

var grid: Grid
var base_tile := 32
var snake_segments: Array[Node2D] = []
var corner_pieces: Dictionary = {}
var _pending_corner_cleanup: Array[Node2D] = []
var score := 0
# Segments present at spawn. The score's length term counts only growth
# beyond this, so a long starting snake (e.g. initial_snake_length = 130)
# never gifts free points at spawn.
var _initial_segment_count := 0
# Set when the intro hands control to the player (start_run). Gates the
# survival clock so score/time don't accrue before the player can act.
var run_started := false
var grow_pending := 0
var _pending_shrink_target := -1  # -1 = no pending shrink
var game_time := 0.0
var current_level := 1
var player_cell: Vector2i = Vector2i.ZERO
var food_cell: Vector2i = Vector2i.ZERO
var powerup_cell: Vector2i = Vector2i(-1, -1)
var is_animating := false
var is_player_animating := false
var is_game_over := false
var bite_instance_ref: Node = null

# Frame-based movement interpolation (replaces tweening).
var _move_active := false
var _move_progress := 0.0
var _move_duration := 0.08
var _move_from: Array[Vector2] = []
var _move_to: Array[Vector2] = []
var _move_did_grow := false
# Set when the snake bites its own body on this move (cutting segments from
# the contact point to the tail). Used to skip the normal tail-pop in
# _on_turn_animation_finished, because the bite already removed the tail.
var _did_bite_this_turn := false
# FIFO queue of hidden segments for staggered growth. Each entry sits at
# the tail's landing cell (z_index = -1) for one frame, then is promoted to
# snake_segments one per frame (front-first, so FIFO). The hidden nodes *are*
# the pending growth; grow_pending bookkeeping still controls the AI's
# tail-freeze prediction. New eats while the queue is non-empty stack another
# hidden segment at the same frozen tail cell immediately.
var _hidden_growth_queue: Array[Node2D] = []

# Frame-based player movement interpolation (replaces tweening): the
# player's exact position is owned by _process, so collision checks see a
# deterministic position on every game frame. The sprite glides through a
# QUEUE of waypoints (one per requested cell step) at a constant speed of
# one cell per _player_move_duration seconds, following the real cardinal
# path around corners — so a long A* route reads as a fast run, never a
# straight-line teleport lerp between distant cells.
var _player_move_active := false
var _player_move_duration := 0.05
# World-space polyline to glide through. Waypoints[0] is the current
# segment's start; _player_move_seg_progress is the fraction traveled into
# the segment waypoints[0] -> waypoints[1].
var _player_move_waypoints: Array[Vector2] = []
var _player_move_seg_progress := 0.0
# Set while the player is animating INTO a snake body cell. The move is
# allowed to land visually; the game-over sequence only starts when the
# interpolation completes (see the player move block in _process).
var _player_move_lethal := false

# Corner cleanup: hide the corner when move progress reaches this fraction.
const CORNER_HIDE_PROGRESS := 1.0
# Undertail corner (old basis = tail's current cell).
var _pending_tail_corner: Node2D = null
# Overtail corner (new basis = tail's destination cell).
var _pending_overtail_corner: Node2D = null

# Frame-based game-over lunge interpolation.
var _lunge_active := false
var _lunge_progress := 0.0
var _lunge_duration := 0.08
var _lunge_from: Array[Vector2] = []
var _lunge_to: Array[Vector2] = []
# Whether the snake grew on the move that killed it. The death move never
# "completes" (its interpolation is replaced by the lunge), so this is needed
# to sync previous_positions after the lunge exactly like
# _on_turn_animation_finished does for normal moves.
var _death_move_did_grow := false
signal lunge_finished

# Camera shake on hit (decays to zero; offset is reset when finished).
var _shake_amount := 0.0
const SHAKE_DECAY := 40.0

# Juice state: HUD overlays, eat-streak pitch, snake speed baseline.
var _hud: CanvasLayer = null
var _proximity_vignette: TextureRect = null
var _danger_vignette: TextureRect = null
var _eat_streak := 0
var _last_eat_time := -100.0
var _snake_start_speed := 0.08
var _player_squash_tween: Tween = null

# Difficulty-driven values (from GlobalState).
var difficulty_multiplier := 2.0
var food_thrown_multiplier := 10
var difficulty_speedup := 0.012
var length_multiplier := 2
var food_thrown := 0

# Cap the snake's top speed so the move duration never gets so small that
# the frame-based interpolation skips cells (teleporting). Below ~0.04s the
# snake moves faster than the interpolation can render smoothly.
const MIN_MOVE_DURATION := 0.04

# Level-up timing scales with the current level, so the game gets
# progressively harder to advance: the player must survive longer
# at each level to speed up the snake.
const LEVEL_UP_BASE_TIME := 15.0
const LEVEL_UP_TIME_STEP := 5.0
var _time_since_level := 0.0

func _ready() -> void:
	# Hide the mouse cursor while the game is playing.
	#Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	snake_head.moved.connect(_on_snake_moved)
	snake_head.snake_trapped.connect(_on_snake_trapped)
	# Level-up is now gated in _process (scaling time + length requirements),
	# so the LevelUpTimer is no longer used for triggering level-ups.
	$LevelUpTimer.stop()

	base_tile = 32
	if is_instance_valid(snake_head):
		base_tile = int(snake_head.tile_size)

	grid = Grid.new(play_area_rect, base_tile)

	# Apply difficulty settings from GlobalState.
	var gs = get_node_or_null("/root/GlobalState")
	if gs:
		var settings = gs.get_difficulty_settings()
		difficulty_multiplier = settings["multiplier"]
		food_thrown_multiplier = settings["food_multiplier"]
		difficulty_speedup = settings["speedup"]
		if is_instance_valid(snake_head):
			snake_head.speed = settings["initial_speed"]
		length_multiplier = settings.get("length_multiplier", 2)

	# Baseline for the danger vignette (how close to top speed we are).
	if is_instance_valid(snake_head):
		_snake_start_speed = snake_head.speed

	# HUD juice: tension vignettes live in the HUD CanvasLayer, above the
	# world but below the intro overlays.
	_hud = get_node_or_null("../CanvasLayer")
	if _hud:
		_danger_vignette = _make_vignette(Color(0.55, 0.05, 0.05))
		_hud.add_child(_danger_vignette)
		_proximity_vignette = _make_vignette(Color(0.45, 0.1, 0.2))
		_hud.add_child(_proximity_vignette)

	AudioManager.play_music_after_transitions(AudioManager.Music.GAMEPLAY)

	if is_instance_valid(player):
		player.tile_size = base_tile
		player.half_size = base_tile * 0.5

	if is_instance_valid(food_spawner):
		food_spawner.tile_size = base_tile

	call_deferred("_snap_entities_to_grid")
	call_deferred("_spawn_initial_segments")
	call_deferred("_spawn_food_deferred")
	call_deferred("_delayed_alignment")
	call_deferred("_spawn_powerup_check")

func _spawn_powerup_check() -> void:
	if is_instance_valid(powerup_spawner):
		powerup_spawner.spawn_powerup_if_ready()

func _process(delta: float) -> void:
	# Survival clock: frozen until the intro hands over control, so score
	# and time never accrue while the player can't act.
	if run_started:
		game_time += delta
		var minutes = int(game_time / 60)
		var seconds = int(game_time) % 60
		var time_string = "%02d:%02d" % [minutes, seconds]
		emit_signal("time_updated", time_string)

	# Camera shake decay (hit feedback).
	if _shake_amount > 0.0:
		_shake_amount = maxf(_shake_amount - SHAKE_DECAY * delta, 0.0)
		var cam := get_viewport().get_camera_2d()
		if is_instance_valid(cam):
			if _shake_amount <= 0.0:
				cam.offset = Vector2.ZERO
			else:
				cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amount

	# Tension vignettes: red glow creeps in when the head gets close and
	# as the snake nears its top speed. Both ease toward their targets so
	# they never pop.
	if is_instance_valid(_proximity_vignette):
		var prox_target := 0.0
		var danger_target := 0.0
		if not is_game_over and is_instance_valid(snake_head) and is_instance_valid(player):
			var cell_dist := snake_head.global_position.distance_to(player.global_position) / base_tile
			if cell_dist <= 3.0:
				prox_target = 0.30
			var speed_frac := 1.0 - inverse_lerp(MIN_MOVE_DURATION, _snake_start_speed, snake_head.speed)
			danger_target = clampf(speed_frac - 0.6, 0.0, 1.0) * 0.35
		_proximity_vignette.modulate.a = lerpf(_proximity_vignette.modulate.a, prox_target, minf(delta * 6.0, 1.0))
		_danger_vignette.modulate.a = lerpf(_danger_vignette.modulate.a, danger_target, minf(delta * 3.0, 1.0))

	# Telegraph: the food pulses when the snake is heading for it instead
	# of the player (it targets whichever meal is closer).
	if not is_game_over and is_instance_valid(snake_head) and is_instance_valid(player):
		for f in get_tree().get_nodes_in_group("Food"):
			if not is_instance_valid(f):
				continue
			var sprite = f.get_node_or_null("Sprite2D")
			if not (sprite is CanvasItem):
				continue
			var food_closer: bool = f.global_position.distance_squared_to(snake_head.global_position) \
				< player.global_position.distance_squared_to(snake_head.global_position)
			var v := 1.0 + (0.15 if food_closer else 0.0) * (0.5 + 0.5 * sin(game_time * 10.0))
			sprite.modulate = Color(v, v, v)

	# Accumulate time toward the next level-up (gated on the run having
	# started, matching the survival clock).
	if run_started:
		_time_since_level += delta

	# Drive the snake's frame-based movement interpolation.
	if _move_active:
		_move_progress += delta / _move_duration
		# Hide corners once segments are far enough along the move.
		if is_instance_valid(_pending_tail_corner) and _move_progress >= CORNER_HIDE_PROGRESS:
			_hide_pending_tail_corner()
		if is_instance_valid(_pending_overtail_corner) and _move_progress >= CORNER_HIDE_PROGRESS:
			_hide_pending_overtail_corner()
		if _move_progress >= 1.0:
			_move_progress = 1.0
			_apply_move_positions(1.0)
			_move_active = false
			_on_turn_animation_finished(_move_did_grow)
			_update_visual_state(false)
			is_animating = false
		else:
			_apply_move_positions(_move_progress)

	# Drive the frame-based game-over lunge interpolation.
	if _lunge_active:
		_lunge_progress += delta / _lunge_duration
		if _lunge_progress >= 1.0:
			_lunge_progress = 1.0
			_apply_lunge_positions(1.0)
			_lunge_active = false
			lunge_finished.emit()
		else:
			_apply_lunge_positions(_lunge_progress)

	# Drive the player's frame-based movement interpolation (see
	# _advance_player_move for the waypoint-glide details).
	_advance_player_move(delta)

	# Background cleanup: free hidden corners whenever convenient.
	if not _pending_corner_cleanup.is_empty():
		for corner in _pending_corner_cleanup:
			if is_instance_valid(corner):
				corner.queue_free()
		_pending_corner_cleanup.clear()

	# Score = (Difficulty Multiplier * Time Elapsed)
	#       + (Food Thrown * Food Thrown Difficulty Multiplier)
	#       + (Snake Growth * Length Difficulty Multiplier)
	score = _compute_score()
	emit_signal("score_updated", score)

	# Level up based on time only — no minimum snake length required.
	if not is_game_over:
		var time_req = LEVEL_UP_BASE_TIME + current_level * LEVEL_UP_TIME_STEP
		if _time_since_level >= time_req:
			_on_level_up()
			_time_since_level = 0.0

	if not is_game_over and not _player_move_lethal and is_instance_valid(player):
		if _player_overlaps_snake_grid():
			_on_game_over_imminent()

# Advances the player sprite along the queued waypoint polyline by `delta`
# seconds. Speed is constant: one cell per _player_move_duration seconds,
# regardless of how many steps were requested in a frame — so the sprite
# follows the actual cardinal path (turning corners properly) instead of
# lerping straight from A to B (which read as a diagonal teleport on long
# A* routes). When the route is fully consumed the glide ends and any
# pending lethal-landing game-over fires from the arrival point.
func _advance_player_move(delta: float) -> void:
	if not _player_move_active:
		return
	var travel := base_tile / maxf(_player_move_duration, 0.001) * delta
	while travel > 0.0 and _player_move_waypoints.size() >= 2:
		var seg_len: float = _player_move_waypoints[0].distance_to(_player_move_waypoints[1])
		if seg_len <= 0.0:
			_player_move_waypoints.remove_at(0)
			_player_move_seg_progress = 0.0
			continue
		var seg_remaining := seg_len * (1.0 - _player_move_seg_progress)
		if travel >= seg_remaining:
			# Finished this segment; advance to the next one.
			travel -= seg_remaining
			_player_move_waypoints.remove_at(0)
			_player_move_seg_progress = 0.0
		else:
			_player_move_seg_progress += travel / seg_len
			travel = 0.0
	if is_instance_valid(player):
		if _player_move_waypoints.size() >= 2:
			player.global_position = _player_move_waypoints[0].lerp(
				_player_move_waypoints[1], _player_move_seg_progress)
		elif _player_move_waypoints.size() == 1:
			player.global_position = _player_move_waypoints[0]
	if _player_move_waypoints.size() <= 1:
		# Route fully consumed — the sprite has arrived.
		_player_move_waypoints.clear()
		_player_move_active = false
		is_player_animating = false
		if _player_move_lethal:
			# The player has now visually arrived inside the snake
			# body — start the game-over sequence from here.
			_player_move_lethal = false
			_on_game_over_imminent()

# Current score: time elapsed + food thrown + snake GROWTH beyond the
# initial body. The starting snake itself is free, so the run always begins
# at 0 regardless of initial_snake_length.
func _compute_score() -> int:
	var grown_segments := maxi(snake_segments.size() - _initial_segment_count, 0)
	return int(difficulty_multiplier * game_time) \
		+ (food_thrown * food_thrown_multiplier) \
		+ (grown_segments * length_multiplier)

# Called by the intro controller the moment the zoom-out finishes and the
# player gains control; starts the survival clock.
func start_run() -> void:
	run_started = true

func _spawn_initial_segments() -> void:
	snake_head.previous_positions.clear()
	var start_cell = grid.world_to_grid(snake_head.global_position)
	for i in range(initial_snake_length):
		snake_head.previous_positions.append(start_cell - Vector2i(i, 0))

	for i in range(initial_snake_length - 1):
		var segment = snake_segment.instantiate()
		segment.add_to_group("SnakeBody")
		
		var segment_grid_pos = snake_head.previous_positions[i + 1]
		segment.global_position = grid.grid_to_world(segment_grid_pos)
		
		if i + 2 < snake_head.previous_positions.size():
			var next_segment_pos = snake_head.previous_positions[i + 2]
			var initial_dir = Vector2(segment_grid_pos - next_segment_pos)
			segment.rotation_degrees = _dir_to_degrees(initial_dir)
		else:
			var prev_segment_pos = snake_head.previous_positions[i]
			var initial_dir = Vector2(segment_grid_pos - prev_segment_pos)
			segment.rotation_degrees = _dir_to_degrees(initial_dir)
		
		get_parent().add_child(segment)
		snake_segments.append(segment)

	# Remember the starting body size so the score's length term only
	# counts growth from here on.
	_initial_segment_count = snake_segments.size()

	rebuild_board_state()
	_update_visual_state(false)

func _snap_entities_to_grid() -> void:
	if is_instance_valid(snake_head):
		snake_head.global_position = grid.grid_to_world(grid.world_to_grid(snake_head.global_position))

	if is_instance_valid(player):
		player.global_position = grid.grid_to_world(grid.world_to_grid(player.global_position))
		player.half_size = player.tile_size * 0.5
		player_cell = grid.world_to_grid(player.global_position)

	for seg in get_tree().get_nodes_in_group("SnakeBody"):
		if is_instance_valid(seg):
			seg.global_position = grid.grid_to_world(grid.world_to_grid(seg.global_position))

	for f in get_tree().get_nodes_in_group("Food"):
		if is_instance_valid(f):
			f.global_position = grid.grid_to_world(grid.world_to_grid(f.global_position))

	for pu in get_tree().get_nodes_in_group("PowerUp"):
		if is_instance_valid(pu):
			pu.global_position = grid.grid_to_world(grid.world_to_grid(pu.global_position))

	rebuild_board_state()

func _spawn_food_deferred() -> void:
	if is_instance_valid(food_spawner):
		food_spawner.spawn_food()

func _delayed_alignment() -> void:
	# Small delay to ensure any spawn animations/tweens finish, then re-snap
	await get_tree().create_timer(0.05).timeout
	_snap_entities_to_grid()

func rebuild_board_state() -> void:
	if not grid: return
	grid.initialize_board()

	if is_instance_valid(player):
		# dont derive visual position, trust the state
		# player_cell = grid.world_to_grid(player.global_position)
		grid.set_cell(player_cell, 1)

	for cell in snake_head.previous_positions:
		grid.set_cell(cell, 2)

	food_cell = Vector2i(-1, -1)
	for f in get_tree().get_nodes_in_group("Food"):
		if is_instance_valid(f):
			food_cell = grid.world_to_grid(f.global_position)
			grid.set_cell(food_cell, 3)

	powerup_cell = Vector2i(-1, -1)
	for pu in get_tree().get_nodes_in_group("PowerUp"):
		if is_instance_valid(pu):
			powerup_cell = grid.world_to_grid(pu.global_position)
			grid.set_cell(powerup_cell, 4)

func _on_food_eaten(food_node: Node) -> void:
	var food_pos: Vector2 = Vector2.ZERO
	if food_node is Node2D:
		food_pos = food_node.global_position
	_play_eat_effect(food_pos)
	_spawn_float_text(food_pos, "+%d" % food_thrown_multiplier)
	food_node.queue_free()
	# Streak: quick successive bites pitch the eat sound up; resets after
	# a few seconds without food.
	if game_time - _last_eat_time <= 4.0:
		_eat_streak = mini(_eat_streak + 1, 8)
	else:
		_eat_streak = 0
	_last_eat_time = game_time
	AudioManager.play(AudioManager.SFX.FOOD_EATEN, 0.0, 1.0 + _eat_streak * 0.08)
	# Tiny screen shake so every bite lands with a bit of weight.
	_shake_amount = maxf(_shake_amount, 2.0)
	# Each food thrown to the snake counts toward the score and grows its length.
	food_thrown += 1
	grow_pending += 1
	# Case B — a second (or later) eat while the tail is already frozen: the
	# tail isn't moving, so stack a new hidden segment at the frozen tail cell
	# immediately, in this same frame. (Case A — first eat of a fresh sequence
	# — waits for the tail to land and spawns in _on_turn_animation_finished.)
	if not _hidden_growth_queue.is_empty():
		_hidden_growth_queue.append(
			_spawn_hidden_growth_segment(snake_head.previous_positions.back()))
	food_cell = Vector2i(-1, -1)
	food_spawner.spawn_food()
	score = _compute_score()
	emit_signal("score_updated", score)

func _on_powerup_eaten_by_snake(powerup_node: Node) -> void:
	# When the SNAKE swallows the powerup there is no shrink: the powerup
	# simply teleports to another free cell. Only the PLAYER collecting it
	# triggers the halving logic in _on_powerup_collected().
	# Snake + powerup: reuse the food sound (no VFX).
	AudioManager.play(AudioManager.SFX.FOOD_EATEN)
	if powerup_node is Node2D and is_instance_valid(powerup_spawner):
		powerup_spawner.relocate_powerup(powerup_node)

func _on_powerup_collected(powerup_node: Node) -> void:
	if not is_instance_valid(powerup_node):
		return

	var pickup_pos := Vector2.ZERO
	if powerup_node is Node2D:
		pickup_pos = powerup_node.global_position

	_play_pickup_effect(pickup_pos)

	# Remove the powerup immediately from the logical game state.
	powerup_cell = Vector2i(-1, -1)

	# Tell the spawner that the powerup has been consumed.
	if is_instance_valid(powerup_spawner):
		powerup_spawner.consume_powerup()

	# Remove the actual node.
	powerup_node.queue_free()

	AudioManager.play(AudioManager.SFX.POWERUP)

	var target_size:int = max(1, int(snake_segments.size() / 2.0))

	if _move_active:
		_pending_shrink_target = target_size
	else:
		_apply_shrink(target_size)

	# Do NOT spawn another powerup here.
	# Let the normal turn-completion logic handle spawning.

func has_pending_shrink() -> bool:
	return _pending_shrink_target > 0

func _apply_shrink(target_size: int) -> void:
	var size_before := snake_segments.size()
	while snake_segments.size() > target_size:
		var segment = snake_segments.pop_back()
		if is_instance_valid(segment):
			segment.queue_free()
	while snake_head.previous_positions.size() > snake_segments.size() + 1:
		snake_head.previous_positions.pop_back()
	if snake_segments.size() < size_before:
		_cleanup_orphaned_corners()
	for seg in _hidden_growth_queue:
		if is_instance_valid(seg):
			seg.queue_free()
	_hidden_growth_queue.clear()
	rebuild_board_state()
	_update_visual_state(false)

func _cleanup_orphaned_corners() -> void:
	# Called after the snake shrinks: hides and frees corner pieces on
	# cells the shrunken snake no longer occupies, and drops pending tail
	# corner refs (they belong to the removed tail region — their normal
	# move-based cleanup would never fire for those cells again).
	if not is_instance_valid(snake_head):
		return

	# Pending tail corners were scheduled at the old tail's current and
	# destination cells — both are inside the removed tail region once the
	# snake has been trimmed.
	for pending_corner in [_pending_tail_corner, _pending_overtail_corner]:
		if is_instance_valid(pending_corner):
			pending_corner.visible = false
			_pending_corner_cleanup.append(pending_corner)
	_pending_tail_corner = null
	_pending_overtail_corner = null

	# Remaining dict corners on cells the snake no longer covers.
	var occupied := {}
	for pos in snake_head.previous_positions:
		occupied[pos] = true
	for cell_pos in corner_pieces.keys():
		if occupied.has(cell_pos):
			continue
		var corner = corner_pieces[cell_pos]
		if is_instance_valid(corner):
			corner.visible = false
			_pending_corner_cleanup.append(corner)
		corner_pieces.erase(cell_pos)
	# A trim can leave the new tail sitting on what used to be a mid-body
	# turn cell. A tail never has an "outgoing" direction, so any corner
	# still registered there is now stale — strip it the same way
	# _schedule_tail_corner_cleanup does for a normal tail advance.
	if not snake_head.previous_positions.is_empty():
		var new_tail = snake_head.previous_positions.back()
		if corner_pieces.has(new_tail):
			var corner = corner_pieces[new_tail]
			if is_instance_valid(corner):
				corner.visible = false
				_pending_corner_cleanup.append(corner)
			corner_pieces.erase(new_tail)

func _on_snake_trapped() -> void:
	print("Snake is trapped! Player wins!")
	_update_visual_state(false)
	is_game_over = true
	if is_instance_valid(snake_head):
		snake_head.set_process(false)
	if is_instance_valid(player):
		player.disable_input()
	# Victory celebration: gold burst on the trapped head, banner, fanfare.
	if is_instance_valid(snake_head):
		_play_pickup_effect(snake_head.global_position)
	_spawn_hud_label("YOU SURVIVED!", Color(1.0, 0.85, 0.3), 1.2, 48)
	_flash_vignette(Color(1.0, 0.85, 0.3), 0.35, 0.8)
	AudioManager.play(AudioManager.SFX.POWERUP)
	await get_tree().create_timer(1.6).timeout
	if not is_inside_tree():
		return
	AudioManager.stop_music(0.3)
	# Same wipe + save + scene-change flow as the death ending.
	if bite_wipe_scene:
		var bite_instance = bite_wipe_scene.instantiate()
		bite_instance.name = "BiteWipe"
		get_tree().get_root().add_child(bite_instance)
		bite_instance_ref = bite_instance
		var bite_anim_player := bite_instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if bite_anim_player:
			bite_anim_player.play("bite")
			await bite_anim_player.animation_finished
	if not is_inside_tree():
		return
	_on_game_over()

func _add_new_segment() -> void:
	var segment = snake_segment.instantiate()
	segment.add_to_group("SnakeBody")

	var positions = snake_head.previous_positions
	var my_pos = positions.back()
	segment.global_position = grid.grid_to_world(my_pos)

	if positions.size() > 1:
		var pos_in_front = positions[-2]
		var initial_dir = Vector2(pos_in_front - my_pos)
		segment.rotation_degrees = _dir_to_degrees(initial_dir)

	get_parent().add_child(segment)
	snake_segments.append(segment)

# Spawns a hidden growth segment at `cell` (z_index = -1, so it sits under
# the real tail while sharing its cell). Sets the initial rotation from the
# neighbor-direction formula (cell → the body segment in front of it) so the
# sprite is correctly oriented the instant it's promoted, even if the visual
# pass and promotion ever land in a different order. The node is a static
# decoration — it never animates on its own.
func _spawn_hidden_growth_segment(cell: Vector2i) -> Node2D:
	var seg = snake_segment.instantiate()
	seg.add_to_group("SnakeBody")
	seg.global_position = grid.grid_to_world(cell)
	seg.z_index = -1
	# Defensive rotation: direction from this cell toward the body segment
	# immediately in front of it (positions[tail_index] → positions[tail_index-1]).
	var positions = snake_head.previous_positions
	var idx = positions.find(cell)
	if idx > 0:
		var dir = Vector2(positions[idx - 1] - positions[idx]).normalized()
		seg.rotation_degrees = _dir_to_degrees(dir)
	get_parent().add_child(seg)
	return seg

# Returns the index of `cell` in the snake's body (previous_positions[1..]),
# or -1 if the cell is not part of the body. Index 0 is the head, so a body
# cell always has index >= 1.
func _find_body_index(cell: Vector2i) -> int:
	var positions = snake_head.previous_positions
	for i in range(1, positions.size()):
		if positions[i] == cell:
			return i
	return -1

# Cuts the snake's body from `bite_idx` (an index into previous_positions,
# which already has the new head at index 0) to the tail. Every segment from
# the contact point onward is removed, freeing up those cells. The head and
# the body cells before the contact point remain.
func _cut_body_from(bite_idx: int) -> void:
	var positions = snake_head.previous_positions
	if bite_idx <= 0 or bite_idx >= positions.size():
		return
	
	for seg in _hidden_growth_queue:
		if is_instance_valid(seg):
			seg.queue_free()

	_hidden_growth_queue.clear()

	# snake_segments[i] sits at previous_positions[i + 1]. The contact cell is
	# at previous_positions[bite_idx], which maps to segment bite_idx - 1, so
	# remove every segment from bite_idx - 1 to the end.
	while snake_segments.size() >= bite_idx:
		var seg = snake_segments.pop_back()
		if is_instance_valid(seg):
			seg.queue_free()

	# Remove the positions from the contact point to the tail.
	while positions.size() > bite_idx:
		positions.pop_back()

	# Corners on the removed tail region are now orphaned — clean them up.
	_cleanup_orphaned_corners()
	# NOTE: Do NOT call _update_visual_state here. The segments are still at
	# their old positions from the previous move; updating rotations now would
	# show them snapped to new orientations while stationary. The visual state
	# is updated at the end of the move interpolation in
	# _on_turn_animation_finished, when segments have actually reached their
	# new positions.

func _on_snake_moved(destination: Vector2i, move_duration: float) -> void:
	is_animating = true
	var next_head_cell = destination
	var destination_world = grid.grid_to_world(next_head_cell)
	var did_grow_this_turn := false

	if next_head_cell == food_cell:
		for food in get_tree().get_nodes_in_group("Food"):
			if is_instance_valid(food) and grid.world_to_grid(food.global_position) == next_head_cell:
				_on_food_eaten(food)
				break

	if next_head_cell == powerup_cell:
		for pu in get_tree().get_nodes_in_group("PowerUp"):
			if is_instance_valid(pu) and grid.world_to_grid(pu.global_position) == next_head_cell:
				_on_powerup_eaten_by_snake(pu)
				break

	var head_cell = grid.world_to_grid(snake_head.global_position)
	var move_diff = next_head_cell - head_cell
	if abs(move_diff.x) + abs(move_diff.y) != 1:
		is_animating = false
		return

	# Self-bite: if the head moved into its own body, cut every segment from
	# the contact point to the tail. This is how the snake escapes being
	# trapped — it eats its own tail region to free up space.
	_did_bite_this_turn = false
	var bite_idx := _find_body_index(next_head_cell)
	if bite_idx > 0:
		_cut_body_from(bite_idx)
		_did_bite_this_turn = true
		# Powerup VFX + SFX on self-bite so the cut feels impactful.
		_play_pickup_effect(grid.grid_to_world(next_head_cell))
		AudioManager.play(AudioManager.SFX.POWERUP)

	rebuild_board_state()

	var positions = snake_head.previous_positions
	if positions.size() >= 3:
		var head_pos = positions[0]
		var neck_pos = positions[1]
		var third_pos = positions[2]
		
		var dir_out = Vector2(head_pos - neck_pos)
		var dir_in = Vector2(neck_pos - third_pos)
		
		if not dir_in.is_equal_approx(dir_out) and not corner_pieces.has(neck_pos):
			var corner = corner_piece.instantiate()
			corner.global_position = grid.grid_to_world(neck_pos)
			get_parent().add_child(corner)
			corner_pieces[neck_pos] = corner
			
			var rotation = 0.0
			if (dir_in == Vector2.UP and dir_out == Vector2.RIGHT) or (dir_in == Vector2.LEFT and dir_out == Vector2.DOWN):
				rotation = 90.0
			elif (dir_in == Vector2.DOWN and dir_out == Vector2.RIGHT) or (dir_in == Vector2.LEFT and dir_out == Vector2.UP):
				rotation = 0.0
			elif (dir_in == Vector2.DOWN and dir_out == Vector2.LEFT) or (dir_in == Vector2.RIGHT and dir_out == Vector2.UP):
				rotation = -90.0
			elif (dir_in == Vector2.UP and dir_out == Vector2.LEFT) or (dir_in == Vector2.RIGHT and dir_out == Vector2.DOWN):
				rotation = 180.0
			
			corner.rotation_degrees = rotation

	# Staggered 2-frame growth animation.
	# 1D trace (snake going left→right, length 3, food at index 3):
	#   Before: 111x00  (positions=[H,B1,B2], segments=[seg0,seg1])
	#   Frame A: 011100  (normal move: head eats, tail pops B2→B1)
	#           hidden_seg spawned at B1 (z_index=-1, under real tail)
	#   Frame B: 011110  (head advances, tail STAYS at B1)
	#           hidden_seg promoted to snake_segments → becomes new tail
	#   Frame C: 001111  (normal movement resumes at new length 4)
	# Drain the queue one reveal per frame (FIFO: front-first). A segment
	# appended this frame during the eat check is never the one popped this
	# frame, because the append only happens when the queue was non-empty
	# before the addition. Tail stays frozen while the queue has entries.
	if not _hidden_growth_queue.is_empty():
		var seg = _hidden_growth_queue.pop_front()
		seg.z_index = 0
		snake_segments.append(seg)
		grow_pending -= 1
		did_grow_this_turn = true
		# The promoted segment is now the tail. Immediately hide the previous
		# tail's OverSprite (it is now a body segment) and show this one, so
		# the overlap stays frozen with the tail during this frame's
		# interpolation instead of following the advancing body. Without this,
		# the old tail's OverSprite stays visible from the previous frame and
		# rides along as that segment moves forward into the body.
		if snake_segments.size() >= 2:
			_hide_tail_over(snake_segments[snake_segments.size() - 2])
		var tail_dir := Vector2.ZERO
		if positions.size() >= 2:
			tail_dir = Vector2(positions[positions.size() - 2] - positions.back()).normalized()
		_show_tail_over(seg, tail_dir)

	_update_head_visual_pre_move(move_diff)

	if not did_grow_this_turn:
		_schedule_tail_corner_cleanup()

	if next_head_cell == player_cell:
		_death_move_did_grow = did_grow_this_turn
		_on_game_over_imminent(next_head_cell)
		return

	# Set up frame-based interpolation instead of a tween.
	_move_duration = move_duration
	_move_did_grow = did_grow_this_turn
	_move_from.clear()
	_move_to.clear()
	_move_from.append(snake_head.global_position)
	_move_to.append(destination_world)
	for i in range(snake_segments.size()):
		if i + 1 < positions.size():
			_move_from.append(snake_segments[i].global_position)
			_move_to.append(grid.grid_to_world(positions[i + 1]))
	_move_progress = 0.0
	_move_active = true

func _apply_move_positions(progress: float) -> void:
	if not is_instance_valid(snake_head):
		return
	if _move_from.is_empty() or _move_to.is_empty():
		return
	snake_head.global_position = _move_from[0].lerp(_move_to[0], progress)
	for i in range(snake_segments.size()):
		if i + 1 < _move_from.size():
			snake_segments[i].global_position = _move_from[i + 1].lerp(_move_to[i + 1], progress)

func _apply_lunge_positions(progress: float) -> void:
	if not is_instance_valid(snake_head):
		return
	if _lunge_from.is_empty() or _lunge_to.is_empty():
		return
	snake_head.global_position = _lunge_from[0].lerp(_lunge_to[0], progress)
	for i in range(snake_segments.size()):
		if i + 1 < _lunge_from.size():
			snake_segments[i].global_position = _lunge_from[i + 1].lerp(_lunge_to[i + 1], progress)

func _on_turn_animation_finished(did_grow: bool) -> void:
	# On a self-bite the tail region was already removed by the cut, so the
	# normal tail-pop must be skipped.
	var was_bite := _did_bite_this_turn
	if not did_grow and not was_bite:
		snake_head.previous_positions.pop_back()
	_did_bite_this_turn = false

	# Apply a powerup shrink that was delayed because the snake was
	# still mid-lerp when the player collected the powerup.
	if _pending_shrink_target > 0:
		var target: int = _pending_shrink_target
		_pending_shrink_target = -1
		_apply_shrink(target)

	rebuild_board_state()

	# Case A — first eat of a fresh sequence (queue empty): after a normal
	# move the tail has landed, so spawn one hidden segment at the tail's
	# landing cell and push it.
	if not did_grow and not was_bite and grow_pending > 0 \
			and _hidden_growth_queue.is_empty():
		_hidden_growth_queue.append(
			_spawn_hidden_growth_segment(snake_head.previous_positions.back()))

	# IMPORTANT:
	# The shrink is now applied BEFORE this check, so the powerup spawner
	# sees the snake's actual new length.
	if not is_game_over and is_instance_valid(powerup_spawner):
		powerup_spawner.spawn_powerup_if_ready()

	if not _player_move_lethal and _player_overlaps_snake_grid():
		_on_game_over_imminent()

func _schedule_tail_corner_cleanup() -> void:
	if not is_instance_valid(snake_head) or snake_head.previous_positions.is_empty():
		return

	var positions = snake_head.previous_positions

	# Undertail corner: old basis — tail's current cell.
	var undertail_pos = positions.back()
	if corner_pieces.has(undertail_pos):
		_pending_tail_corner = corner_pieces[undertail_pos]
		corner_pieces.erase(undertail_pos)

	# Overtail corner: new basis — tail's destination cell.
	var dest_idx = snake_segments.size()
	if dest_idx < positions.size():
		var overtail_pos = positions[dest_idx]
		if corner_pieces.has(overtail_pos):
			_pending_overtail_corner = corner_pieces[overtail_pos]
			corner_pieces.erase(overtail_pos)

func _hide_pending_tail_corner() -> void:
	if is_instance_valid(_pending_tail_corner):
		_pending_tail_corner.visible = false
		_pending_corner_cleanup.append(_pending_tail_corner)
	_pending_tail_corner = null

func _hide_pending_overtail_corner() -> void:
	if is_instance_valid(_pending_overtail_corner):
		_pending_overtail_corner.visible = false
		_pending_corner_cleanup.append(_pending_overtail_corner)
	_pending_overtail_corner = null

func _update_head_visual_pre_move(move_diff: Vector2i) -> void:
	if not is_instance_valid(snake_head):
		return

	var head_sprite = snake_head.get_node_or_null("AnimatedSprite2D")
	if head_sprite:
		head_sprite.play("head")

	var head_dir = Vector2(move_diff).normalized()
	snake_head.rotation_degrees = _dir_to_degrees(head_dir)
	_show_head_over()

func _player_overlaps_snake_grid() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(snake_head):
		return false

	if snake_head.previous_positions.is_empty():
		return false
	return snake_head.previous_positions[0] == player_cell

func request_player_move_to(target_cell: Vector2i) -> bool:
	if is_game_over:
		return false
	
	var diff = target_cell - player_cell
	if diff == Vector2i.ZERO:
		return false
	
	var step = Vector2i(clamp(diff.x, -1, 1), 0) if abs(diff.x) >= abs(diff.y) else Vector2i(0, clamp(diff.y, -1, 1))
	var next_cell = player_cell + step

	if not grid.is_cell_inside(next_cell):
		return false

	var cell_value = grid.get_cell(next_cell)
	if _player_move_lethal:
		# A lethal move (into the snake body) is in flight; block any
		# further chained moves until it lands and game over starts.
		return false
	if cell_value == 2:
		# Snake body is unpassable by the player — block the move. The player
		# can only be caught when the snake HEAD moves onto the player's cell,
		# not by walking into the body.
		return false

	if cell_value == 3:
		for food in get_tree().get_nodes_in_group("Food"):
			if is_instance_valid(food) and grid.world_to_grid(food.global_position) == next_cell:
				_on_food_eaten(food)
				break

	if cell_value == 4:
		for pu in get_tree().get_nodes_in_group("PowerUp"):
			if is_instance_valid(pu) and grid.world_to_grid(pu.global_position) == next_cell:
				_on_powerup_collected(pu)
				break

	grid.set_cell(player_cell, 0)
	player_cell = next_cell
	grid.set_cell(player_cell, 1)
	if is_instance_valid(player):
		player.current_cell = player_cell
		animate_player_to(next_cell, player.move_delay)
	return true

# A* pathfinding for the player across the grid. Snake body cells (value 2)
# are treated as unpassable obstacles; empty cells, food (3) and powerups (4)
# are all walkable. Movement is 4-directional with a Manhattan heuristic.
# Returns the waypoint list from `start` to `goal` EXCLUDING the start cell
# (so path[0] is the next step to request), or an empty array when no route
# exists — e.g. the goal is covered by the snake or walled off by it. Callers
# should fall back to their own greedy stepping when the path is empty.
func find_player_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not grid.is_cell_inside(start) or not grid.is_cell_inside(goal):
		return result
	if start == goal:
		return result

	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, grid.columns, grid.rows)
	astar.cell_size = Vector2(grid.tile_size, grid.tile_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()

	# Mark the snake body as solid. The board is tiny (~23x17), so rebuilding
	# the solid map per call is negligible and guarantees the path always
	# reflects the snake's latest position.
	for y in range(grid.rows):
		for x in range(grid.columns):
			if grid.get_cell(Vector2i(x, y)) == 2:
				astar.set_point_solid(Vector2i(x, y), true)

	# A goal sitting on the snake is unreachable — report no path rather
	# than crashing A* with a solid endpoint.
	if astar.is_point_solid(goal) or astar.is_point_solid(start):
		return result

	var id_path := astar.get_id_path(start, goal)
	# get_id_path includes the start cell; skip it so the first returned
	# waypoint is the immediate next step.
	for i in range(1, id_path.size()):
		result.append(id_path[i])
	return result

func animate_player_to(cell: Vector2i, move_duration: float) -> void:
	if not is_instance_valid(player):
		return

	# Frame-based: _process owns the interpolation, same as the snake. Each
	# requested step APPENDS a waypoint to the glide queue, so chained steps
	# (from the A* follow loop) form a polyline the sprite runs through at
	# constant speed instead of a single straight-line jump to the last cell.
	var target_pos := grid.grid_to_world(cell)
	_player_move_duration = move_duration
	if _player_move_active:
		_player_move_waypoints.append(target_pos)
	else:
		_player_move_waypoints = [player.global_position, target_pos]
		_player_move_seg_progress = 0.0
		_player_move_active = true
		is_player_animating = true

	# Tiny squash per step gives the hop a bit of weight (skipped on the
	# lethal landing so death stays rigid). Fired only when a fresh glide
	# starts, so queued steps don't stack squashes every frame.
	if is_instance_valid(player) and not _player_move_lethal \
			and _player_move_waypoints.size() == 2:
		if is_instance_valid(_player_squash_tween):
			_player_squash_tween.kill()
		player.scale = Vector2(1.1, 0.88)
		_player_squash_tween = create_tween()
		_player_squash_tween.tween_property(player, "scale", Vector2.ONE, maxf(move_duration, 0.08)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# How many cell steps are queued for the player's visual glide but not yet
# reached by the sprite (the first entry of the waypoint list is the segment
# the sprite is currently traversing). player.gd uses this to keep the logic
# position only a couple of cells ahead of the sprite.
func player_move_queue_count() -> int:
	return maxi(_player_move_waypoints.size() - 1, 0)

# Snaps the player's sprite to a specific cell and stops all player movement
# frames. Used at the instant the snake head catches the player so the sprite
# is pinned exactly where the snake lunges, even if the player was mid-move.
# If `cell` is invalid (-1), falls back to the last queued glide destination.
func _snap_player_to_cell(cell: Vector2i) -> void:
	if not is_instance_valid(player):
		return
	if cell != Vector2i(-1, -1):
		player.global_position = grid.grid_to_world(cell)
	elif _player_move_active and not _player_move_waypoints.is_empty():
		player.global_position = _player_move_waypoints.back()
	_player_move_waypoints.clear()
	_player_move_active = false
	is_player_animating = false
	_player_move_lethal = false

func _update_visual_state(_is_pre_move: bool) -> void:
	var positions = snake_head.previous_positions
	if positions.size() < 2: return

	var head_sprite = snake_head.get_node_or_null("AnimatedSprite2D")
	if head_sprite:
		head_sprite.play("head")
		var head_dir = Vector2(positions[0] - positions[1]).normalized()
		snake_head.rotation_degrees = _dir_to_degrees(head_dir)
	_show_head_over()

	# Map each segment to its cell by anchoring the LAST segment to the real
	# tail cell (positions.back()) and walking backwards. This is correct in
	# every state: normal (positions = segments + 1), pre-move death lunge
	# (positions = segments + 2), and while the tail is frozen during
	# staggered growth (positions grows faster than segments). The old
	# `i + 1` offset assumed positions and segments always differ by exactly
	# one, which broke tail rotation on frozen frames.
	var seg_count: int = snake_segments.size()
	var tail_idx: int = positions.size() - 1
	for i in range(seg_count):
		var segment = snake_segments[i]
		if not is_instance_valid(segment): continue
		
		var anim_sprite = segment.get_node("AnimatedSprite2D") as AnimatedSprite2D
		var current_idx = clamp(tail_idx - (seg_count - 1 - i), 0, positions.size() - 1)
		var head_neighbor_idx = max(current_idx - 1, 0)
		# Tail/body rotation source of truth: direction from this cell toward
		# the body segment immediately in front of it. Always well-defined and
		# non-zero, since the neighbor keeps advancing even while the tail
		# itself sits still. Recomputed unconditionally every frame.
		var direction = Vector2(positions[head_neighbor_idx] - positions[current_idx]).normalized()

		if direction == Vector2.ZERO and current_idx + 1 < positions.size():
			direction = Vector2(positions[current_idx] - positions[current_idx + 1]).normalized()
		if direction == Vector2.ZERO and is_instance_valid(snake_head):
			direction = snake_head.last_dir

		segment.rotation_degrees = _dir_to_degrees(direction)
		segment.visible = true

		if i == seg_count - 1:
			anim_sprite.play("tail")
			_show_tail_over(segment, direction)
		else:
			anim_sprite.play("body_straight")
			_hide_tail_over(segment)

# Shows the tail's OverSprite (the visual patch that completes the tail
# sprite) directly on top of the tail segment itself, and makes it visible.
# It is anchored to the tail's own position (not offset behind it) so it
# stays frozen with the tail during staggered growth, instead of following
# the body segment that happens to occupy the cell behind (which would make
# the body read as the tail).
func _show_tail_over(segment: Node2D, direction: Vector2) -> void:
	var over = segment.get_node_or_null("OverSprite") as AnimatedSprite2D
	if not over:
		return
	over.visible = true
	over.position = Vector2.ZERO
	over.rotation = 0.0
	over.play("tail_over")

func _hide_tail_over(segment: Node2D) -> void:
	var over = segment.get_node_or_null("OverSprite") as AnimatedSprite2D
	if over:
		over.visible = false

# Shows the head's OverSprite (the visual patch that completes the head
# sprite) overlapping the head's own cell — same anchoring as the tail's
# OverSprite, but without the freeze handling: the head never stalls, so
# the patch simply rides along with the head node as it moves and rotates.
func _show_head_over() -> void:
	var over = snake_head.get_node_or_null("OverSprite") as AnimatedSprite2D
	if not over:
		return
	over.visible = true
	over.position = Vector2.ZERO
	over.rotation = 0.0
	over.play("head_over")

func _play_pickup_effect(pickup_pos: Vector2) -> void:
	var effect := PICKUP_EFFECT_SCENE.instantiate() as Node2D
	effect.global_position = pickup_pos
	get_tree().get_root().add_child(effect)
	_shake_amount = maxf(_shake_amount, 4.5)

func _play_eat_effect(eat_pos: Vector2) -> void:
	var effect := EAT_EFFECT_SCENE.instantiate() as Node2D
	effect.global_position = eat_pos
	get_tree().get_root().add_child(effect)

func _spawn_float_text(pos: Vector2, text: String) -> void:
	# Small "+N" that rises and fades at the eaten food's position. The
	# gameplay camera is unzoomed, so world space works as screen space.
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FLOAT_FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.15, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 50
	get_tree().get_root().add_child(label)
	label.position = pos + Vector2(-14.0, -34.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 26.0, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(label.queue_free)

func _make_vignette(color: Color) -> TextureRect:
	# Full-screen radial gradient: transparent center, colored edges.
	var rect := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.0))
	grad.set_color(1, Color(color.r, color.g, color.b, 1.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	rect.texture = tex
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	return rect

func _flash_vignette(color: Color, strength: float, duration: float = 0.6) -> void:
	if not is_instance_valid(_hud):
		return
	var rect := _make_vignette(color)
	_hud.add_child(rect)
	rect.modulate.a = strength
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(rect.queue_free)

func _spawn_hud_label(text: String, color: Color, duration: float = 0.9, font_size: int = 40) -> void:
	if not is_instance_valid(_hud):
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FLOAT_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.1, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud.add_child(label)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.pivot_offset = Vector2(400, 320)
	label.scale = Vector2(0.3, 0.3)
	label.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 1.0, 0.15)
	tw.chain().tween_interval(duration)
	tw.chain().tween_property(label, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(label.queue_free)

func _play_hit_effect(killer_cell: Vector2i) -> void:
	# Impact at the cell the snake lunged into (the player's cell).
	var hit_pos := Vector2.ZERO
	if killer_cell != Vector2i(-1, -1):
		hit_pos = grid.grid_to_world(killer_cell)
	elif is_instance_valid(player):
		hit_pos = player.global_position
	elif is_instance_valid(snake_head):
		hit_pos = snake_head.global_position

	var effect := HIT_EFFECT_SCENE.instantiate() as Node2D
	effect.global_position = hit_pos
	get_tree().get_root().add_child(effect)

	_shake_amount = maxf(_shake_amount, 9.0)
	_flash_player_sprite()
	# Cut the gameplay music on impact; it stays silent until the next
	# scene (Profile_Screen) starts its own menu music.
	AudioManager.stop_music(0.15)
	AudioManager.play(AudioManager.SFX.HIT)

func _flash_player_sprite() -> void:
	if not is_instance_valid(player):
		return
	var sprite = player.get_node_or_null("AnimatedSprite2D")
	if not (sprite is CanvasItem):
		return
	sprite.modulate = Color(1.0, 0.25, 0.25)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.45)

func _on_game_over_imminent(killer_cell: Vector2i = Vector2i(-1, -1)) -> void:
	if is_game_over:
		return
	is_game_over = true
	# Discard any pending growth animation.
	for seg in _hidden_growth_queue:
		if is_instance_valid(seg):
			seg.queue_free()
	_hidden_growth_queue.clear()

	# Freeze the player IMMEDIATELY at the collision instant, before any
	# slow-mo or await. The player's sprite is pinned to the killer cell
	# (where the snake head is), so it can't keep drifting during the
	# hit-stop and end up looking far from the snake when the lunge plays.
	if is_instance_valid(snake_head):
		snake_head.set_process(false)
	if is_instance_valid(player):
		player.disable_input()
		player.set_process(false)
		_snap_player_to_cell(killer_cell)

	# Hit-stop: freeze the whole world at the collision instant. The timer
	# runs on real time (ignore_time_scale) so the pause itself is not
	# stretched by its own slow-mo.
	Engine.time_scale = 0.1
	await get_tree().create_timer(0.13, true, false, true).timeout
	Engine.time_scale = 1.0
	
	if is_instance_valid(player):
		player.play_surprise_animation()
	
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree():
		return
	
	if killer_cell != Vector2i(-1, -1) and is_instance_valid(snake_head):
		_update_visual_state(true)

		var lunge_speed = snake_head.speed
		var target_world = grid.grid_to_world(killer_cell)
		_lunge_duration = lunge_speed
		_lunge_from.clear()
		_lunge_to.clear()
		_lunge_from.append(snake_head.global_position)
		_lunge_to.append(target_world)
		var positions = snake_head.previous_positions
		for i in range(snake_segments.size()):
			if i + 1 < positions.size():
				_lunge_from.append(snake_segments[i].global_position)
				_lunge_to.append(grid.grid_to_world(positions[i + 1]))
		_lunge_progress = 0.0
		_lunge_active = true
		await lunge_finished
		# The lunge shifts the whole snake forward one cell just like a
		# completed move. Sync previous_positions the same way
		# _on_turn_animation_finished does, otherwise the stale vacated tail
		# entry makes _update_visual_state() place the tail-over sprite in the
		# old tail cell, leaving a leftover tail-over behind the snake.
		if not _death_move_did_grow and not snake_head.previous_positions.is_empty():
			snake_head.previous_positions.pop_back()
		_update_visual_state(false)
		_play_hit_effect(killer_cell)
	else:
		# Player walked into the snake: there is no lunge cell, but the
		# impact feedback (effect, shake, flash, music cut, hit SFX) must
		# still fire. Falls back to the player's position.
		_play_hit_effect(Vector2i(-1, -1))
	await get_tree().create_timer(0.1).timeout

	# Game-over sting plays here, before the wipe, so it isn't buried under
	# the next scene's menu music. (Was previously in _on_game_over(), which
	# is reached only after the scene change.)
	AudioManager.play(AudioManager.SFX.GAME_OVER)

	if bite_wipe_scene:
		var bite_instance = bite_wipe_scene.instantiate()
		bite_instance.name = "BiteWipe"
		get_tree().get_root().add_child(bite_instance)
		bite_instance_ref = bite_instance
		var bite_anim_player := bite_instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if bite_anim_player:
			bite_anim_player.play("bite")
			await bite_anim_player.animation_finished

	if not is_inside_tree():
		return

	_on_game_over()

func _exit_tree() -> void:
	# Always restore normal time and the cursor when leaving the game scene.
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_game_over() -> void:
	# is_game_over is already true when we get here (set in
	# _on_game_over_imminent), so the sting is played earlier — see
	# _on_game_over_imminent — where it isn't drowned by the next scene.
	if not is_game_over:
		is_game_over = true

	# Restore the cursor so the player can interact with the leaderboard.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var gs = get_node_or_null("/root/GlobalState")
	var profile_name = gs.current_profile_name if gs else "Guest"
	var final_score = score
	var final_time = game_time

	if gs:
		gs.last_score = final_score
		gs.last_time = final_time
		gs.update_high_score(profile_name, final_score, final_time)
		var high_score_data = gs.get_high_score(profile_name)
		print("High score for %s updated. Score: %d, Time: %.2f" % [profile_name, high_score_data["score"], high_score_data["time"]])
	else:
		print("GlobalState not found, score not saved.")

	if is_inside_tree():
		get_tree().paused = false
		var change_err = get_tree().change_scene_to_file("res://Profile_Screen.tscn")
		if change_err != OK:
			push_error("Failed to change to Profile_Screen.tscn. Error code: %d" % change_err)
		if is_instance_valid(bite_instance_ref):
			var bite_anim_player := bite_instance_ref.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if bite_anim_player:
				if bite_anim_player.has_animation("bite_out"):
					bite_anim_player.play("bite_out")
					await bite_anim_player.animation_finished
			bite_instance_ref.queue_free()
			bite_instance_ref = null

func _dir_to_degrees(dir: Vector2) -> float:
	if dir.is_equal_approx(Vector2.RIGHT): return 0.0
	if dir.is_equal_approx(Vector2.DOWN): return 90.0
	if dir.is_equal_approx(Vector2.LEFT): return 180.0
	if dir.is_equal_approx(Vector2.UP): return -90.0
	return 0.0

func _on_level_up() -> void:
	current_level += 1
	# Pitch rises with each level so every speed-up feels like an escalation.
	AudioManager.play(AudioManager.SFX.LEVEL_UP, 0.0, 1.0 + minf(current_level * 0.06, 0.6))
	emit_signal("level_changed", current_level)
	# Telegraph on the snake itself: the head pulses once.
	if is_instance_valid(snake_head):
		var head_sprite = snake_head.get_node_or_null("AnimatedSprite2D")
		if head_sprite is Node2D:
			var base_scale: Vector2 = head_sprite.scale
			head_sprite.scale = base_scale * 1.25
			var tw := create_tween()
			tw.tween_property(head_sprite, "scale", base_scale, 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spawn_hud_label("SPEED UP!", Color(0.9, 0.15, 0.15), 0.9)
	_flash_vignette(Color(0.8, 0.1, 0.1), 0.4)
	print("Level Up! Reached level ", current_level)
	
	# Cap the snake's top speed so the move duration never gets so small that
	# the frame-based interpolation skips cells (teleporting).
	snake_head.speed = max(MIN_MOVE_DURATION, snappedf(snake_head.speed - difficulty_speedup, 0.01))
