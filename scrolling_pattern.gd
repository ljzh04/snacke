@tool
extends ColorRect
class_name ScrollingPattern

# @tool + setter-driven _apply_params() keeps the shader preview live in the
# editor: add this node to a scene and tune the exports in the Inspector.

enum DiagonalDirection { LEFT, RIGHT }
enum ShapeType { CIRCLE, SQUARE, TRIANGLE, STAR, DIAMOND }

@export var density: float = 0.15:
	set(value):
		density = value
		_apply_params()

@export var base_scroll_speed: float = 0.05:
	set(value):
		base_scroll_speed = value
		_apply_params()

@export var diagonal_direction: DiagonalDirection = DiagonalDirection.RIGHT:
	set(value):
		diagonal_direction = value
		_apply_params()

@export var background_color: Color = Color(0.15, 0.15, 0.30, 0.18):
	set(value):
		background_color = value
		_apply_params()

@export var shape_color: Color = Color(0.75, 0.75, 0.95, 0.45):
	set(value):
		shape_color = value
		_apply_params()

@export var shape_size: float = 0.14:
	set(value):
		shape_size = value
		_apply_params()

@export var shape_type: ShapeType = ShapeType.CIRCLE:
	set(value):
		shape_type = value
		_apply_params()

@export var use_pattern: bool = true:
	set(value):
		use_pattern = value
		_apply_params()

@export var pattern_seed: float = 0.0:
	set(value):
		pattern_seed = value
		_apply_params()

# When true, negates the vertical scroll component (layers can move in
# fully opposite diagonals, e.g. down-right vs. up-left).
@export var invert_y: bool = false:
	set(value):
		invert_y = value
		_apply_params()


func _ready() -> void:
	var mat := material as ShaderMaterial
	if not mat:
		mat = ShaderMaterial.new()
		mat.shader = load("res://shaders/scrolling_pattern.gdshader")
		material = mat
	_apply_params()


func _apply_params() -> void:
	var mat := material as ShaderMaterial
	if not mat:
		return

	var dir: Vector2
	if diagonal_direction == DiagonalDirection.LEFT:
		dir = Vector2(-1.0, 1.0)
	else:
		dir = Vector2(1.0, 1.0)
	if invert_y:
		dir.y = -dir.y

	var scroll_vec := dir * base_scroll_speed

	mat.set_shader_parameter("density", density)
	mat.set_shader_parameter("scroll_direction", scroll_vec)
	mat.set_shader_parameter("background_color", background_color)
	mat.set_shader_parameter("shape_color", shape_color)
	mat.set_shader_parameter("shape_size", shape_size)
	mat.set_shader_parameter("shape_type", shape_type)
	mat.set_shader_parameter("use_pattern", use_pattern)
	mat.set_shader_parameter("pattern_seed", pattern_seed)


func randomize_diagonal() -> void:
	diagonal_direction = DiagonalDirection.values()[randi() % DiagonalDirection.size()]
	_apply_params()


func reversed_direction() -> DiagonalDirection:
	if diagonal_direction == DiagonalDirection.LEFT:
		return DiagonalDirection.RIGHT
	return DiagonalDirection.LEFT
