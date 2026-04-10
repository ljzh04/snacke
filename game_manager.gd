class_name GameManager
extends Node

signal score_updated(new_score: int)
signal time_updated(time_string: String) 

# --- Grid Helper ---
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

@export var snake_head: Area2D
@export var snake_segment: PackedScene
@export var corner_piece: PackedScene
@export var food_spawner: Node
@export var initial_snake_length := 3
@export var bite_wipe_scene: PackedScene
@export var player: CharacterBody2D
@export var play_area_rect := Rect2(32, 64, 736, 544)

var grid: Grid
var snake_segments: Array[Node2D] = []
var corner_pieces: Dictionary = {}
var score := 0
var grow_pending := 0
var game_time := 0.0
var current_level := 1
var player_cell: Vector2i = Vector2i.ZERO
var food_cell: Vector2i = Vector2i.ZERO
var is_animating := false
var is_player_animating := false
var is_game_over := false
var current_animation_tween: Tween

# Legacy aliases for compatibility (can be refactored out later)
func world_to_grid(pos: Vector2) -> Vector2i: return grid.world_to_grid(pos)
func grid_to_world(pos: Vector2i) -> Vector2: return grid.grid_to_world(pos)
func is_cell_inside(cell: Vector2i) -> bool: return grid.is_cell_inside(cell)
func board_get(cell: Vector2i) -> int: return grid.get_cell(cell)
func board_set(cell: Vector2i, value: int): grid.set_cell(cell, value)

func _ready() -> void:
	snake_head.moved.connect(_on_snake_moved)
	snake_head.snake_trapped.connect(_on_snake_trapped)
	$LevelUpTimer.timeout.connect(_on_level_up)

	var base_tile := 32
	if is_instance_valid(snake_head):
		base_tile = int(snake_head.tile_size)

	grid = Grid.new(play_area_rect, base_tile)

	if is_instance_valid(player):
		player.tile_size = base_tile
		player.half_size = base_tile * 0.5

	if is_instance_valid(food_spawner):
		food_spawner.tile_size = base_tile

	# Snap entities to grid before creating segments or spawning food.
	call_deferred("_snap_entities_to_grid")
	call_deferred("_spawn_initial_segments")
	# Spawn food after segments are created so occupied-cells are considered.
	call_deferred("_spawn_food_deferred")

	# Also perform a tiny delayed re-snap to guard against animations/tweens
	call_deferred("_delayed_alignment")

func _process(delta: float) -> void:
	game_time += delta
	var minutes = int(game_time / 60)
	var seconds = int(game_time) % 60
	var time_string = "%02d:%02d" % [minutes, seconds]
	emit_signal("time_updated", time_string)

	# Collision check after player has moved in this frame.
	# Check even during animation to catch mid-frame collisions.
	if not is_game_over and is_instance_valid(player):
		if _player_overlaps_snake_grid():
			_on_game_over_imminent()

func _spawn_initial_segments() -> void:
	snake_head.previous_positions.clear()
	var start_cell = world_to_grid(snake_head.global_position)
	for i in range(initial_snake_length):
		snake_head.previous_positions.append(start_cell - Vector2i(i, 0))

	# Create the visual segments based on the data
	for i in range(initial_snake_length - 1):
		_add_new_segment()

	rebuild_board_state()
	# Set the correct visual state (sprites, rotations) at the start of the game.
	_update_visual_state()

func _snap_entities_to_grid() -> void:
	# Snap primary actors (head, player) and any existing bodies/food to the nearest grid cell
	if is_instance_valid(snake_head):
		snake_head.global_position = grid_to_world(world_to_grid(snake_head.global_position))

	if is_instance_valid(player):
		player.global_position = grid_to_world(world_to_grid(player.global_position))
		player.half_size = player.tile_size * 0.5
		player_cell = world_to_grid(player.global_position)

	# Snap any already-instantiated snake body pieces
	for seg in get_tree().get_nodes_in_group("SnakeBody"):
		if is_instance_valid(seg):
			seg.global_position = grid_to_world(world_to_grid(seg.global_position))

	# Snap any existing food nodes
	for f in get_tree().get_nodes_in_group("Food"):
		if is_instance_valid(f):
			f.global_position = grid_to_world(world_to_grid(f.global_position))

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
		player_cell = grid.world_to_grid(player.global_position)
		grid.set_cell(player_cell, 1)

	for cell in snake_head.previous_positions:
		grid.set_cell(cell, 2)

	food_cell = Vector2i(-1, -1)
	for f in get_tree().get_nodes_in_group("Food"):
		if is_instance_valid(f):
			food_cell = grid.world_to_grid(f.global_position)
			grid.set_cell(food_cell, 3)

func _on_food_eaten(food_node: Node) -> void:
	food_node.queue_free()
	score = (5 * current_level - 1)
	grow_pending += 1
	food_cell = Vector2i(-1, -1)
	food_spawner.spawn_food()
	emit_signal("score_updated", score)

func _on_snake_trapped() -> void:
	print("Snake is trapped! Player wins!")
	_update_visual_state()
	# win animation here
	await get_tree().create_timer(0.5).timeout
	get_tree().paused = true

func _add_new_segment() -> void:
	var segment = snake_segment.instantiate()
	segment.add_to_group("SnakeBody")

	var positions = snake_head.previous_positions
	var my_pos = positions.back()
	segment.global_position = grid_to_world(my_pos)

	if positions.size() > 1:
		var pos_in_front = positions[-2]
		var initial_dir = Vector2(pos_in_front - my_pos)
		segment.rotation_degrees = _dir_to_degrees(initial_dir)

	get_parent().add_child(segment)
	snake_segments.append(segment)

func _on_snake_moved(destination: Vector2i, move_duration: float) -> void:
	is_animating = true
	var next_head_cell = destination
	var destination_world = grid_to_world(next_head_cell)
	var did_grow_this_turn := false

	if next_head_cell == food_cell:
		for food in get_tree().get_nodes_in_group("Food"):
			if is_instance_valid(food) and grid.world_to_grid(food.global_position) == next_head_cell:
				_on_food_eaten(food)
				break

	# DIAGONAL MOVEMENT VALIDATION: ensure destination is only 1 cell away (cardinal direction)
	var head_cell = grid.world_to_grid(snake_head.global_position)
	var move_diff = next_head_cell - head_cell
	if abs(move_diff.x) + abs(move_diff.y) != 1:
		# Diagonal or invalid move - reject it silently
		print("REJECTED: Diagonal/invalid move - head_cell: %s, next_cell: %s, diff: %s (manhattan: %d)" % [head_cell, next_head_cell, move_diff, abs(move_diff.x) + abs(move_diff.y)])
		is_animating = false
		return

	rebuild_board_state()

	# --- Corner Piece Logic ---
	var positions = snake_head.previous_positions
	if positions.size() >= 3:
		var head_pos = positions[0]
		var neck_pos = positions[1]
		var third_pos = positions[2]
		
		var dir_out = Vector2(head_pos - neck_pos)
		var dir_in = Vector2(neck_pos - third_pos)
		
		if not dir_in.is_equal_approx(dir_out) and not corner_pieces.has(neck_pos):
			var corner = corner_piece.instantiate()
			corner.global_position = grid_to_world(neck_pos)
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

	if grow_pending > 0:
		grow_pending -= 1
		_add_new_segment()
		did_grow_this_turn = true
	
	# Start normal animation (rotations will be applied AFTER animation completes)
	if next_head_cell == player_cell:
		_on_game_over_imminent(next_head_cell)
		return

	# Start normal animation
	current_animation_tween = create_tween()
	current_animation_tween.set_parallel()
	current_animation_tween.tween_property(snake_head, "global_position", destination_world, move_duration).set_trans(Tween.TRANS_EXPO)

	for i in range(snake_segments.size()):
		if i + 1 < positions.size():
			var segment = snake_segments[i]
			var target_pos = grid_to_world(positions[i+1])
			current_animation_tween.tween_property(segment, "global_position", target_pos, move_duration).set_trans(Tween.TRANS_EXPO)
	
	# We use tween_callback to run this AFTER the tween completes.
	current_animation_tween.tween_callback(
		func():
			_on_turn_animation_finished(did_grow_this_turn)
			_update_visual_state()  # Apply rotations AFTER animation, before next turn can start
			is_animating = false  # Allow next turn to start AFTER visual state is updated
	)

func _on_turn_animation_finished(did_grow: bool) -> void:
	# This function's only job is data cleanup.
	if not did_grow:
		var tail_cleanup_pos = snake_head.previous_positions.pop_back()
		if corner_pieces.has(tail_cleanup_pos):
			var corner_to_remove = corner_pieces[tail_cleanup_pos]
			corner_pieces.erase(tail_cleanup_pos)
			corner_to_remove.queue_free()

	rebuild_board_state()

	# Re-check lethal overlap after turn animation settles to catch turn timing cases.
	if _player_overlaps_snake_grid():
		_on_game_over_imminent()
		return
	# NOTE: is_animating stays true here, set to false AFTER _update_visual_state() in callback

func _player_overlaps_snake_grid() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(snake_head):
		return false

	for snake_pos in snake_head.previous_positions:
		if snake_pos == player_cell:
			return true

	return false

func request_player_move_to(target_cell: Vector2i) -> bool:
	if is_game_over:
		return false
	
	# To support "as fast as mouse can", we allow movement even if already animating,
	# but we only move one step at a time towards the mouse to avoid skipping walls/segments.
	var diff = target_cell - player_cell
	if diff == Vector2i.ZERO:
		return false
	
	# Move 1 step towards target
	var step = Vector2i(clamp(diff.x, -1, 1), 0) if abs(diff.x) >= abs(diff.y) else Vector2i(0, clamp(diff.y, -1, 1))
	var next_cell = player_cell + step

	if not is_cell_inside(next_cell):
		return false

	var cell_value = board_get(next_cell)
	if cell_value == 2:
		_on_game_over_imminent()
		return false

	if cell_value == 3:
		for food in get_tree().get_nodes_in_group("Food"):
			if is_instance_valid(food) and grid.world_to_grid(food.global_position) == next_cell:
				_on_food_eaten(food)
				break

	board_set(player_cell, 0)
	player_cell = next_cell
	board_set(player_cell, 1)
	if is_instance_valid(player):
		player.current_cell = player_cell
		animate_player_to(next_cell, player.move_delay)
	return true

func animate_player_to(cell: Vector2i, move_duration: float) -> void:
	if not is_instance_valid(player):
		return
	
	# Kill existing tween to avoid stacking when moving fast
	if player.has_meta("tween"):
		var old_tween = player.get_meta("tween")
		if is_instance_valid(old_tween):
			old_tween.kill()

	var destination = grid_to_world(cell)
	var player_tween = create_tween()
	player.set_meta("tween", player_tween)
	player_tween.tween_property(player, "global_position", destination, move_duration).set_trans(Tween.TRANS_LINEAR)
	player_tween.tween_callback(func(): is_player_animating = false)

func _update_visual_state(is_pre_move: bool = false) -> void:
	var positions = snake_head.previous_positions
	if positions.size() < 2: return

	# --- Head Visuals ---
	var head_sprite = snake_head.get_node_or_null("AnimatedSprite2D")
	if head_sprite:
		head_sprite.play("head")
		var head_dir = Vector2(positions[0] - positions[1]).normalized()
		snake_head.rotation_degrees = _dir_to_degrees(head_dir)

	# --- Body & Tail Visuals ---
	for i in range(snake_segments.size()):
		var segment = snake_segments[i]
		if not is_instance_valid(segment): continue
		
		var anim_sprite = segment.get_node("AnimatedSprite2D") as AnimatedSprite2D
		
		# Indices for Segment i:
		# is_pre_move: physically at positions[i+2], moving to positions[i+1]
		# is_post_move: physically at positions[i+1], next target is positions[i]
		var current_idx = i + 2 if is_pre_move else i + 1
		var target_idx = i + 1 if is_pre_move else i
		
		# Clamp indices to valid range
		current_idx = clamp(current_idx, 0, positions.size() - 1)
		target_idx = clamp(target_idx, 0, positions.size() - 1)
		
		var cur_pos = positions[current_idx]
		var tar_pos = positions[target_idx]
		var segment_pos = positions[target_idx]
		
		# CORNER PIECE ORIENTATION LOGIC:
		# Only apply corner-specific rotation when segment is AT corner (post-move).
		# At that point: segment physically at corner, corner piece can hide rotation.
		if corner_pieces.has(segment_pos) and not is_pre_move and target_idx + 1 < positions.size():
			# Segment at corner (post-move): rotate to exit direction (hidden by corner)
			var next_pos = positions[target_idx - 1] if target_idx > 0 else tar_pos
			tar_pos = next_pos
			cur_pos = segment_pos
		# else: Use normal direction (cur_pos → tar_pos)

		var direction = Vector2(tar_pos - cur_pos).normalized()
		
		# Fallback for growth/tail cases
		if direction == Vector2.ZERO:
			if target_idx + 1 < positions.size():
				direction = Vector2(positions[target_idx] - positions[target_idx+1]).normalized()
			elif is_instance_valid(snake_head):
				direction = snake_head.last_dir # Use head's last direction as final fallback

		segment.rotation_degrees = _dir_to_degrees(direction)
		segment.visible = true 

		if i == snake_segments.size() - 1:
			anim_sprite.play("tail")
		else:
			anim_sprite.play("body_straight")
func _on_game_over_imminent(killer_cell: Vector2i = Vector2i(-1, -1)) -> void:
	if is_game_over:
		return
	is_game_over = true
	
	# Stop logic
	if is_instance_valid(snake_head):
		snake_head.set_process(false)
	if is_instance_valid(player):
		player.disable_input()
		player.set_process(false)
	
	# Stage 1: Player Surprise
	if is_instance_valid(player):
		player.play_surprise_animation()
	
	await get_tree().create_timer(0.4).timeout
	
	# Stage 2: Snake "Lunge" overlap (if applicable)
	if killer_cell != Vector2i(-1, -1) and is_instance_valid(snake_head):
		_update_visual_state(true) # Set rotations for lunge
		
		var lunge_speed = 0.08
		var target_world = grid_to_world(killer_cell)
		var lunge_tween = create_tween()
		lunge_tween.set_parallel()
		lunge_tween.tween_property(snake_head, "global_position", target_world, lunge_speed).set_trans(Tween.TRANS_SINE)
		
		var positions = snake_head.previous_positions
		for i in range(snake_segments.size()):
			if i + 1 < positions.size():
				var segment = snake_segments[i]
				var target_pos = grid_to_world(positions[i + 1])
				lunge_tween.tween_property(segment, "global_position", target_pos, lunge_speed).set_trans(Tween.TRANS_SINE)
		
		await lunge_tween.finished
		_update_visual_state(false) # Final rotations
		await get_tree().create_timer(0.1).timeout

	# Stage 3: Bite Transition
	var bite_instance = bite_wipe_scene.instantiate()
	add_child(bite_instance)
	bite_instance.get_node("AnimationPlayer").play("bite")
	
	await get_tree().create_timer(0.3).timeout

	_on_game_over()

func _on_game_over() -> void:
	if not is_game_over:
		is_game_over = true
	
	var gs = get_node_or_null("/root/GlobalState")
	var profile_name = gs.current_profile_name if gs else "Guest"
	var final_score = score
	var final_time = game_time

	if gs:
		gs.update_high_score(profile_name, final_score, final_time)
		var high_score_data = gs.get_high_score(profile_name)
		print("High score for %s updated. Score: %d, Time: %.2f" % [profile_name, high_score_data["score"], high_score_data["time"]])
	else:
		print("GlobalState not found, score not saved.")

	# Go back to the profile selection screen after a short delay.
	if is_inside_tree():
		await get_tree().create_timer(2.0).timeout
		get_tree().paused = false
		get_tree().change_scene_to_file("res://Profile_Screen.tscn")

func _dir_to_degrees(dir: Vector2) -> float:
	if dir.is_equal_approx(Vector2.RIGHT): return 0.0
	if dir.is_equal_approx(Vector2.DOWN): return 90.0
	if dir.is_equal_approx(Vector2.LEFT): return 180.0
	if dir.is_equal_approx(Vector2.UP): return -90.0
	return 0.0

func _on_level_up() -> void:
	current_level += 1
	print("Level Up! Reached level ", current_level)
	
	snake_head.speed = max(0.05, snappedf(snake_head.speed - 0.01, 0.01))
