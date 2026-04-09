extends Node2D

@export var food_scene: PackedScene
@export var tile_size := 32
@export var game_manager: Node

func spawn_food() -> void:
	if not game_manager: return
	var play_area = game_manager.play_area_rect
	
	# collect occupied positions
	var occupied := {}
	for node in get_tree().get_nodes_in_group("SnakeBody"):
		occupied[node.global_position] = true
	var snake_head = get_tree().get_first_node_in_group("SnakeHead")
	if snake_head:
		occupied[snake_head.global_position] = true
	var player = get_tree().get_first_node_in_group("Player")
	if player:
		occupied[player.global_position] = true

	# compute valid spawn grid
	var valid_positions: Array[Vector2] = []
	for x in range(int(play_area.position.x), int(play_area.end.x), tile_size):
		for y in range(int(play_area.position.y), int(play_area.end.y), tile_size):
			var pos = Vector2(x + tile_size/2, y + tile_size/2)
			if not occupied.has(pos):
				valid_positions.append(pos)

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
