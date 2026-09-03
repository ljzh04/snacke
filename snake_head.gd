extends Area2D

signal moved(destination, move_duration)
signal snake_trapped()

@onready var sprite = $AnimatedSprite2D

@export var speed := 0.08
@export var tile_size := 32
@export var player: Node2D
@export var game_manager: GameManager

@export_group("Pathing Biases")
@export var pathing_lookahead_cells := 120
@export var pathing_randomness := 0.05

# When the player is within this many cells of the snake's head, the snake
# switches to interception targeting (aiming at the player's predicted next
# cell) to prevent the player from cheesing it by orbiting forever.
const INTERCEPT_RADIUS := 4

# ---------------------------------------------------------------------------
# Untrappable AI tuning
# ---------------------------------------------------------------------------
# Minimum free cells the snake must be able to reach after a move before it
# will commit to a chase step. This is the "breathing room" that keeps the
# snake out of razor-thin corridors where it could box itself in over the
# next few moves. Higher = safer but slightly less aggressive.
const MIN_SAFE_AREA := 8
# How many cells of free space the snake considers "plenty" — beyond this,
# extra space no longer increases its willingness to chase.
const MAX_SAFE_AREA := 40
# Aggression floor/ceiling. The floor keeps the snake from ever going fully
# passive (tension retention); the ceiling stops it from being suicidally
# reckless even when tiny.
const AGGRESSION_FLOOR := 0.25
const AGGRESSION_CEILING := 0.95
# How strongly length reduces aggression (longer snake = more cautious).
const LENGTH_AGGRESSION_WEIGHT := 0.5
# How strongly free-space pressure reduces aggression.
const SPACE_AGGRESSION_WEIGHT := 0.35
# How strongly proximity to the target raises aggression (a near kill is
# worth committing to).
const PROXIMITY_AGGRESSION_WEIGHT := 0.4
# The snake re-commits to chasing whenever the target drifts beyond this
# many cells, so it never lets the player wander off and relax.
const PRESSURE_RADIUS := 10
# While the snake is growing (tail frozen for `grow_pending` moves), it must
# keep an escape route open for the ENTIRE growth window, not just the next
# move. This prevents consecutive food pickups from funneling the snake into
# a region where the frozen tail eventually blocks the only exit.
const GROWTH_SAFETY_MARGIN := 2
# How much growth reduces aggression (a growing snake is more vulnerable to
# self-trapping, so it should back off the chase while it's extending).
const GROWTH_AGGRESSION_PENALTY := 0.35

var move_timer := 0.0
var last_dir := Vector2.ZERO
var previous_positions: Array[Vector2i] = []

func _ready() -> void:
	add_to_group("SnakeHead")
	
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
		# No safe move exists — the snake would be trapped. Instead of losing,
		# it bites its own body: it moves into an adjacent body cell and the
		# game manager cuts every segment from that contact point to the tail.
		# This frees up space so the snake can keep chasing.
		dir = _get_self_bite_direction()
		if dir == Vector2.ZERO:
			emit_signal("snake_trapped")
			set_process(false)
			return
	
	var head_cell = game_manager.grid.world_to_grid(global_position)
	var next_cell = head_cell + Vector2i(int(dir.x), int(dir.y))
	if not game_manager.grid.is_cell_inside(next_cell):
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
		return player if player_dist <= min_dist * 0.8 else closest_food
	
	return player

# Anti-cheese: when the player is close, aim at where they are HEADING (their
# predicted next cell) instead of their current cell. This cuts across a tight
# orbit instead of chasing the player's tail, so the player can't cheese the
# snake by rotating around it forever.
func _get_interception_target() -> Vector2i:
	if not is_instance_valid(player):
		return Vector2i(-1, -1)
	var player_cell = game_manager.grid.world_to_grid(player.global_position)
	var mouse_cell = game_manager.grid.world_to_grid(get_global_mouse_position())
	var move_dir = Vector2i(clamp(mouse_cell.x - player_cell.x, -1, 1), clamp(mouse_cell.y - player_cell.y, -1, 1))
	# Only intercept if the player is actually moving (not standing still).
	if move_dir == Vector2i.ZERO:
		return player_cell
	var predicted = player_cell + move_dir
	if game_manager.grid.is_cell_inside(predicted):
		return predicted
	return player_cell

# ---------------------------------------------------------------------------
# Adaptive aggression
# ---------------------------------------------------------------------------
# Returns 0..1 describing how hard the snake should commit to chasing the
# target right now. High = follow the chase path greedily. Low = prioritize
# preserving open space (survival) while still drifting toward the target.
func _compute_aggression(head_grid: Vector2i, target_grid: Vector2i) -> float:
	var total_cells := game_manager.grid.columns * game_manager.grid.rows
	var body_len := previous_positions.size()

	# 1) Length pressure: a longer snake is more likely to trap itself, so it
	#    should be more cautious. Normalize by board size.
	var length_frac := clampf(float(body_len) / float(max(total_cells, 1)), 0.0, 1.0)
	var length_aggression := 1.0 - length_frac

	# 2) Space pressure: how much free room does the snake currently have?
	#    Less free room => more cautious.
	var free_area := _reachable_area_virtual(head_grid, _get_virtual_positions(head_grid))
	var space_frac := clampf(float(free_area) / float(MAX_SAFE_AREA), 0.0, 1.0)
	var space_aggression := space_frac

	# 3) Proximity pressure: a close target is a near-kill, worth committing
	#    to. This is what keeps the snake sharp and prevents it from drifting
	#    away from a player that's right next to it.
	var dist := Vector2(target_grid - head_grid).length()
	var proximity_aggression := clampf(1.0 - dist / float(PRESSURE_RADIUS), 0.0, 1.0)

	# Blend the three pressures. Length and space pull toward caution;
	# proximity pulls toward commitment.
	var weight_sum := LENGTH_AGGRESSION_WEIGHT + SPACE_AGGRESSION_WEIGHT + PROXIMITY_AGGRESSION_WEIGHT
	var weighted := (length_aggression * LENGTH_AGGRESSION_WEIGHT + space_aggression * SPACE_AGGRESSION_WEIGHT + proximity_aggression * PROXIMITY_AGGRESSION_WEIGHT) / weight_sum
	var aggression := AGGRESSION_FLOOR + (1.0 - AGGRESSION_FLOOR) * weighted

	# 4) Growth penalty: while the snake is growing, its tail is frozen for
	#    several moves, so it's more vulnerable to self-trapping. Back off the
	#    chase proportionally to how many growth moves remain. This is what
	#    keeps consecutive food pickups from luring the snake into a trap.
	if is_instance_valid(game_manager) and game_manager.grow_pending > 0:
		var growth_frac := clampf(float(game_manager.grow_pending) / float(GROWTH_SAFETY_MARGIN), 0.0, 1.0)
		aggression -= GROWTH_AGGRESSION_PENALTY * growth_frac

	return clampf(aggression, AGGRESSION_FLOOR, AGGRESSION_CEILING)

func _get_perfect_direction(target: Node2D) -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO

	var head_grid = game_manager.grid.world_to_grid(global_position)
	var target_grid = game_manager.grid.world_to_grid(target.global_position)

	# When the player is close, intercept their predicted next cell instead of
	# their current cell, so orbiting can't keep the snake chasing its tail.
	var player_cell = game_manager.grid.world_to_grid(player.global_position)
	var head_to_player = Vector2(player_cell - head_grid).length()
	if head_to_player <= INTERCEPT_RADIUS:
		var intercept = _get_interception_target()
		if intercept != Vector2i(-1, -1):
			target_grid = intercept

	# Decide how hard to commit to the chase this tick.
	var aggression := _compute_aggression(head_grid, target_grid)

	# --- Tier 1: try the direct chase path, but only if it stays safe. ---
	var path = _find_astar_path(head_grid, target_grid)
	if not path.is_empty() and path.size() > 1:
		var next_step = path[1]
		var dir = Vector2(next_step - head_grid)
		if not _is_reverse_direction(dir):
			var area_after = _reachable_area_virtual(next_step, _get_virtual_positions(next_step))
			# Commit to the chase only if the move keeps enough breathing room
			# (scaled by aggression: more aggressive = willing to accept a
			# tighter squeeze for a near kill).
			var min_area = int(lerpf(MIN_SAFE_AREA, 0.0, aggression))
			if area_after >= min_area and _can_reach_tail_after_move(next_step) \
					and _can_survive_growth_window(next_step):
				return dir

	# --- Tier 2: survival-biased move. Pick the neighbor that best balances
	#     staying safe AND drifting toward the target. ---
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	neighbors.shuffle()

	var best_dir := Vector2.ZERO
	var best_score := -INF

	for n_dir in neighbors:
		var neighbor = head_grid + n_dir
		if not game_manager.grid.is_cell_inside(neighbor): continue
		if _is_cell_occupied(neighbor): continue
		if _is_reverse_direction(Vector2(n_dir)): continue
		if not _can_reach_tail_after_move(neighbor): continue

		var area = _reachable_area_virtual(neighbor, _get_virtual_positions(neighbor))
		# Score = how much open space this move preserves, plus a small
		# attraction toward the target so the snake keeps pressure on even
		# while playing safe. The attraction term is scaled by aggression.
		var toward_target := -Vector2(neighbor - target_grid).length()
		var score := float(area) + aggression * toward_target * 0.5
		if score > best_score:
			best_score = score
			best_dir = Vector2(n_dir)

	if best_dir != Vector2.ZERO:
		return best_dir

	# --- Tier 3: last resort. Any legal move that keeps us alive, even if it
	#     sacrifices open space. Prefer the one with the most room. ---
	var last_resort_dir = Vector2.ZERO
	var last_resort_max_area = -1
	for n_dir in neighbors:
		var neighbor = head_grid + n_dir
		if not game_manager.grid.is_cell_inside(neighbor): continue
		if _is_cell_occupied(neighbor): continue
		if _is_reverse_direction(Vector2(n_dir)): continue
		var area = _reachable_area_virtual(neighbor, _get_virtual_positions(neighbor))
		if area > last_resort_max_area:
			last_resort_max_area = area
			last_resort_dir = Vector2(n_dir)
			
	return last_resort_dir

func _is_reverse_direction(dir: Vector2) -> bool:
	if last_dir == Vector2.ZERO:
		return false
	return dir.is_equal_approx(-last_dir)

func _find_astar_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, game_manager.grid.columns, game_manager.grid.rows)
	astar.cell_size = Vector2(1, 1)
	# Only allow cardinal (orthogonal) movement, never diagonals.
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	
	for pos in previous_positions:
		if pos != start and pos != end and astar.is_in_boundsv(pos):
			astar.set_point_solid(pos, true)
	
	return astar.get_id_path(start, end)

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

# Multi-move safety check used while the snake is growing. When the snake is
# growing, its tail is frozen for `grow_pending` moves, so the escape route is
# constrained for several moves — not just the next one. This simulates the
# snake's body staying put for the whole growth window and verifies the head
# can still reach the (frozen) tail after every one of those moves. If the
# route would close off mid-growth, the move is rejected so the snake can't be
# funneled into a trap by consecutive food pickups.
func _can_survive_growth_window(next_head: Vector2i) -> bool:
	if not is_instance_valid(game_manager) or game_manager.grow_pending <= 0:
		return true

	# Simulate the body staying frozen for the entire growth window. Each
	# simulated move keeps the tail in place (no pop), so the occupied set
	# only ever grows by the new head cells.
	var occupied: Array[Vector2i] = previous_positions.duplicate()

	var head := next_head
	var tail: Vector2i = previous_positions.back()
	var remaining := game_manager.grow_pending

	# Walk the head forward for `remaining` moves, keeping the tail frozen,
	# and confirm the head can always reach the tail at every step. If the
	# route would close off mid-growth, reject the move so consecutive food
	# pickups can't funnel the snake into a trap.
	while remaining > 0:
		if not _path_exists_virtual(head, tail, occupied):
			return false
		# Advance the head one step that keeps the escape route open. We just
		# need to confirm a route exists at each step, so pick any neighbor
		# that preserves it.
		var advanced := false
		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nxt: Vector2i = head + dir
			if not game_manager.grid.is_cell_inside(nxt): continue
			if _is_cell_in_array(occupied, nxt): continue
			if _path_exists_virtual(nxt, tail, occupied):
				occupied.append(nxt)
				head = nxt
				advanced = true
				break
		if not advanced:
			return false
		remaining -= 1

	return _path_exists_virtual(head, tail, occupied)

func _is_cell_in_array(arr: Array[Vector2i], cell: Vector2i) -> bool:
	for p in arr:
		if p == cell:
			return true
	return false

func _path_exists_virtual(start: Vector2i, end: Vector2i, occupied: Array[Vector2i]) -> bool:
	var queue = [start]
	var visited = {start: true}
	var occupied_set = {}
	for p in occupied: occupied_set[p] = true
	occupied_set.erase(end)

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

func _is_cell_occupied(cell: Vector2i) -> bool:
	for p in previous_positions:
		if p == cell: return true
	return false

# Returns the index of `cell` in `previous_positions`, or -1 if it is not a
# body cell. Index 0 is the head; larger indices are closer to the tail.
func _body_index_at(cell: Vector2i) -> int:
	for i in range(previous_positions.size()):
		if previous_positions[i] == cell:
			return i
	return -1

# When the snake has no safe move (it would otherwise be trapped), it bites
# its own body. This picks an adjacent body cell to bite into, preferring the
# one closest to the tail so the fewest segments are cut off. Returns ZERO if
# there is no legal body cell to bite (the snake is genuinely stuck).
func _get_self_bite_direction() -> Vector2:
	var head_grid = game_manager.grid.world_to_grid(global_position)
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var best_dir := Vector2.ZERO
	var best_index := -1
	for n_dir in neighbors:
		var neighbor = head_grid + n_dir
		if not game_manager.grid.is_cell_inside(neighbor): continue
		if _is_reverse_direction(Vector2(n_dir)): continue
		var idx := _body_index_at(neighbor)
		# Only bite a body cell that is NOT the head's own current cell, and
		# prefer the largest index (closest to the tail = least damage).
		if idx > best_index:
			best_index = idx
			best_dir = Vector2(n_dir)
	return best_dir
