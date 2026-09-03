extends Node2D

@export var food_scene: PackedScene
@export var tile_size := 32
@export var game_manager: Node

# Returns a random free world position, or Vector2.INF if none is free.
# "Free" means not on the snake's actual body, not on the player, and not on
# an existing food/powerup cell. The snake body is read from
# snake_head.previous_positions (not the grid) because spawn_food can be
# called before the board state is rebuilt, leaving the grid's body stale.
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

func spawn_food() -> void:
	if not game_manager:
		return

	if not food_scene:
		return

	var pos := _random_free_position()

	if pos == Vector2.INF:
		print("No space left for food! Game over?")
		return

	# Instantiate food.
	var food = food_scene.instantiate()
	food.global_position = pos
	food.add_to_group("Food")

	# Add immediately so the food exists before we validate its position.
	get_parent().add_child(food)

	# Safety fallback:
	# If the food somehow spawned on the snake, move it to another
	# free cell. Bounded retries avoid an infinite loop.
	var attempts: int = 0

	while _is_on_snake_body(food.global_position) and attempts < 20:
		attempts += 1

		var new_pos := _random_free_position()

		if new_pos == Vector2.INF:
			print("Food spawned on snake, but no other free position exists.")
			food.queue_free()
			return

		food.global_position = new_pos

	# Spawn pop.
	# Scale the sprite rather than the Area2D so the collision shape
	# remains unchanged.
	var sprite := food.get_node_or_null("Sprite2D") as Node2D

	if sprite:
		sprite.scale = Vector2.ZERO

		var tw := create_tween()
		tw.tween_property(sprite, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)

	if is_instance_valid(game_manager):
		game_manager.rebuild_board_state()
