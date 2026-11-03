extends SceneTree
var station: Node
var output := "res://builds/pacing-qa/visual"
func _init() -> void: call_deferred("run")
func capture(label: String) -> void:
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + label + ".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(3)
	station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for path in ["NightEvents", "PassengerDialogueEvents", "TrainService", "PassengerService", "HorrorPacing"]: station.get_node(path).set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	var player = station.get_node("Player")
	player.set_physics_process(false)
	gm.restore_power()
	gm.sign_in()
	station.get_node("NightHUD")._opening_title.hide()
	for actor in station.get_node("PassengerService").actors: actor.set_physics_process(false)
	player.position = Vector3(23.1,0.35,3.5)
	player.camera.make_current()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1080)
	root.content_scale_size = root.size
	await create_timer(1).timeout
	root.size = Vector2i(Vector2(root.size) * Vector2(1920,1080) / root.get_texture().get_size())
	var pacing = station.get_node("HorrorPacing")
	pacing.sighting_chance = 1
	pacing.try_sighting()
	var monitor = station.get_node("StationServices").cctv
	monitor.open_panel()
	monitor.select_feed(2)
	await capture("01-camera-still-figure")
	monitor.close_panel()
	player.position = Vector3(14,0.35,16.2)
	player.camera.look_at(pacing.FIGURE_POINT + Vector3.UP)
	await capture("02-same-position-world-empty")
	player.position = Vector3(23.1,0.35,3.5)
	player.camera.look_at(pacing._archive.global_position)
	await capture("03-archive-on-desk")
	pacing.read_archive()
	await capture("04-archive-text")
	pacing._reader.close_panel()
	gm.start_night(4)
	gm.restore_power()
	gm.sign_in()
	station.get_node("NightHUD")._opening_title.hide()
	for actor in station.get_node("PassengerService").actors: actor.set_physics_process(false)
	pacing.begin_turn()
	player.position = Vector3(-9,0.35,8.5)
	player.camera.look_at(Vector3(-9,1.9,7.2))
	await capture("05-departure-dispatch")
	player.position = Vector3(14,0.35,16.2)
	player.camera.look_at(pacing.FIGURE_POINT + Vector3.UP)
	await capture("06-platform-aftermath")
	gm.night = 7
	gm.campaign["mystery"] = ["archive", "camera", "departure", "note/0"]
	var service = station.get_node("PassengerService")
	service.reviewed = service.total_cases()
	service.correct = service.reviewed
	station.get_node("TrainService").boarded_count = 1
	station.get_node("PassengerEntity").banished = true
	gm.objectives.clear()
	gm.objectives["check_platform"] = {"text":"Patrol", "done":true}
	gm.state = gm.NightState.SHIFT_OVER
	station.get_node("ShiftReport")._show_report()
	await capture("07-ending")
	paused = false
	station.queue_free()
	for i in range(10): await process_frame
	print("PASS: Captured horror pacing visuals")
	quit()
