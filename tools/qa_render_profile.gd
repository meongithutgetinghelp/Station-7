extends SceneTree
## Repeatable rendered samples; never use --headless or --fixed-fps for FPS data.
var station: Node
var player: Node
var service: Node
var train: Node
var results: Array = []
var output := "res://builds/qa-2026-11-02/render-before.json"
var sample_seconds := 6.0
var target_pixels := Vector2i(1920, 1080)
var render_scale := 1.0
var stress_only := false
var trials := 3
var early_mess := false

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output = argument.trim_prefix("--report=")
		elif argument == "--stress-only": stress_only = true
		elif argument == "--early-mess": early_mess = true
		elif argument.begins_with("--seconds="): sample_seconds = clampf(float(argument.trim_prefix("--seconds=")), 6, 120)
		elif argument.begins_with("--trials="): trials = clampi(int(argument.trim_prefix("--trials=")), 1, 10)
		elif argument.begins_with("--scale="): render_scale = float(argument.trim_prefix("--scale="))
		elif argument.begins_with("--pixels="):
			var parts := argument.trim_prefix("--pixels=").split("x")
			target_pixels = Vector2i(int(parts[0]), int(parts[1]))
	call_deferred("run")

func view(at: Vector3, target: Vector3) -> void:
	player.global_position = at
	player.camera.look_at(target)
	player.camera.make_current()

func sample(label: String, animate_doors: bool = false, walk_crowd: bool = false) -> void:
	await create_timer(1.5).timeout
	var times: Array[float] = []
	var draws := 0.0
	var cpu := 0.0
	var physics := 0.0
	var memory_start := OS.get_static_memory_usage()
	var previous := Time.get_ticks_usec()
	var start := previous
	var toggled := 0
	var jobs = station.get_node("StationJobs")
	var last_messes: int = jobs._messes.size()
	var world_events: Array = []
	var forced_mess := false
	while (Time.get_ticks_usec() - start) / 1000000.0 < sample_seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - previous) / 1000.0)
		previous = now
		if early_mess and not forced_mess and (now - start) / 1000000.0 > 18.5:
			forced_mess = true
			jobs._spawn_mess(2)
			jobs._update_cleanliness()
		if jobs._messes.size() != last_messes:
			last_messes = jobs._messes.size()
			var visible_messes: Array = []
			for id in jobs._messes:
				visible_messes.append({"id":id,"in_frustum":player.camera.is_position_in_frustum(jobs._messes[id].global_position)})
			var event := {"event":"mess_spawn", "sample_seconds":(now-start)/1000000.0, "frame_ms":times.back(), "count":last_messes,"meshes":visible_messes}
			world_events.append(event)
			print(JSON.stringify(event))
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		cpu += Performance.get_monitor(Performance.TIME_PROCESS) * 1000
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000
		var interval := int((now - start) / 1500000)
		if animate_doors and interval != toggled:
			toggled = interval
			train._set_doors(interval % 2 == 1)
			if walk_crowd:
				for index in range(service.actors.size()):
					var actor = service.actors[index]
					actor.phase = "ACTIVITY"
					actor._navigate_to(Vector3(-12 + (index % 8)*3.0 + (0.6 if interval % 2 == 0 else -0.6), 0.35, 14 + int(index/8)*0.7))
	var ordered := times.duplicate()
	ordered.sort()
	var total := 0.0
	var hitches := 0
	for ms in times:
		total += ms
		if ms > 50: hitches += 1
	var frame_count := times.size()
	var pixels := root.get_texture().get_size()
	var record := {"scenario": label, "renderer": RenderingServer.get_current_rendering_method(), "pixels": [int(pixels.x), int(pixels.y)], "render_scale": root.scaling_3d_scale, "frames": frame_count, "fps": frame_count * 1000.0 / total, "median_ms": ordered[frame_count/2], "p95_ms": ordered[mini(frame_count-1, int(frame_count*0.95))], "p99_ms": ordered[mini(frame_count-1, int(frame_count*0.99))], "hitches_over_50ms": hitches, "mean_draw_calls": draws/frame_count, "mean_cpu_process_ms": cpu/frame_count, "mean_physics_ms": physics/frame_count, "memory_start_bytes": memory_start, "memory_end_bytes": OS.get_static_memory_usage(), "trace_ms": times}
	results.append(record)
	record["world_events"] = world_events
	var summary := record.duplicate()
	summary.erase("trace_ms")
	print(JSON.stringify(summary))
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"engine": Engine.get_version_info().string, "scope": "Single local rendered instance on Apple M1 Pro; uncapped, VSync off; %d passenger fixtures; %.0f-second samples after warm-up; not a human full-shift or remote hardware benchmark." % [service.actors.size(), sample_seconds], "samples": results}, "  "))

func run() -> void:
	seed(77)
	root.mode = Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	station.get_node("NightEvents").set_process(false)
	station.get_node("PassengerDialogueEvents").set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	service = station.get_node("PassengerService")
	service.passengers_per_round = 8 # Measure the full crowd, independent of the lighter tutorial.
	service.pre_ticket_routines_enabled = false
	service.set_process(false)
	gm.turn_on_power()
	gm.sign_in()
	service._spawn_wave()
	service._spawn_wave()
	for index in range(service.actors.size()):
		var actor = service.actors[index]
		actor.set_physics_process(false)
		actor.position = Vector3(-4 + (index % 8)*1.3, 0.35, -6 + int(index/8)*1.3)
		actor.phase = "SAFE"
	train = station.get_node("TrainService")
	train.set_process(false)
	player = station.get_node("Player")
	player.set_physics_process(false)
	player.set_flashlight(false, false)
	station.get_node("PauseMenu")._render_scale.value = render_scale * 100
	station.get_node("PauseMenu")._dirty = false
	root.scaling_3d_scale = render_scale
	await create_timer(2).timeout
	root.mode = Window.MODE_WINDOWED
	root.size = target_pixels
	root.content_scale_size = target_pixels
	await create_timer(1).timeout
	# macOS may back the window with 2x Retina pixels. Calibrate actual render size.
	var pixels := root.get_texture().get_size()
	root.size = Vector2i(Vector2(root.size) * Vector2(target_pixels) / pixels)
	await create_timer(2).timeout
	if stress_only:
		if early_mess:
			station.get_node("StationJobs")._spawn_timer = 0
			station.get_node("StationJobs")._next_mess_delay = 100000
		train.vehicle.visible = true
		train.vehicle.position.x = 0
		train.phase = "BOARDING"
		for index in range(service.actors.size()):
			var actor = service.actors[index]
			actor.position = Vector3(-12 + (index % 8)*3.0, 0.35, 14 + int(index/8)*0.7)
			actor._path_pending = false
			actor.set_physics_process(true)
			actor.phase = "ACTIVITY"
			actor._navigate_to(actor.position + Vector3(0.6,0,0))
		view(Vector3(4.5,0.35,10.8), Vector3(4.5,1.3,18))
		player.set_flashlight(true, false)
		for trial in range(trials): await sample("moving_crowd_train_flashlight_trial_%d" % (trial+1), true, true)
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(output.trim_suffix(".json") + "-scene.png")
		for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
		station.queue_free()
		for frame in range(12): await process_frame
		OS.delay_msec(120)
		quit()
		return
	view(Vector3(3,0.35,-11), Vector3(0,1.3,-3))
	await sample("hall_24_passengers")
	train.vehicle.visible = true
	train.vehicle.position.x = 0
	train.phase = "BOARDING"
	view(Vector3(-16,0.35,15), Vector3(-5,1.3,21))
	await sample("train_48_sliding_leaves", true)
	train.vehicle.visible = false
	train.phase = "WAITING"
	var actor = service.actors[0]
	actor.phase = "COUNTER"
	actor.position = Vector3(-5.85,0.35,4)
	service._on_counter_ready(actor)
	player.position = Vector3(-9.3,0.35,3.2)
	service.open_desk()
	player.camera.look_at(Vector3(-7.68,1.235,4))
	await sample("booth_papers")
	var desk = station.get_node("BoothDesk")
	desk.pick_up("passport")
	player.camera.look_at(Vector3(-5.85,1.5,4))
	await sample("booth_held_passport")
	desk.put_down()
	desk.verify_record()
	player.camera.look_at(desk.get_node("BoothComputerScreen").global_position)
	await sample("booth_live_computer")
	service.ui.close_desk()
	view(Vector3(23,0.35,2.5), Vector3(24.78,1.85,2.5))
	await sample("security_wall_monitors")
	var cctv = station.get_node("StationServices").cctv
	cctv.open_panel()
	cctv.select_feed(0)
	await sample("fullscreen_cctv")
	cctv.close_panel()
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for frame in range(12): await process_frame
	OS.delay_msec(100)
	quit()
