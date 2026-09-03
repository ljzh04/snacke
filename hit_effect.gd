class_name HitEffect
extends Node2D

# One-shot impact effect: a white flash plus a burst of red/purple sparks
# (textures from Kenney's CC0 Particle Pack). Frees itself when done.

const LIFETIME := 1.0

@onready var _flash: Sprite2D = $Flash
@onready var _sparks: CPUParticles2D = $Sparks

func _ready() -> void:
	_sparks.restart()
	_flash.scale = Vector2(0.25, 0.25)
	_flash.modulate = Color(1.0, 1.0, 1.0, 0.9)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_flash, "scale", Vector2(1.4, 1.4), 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_flash, "modulate:a", 0.0, 0.22)
	await get_tree().create_timer(LIFETIME).timeout
	if is_inside_tree():
		queue_free()
