extends SceneTree
func _init() -> void: call_deferred("run")
func capture(file: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/performance-qa/"+file+".png")
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.new_campaign()
	gm.set_process(false)
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	gm.turn_on_power()
	gm.sign_in()
	var player = station.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector3(19,0.36,2.5)
	player.rotation.y = -PI/2
	await create_timer(3).timeout
	var console = station.get_node("StationServices").cctv
	console.open_panel()
	console.select_feed(4)
	await capture("live-cctv")
	var vp: SubViewport = console.feeds[4].viewport
	var original: Image = vp.get_texture().get_image()
	console.pan(0.5,0)
	await create_timer(0.8).timeout
	var moved: Image = vp.get_texture().get_image()
	print("FEED_PAN_IMAGE_CHANGED: ", original.get_data() != moved.get_data())
	gm.cause_power_failure()
	await capture("cctv-outage")
	gm.restore_power()
	await capture("cctv-restored")
	console.close_panel()
	await capture("returned-to-world")
	var settings = station.get_node("PauseMenu")
	settings.set_paused(true)
	settings._pages.current_tab = 1
	await capture("display-settings")
	settings._dirty = false
	quit()
