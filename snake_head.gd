extends Area2D

# note: Decide, Update, Announce, Animate

signal food_eaten(food_node)
signal moved()
signal game_over()
signal game_over_imminent(final_move_tween)
signal snake_trapped()

@onready var sprite = $AnimatedSprite2D

@export var speed := 0.2
@export var tile_size := 32
@export var player: Node2D
@export var game_manager: Node

var move_timer := 0.0
var last_dir := Vector2.ZERO
var previous_positions: Array[Vector2] = []

@export var min_x := 0
@export var max_x := 800
@export var min_y := 0
@export var max_y := 640
var half_size := tile_size / 2

func _ready():
	if game_manager:
		var play_area = game_manager.play_area_rect
		min_x = play_area.position.x
		max_x = play_area.end.x
		min_y = play_area.position.y
		max_y = play_area.end.y

func _process(delta: float) -> void:
	if game_manager.is_animating:
		return
	
	if not _tick(delta):
		return

	var target = _choose_target()
	if not is_instance_valid(target):
		return

	var dir = _get_safe_direction(target)
	if dir == Vector2.ZERO:
		emit_signal("snake_trapped")
		set_process(false)
		return
	
	var next_pos = global_position + dir * tile_size
	var player_pos = player.global_position
	next_pos.x = clamp(next_pos.x, min_x + half_size, max_x - half_size)
	next_pos.y = clamp(next_pos.y, min_y + half_size, max_y - half_size)
	
	last_dir = dir
	previous_positions.insert(0, next_pos)
	emit_signal("moved", next_pos, speed)
	
	if next_pos.distance_to(player.global_position) < 1.0:
		emit_signal("game_over_imminent")
		set_process(false)

func _tick(delta: float) -> bool:
	move_timer += delta
	if move_timer < speed:
		return false
	move_timer = 0.0
	return true

func _choose_target() -> Node2D:
	var closest_food: Node2D = null
	var min_dist := INF
	
	for food in get_tree().get_nodes_in_group("Food"):
		var dist = global_position.distance_squared_to(food.global_position)
		if dist < min_dist:
			min_dist = dist
			closest_food = food
	
	if closest_food:
		var player_dist = global_position.distance_squared_to(player.global_position)
		return player if player_dist <= min_dist else closest_food
	
	return player

func _get_safe_direction(target: Node2D) -> Vector2:
	var difference: Vector2 = target.global_position - global_position
	var candidate_dirs: Array[Vector2] = []

	if abs(difference.x) >= abs(difference.y):
		if difference.x != 0: candidate_dirs.append(Vector2(sign(difference.x), 0))
		if difference.y != 0: candidate_dirs.append(Vector2(0, sign(difference.y)))
	else:
		if difference.y != 0: candidate_dirs.append(Vector2(0, sign(difference.y)))
		if difference.x != 0: candidate_dirs.append(Vector2(sign(difference.x), 0))

	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if not candidate_dirs.has(d):
			candidate_dirs.append(d)

	for dir in candidate_dirs:
		if dir == -last_dir and not previous_positions.is_empty():
			continue
		if not _would_collide(dir):
			return dir
	
	if not candidate_dirs.is_empty() and -last_dir == candidate_dirs[0]:
		if not _would_collide(-last_dir):
			return -last_dir

	return Vector2.ZERO

func _would_collide(dir: Vector2) -> bool:
	var next_pos = global_position + dir * tile_size
	
	var next_grid_pos = game_manager.world_to_grid(next_pos)

	# --- Wall collision
	if next_pos.x < min_x + half_size \
	or next_pos.x > max_x - half_size \
	or next_pos.y < min_y + half_size \
	or next_pos.y > max_y - half_size:
		return true

	for pos in previous_positions:
		if game_manager.world_to_grid(pos) == next_grid_pos:
			return true

	return false


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Food"):
		# We don't need to check for position, the overlap is guaranteed.
		# The area node *is* the food node.
		emit_signal("food_eaten", area)
