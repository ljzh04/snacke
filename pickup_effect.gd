class_name PickUpEffect
extends Node2D

# One-shot pickup effect: a soft glow that pops outward plus a drift of
# gold/purple star sparkles (textures from Kenney's CC0 Particle Pack).
# Frees itself when done.

const LIFETIME := 0.9

@onready var _glow: Sprite2D = $Glow
@onready var _sparkles: CPUParticles2D = $Sparkles

func _ready() -> void:
	_sparkles.restart()
	_glow.scale = Vector2(0.15, 0.15)
	_glow.modulate = Color(1.0, 0.95, 0.6, 0.9)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_glow, "scale", Vector2(1.0, 1.0), 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_glow, "modulate:a", 0.0, 0.25)
	await get_tree().create_timer(LIFETIME).timeout
	if is_inside_tree():
		queue_free()
