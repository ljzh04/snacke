extends Node2D

@export var food_scene: PackedScene
@export var tile_size := 32
@export var game_manager: Node

func spawn_food() -> void:
	if not game_manager: return
	var play_area = game_manager.play_area_rect

	# compute valid spawn grid using canonical board state
	var valid_positions: Array[Vector2] = []
	var columns = int(play_area.size.x / tile_size)
	var rows = int(play_area.size.y / tile_size)
	for x in range(columns):
		for y in range(rows):
			var grid_pos = Vector2i(x, y)
			if game_manager.board_get(grid_pos) != 0:
				continue
			valid_positions.append(game_manager.grid_to_world(grid_pos))

	if valid_positions.is_empty():
		print("No space left for food! Game over?")
		return

	# pick random free spot
	var pos = valid_positions[randi() % valid_positions.size()]

	# instantiate food
	var food = food_scene.instantiate()
	food.global_position = pos
	food.add_to_group("Food")
	get_parent().call_deferred("add_child", food)
	if is_instance_valid(game_manager):
		game_manager.rebuild_board_state()
