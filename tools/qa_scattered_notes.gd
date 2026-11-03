extends SceneTree

func _init() -> void: call_deferred("run")

func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	gm.turn_on_power()
	for path in ["NightEvents", "PassengerDialogueEvents", "TrainService", "PassengerService"]:
		station.get_node(path).set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	station.get_node("Player").set_physics_process(false)
	for actor in station.get_node("PassengerService").actors: actor.set_physics_process(false)
	station.get_node("NightHUD").hide()
	var camera := Camera3D.new()
	station.add_child(camera)
	camera.make_current()
	# A close-range inspection light stands in for the player's flashlight.
	var light := OmniLight3D.new()
	light.omni_range = 3.0
	light.light_energy = 0.65
	light.shadow_enabled = false
	camera.add_child(light)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	await create_timer(0.5).timeout
	root.size = Vector2i(Vector2(root.size) * Vector2(1280, 720) / root.get_texture().get_size())
	var jobs = station.get_node("StationJobs")
	var output := "res://builds/scattered-notes-qa"
	DirAccess.make_dir_recursive_absolute(output)
	for night in range(1, 8):
		jobs._new_night(night)
		gm.restore_power()
		for note in jobs.scattered_notes.get_children():
			camera.position = note.global_position + Vector3(0.35, 1.05, 0.65)
			if night == 4: camera.position = note.global_position + Vector3(0.9, 1.05, 0.2)
			if note.get_meta("note_id") == 3: camera.position = note.global_position + Vector3(-0.8, 1.05, 0.1)
			camera.look_at(note.global_position)
			await create_timer(0.15).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output + "/world-%02d.png" % int(note.get_meta("note_id")))
			if night == 3:
				note.get_node("Interaction").interact()
				await create_timer(0.2).timeout
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output + "/reader-%02d.png" % int(note.get_meta("note_id")))
				jobs.entity_letter.close_panel()
	print("PASS: Rendered all ten nightly note placements and variant readers")
	station.queue_free()
	await process_frame
	quit()
