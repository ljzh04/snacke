extends Node

enum SFX {
	CLICK,
	FOOD_EATEN,
	LEVEL_UP,
	GAME_OVER,
	POWERUP,
	HIT,
}

enum Music {
	MENU,
	GAMEPLAY,
	PROFILE,
}

const POOL_SIZE := 8

var _sfx_paths: Dictionary = {
	SFX.CLICK: "res://assets/sounds/sfx/sfx_click.ogg",
	SFX.FOOD_EATEN: "res://assets/sounds/sfx/sfx_food_eaten.ogg",
	SFX.LEVEL_UP: "res://assets/sounds/sfx/sfx_level_up.ogg",
	SFX.GAME_OVER: "res://assets/sounds/sfx/sfx_game_over.ogg",
	SFX.POWERUP: "res://assets/sounds/sfx/sfx_powerup.ogg",
	SFX.HIT: "res://assets/sounds/sfx/sfx_hit.ogg",
}

var _music_paths: Dictionary = {
	Music.MENU: "res://assets/sounds/music/music_menu.ogg",
	Music.GAMEPLAY: "res://assets/sounds/music/music_gameplay.ogg",
	Music.PROFILE: "res://assets/sounds/music/music_profile.ogg",
}

var _pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _music_player: AudioStreamPlayer
var _music_streams: Dictionary = {}

func _ready() -> void:
	# Keep audio alive while the tree is paused so pause-menu clicks (and
	# music) still play; the autoload would otherwise inherit PAUSABLE and
	# go silent the moment the pause modal opens.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	for id in _sfx_paths:
		if ResourceLoader.exists(_sfx_paths[id]):
			_streams[id] = load(_sfx_paths[id])
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)

func play(sfx: SFX, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not _streams.has(sfx):
		return
	var player := _get_available_player()
	player.stream = _streams[sfx]
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()

func play_music(music: Music, volume_db: float = 0.0) -> void:
	if not _music_paths.has(music):
		return
	if not _music_streams.has(music):
		var stream = load(_music_paths[music])
		stream.loop = true
		_music_streams[music] = stream
	if _music_player.playing and _music_player.stream == _music_streams[music]:
		return
	_music_player.stream = _music_streams[music]
	_music_player.volume_db = volume_db
	_music_player.play()

func stop_music(fade_out: float = 0.0) -> void:
	if fade_out <= 0.0:
		_music_player.stop()
		return
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -60.0, fade_out)
	tw.tween_callback(_music_player.stop)
	tw.tween_callback(func(): _music_player.volume_db = 0.0)

func _get_available_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[0]

func play_music_after_transitions(music: Music, volume_db: float = 0.0) -> void:
	# Start a music track only after any incoming bite-wipe has finished
	# revealing the new scene, so the track swap isn't heard mid-transition.
	# The wipe's AnimationPlayer is guaranteed to be mid-"bite_out" by the
	# time the new scene's _ready runs (change_scene_to_file is deferred),
	# so waiting for its animation_finished lands right on the reveal.
	await get_tree().process_frame
	var bite = get_tree().get_root().get_node_or_null("BiteWipe")
	if is_instance_valid(bite):
		var bite_anim := bite.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if bite_anim and bite_anim.is_playing():
			await bite_anim.animation_finished
	play_music(music, volume_db)
