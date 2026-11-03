extends SceneTree
var station: Node
func _init() -> void: call_deferred("run")
func capture(label: String, delay: float = 0.4) -> void:
	await create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/hands-interior-qa/"+label+".png")
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for path in ["NightEvents","PassengerDialogueEvents","TrainService"]: station.get_node(path).set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	var service = station.get_node("PassengerService")
	service.set_process(false)
	service.pre_ticket_routines_enabled = false
	gm.turn_on_power()
	gm.sign_in()
	for actor in service.actors: actor.set_physics_process(false)
	var actor = service.actors[0]
	actor.position = Vector3(-5.85,0.35,4)
	actor.phase = "COUNTER"
	actor.rotation.y = -PI*0.5
	service._on_counter_ready(actor)
	var player = station.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector3(-9.3,0.35,3.2)
	service.open_desk()
	player.camera.make_current()
	await create_timer(2).timeout
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1920,1080)
	root.content_scale_size=root.size
	await create_timer(1).timeout
	var pixels := root.get_texture().get_size()
	root.size=Vector2i(Vector2(root.size)*Vector2(1920,1080)/pixels)
	await create_timer(1).timeout
	player.camera.look_at(Vector3(-5.85,1.6,4))
	var equipment = player.camera.get_node("Equipment")
	player.set_flashlight(false,false)
	await capture("01-relaxed")
	player.set_flashlight(true,false)
	await capture("02-preferred-flashlight")
	var desk=station.get_node("BoothDesk")
	desk.pick_up("passport")
	await capture("03-document")
	desk.put_down()
	desk.pick_up("ticket")
	await capture("04-reach",0.10)
	desk.put_down()
	player.camera.look_at(desk.get_node("BoothComputerScreen").global_position)
	desk.verify_record()
	await capture("06-keyboard",0.6)
	desk.exit_computer(true)
	desk.stamp_ticket(true)
	await capture("05-stamp",0.33)
	await create_timer(0.6).timeout
	service.ui.close_desk()
	player.camera.look_at(Vector3(-5.85,1.6,4))
	for pair in [["mop","07-cleaning"],["phone","08-phone"]]:
		gm.inventory[pair[0]]=1
		equipment.equip(pair[0],false)
		await capture(pair[1])
	service._queue_revision += 1
	service._queue_release = null
	service._queue.clear()
	var train=station.get_node("TrainService")
	train.phase="BOARDING"
	train.elapsed=1
	train.vehicle.position.x=0
	train.vehicle.visible=true
	train._set_doors(true,true)
	var camera:=Camera3D.new()
	station.add_child(camera)
	camera.position=Vector3(-11.7,1.75,20.7)
	camera.look_at(Vector3(-1.2,1.5,21.3))
	camera.make_current()
	station.get_node("NightHUD").hide()
	await capture("09-coach-interior")
	camera.position=Vector3(-10,2.2,16)
	camera.look_at(Vector3(-6.25,1.2,20.3))
	await capture("10-interior-from-platform")
	for i in range(3):
		var person=service.actors[i]
		person.phase="BOARD_TRAIN"
		person._path_pending=false
		person._train=train
		person.position=Vector3(-6.25+(-0.8 if i%2==1 else 0.8) if i>0 else -6.25,0.35,18.6-ceilf(float(i)/2)*0.85)
		person._queue_destination=train.queue_point(person)
		person._points.assign([person._queue_destination])
		person.set_physics_process(true)
	await create_timer(15).timeout
	await capture("11-passengers-seated")
	print("PASS: Native eight-pose gallery and train interior rendered; boarded ",train.boarded_count)
	for audio in station.find_children("*","AudioStreamPlayer3D",true,false): audio.stop()
	station.queue_free()
	await create_timer(0.2).timeout
	quit()
