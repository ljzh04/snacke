class_name ButtonJuice
extends RefCounted

## Shared hover/press/idle animation "juice" for themed buttons, extracted
## from the title screen so every menu (title, pause modal, ...) feels
## identical. Attach once per button; each call wires the four mouse/press
## reactions and optionally starts the gentle idle brightness pulse.

static func attach(button: Button, idle_pulse := true) -> void:
	button.mouse_entered.connect(_on_hover.bind(button))
	button.mouse_exited.connect(_on_unhover.bind(button))
	button.button_down.connect(_on_down.bind(button))
	button.button_up.connect(_on_up.bind(button))
	if idle_pulse:
		# Subtle looping brightness breath, exactly like the title screen.
		var tween := button.create_tween()
		tween.set_loops()
		tween.tween_property(button, "modulate:v", 0.9, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(button, "modulate:v", 1.0, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

static func _on_hover(button: Button) -> void:
	button.modulate.v = 1.15

static func _on_unhover(button: Button) -> void:
	button.modulate.v = 1.0

static func _on_down(button: Button) -> void:
	button.pivot_offset = button.size / 2.0
	var tw := button.create_tween()
	tw.tween_property(button, "scale", Vector2(0.92, 0.92), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func _on_up(button: Button) -> void:
	var tw := button.create_tween()
	tw.tween_property(button, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
