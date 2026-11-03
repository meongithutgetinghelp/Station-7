extends SceneTree

func _init() -> void: call_deferred("run")
func capture(file: String) -> void:
	await create_timer(0.25, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/station-finishes-qa/" + file + ".png")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var gm := root.get_node("GameManager")
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
	camera.fov = 68
	station.add_child(camera)
	camera.current = true
	camera.position = Vector3(14.0, 1.8, 3.5)
	camera.look_at(Vector3(16, 1.55, 2.5))
	await create_timer(2.4, true).timeout
	await capture("cctv-door")
	camera.position = Vector3(3.0, 2.2, -10.5)
	camera.look_at(Vector3(-0.65, 0.35, -4.5))
	await capture("tile-and-guidance")
	camera.position = Vector3(0.6, 6.1, -31.2)
	camera.look_at(Vector3(0, 1.25, -23.0))
	await capture("stairway")
	station.get_node("StationJobs")._spawn_mess(0)
	camera.position = Vector3(3.1, 1.9, -6.3)
	camera.look_at(Vector3(2, 0.35, -8))
	await capture("textured-mess")
	quit()
