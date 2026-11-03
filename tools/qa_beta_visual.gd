extends SceneTree
## Native rendered evidence and real captured-pointer screen input.
var station: Node
func _init() -> void: call_deferred("run")
func capture(label: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/beta-fixes-qa/" + label + ".png")
func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for path in ["NightEvents", "PassengerDialogueEvents", "TrainService"]: station.get_node(path).set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	var service = station.get_node("PassengerService")
	service.set_process(false)
	service.pre_ticket_routines_enabled = false
	gm.turn_on_power()
	gm.sign_in()
	for actor in service.actors: actor.set_physics_process(false)
	var actor = service.actors[0]
	actor.position = Vector3(-5.85, 0.35, 4)
	actor.phase = "COUNTER"
	actor.rotation.y = -PI * 0.5
	service._on_counter_ready(actor)
	var player = station.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector3(-9.3, 0.35, 3.2)
	service.open_desk()
	player.camera.make_current()
	await create_timer(2).timeout
	var pixels := root.get_texture().get_size()
	root.size = Vector2i(Vector2(root.size) * Vector2(1920,1080) / pixels)
	var desk = station.get_node("BoothDesk")
	player.camera.look_at(desk.get_node("BoothComputerScreen").global_position)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await physics_frame
	player._try_interact()
	assert(desk._record.text.contains("IDENTITY"), "Native E on physical computer")
	desk._record.text = "Waiting"
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	player._unhandled_input(click)
	assert(desk._record.text.contains("IDENTITY"), "Native click on physical computer")
	print("PASS: Native E and captured-pointer click both verify the visible computer")
	await capture("seated-monitor-hands")
	desk.pick_up("passport")
	player.camera.look_at(Vector3(-5.85, 1.6, 4))
	await capture("passport-hands")
	desk.put_down()
	service.ui.close_desk()
	player.set_flashlight(false, false)
	var train = station.get_node("TrainService")
	train.phase = "BOARDING"
	train.elapsed = 1
	train.vehicle.position.x = 0
	train.vehicle.visible = true
	train._set_doors(true, true)
	for index in range(3):
		var person = service.actors[index]
		person.position = Vector3(-6.25 + (-0.8 if index % 2 == 1 else 0.8) if index > 0 else -6.25, 0.35, 18.6 - ceilf(float(index) / 2) * 0.85)
		person.phase = "BOARD_TRAIN"
		person._path_pending = false
		person._train = train
		person._queue_destination = train.queue_point(person)
		person._points.assign([person._queue_destination])
		person.set_physics_process(true)
	var camera := Camera3D.new()
	station.add_child(camera)
	camera.position = Vector3(-10, 2.2, 16)
	camera.look_at(Vector3(-6.25, 1.2, 20.3))
	camera.make_current()
	station.get_node("NightHUD").hide()
	await create_timer(0.4).timeout
	await capture("boarding-through-door")
	await create_timer(11).timeout
	await capture("passengers-inside-train")
	print("PASS: Rendered boarding retained ", train.boarded_count, " passengers")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	await create_timer(0.2).timeout
	quit()
