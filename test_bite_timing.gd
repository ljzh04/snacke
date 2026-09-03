extends SceneTree

# Headless timing test: simulates the game-over transition into the profile
# scene (bite cover -> change scene -> bite_out reveal) and verifies the
# GAME OVER title entrance only becomes visible after bite_out finishes.
func _initialize() -> void:
	_run_test()

func _run_test() -> void:
	var wipe = load("res://Bite_Wipe.tscn").instantiate()
	wipe.name = "BiteWipe"
	root.add_child(wipe)
	var anim: AnimationPlayer = wipe.get_node("AnimationPlayer")
	anim.play("bite")
	await anim.animation_finished
	anim.play("bite_out")
	change_scene_to_file("res://Profile_Screen.tscn")
	var wipe_finish_frame := -1
	var title_shown_frame := -1
	for i in 900:
			await process_frame
			var wipe_now = root.get_node_or_null("BiteWipe")
			if wipe_now == null or not wipe_now.get_node("AnimationPlayer").is_playing():
					if wipe_finish_frame < 0:
							wipe_finish_frame = Engine.get_process_frames()
			var cs := current_scene
			if cs != null and cs.name == "ProfileScreen":
					var title = cs.get_node_or_null("VBoxContainer/TitleRow/TitleLabel")
					if title != null and title.modulate.a > 0.0:
							title_shown_frame = Engine.get_process_frames()
							break
	if title_shown_frame < 0:
			print("FAIL: title never became visible")
	elif wipe_finish_frame < 0 or title_shown_frame < wipe_finish_frame:
			print("FAIL: title entrance (frame %d) started before bite_out finished (frame %d)" % [title_shown_frame, wipe_finish_frame])
	else:
			print("PASS: bite_out finished on frame %d; title entrance started on frame %d" % [wipe_finish_frame, title_shown_frame])
	quit()
