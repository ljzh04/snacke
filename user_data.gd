class_name UserData
extends Resource

@export var profiles: Dictionary = {}
@export var leaderboard: Array = []
# The most recently entered profile name, so the profile screen can pre-fill
# the name field on the next visit until the player changes or clears it.
@export var last_profile_name: String = "Guest"
