# ScoreUI.gd

extends Label

@export var game_manager: GameManager

var high_score = 0
var _last_score := 0

func _ready() -> void:
	if game_manager:
		game_manager.score_updated.connect(_on_score_updated)
	
	# Get the high score for the current player
	high_score = GlobalState.get_high_score(GlobalState.current_profile_name)
	# Update the text with the initial score
	_on_score_updated(0) 

func _on_score_updated(new_score: int) -> void:
	text = "%d" % [new_score]
	if new_score <= _last_score:
		_last_score = new_score
		return
	_last_score = new_score
	# Score punch: bump the label's scale, easing back from its center.
	pivot_offset = size / 2.0
	scale = Vector2(1.18, 1.18)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
