extends SceneTree
var station: Node
var output := "res://builds/dinner-qa/visual"
func _init() -> void: call_deferred("run")
func capture(label: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + label + ".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var service = station.get_node("PassengerService")
	service.pre_ticket_routines_enabled = false
	for path in ["NightEvents", "PassengerDialogueEvents", "TrainService", "PassengerService"]: station.get_node(path).set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	var player = station.get_node("Player")
	player.set_physics_process(false)
	gm.restore_power()
	gm.sign_in()
	for actor in service.actors: actor.set_physics_process(false)
	var actor = service.actors[0]
	actor.position = Vector3(-5.85,0.35,4)
	actor.phase = "COUNTER"
	service._on_counter_ready(actor)
	player.position = Vector3(-9.3,0.35,3.2)
	service.open_desk()
	player.camera.make_current()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1080)
	root.content_scale_size = root.size
	await create_timer(1).timeout
	root.size = Vector2i(Vector2(root.size) * Vector2(1920,1080) / root.get_texture().get_size())
	var desk = station.get_node("BoothDesk")
	player.camera.look_at(desk.documents.ticket.body.global_position)
	await capture("01-desk-lesson")
	desk.pick_up("passport")
	await capture("02-document-lesson")
	desk.put_down()
	desk.verify_record()
	await capture("03-computer-lesson")
	desk.exit_computer(true)
	service.ui.close_desk()
	station.get_node("StationJobs").open_journal()
	await capture("04-journal")
	station.get_node("StationJobs").journal.close_panel()
	service.reviewed = service.total_cases()
	service.correct = 0
	gm._process(0.3)
	await capture("05-retry-report")
	var report = station.get_node("ShiftReport")
	print("REPORT ROOT: ", report._root.get_global_rect())
	for button in report.find_children("*", "Button", true, false):
		if button.visible: print("REPORT BUTTON: ", button.text, " ", button.get_global_rect())
	paused = false
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(10): await process_frame
	OS.delay_msec(100)
	print("PASS: Captured physical booth teaching, journal and retry report")
	quit()
