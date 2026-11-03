extends SceneTree

func _init() -> void: call_deferred("run")

func capture(file: String) -> void:
	await create_timer(0.6, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/opening-flow-qa/" + file + ".png")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	gm.new_campaign()
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	await capture("station-dark")
	station._use_breaker()
	gm.sign_in()
	await capture("station-open")
	quit()
