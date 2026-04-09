extends Control

@onready var name_edit: LineEdit = $VBoxContainer/LineEdit
@onready var play_button: Button = $VBoxContainer/Button

# main menu gui plan -> main centered buttons(1 player, 2 player), settings top right. profile selector top left, copyright + version bottom right

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)

func _on_play_pressed() -> void:
	var profile_name = name_edit.text
	
	# If the name is empty, default to "Guest"
	if profile_name.is_empty():
		profile_name = "Guest"
	
	# Set the current profile in our global state
	GlobalState.current_profile_name = profile_name
	
	# Ensure the profile exists in our data file
	GlobalState.update_high_score(profile_name, 0, 0)
	
	# Change to the main game scene
	get_tree().change_scene_to_file("res://Main.tscn")
