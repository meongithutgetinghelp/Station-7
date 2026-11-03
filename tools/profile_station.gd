extends SceneTree
var station: Node
var results: Array = []
func _init() -> void: call_deferred("run")
func sample(label: String) -> void:
	if "--legacy" in OS.get_cmdline_user_args():
		station.get_node("StationJobs").set_process(false)
		root.disable_3d = false
		for screen in station.get_node("StationJobs").find_children("*", "MeshInstance3D", false, false):
			if screen.layers == (1 << 16): screen.layers = 1
		for entry in station.get_node("StationJobs")._camera_screens:
			entry.viewport.positional_shadow_atlas_size = 2048
			entry.viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		var console = station.get_node("StationServices").cctv
		if console.is_open: console.feeds[console.selected].viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await create_timer(2).timeout
	var times: Array[float] = []
	var draws := 0.0
	var cpu := 0.0
	var physics := 0.0
	var previous := Time.get_ticks_usec()
	var count := 0
	var deadline := Time.get_ticks_usec() + 3000000
	while Time.get_ticks_usec() < deadline:
		count += 1
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now-previous)/1000.0)
		previous = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		cpu += Performance.get_monitor(Performance.TIME_PROCESS)*1000
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
	times.sort()
	var total := 0.0
	for t in times: total += t
	var result := {"scene":label,"size":str(root.size),"scale":root.scaling_3d_scale,"fps":count*1000.0/total,"median_ms":times[times.size()/2],"p95_ms":times[int(times.size()*0.95)],"draw_calls":draws/count,"cpu_ms":cpu/count,"physics_ms":physics/count}
	results.append(result)
	print(JSON.stringify(result))
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var gm = root.get_node("GameManager")
	seed(77)
	gm.new_campaign()
	gm.set_process(false)
	station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1080)
	gm.turn_on_power()
	gm.sign_in()
	var service = station.get_node("PassengerService")
	for i in range(2): service._spawn_wave()
	var player = station.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector3(5,0.36,-12)
	player.rotation.y = 0
	await create_timer(3).timeout
	root.scaling_3d_scale = 1.0
	await sample("hall")
	player.position = Vector3(19,0.36,2.5)
	player.rotation.y = -PI/2
	await sample("security")
	var console = station.get_node("StationServices").cctv
	console.open_panel()
	console.select_feed(0)
	await sample("cctv")
	console.close_panel()
	if "--ablations" in OS.get_cmdline_user_args():
		for entry in station.get_node("StationJobs")._camera_screens: entry.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		await sample("security_no_cctv")
		for light in get_nodes_in_group("station_lights"): light.shadow_enabled = false
		await sample("security_no_cctv_no_shadows")
		player.position = Vector3(5,0.36,-12)
		player.rotation.y = 0
		await sample("hall_no_shadows")
	if not "--ablations" in OS.get_cmdline_user_args() and not "--legacy" in OS.get_cmdline_user_args():
		root.scaling_3d_scale = 0.75
		player.position = Vector3(5,0.36,-12)
		player.rotation.y = 0
		await sample("hall_75pct")
		player.position = Vector3(19,0.36,2.5)
		player.rotation.y = -PI/2
		await sample("security_75pct")
		console.open_panel()
		console.select_feed(0)
		await sample("cctv_75pct")
		console.close_panel()
	var path := "res://builds/performance-qa/" + ("before.json" if "--legacy" in OS.get_cmdline_user_args() or "--ablations" in OS.get_cmdline_user_args() else "after.json")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): path = argument.trim_prefix("--report=")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	quit()
