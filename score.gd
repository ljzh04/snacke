# ScoreUI.gd

extends Label

@export var game_manager: Node

var high_score = 0

func _ready() -> void:
	if game_manager:
		game_manager.score_updated.connect(_on_score_updated)
	
	# Get the high score for the current player
	high_score = GlobalState.get_high_score(GlobalState.current_profile_name)
	# Update the text with the initial score
	_on_score_updated(0) 

func _on_score_updated(new_score: int) -> void:
	text = "Score: %d" % [new_score]
