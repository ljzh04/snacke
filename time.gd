extends Label

@export var game_manager: Node

func _ready() -> void:
	if game_manager:
		game_manager.time_updated.connect(_on_time_updated)

func _on_time_updated(time_string: String) -> void:
	text = "Time: " + time_string
