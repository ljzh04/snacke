extends Area2D

# note: Decide, Update, Announce, Animate

signal food_eaten(food_node)
signal moved(destination, move_duration)
signal snake_trapped()

enum Personality { GREEDY, CAUTIOUS, SMART, TRAPPER, ZIGZAG, STRAIGHT }

@onready var sprite = $AnimatedSprite2D

@export var speed := 0.2
@export var tile_size := 32
@export var player: Node2D
@export var game_manager: Node
@export var personality: Personality = Personality.SMART
@export var trapper_engage_distance := 7

@export var pathing_target_bias := 1.2
@export var pathing_space_bias := 1.0
@export var pathing_turn_penalty := 0.6
@export var pathing_reverse_penalty := 2.0
@export var pathing_lookahead_cells := 24
@export var pathing_dead_end_penalty := 10.0
@export var pathing_randomness := 0.12
@export var pathing_axis_completion_weight := 2.0	# boost for finishing a major axis
@export var pathing_axis_lock_steps := 3			# how many steps to commit to an axis

var move_timer := 0.0
var last_dir := Vector2.ZERO
var previous_positions: Array[Vector2i] = []
var _axis_lock_axis := 0		# 0 = none, 1 = x, 2 = y
var current_axis := Vector2.ZERO
var _last_target_ref: Node2D = null
var _axis_lock_remaining = 0

@export var min_x := 0
@export var max_x := 800
@export var min_y := 0
@export var max_y := 640
var half_size := tile_size * 0.5

func _ready():
	add_to_group("SnakeHead")
	if game_manager:
		var play_area = game_manager.play_area_rect
		min_x = play_area.position.x
		max_x = play_area.end.x
		min_y = play_area.position.y
		max_y = play_area.end.y

func _process(delta: float) -> void:
	if not is_instance_valid(game_manager) or game_manager.is_animating:
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
	
	var head_cell = game_manager.world_to_grid(global_position)
	var next_cell = head_cell + Vector2i(int(dir.x), int(dir.y))
	if not game_manager.is_cell_inside(next_cell):
		return

	last_dir = dir
	previous_positions.insert(0, next_cell)
	emit_signal("moved", next_cell, speed)

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
	if not is_instance_valid(target):
		return Vector2.ZERO

	# reset lock when target changes
	if target != _last_target_ref:
		_last_target_ref = target
		_axis_lock_axis = 0
		_axis_lock_remaining = 0

	var candidate_dirs = _build_candidate_dirs(target)
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if not candidate_dirs.has(d):
			candidate_dirs.append(d)

	var best_dir = Vector2.ZERO
	var best_score = -INF
	var second_best_dir = Vector2.ZERO
	var second_best_score = -INF

	for dir in candidate_dirs:
		if dir == -last_dir and not previous_positions.is_empty():
			continue
		if _would_collide(dir):
			continue

		var next_pos = global_position + dir * tile_size
		var score = _score_direction(next_pos, target, dir)
		if score > best_score:
			second_best_dir = best_dir
			second_best_score = best_score
			best_dir = dir
			best_score = score
		elif score > second_best_score:
			second_best_dir = dir
			second_best_score = score

	if best_dir == Vector2.ZERO:
		if not _would_collide(-last_dir):
			return -last_dir
		return Vector2.ZERO

	# occasional exploration
	var chosen: Vector2 = second_best_dir if second_best_dir != Vector2.ZERO and randf() < pathing_randomness else best_dir

	# axis lock bookkeeping: decrement if chosen continues the locked axis, otherwise clear lock
	if _axis_lock_axis != 0:
		if (_axis_lock_axis == 1 and chosen.x != 0) or (_axis_lock_axis == 2 and chosen.y != 0):
			_axis_lock_remaining -= 1
			if _axis_lock_remaining <= 0:
				_axis_lock_axis = 0
				_axis_lock_remaining = 0
		else:
			_axis_lock_axis = 0
			_axis_lock_remaining = 0

	return chosen

func _build_candidate_dirs(target: Node2D) -> Array[Vector2]:
	var candidate_dirs: Array[Vector2] = []
	var diff = target.global_position - global_position
	var dx = sign(diff.x)
	var dy = sign(diff.y)
	var major_axis = 1 if abs(diff.x) >= abs(diff.y) else 2

	match personality:
		Personality.STRAIGHT:
			if last_dir != Vector2.ZERO:
				candidate_dirs.append(last_dir)
				if major_axis == 1:
					if dx != 0: candidate_dirs.append(Vector2(dx, 0))
					if dy != 0: candidate_dirs.append(Vector2(0, dy))
				else:
					if dy != 0: candidate_dirs.append(Vector2(0, dy))
					if dx != 0: candidate_dirs.append(Vector2(dx, 0))
			else:
				if major_axis == 1:
					if dx != 0: candidate_dirs.append(Vector2(dx, 0))
					if dy != 0: candidate_dirs.append(Vector2(0, dy))
				else:
					if dy != 0: candidate_dirs.append(Vector2(0, dy))
					if dx != 0: candidate_dirs.append(Vector2(dx, 0))
		Personality.ZIGZAG:
			if last_dir != Vector2.ZERO and dx != 0 and dy != 0:
				if last_dir.x != 0:
					candidate_dirs.append(Vector2(0, dy))
				else:
					candidate_dirs.append(Vector2(dx, 0))
			if major_axis == 1:
				if dx != 0: candidate_dirs.append(Vector2(dx, 0))
				if dy != 0: candidate_dirs.append(Vector2(0, dy))
			else:
				if dy != 0: candidate_dirs.append(Vector2(0, dy))
				if dx != 0: candidate_dirs.append(Vector2(dx, 0))
		_:
			if major_axis == 1:
				if dx != 0: candidate_dirs.append(Vector2(dx, 0))
				if dy != 0: candidate_dirs.append(Vector2(0, dy))
			else:
				if dy != 0: candidate_dirs.append(Vector2(0, dy))
				if dx != 0: candidate_dirs.append(Vector2(dx, 0))

	return candidate_dirs

func _score_direction(next_pos: Vector2, target: Node2D, dir: Vector2) -> float:
	var dist_before = global_position.distance_squared_to(target.global_position)
	var dist_after = next_pos.distance_squared_to(target.global_position)
	var approach_score := 0.0
	if dist_before > 0.0:
		approach_score = (dist_before - dist_after) / dist_before

	var area_count = _reachable_area(next_pos)
	var area_score = clamp(float(area_count) / float(pathing_lookahead_cells), 0.0, 1.0)
	var tightness = 1.0 - area_score
	var board_cells = max(1, int(float(max_x - min_x) / float(tile_size)) * int(float(max_y - min_y) / float(tile_size)))
	var length_pressure = clamp(float(previous_positions.size()) / max(1.0, float(board_cells) * 0.35), 0.0, 1.0)
	var crowding = clamp((tightness + length_pressure) * 0.5, 0.0, 1.0)
	var dead_end_penalty = _dead_end_penalty(next_pos)
	var turn_bonus := 0.0
	var straight_bonus := 0.0
	var zigzag_bonus := 0.0
	if last_dir != Vector2.ZERO:
		if dir == last_dir:
			turn_bonus = 0.6
			straight_bonus = 1.0
		elif dir == -last_dir:
			turn_bonus = -2.2
		else:
			turn_bonus = -0.45
			zigzag_bonus = 0.85

	var diff = target.global_position - next_pos
	var ax = abs(diff.x)
	var ay = abs(diff.y)
	var axis_bonus = 0.0
	if ax + ay > 0:
		if ax > ay and dir.x != 0:
			axis_bonus = pathing_axis_completion_weight * (ax / (ax + ay))
		elif ay > ax and dir.y != 0:
			axis_bonus = pathing_axis_completion_weight * (ay / (ax + ay))
		elif ax == ay:
			if dir == last_dir:
				axis_bonus = pathing_axis_completion_weight * 0.7
			elif dir.x != 0:
				axis_bonus = pathing_axis_completion_weight * 0.5

	var trap_score = _target_escape_score(next_pos, target)

	match personality:
		Personality.GREEDY:
			return approach_score * 7.0 + axis_bonus * 1.8 + straight_bonus * 0.4 - dead_end_penalty * 1.2 - crowding * 0.5 + turn_bonus
		Personality.CAUTIOUS:
			return area_score * 5.0 + (1.0 - crowding) * 0.8 + approach_score * 1.5 - dead_end_penalty * 3.0 + turn_bonus * 0.5
		Personality.SMART:
			var greedy_mix = clamp(1.0 - crowding * 1.2, 0.0, 1.0)
			var cautious_mix = 1.0 - greedy_mix
			return approach_score * lerp(2.0, 6.0, greedy_mix) + area_score * lerp(4.5, 1.0, greedy_mix) + axis_bonus * lerp(0.5, 1.5, greedy_mix) - dead_end_penalty * lerp(3.0, 1.0, greedy_mix) + turn_bonus * lerp(0.4, 1.0, cautious_mix)
		Personality.TRAPPER:
			var engage_distance = tile_size * trapper_engage_distance
			if global_position.distance_to(target.global_position) > engage_distance:
				return approach_score * 3.5 + area_score * 3.2 + axis_bonus * 0.6 - dead_end_penalty * 2.0 + turn_bonus * 0.5
			return trap_score * 5.0 + area_score * 2.5 + approach_score * 1.0 + straight_bonus * 0.4 - dead_end_penalty * 2.5 + turn_bonus
		Personality.ZIGZAG:
			return approach_score * 4.0 + zigzag_bonus * 4.5 + axis_bonus * 0.6 + area_score * 0.8 - dead_end_penalty * 1.5 + turn_bonus
		Personality.STRAIGHT:
			return approach_score * 3.0 + straight_bonus * 5.0 + axis_bonus * 0.8 + area_score * 0.2 - dead_end_penalty * 1.2 + turn_bonus

	return approach_score * pathing_target_bias + area_score * pathing_space_bias + axis_bonus - dead_end_penalty * pathing_dead_end_penalty + turn_bonus

func _reachable_area(start_pos: Vector2) -> int:
	var start_grid = game_manager.world_to_grid(start_pos)
	var queue: Array[Vector2i] = [start_grid]
	var visited := {start_grid: true}
	var count := 0

	while not queue.is_empty() and count < pathing_lookahead_cells:
		var current = queue.pop_front()
		count += 1
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var neighbor = current + Vector2i(int(dir.x), int(dir.y))
			if visited.has(neighbor):
				continue
			if _grid_cell_blocked(neighbor):
				continue
			visited[neighbor] = true
			queue.append(neighbor)

	return count

func _dead_end_penalty(next_pos: Vector2) -> float:
	var grid_pos = game_manager.world_to_grid(next_pos)
	var open_neighbors = 0
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if not _grid_cell_blocked(grid_pos + Vector2i(int(dir.x), int(dir.y))):
			open_neighbors += 1

	if open_neighbors == 0:
		return 2.0
	elif open_neighbors == 1:
		return 1.0
	return 0.0

func _grid_cell_blocked(grid_pos: Vector2i) -> bool:
	return _grid_cell_blocked_with_occupied(grid_pos, {})

func _grid_cell_blocked_with_occupied(grid_pos: Vector2i, occupied: Dictionary) -> bool:
	if occupied.has(grid_pos):
		return true

	if not game_manager.is_cell_inside(grid_pos):
		return true

	for index in range(previous_positions.size()):
		if _tail_will_vacate() and index == previous_positions.size() - 1:
			continue
		if previous_positions[index] == grid_pos:
			return true

	return false

func _would_collide(dir: Vector2) -> bool:
	var head_cell = game_manager.world_to_grid(global_position)
	var next_cell = head_cell + Vector2i(int(dir.x), int(dir.y))

	if not game_manager.is_cell_inside(next_cell):
		return true

	for index in range(previous_positions.size()):
		if _tail_will_vacate() and index == previous_positions.size() - 1:
			continue
		if previous_positions[index] == next_cell:
			return true

	return false


func _tail_will_vacate() -> bool:
	return is_instance_valid(game_manager) and game_manager.grow_pending == 0 and not previous_positions.is_empty()

func _future_occupied_cells(next_grid_pos: Vector2i) -> Dictionary:
	var occupied := {next_grid_pos: true}
	for index in range(previous_positions.size()):
		if _tail_will_vacate() and index == previous_positions.size() - 1:
			continue
		occupied[previous_positions[index]] = true
	return occupied

func _target_escape_score(next_pos: Vector2, target: Node2D) -> float:
	if not is_instance_valid(target):
		return 0.0

	var target_grid = game_manager.world_to_grid(target.global_position)
	var next_grid = game_manager.world_to_grid(next_pos)
	var occupied = _future_occupied_cells(next_grid)
	occupied.erase(target_grid)

	var queue: Array[Vector2i] = [target_grid]
	var visited := {target_grid: true}
	var count := 0

	while not queue.is_empty() and count < pathing_lookahead_cells:
		var current = queue.pop_front()
		count += 1
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var neighbor = current + Vector2i(int(dir.x), int(dir.y))
			if visited.has(neighbor):
				continue
			if _grid_cell_blocked_with_occupied(neighbor, occupied):
				continue
			visited[neighbor] = true
			queue.append(neighbor)

	return 1.0 - clamp(float(count) / float(pathing_lookahead_cells), 0.0, 1.0)


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Food"):
		emit_signal("food_eaten", area)
