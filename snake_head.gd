extends Area2D

# note: Decide, Update, Announce, Animate

signal moved(destination, move_duration)
signal snake_trapped()

# 64*16 total; divided into 16x16 for each sprite parts; namely: head (direction facing right), straight body piece (oriented horizontally), tail(closed-end facing left, open-connectable to the right), body corner (corner vertex is bottom left, connectable portions are top and right)
@onready var sprite = $AnimatedSprite2D

@export var speed := 0.08
@export var tile_size := 32
@export var player: Node2D
@export var game_manager: Node

@export_group("Pathing Biases")
@export var pathing_lookahead_cells := 120
@export var pathing_randomness := 0.05

var move_timer := 0.0
var last_dir := Vector2.ZERO
var previous_positions: Array[Vector2i] = []

@export_group("Bounds")
@export var min_x := 32.0
@export var max_x := 736.0
@export var min_y := 64.0
@export var max_y := 544.0

func _ready() -> void:
	add_to_group("SnakeHead")
	if game_manager:
		var play_area = game_manager.play_area_rect
		min_x = play_area.position.x
		max_x = play_area.end.x
		min_y = play_area.position.y
		max_y = play_area.end.y
	
	# Consolidate collision: GameManager handles it now.
	for connection in area_entered.get_connections():
		area_entered.disconnect(connection.callable)

func _process(delta: float) -> void:
	if not is_instance_valid(game_manager) or game_manager.is_animating:
		return
	
	if not _tick(delta):
		return

	var target = _choose_target()
	if not is_instance_valid(target):
		return

	var dir = _get_perfect_direction(target)
	if dir == Vector2.ZERO:
		emit_signal("snake_trapped")
		set_process(false)
		return
	
	var head_cell = game_manager.grid.world_to_grid(global_position)
	var next_cell = head_cell + Vector2i(int(dir.x), int(dir.y))
	if not game_manager.grid.is_cell_inside(next_cell):
		print("DEBUG: Next cell out of bounds - head_cell: %s, dir: %s, next_cell: %s" % [head_cell, dir, next_cell])
		return

	if abs(int(dir.x)) + abs(int(dir.y)) != 1:
		print("DEBUG: Non-cardinal direction returned - dir: %s, head_cell: %s, next_cell: %s" % [dir, head_cell, next_cell])
	
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
		# Prioritize player if close to make it feel like a chase
		return player if player_dist <= min_dist * 0.8 else closest_food
	
	return player

func _get_perfect_direction(target: Node2D) -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO

	var head_grid = game_manager.grid.world_to_grid(global_position)
	var target_grid = game_manager.grid.world_to_grid(target.global_position)
	
	# 1. Try to find shortest path to target using A*
	var path = _find_astar_path(head_grid, target_grid)
	
	if not path.is_empty() and path.size() > 1:
		var next_step = path[1]
		var dir = Vector2(next_step - head_grid)
		# Survival check: if I move here, can I still reach my tail?
		if _can_reach_tail_after_move(next_step):
			if abs(int(dir.x)) + abs(int(dir.y)) != 1:
				print("WARNING: A* returned non-cardinal dir: %s (next_step: %s, head: %s)" % [dir, next_step, head_grid])
			return dir

	# 2. If A* to target is unsafe, try to move to a neighbor that can still reach the tail
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	neighbors.shuffle() # Add slight variety
	
	var best_neighbor_dir = Vector2.ZERO
	var max_area = -1
	
	for n_dir in neighbors:
		var neighbor = head_grid + n_dir
		if not game_manager.grid.is_cell_inside(neighbor): continue
		if _is_cell_occupied(neighbor): continue
		
		if _can_reach_tail_after_move(neighbor):
			var area = _reachable_area_virtual(neighbor, _get_virtual_positions(neighbor))
			if area > max_area:
				max_area = area
				best_neighbor_dir = Vector2(n_dir)
				
	if best_neighbor_dir != Vector2.ZERO:
		return best_neighbor_dir

	# 3. Last resort: just move to the neighbor with most space
	var last_resort_dir = Vector2.ZERO
	var last_resort_max_area = -1
	for n_dir in neighbors:
		var neighbor = head_grid + n_dir
		if not game_manager.grid.is_cell_inside(neighbor): continue
		if _is_cell_occupied(neighbor): continue
		var area = _reachable_area_virtual(neighbor, _get_virtual_positions(neighbor))
		if area > last_resort_max_area:
			last_resort_max_area = area
			last_resort_dir = Vector2(n_dir)
			
	return last_resort_dir

func _find_astar_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var open_set = [start]
	var came_from = {}
	var g_score = {start: 0}
	var f_score = {start: _manhattan_dist(start, end)}
	
	while not open_set.is_empty():
		var current = open_set[0]
		for node in open_set:
			if f_score.get(node, INF) < f_score.get(current, INF):
				current = node
		
		if current == end:
			return _reconstruct_path(came_from, current)
			
		open_set.erase(current)
		
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor = current + dir
			if not game_manager.grid.is_cell_inside(neighbor): continue
			# In A*, we consider occupied cells as blocks, unless it's the target
			if _is_cell_occupied(neighbor) and neighbor != end: continue
			
			var tentative_g_score = g_score[current] + 1
			if tentative_g_score < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g_score
				f_score[neighbor] = tentative_g_score + _manhattan_dist(neighbor, end)
				if not open_set.has(neighbor):
					open_set.append(neighbor)
					
	return []

func _get_virtual_positions(next_head: Vector2i) -> Array[Vector2i]:
	var virtual = previous_positions.duplicate()
	virtual.insert(0, next_head)
	if is_instance_valid(game_manager) and game_manager.grow_pending == 0:
		virtual.pop_back()
	return virtual

func _can_reach_tail_after_move(next_head: Vector2i) -> bool:
	var virtual = _get_virtual_positions(next_head)
	var tail = virtual.back()
	return _path_exists_virtual(next_head, tail, virtual)

func _path_exists_virtual(start: Vector2i, end: Vector2i, occupied: Array[Vector2i]) -> bool:
	var queue = [start]
	var visited = {start: true}
	var occupied_set = {}
	for p in occupied: occupied_set[p] = true
	occupied_set.erase(end) # Tail will move

	while not queue.is_empty():
		var current = queue.pop_front()
		if current == end: return true
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor = current + dir
			if not game_manager.grid.is_cell_inside(neighbor): continue
			if occupied_set.has(neighbor): continue
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return false

func _reachable_area_virtual(start: Vector2i, occupied: Array[Vector2i]) -> int:
	var queue = [start]
	var visited = {start: true}
	var occupied_set = {}
	for p in occupied: occupied_set[p] = true
	var count = 0

	while not queue.is_empty() and count < pathing_lookahead_cells:
		var current = queue.pop_front()
		count += 1
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor = current + dir
			if not game_manager.grid.is_cell_inside(neighbor): continue
			if occupied_set.has(neighbor): continue
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return count

func _manhattan_dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)
	return path

func _is_cell_occupied(cell: Vector2i) -> bool:
	for p in previous_positions:
		if p == cell: return true
	return false

func _dir_to_degrees(dir: Vector2) -> float:
	if dir.is_equal_approx(Vector2.RIGHT): return 0.0
	if dir.is_equal_approx(Vector2.DOWN): return 90.0
	if dir.is_equal_approx(Vector2.LEFT): return 180.0
	if dir.is_equal_approx(Vector2.UP): return -90.0
	return 0.0
