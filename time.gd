extends Label

@export var game_manager: GameManager

func _ready() -> void:
	if game_manager:
		game_manager.time_updated.connect(_on_time_updated)
		game_manager.level_changed.connect(_on_level_changed)

func _on_time_updated(time_string: String) -> void:
	text = "" + time_string

func _on_level_changed(level: int) -> void:
	# The clock creeps toward danger-red as the snake speeds up.
	var t := clampf(float(level) / 10.0, 0.0, 1.0)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.0, 1.0 - t * 0.7, 1.0 - t * 0.7), 0.5)
