extends SceneTree
func _init() -> void: call_deferred("run")
func capture(file: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/atmosphere-qa/" + file + ".png")
func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.new_campaign()
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	gm.turn_on_power()
	station.get_node("Player").hide()
	station.get_node("Player").set_physics_process(false)
	station.get_node("NightHUD").hide()
	station.get_node("PauseMenu").hide()
	var camera := Camera3D.new()
	station.add_child(camera)
	camera.current = true
	camera.position = Vector3(-12.3,1.85,-10.2)
	camera.look_at(Vector3(-13.8,1.65,-14.2))
	await create_timer(2.4).timeout
	await capture("robot-kiosk")
	camera.position = Vector3(5, 1.8, -12)
	camera.look_at(Vector3(0, 1.5, 5))
	await capture("powered-hall")
	gm.powered = false
	station._apply_station_power(false)
	await capture("power-off-hall")
	gm.powered = true
	station._apply_station_power(true)
	camera.position = Vector3(12.7,2.5,-11.7)
	camera.look_at(Vector3(14.9,3.15,-14.8))
	await capture("mounted-camera")
	var entries = station.get_node("StationJobs")._camera_screens
	for i in range(entries.size()):
		var vp: SubViewport = entries[i].viewport
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.resize(1024,576)
		img.save_png("res://builds/atmosphere-qa/feed-%d.png" % (i+1))
	quit()
