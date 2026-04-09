extends CharacterBody2D

@export var move_delay := 0.2
@export var hold_repeat_delay := 0.08
var tile_size := 32
var dir = Vector2.ZERO
var current_cell: Vector2i = Vector2i.ZERO

@export var game_manager: Node
var min_x := 0.0
var max_x := 800.0
var min_y := 0.0
var max_y := 640.0

# accounting for centered anchor
var half_size := tile_size * 0.5
var is_moving := false
var queued_direction := Vector2.ZERO
var last_input_direction := Vector2.ZERO
var hold_repeat_timer := 0.0
# idea move food behind when passed

@onready var animation_player = $AnimationPlayer

func _ready():
	add_to_group("Player")
	if game_manager:
		var play_area = game_manager.play_area_rect
		min_x = play_area.position.x
		max_x = play_area.end.x
		min_y = play_area.position.y
		max_y = play_area.end.y
		current_cell = game_manager.world_to_grid(global_position)
	call_deferred("_animate_player_spawn")

func _process(_delta):
	if not is_instance_valid(game_manager):
		return

	var input_dir = _get_input_direction()
	if input_dir != Vector2.ZERO:
		queued_direction = input_dir
		if input_dir != last_input_direction:
			hold_repeat_timer = 0.0
		last_input_direction = input_dir
	else:
		last_input_direction = Vector2.ZERO
		queued_direction = Vector2.ZERO

	if hold_repeat_timer > 0.0:
		hold_repeat_timer -= _delta

	if game_manager.is_player_animating:
		return

	if queued_direction == Vector2.ZERO:
		return

	if hold_repeat_timer > 0.0:
		return

	if game_manager.request_player_move(queued_direction):
		dir = queued_direction
		hold_repeat_timer = hold_repeat_delay

	global_position.x = clamp(global_position.x, min_x + half_size, max_x - half_size)
	global_position.y = clamp(global_position.y, min_y + half_size, max_y - half_size)

func _get_input_direction() -> Vector2:
	if Input.is_action_pressed("ui_up"):
		return Vector2(0, -1)
	if Input.is_action_pressed("ui_down"):
		return Vector2(0, 1)
	if Input.is_action_pressed("ui_left"):
		return Vector2(-1, 0)
	if Input.is_action_pressed("ui_right"):
		return Vector2(1, 0)
	return Vector2.ZERO

func _move(_direction: Vector2):
	# Movement is handled by GameManager to keep logic in the matrix layer.
	pass

func _animate_player_spawn():
	var anim_sprite = get_node("AnimatedSprite2D") as AnimatedSprite2D
	anim_sprite.play("player_wake_up")
	await anim_sprite.animation_finished
	anim_sprite.play("player_idle")

func play_surprise_animation():
	animation_player.play("player_dead")

func disable_input():
	set_process(false)
