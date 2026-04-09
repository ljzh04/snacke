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
@export var play_area_rect := Rect2(0, 0, 800, 640)

var snake_segments: Array[Node2D] = []
var corner_pieces: Dictionary = {}
var score := 0
var grow_pending := 0
var game_time := 0.0
var current_level := 1
var is_animating := false
var current_animation_tween: Tween

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var grid_x = int(round(world_pos.x / snake_head.tile_size))
	var grid_y = int(round(world_pos.y / snake_head.tile_size))
	return Vector2i(grid_x, grid_y)

func _ready() -> void:
	snake_head.food_eaten.connect(_on_food_eaten)
	snake_head.moved.connect(_on_snake_moved)
	snake_head.game_over.connect(_on_game_over)
	snake_head.game_over_imminent.connect(_on_game_over_imminent)
	snake_head.snake_trapped.connect(_on_snake_trapped)
	$LevelUpTimer.timeout.connect(_on_level_up)
	food_spawner.spawn_food()
	call_deferred("_spawn_initial_segments")

func _process(delta: float) -> void:
	game_time += delta
	var minutes = int(game_time) / 60
	var seconds = int(game_time) % 60
	var time_string = "%02d:%02d" % [minutes, seconds]
	emit_signal("time_updated", time_string)

func _spawn_initial_segments() -> void:
	snake_head.previous_positions.clear()
	var start_pos = snake_head.global_position
	for i in range(initial_snake_length):
		snake_head.previous_positions.append(start_pos - Vector2(i * snake_head.tile_size, 0))

	# Create the visual segments based on the data
	for i in range(initial_snake_length - 1):
		_add_new_segment()

	# Set the correct visual state (sprites, rotations) at the start of the game.
	_update_visual_state()

func _on_food_eaten(food_node: Node) -> void:
	food_node.queue_free()
	score = (5 ** current_level - 1)
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
	segment.global_position = my_pos

	if positions.size() > 1:
		var pos_in_front = positions[-2] # The second to last element
		var initial_dir = (pos_in_front - my_pos).normalized()
		segment.rotation_degrees = _dir_to_degrees(initial_dir)

	get_parent().add_child(segment)
	snake_segments.append(segment)

func _on_snake_moved(destination: Vector2, move_duration: float) -> void:
	is_animating = true
	var did_grow_this_turn := false

	# --- Corner Piece Logic ---
	# This part is for CREATING corner nodes. It runs before movement.
	var positions = snake_head.previous_positions
	if positions.size() >= 3:
		var head_pos = positions[0]
		var neck_pos = positions[1]
		var third_pos = positions[2]
		
		var dir_out = (head_pos - neck_pos).normalized()
		var dir_in = (neck_pos - third_pos).normalized()
		
		if not dir_in.is_equal_approx(dir_out) and not corner_pieces.has(neck_pos):
			var corner = corner_piece.instantiate()
			corner.global_position = neck_pos
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
	current_animation_tween.tween_property(snake_head, "global_position", destination, move_duration).set_trans(Tween.TRANS_LINEAR)

	for i in range(snake_segments.size()):
		if i + 1 < positions.size():
			var segment = snake_segments[i]
			var target_pos = positions[i+1]
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

	is_animating = false

func _update_visual_state() -> void:
	# This is the master "renderer" function. It runs after everything has moved.
	var positions = snake_head.previous_positions
	if positions.size() < 2: return

	# --- Head Visuals ---
	var head_sprite = snake_head.get_node_or_null("AnimatedSprite2D")
	if head_sprite:
		head_sprite.play("head")
		var head_dir = (positions[0] - positions[1]).normalized()
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
				var direction = (pos_in_front - my_pos).normalized()
				segment.rotation_degrees = _dir_to_degrees(direction)

				if i == snake_segments.size() - 1:
					anim_sprite.play("tail")
				else:
					anim_sprite.play("body_straight")
func _on_game_over_imminent() -> void:
	if is_instance_valid(current_animation_tween):
		current_animation_tween.kill()
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
	var profile_name = GlobalState.current_profile_name
	var final_score = score
	var final_time = game_time

	GlobalState.update_high_score(profile_name, final_score, final_time)
	
	var high_score_data = GlobalState.get_high_score(profile_name)
	print("High score for %s updated. Score: %d, Time: %.2f" % [profile_name, high_score_data["score"], high_score_data["time"]])
	
	# Go back to the profile selection screen after a short delay
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
	
	snake_head.speed = max(0.1, snake_head.speed * 0.5) 

	player.move_delay = max(0.1, player.move_delay * 0.5)
