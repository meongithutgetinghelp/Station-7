extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ",message)
	else:
		failures += 1
		push_error(message)
func pending(jobs: Node) -> Array:
	var indices := []
	for i in range(jobs._camera_screens.size()):
		if jobs._camera_screens[i].viewport.render_target_update_mode == SubViewport.UPDATE_ONCE: indices.append(i)
	return indices
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.new_campaign()
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var jobs = station.get_node("StationJobs")
	jobs.set_process(false)
	var console = station.get_node("StationServices").cctv
	console.set_process(false)
	jobs._update_camera_feeds(1)
	check(pending(jobs).is_empty(), "Unpowered cameras do not render")
	gm.turn_on_power()
	var player = station.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector3(0,0.36,-12)
	jobs._update_camera_feeds(1)
	check(pending(jobs).is_empty(), "Distant wall monitors consume no feed renders")
	player.position = Vector3(23,0.36,2.5)
	player.rotation.y = -PI/2
	jobs._update_camera_feeds(1)
	check(pending(jobs).size() == 1, "Visible wall monitors refresh at most one feed per frame")
	var first: Array = pending(jobs)
	jobs._update_camera_feeds(0.01)
	check(pending(jobs).size() <= 1 and pending(jobs) != first, "Wall refreshes are staggered across frames")
	console.open_panel()
	console.select_feed(4)
	jobs._update_camera_feeds(0)
	check(pending(jobs) == [4], "Only selected fullscreen feed renders immediately")
	check(root.disable_3d, "Opaque CCTV panel suppresses hidden main-world rendering")
	jobs._update_camera_feeds(0.01)
	check(pending(jobs).is_empty(), "Selected feed respects refresh-rate budget")
	jobs._update_camera_feeds(1.0/24.0)
	check(pending(jobs) == [4], "Selected camera continues live refreshes")
	console.select_feed(2)
	jobs._update_camera_feeds(0)
	check(pending(jobs) == [2], "Changing feeds schedules a fresh frame immediately")
	gm.cause_power_failure()
	jobs._update_camera_feeds(1)
	check(pending(jobs).is_empty(), "Outage stops every feed")
	gm.restore_power()
	jobs._update_camera_feeds(0)
	check(pending(jobs) == [2], "Restored power resumes selected feed")
	console.close_panel()
	check(not root.disable_3d and not player.in_booth_inspection, "Lowering monitor restores world rendering and player control")
	var screens = jobs.find_children("*", "MeshInstance3D", false, false)
	var isolated := 0
	for screen in screens:
		if screen.layers == (1 << 16): isolated += 1
	check(isolated == 3, "Wall display textures are excluded from CCTV views")
	for entry in jobs._camera_screens:
		check((entry.camera.cull_mask & (1 << 16)) == 0, "CCTV feed cannot recursively render wall displays")
	var settings = station.get_node("PauseMenu")
	settings.settings_path = "user://performance-test.cfg"
	settings._render_scale.value = 60
	check(is_equal_approx(root.scaling_3d_scale,0.6), "Render scale changes 3D resolution without changing UI scale")
	settings.set_paused(false)
	settings._render_scale.value = 100
	settings._load_settings()
	settings._apply_settings()
	check(is_equal_approx(root.scaling_3d_scale,0.6), "Render scale survives saved settings reload")
	settings._dirty = false
	DirAccess.remove_absolute(settings.settings_path)
	console.open_panel()
	station.queue_free()
	for i in range(12): await process_frame
	check(not root.disable_3d, "Scene teardown restores main viewport rendering even with CCTV open")
	OS.delay_msec(100)
	await process_frame
	print("PERFORMANCE CHECKS: ",failures," failures")
	quit(0 if failures == 0 else 1)
