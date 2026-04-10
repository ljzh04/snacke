extends CharacterBody2D

@export var move_delay := 0.05
var tile_size := 32
var current_cell: Vector2i = Vector2i.ZERO

@export var game_manager: Node
var min_x := 0.0
var max_x := 800.0
var min_y := 0.0
var max_y := 640.0

var half_size := tile_size * 0.5
var move_timer := 0.0
@onready var animation_player = $AnimationPlayer

func _ready():
	add_to_group("Player")
	if game_manager:
		var play_area = game_manager.play_area_rect
		min_x = play_area.position.x
		max_x = play_area.end.x
		min_y = play_area.position.y
		max_y = play_area.end.y
		current_cell = game_manager.grid.world_to_grid(global_position)
	call_deferred("_animate_player_spawn")

func _process(_delta: float) -> void:
	if not is_instance_valid(game_manager) or game_manager.is_game_over:
		return

	var mouse_pos = get_global_mouse_position()
	var target_cell = game_manager.grid.world_to_grid(mouse_pos)
	
	# Attempt multiple moves per frame until we reach the mouse or hit a wall/snake
	var max_steps_per_frame = 10 
	for i in range(max_steps_per_frame):
		if game_manager.is_game_over:
			break
			
		if target_cell == current_cell:
			break
			
		if game_manager.grid.is_cell_inside(target_cell):
			if game_manager.request_player_move_to(target_cell):
				current_cell = game_manager.player_cell # Sync with manager
			else:
				break # Hit a wall or snake
		else:
			break

	global_position.x = clamp(global_position.x, min_x + half_size, max_x - half_size)
	global_position.y = clamp(global_position.y, min_y + half_size, max_y - half_size)

func _animate_player_spawn():
	var anim_sprite = get_node("AnimatedSprite2D") as AnimatedSprite2D
	anim_sprite.play("player_wake_up")
	await anim_sprite.animation_finished
	anim_sprite.play("player_idle")

func play_surprise_animation():
	animation_player.play("player_dead")

func disable_input():
	set_process(false)
