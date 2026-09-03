extends Node2D

@export var powerup_scene: PackedScene
@export var tile_size := 32
@export var game_manager: Node

var powerup_active := false

func spawn_powerup_if_ready() -> void:
	if not game_manager:
		return

	if powerup_active:
		return

	if game_manager.has_pending_shrink():
		return

	if not game_manager.grid:
		return

	var snake_length: int = game_manager.snake_segments.size() + 1
	var total_cells: int = game_manager.grid.columns * game_manager.grid.rows
	var threshold: int = int(total_cells / 4)

	if snake_length < threshold:
		return

	_spawn_powerup()

# Returns a random free world position, or Vector2.INF if none is free.
# "Free" means not on the snake's actual body, not on the player, and not on
# an existing food/powerup cell. The snake body is read from
# snake_head.previous_positions (not the grid) because spawning can happen
# before the board state is rebuilt, leaving the grid's body stale.
func _random_free_position() -> Vector2:
	if not game_manager:
		return Vector2.INF
	var play_area = game_manager.play_area_rect

	var occupied := {}
	if is_instance_valid(game_manager.snake_head):
		for cell in game_manager.snake_head.previous_positions:
			occupied[cell] = true
	if is_instance_valid(game_manager.player):
		occupied[game_manager.player_cell] = true

	var valid_positions: Array[Vector2] = []
	var columns = int(play_area.size.x / tile_size)
	var rows = int(play_area.size.y / tile_size)
	for x in range(columns):
		for y in range(rows):
			var grid_pos = Vector2i(x, y)
			if occupied.has(grid_pos):
				continue
			var cell_value = game_manager.grid.get_cell(grid_pos)
			if cell_value == 3 or cell_value == 4:
				continue
			valid_positions.append(game_manager.grid.grid_to_world(grid_pos))

	if valid_positions.is_empty():
		return Vector2.INF
	return valid_positions[randi() % valid_positions.size()]

# True if the given world position sits on the snake's body.
func _is_on_snake_body(world_pos: Vector2) -> bool:
	if not is_instance_valid(game_manager) or not is_instance_valid(game_manager.snake_head):
		return false
	var cell = game_manager.grid.world_to_grid(world_pos)
	for body_cell in game_manager.snake_head.previous_positions:
		if body_cell == cell:
			return true
	return false

func _spawn_powerup() -> void:
	if not game_manager:
		return
	if not powerup_scene:
		return

	var pos := _random_free_position()
	if pos == Vector2.INF:
		return

	var powerup = powerup_scene.instantiate()
	powerup.global_position = pos
	powerup.add_to_group("PowerUp")

	get_parent().add_child(powerup)

	# Fallback: if the powerup somehow lands on the snake's body,
	# move it to another free cell.
	var attempts := 0
	while _is_on_snake_body(powerup.global_position) and attempts < 20:
		attempts += 1

		var new_pos := _random_free_position()
		if new_pos == Vector2.INF:
			break

		powerup.global_position = new_pos

	powerup_active = true

	if is_instance_valid(game_manager):
		game_manager.rebuild_board_state()

func relocate_powerup(powerup_node: Node2D) -> void:
	# Moves an existing powerup to a random free cell. Used when the snake
	# eats the powerup: the pickup escapes elsewhere instead of shrinking
	# the snake, and powerup_active stays true because the node survives.
	if not game_manager or not game_manager.grid:
		return
	if not is_instance_valid(powerup_node):
		return

	var new_pos := _random_free_position()
	if new_pos == Vector2.INF:
		return
	powerup_node.global_position = new_pos
	if is_instance_valid(game_manager):
		game_manager.rebuild_board_state()

func consume_powerup() -> void:
	powerup_active = false
	for pu in get_tree().get_nodes_in_group("PowerUp"):
		if is_instance_valid(pu):
			pu.queue_free()
