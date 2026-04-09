extends CharacterBody2D

@export var move_delay := 0.2
var tile_size := 32
var dir = Vector2.ZERO

@export var game_manager: Node
var min_x := 0.0
var max_x := 800.0
var min_y := 0.0
var max_y := 640.0

# accounting for centered anchor
var half_size := tile_size / 2
var is_moving := false
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
	call_deferred("_animate_player_spawn")

func _process(delta):
	if is_moving:
		return
	
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("ui_up"): input_dir = Vector2(0, -1)
	elif Input.is_action_pressed("ui_down"): input_dir = Vector2(0, 1)
	elif Input.is_action_pressed("ui_left"): input_dir = Vector2(-1, 0)
	elif Input.is_action_pressed("ui_right"): input_dir = Vector2(1, 0)
	
	if input_dir != Vector2.ZERO:
		dir = input_dir
		_move(dir)
	
	global_position.x = clamp(global_position.x, min_x + half_size, max_x - half_size)
	global_position.y = clamp(global_position.y, min_y + half_size, max_y - half_size)

func _move(direction: Vector2):
	var target_position = global_position + direction * tile_size
	target_position.x = clamp(target_position.x, min_x + half_size, max_x - half_size)
	target_position.y = clamp(target_position.y, min_y + half_size, max_y - half_size)
	
	if global_position.is_equal_approx(target_position):
		return
	
	is_moving = true
	var tween = create_tween()
	tween.tween_property(self, "global_position", target_position,move_delay).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	await tween.finished
	is_moving = false

func _animate_player_spawn():
	var anim_sprite = get_node("AnimatedSprite2D") as AnimatedSprite2D
	anim_sprite.play("player_wake_up")
	await anim_sprite.animation_finished
	anim_sprite.play("player_idle")

func play_surprise_animation():
	animation_player.play("player_dead")

func disable_input():
	set_process(false)
