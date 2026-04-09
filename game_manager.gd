extends Node

signal score_updated(new_score)
signal time_updated(time_string) 

@export var snake_head: Area2D
@export var snake_segment: PackedScene
@export var corner_piece: PackedScene
@export var food_spawner: Node
@export var initial_snake_length := 3
@export var bite_wipe_scene: PackedScene
@export var player: CharacterBody2D
@export var play_area_rect := Rect2(32, 64, 736, 544)

var snake_segments: Array[Node2D] = []
var corner_pieces: Dictionary = {}
var score := 0
var grow_pending := 0
var game_time := 0.0
var current_level := 1
var columns := 0
var rows := 0
var player_cell: Vector2i = Vector2i.ZERO
var food_cell: Vector2i = Vector2i.ZERO
var board: Array = []
var is_animating := false
var is_player_animating := false
var is_game_over := false
var current_animation_tween: Tween

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var half_size = snake_head.tile_size * 0.5
	var local_pos = world_pos - play_area_rect.position
	var grid_x = int(floor((local_pos.x - half_size) / snake_head.tile_size))
	var grid_y = int(floor((local_pos.y - half_size) / snake_head.tile_size))
	return Vector2i(grid_x, grid_y)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	var half_size = snake_head.tile_size * 0.5
	return play_area_rect.position + Vector2(grid_pos.x * snake_head.tile_size, grid_pos.y * snake_head.tile_size) + Vector2(half_size, half_size)

func initialize_board() -> void:
	columns = int(play_area_rect.size.x / snake_head.tile_size)
	rows = int(play_area_rect.size.y / snake_head.tile_size)
	board.clear()
	for y in range(rows):
		var row := []
		for x in range(columns):
			row.append(0)
		board.append(row)

func board_get(cell: Vector2i) -> int:
	if not is_cell_inside(cell):
		return 0
	return board[cell.y][cell.x]

func board_set(cell: Vector2i, value: int) -> void:
	if not is_cell_inside(cell):
		return
	board[cell.y][cell.x] = value

func is_cell_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < columns and cell.y >= 0 and cell.y < rows

func _ready() -> void:
	snake_head.moved.connect(_on_snake_moved)
	snake_head.snake_trapped.connect(_on_snake_trapped)
	$LevelUpTimer.timeout.connect(_on_level_up)

	# Ensure a single tile size is used by player and spawner (use snake_head as source of truth)
	var base_tile := 32
	if is_instance_valid(snake_head):
		base_tile = int(snake_head.tile_size)

	if is_instance_valid(player):
		player.tile_size = base_tile
		player.half_size = base_tile * 0.5

	if is_instance_valid(food_spawner):
		food_spawner.tile_size = base_tile

	initialize_board()

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

	# Deterministic collision check based on grid occupancy only.
	# Run at stable positions to avoid tween interpolation false positives.
	if not is_game_over and not is_animating and is_instance_valid(player):
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
	for y in range(rows):
		for x in range(columns):
			board[y][x] = 0

	if is_instance_valid(player):
		player_cell = world_to_grid(player.global_position)
		board_set(player_cell, 1)

	for cell in snake_head.previous_positions:
		board_set(cell, 2)

	food_cell = Vector2i(-1, -1)
	for f in get_tree().get_nodes_in_group("Food"):
		if is_instance_valid(f):
			food_cell = world_to_grid(f.global_position)
			board_set(food_cell, 3)

func _on_food_eaten(food_node: Node) -> void:
	food_node.queue_free()
	score = (5 * current_level - 1)
	grow_pending += 1
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

	if next_head_cell == player_cell:
		_on_game_over_imminent()

	if next_head_cell == food_cell:
		food_cell = Vector2i(-1, -1)
		for food in get_tree().get_nodes_in_group("Food"):
			if is_instance_valid(food) and world_to_grid(food.global_position) == next_head_cell:
				food.queue_free()
				break
		score = (5 * current_level - 1)
		grow_pending += 1
		food_spawner.spawn_food()
		emit_signal("score_updated", score)

	rebuild_board_state()

	# --- Corner Piece Logic ---
	# This part is for CREATING corner nodes. It runs before movement.
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
			
			if (dir_in == Vector2.UP and dir_out == Vector2.RIGHT) or (dir_in == Vector2.LEFT and dir_out == Vector2.DOWN): corner.rotation_degrees = 90
			elif (dir_in == Vector2.DOWN and dir_out == Vector2.RIGHT) or (dir_in == Vector2.LEFT and dir_out == Vector2.UP): corner.rotation_degrees = 0
			elif (dir_in == Vector2.DOWN and dir_out == Vector2.LEFT) or (dir_in == Vector2.RIGHT and dir_out == Vector2.UP): corner.rotation_degrees = -90
			elif (dir_in == Vector2.UP and dir_out == Vector2.LEFT) or (dir_in == Vector2.RIGHT and dir_out == Vector2.DOWN): corner.rotation_degrees = 180

	if grow_pending > 0:
		grow_pending -= 1
		_add_new_segment()
		did_grow_this_turn = true
	
	current_animation_tween = create_tween()
	current_animation_tween.set_parallel()
	current_animation_tween.tween_property(snake_head, "global_position", destination_world, move_duration).set_trans(Tween.TRANS_LINEAR)

	for i in range(snake_segments.size()):
		if i + 1 < positions.size():
			var segment = snake_segments[i]
			var target_pos = grid_to_world(positions[i+1])
			current_animation_tween.tween_property(segment, "global_position", target_pos, move_duration).set_trans(Tween.TRANS_LINEAR)
	
	# We use call_deferred here to guarantee the visual update happens AFTER the tween completes.
	current_animation_tween.tween_callback(
		func():
			_on_turn_animation_finished(did_grow_this_turn)
			call_deferred("_update_visual_state")
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

	is_animating = false

func _player_overlaps_snake_grid() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(snake_head):
		return false

	for snake_pos in snake_head.previous_positions:
		if snake_pos == player_cell:
			return true

	return false

func request_player_move(direction: Vector2) -> bool:
	if is_game_over or is_player_animating:
		return false
	var delta = Vector2i.ZERO
	if abs(direction.x) > abs(direction.y):
		delta = Vector2i(sign(direction.x), 0)
	elif abs(direction.y) > 0.0:
		delta = Vector2i(0, sign(direction.y))
	if delta == Vector2i.ZERO:
		return false

	var target_cell = player_cell + delta
	if not is_cell_inside(target_cell):
		return false

	var cell_value = board_get(target_cell)
	if cell_value == 2:
		_on_game_over_imminent()
		return false

	if cell_value == 3:
		# eat food and spawn next.
		for food in get_tree().get_nodes_in_group("Food"):
			if is_instance_valid(food) and world_to_grid(food.global_position) == target_cell:
				food.queue_free()
				food_cell = Vector2i(-1, -1)
				break
		score = (5 * current_level - 1)
		grow_pending += 1
		food_spawner.spawn_food()
		emit_signal("score_updated", score)

	board_set(player_cell, 0)
	player_cell = target_cell
	board_set(player_cell, 1)
	if is_instance_valid(player):
		player.current_cell = player_cell
	animate_player_to(target_cell, player.move_delay)
	return true

func animate_player_to(cell: Vector2i, move_duration: float) -> void:
	if not is_instance_valid(player):
		return
	is_player_animating = true
	var destination = grid_to_world(cell)
	var player_tween = create_tween()
	player_tween.tween_property(player, "global_position", destination, move_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	player_tween.tween_callback(func(): is_player_animating = false)

func _update_visual_state() -> void:
	# This is the master "renderer" function. It runs after everything has moved.
	var positions = snake_head.previous_positions
	if positions.size() < 2: return

	# --- Head Visuals ---
	var head_sprite = snake_head.get_node_or_null("AnimatedSprite2D")
	if head_sprite:
		head_sprite.play("head")
		var head_dir = Vector2(positions[0] - positions[1]).normalized()
		snake_head.rotation_degrees = _dir_to_degrees(head_dir)

	# --- Body & Tail Visuals ---
	if not snake_segments.is_empty():
		for i in range(snake_segments.size()):
			var segment = snake_segments[i]
			var anim_sprite = segment.get_node("AnimatedSprite2D") as AnimatedSprite2D
			
			var my_pos = positions[i + 1]

			if corner_pieces.has(my_pos):
				pass
			else:
				# Otherwise, make sure it's visible and set its sprite.
				segment.visible = true
				var pos_in_front = positions[i]
				var direction = Vector2(pos_in_front - my_pos).normalized()
				segment.rotation_degrees = _dir_to_degrees(direction)

				if i == snake_segments.size() - 1:
					anim_sprite.play("tail")
				else:
					anim_sprite.play("body_straight")
func _on_game_over_imminent() -> void:
	if is_game_over:
		return
	is_game_over = true
	if is_instance_valid(snake_head):
		snake_head.set_process(false)
	player.disable_input()
	
	player.play_surprise_animation()
	player.set_process(false)
	await get_tree().create_timer(0.4).timeout
	
	var bite_instance = bite_wipe_scene.instantiate()
	add_child(bite_instance)
	bite_instance.get_node("AnimationPlayer").play("bite")
	
	await get_tree().create_timer(0.3).timeout

	_on_game_over()

func _on_game_over() -> void:
	if not is_game_over:
		is_game_over = true
	var profile_name = GlobalState.current_profile_name
	var final_score = score
	var final_time = game_time

	GlobalState.update_high_score(profile_name, final_score, final_time)
	
	var high_score_data = GlobalState.get_high_score(profile_name)
	print("High score for %s updated. Score: %d, Time: %.2f" % [profile_name, high_score_data["score"], high_score_data["time"]])

	# Go back to the profile selection screen after a short delay.
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
	
	snake_head.speed = max(0.1, snappedf(snake_head.speed * 0.8, 0.1)) 

	player.move_delay = max(0.1, snappedf(player.move_delay * 0.8, 0.1))
