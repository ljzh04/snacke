class_name EatEffect
extends Node2D

# One-shot food-eaten effect: a small warm pop plus a burst of crumb
# sparkles (textures from Kenney's CC0 Particle Pack). Frees itself when done.

const LIFETIME := 0.6

@onready var _pop: Sprite2D = $Pop
@onready var _crumbs: CPUParticles2D = $Crumbs

func _ready() -> void:
	_crumbs.restart()
	_pop.scale = Vector2(0.1, 0.1)
	_pop.modulate = Color(1.0, 0.8, 0.6, 0.9)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_pop, "scale", Vector2(0.3, 0.3), 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_pop, "modulate:a", 0.0, 0.18)
	await get_tree().create_timer(LIFETIME).timeout
	if is_inside_tree():
		queue_free()
