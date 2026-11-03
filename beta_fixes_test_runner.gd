extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func wait_for(predicate: Callable, frames: int = 5000) -> bool:
	for i in range(frames):
		if predicate.call(): return true
		await physics_frame
	return false
func run() -> void:
	seed(77)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): seed(int(argument.trim_prefix("--seed=")))
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	station.get_node("PassengerEntity").set_physics_process(false)
	station.get_node("NightEvents").set_process(false)
	station.get_node("PassengerDialogueEvents").set_process(false)
	var service = station.get_node("PassengerService")
	service.passengers_per_round = 6
	service.pre_ticket_routines_enabled = false
	gm.turn_on_power()
	gm.sign_in()
	service.set_process(false)
	var train = station.get_node("TrainService")
	train.set_process(false)
	var player = station.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector3(-9.3, 0.35, 3.2)
	var first_ready := await wait_for(func() -> bool: return service.counter_ready)
	check(first_ready, "First passenger reaches the booth")
	if not first_ready:
		for person in service.actors: print(person.phase, " ", person.position, " ", person._points)
		quit(1)
		return
	service.open_desk()
	check(player.head.position.y > 1.4, "Seat eye is raised above the old 1.1 metre offset")
	var equipment = player.camera.get_node("Equipment")
	await process_frame
	check(equipment.visible, "Hands and equipment stay visible at the seated physical desk")
	var desk = station.get_node("BoothDesk")
	await wait_for(func() -> bool: return not desk.sliding)
	player.camera.look_at(desk.get_node("BoothComputerScreen").global_position)
	await physics_frame
	var hit: Dictionary = player._raycast_hit()
	check(not hit.is_empty() and hit.collider.is_in_group("booth_computer_screen"), "A seated centre ray reaches the visible screen without hitting its stand")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if DisplayServer.get_name() == "headless": player._get_interaction_target().interact()
	else: player._try_interact()
	check(desk._record.text.contains("IDENTITY"), "Screen interaction performs the physical record check")
	desk._record.text = "Waiting"
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	if DisplayServer.get_name() == "headless": player._get_interaction_target().interact()
	else: player._unhandled_input(click)
	check(desk._record.text.contains("IDENTITY"), "Screen click target uses the same record check")
	var before: Vector3 = player.flashlight.rotation
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(12, 5)
	for i in range(10): player._unhandled_input(look)
	await process_frame
	check(player.flashlight.rotation.is_equal_approx(before), "Seated looking cannot accumulate flashlight sway")
	check(player.flashlight.position.z < -0.6 and absf(equipment.rotation.y) < 0.01, "Beam starts at the held lens and the desk cannot twist the torch sideways")
	desk.pick_up("passport")
	await process_frame
	check(not equipment.visible and desk.held.get_child_count() > 0, "Held passport uses its own rounded hand pose without duplicate arms")
	desk.put_down()
	service.ui.close_desk()
	var released: Array = []
	for i in range(6):
		var ready := await wait_for(func() -> bool: return service.counter_ready)
		if not ready:
			print("RELEASE STALL state ", gm.state)
			for person in service.actors: print(person.phase, " ", person.position, " ", person._points.slice(0, 2))
			break
		released.append(service.current_actor)
		service.decide(true)
	if released.is_empty():
		quit(1)
		return
	check(released.size() == 6, "A six-passenger release burst does not jam the ticket queue")
	check(await wait_for(func() -> bool:
		for actor in released:
			if actor.phase not in ["SEATED", "ACTIVITY", "IDLE_ACTIVITY", "RETURN_SEAT"]: return false
		return true), "All released passengers pass the gate and reach their seats")
	# Use one real doorway with six arrivals to stress admission and distinct interior places.
	train.phase = "BOARDING"
	train.elapsed = 1
	train.vehicle.position.x = 0
	train.vehicle.visible = true
	train._set_doors(true, true)
	for i in range(released.size()):
		var actor = released[i]
		actor.visual.set_seated(false)
		actor.position = Vector3(-6.25 + (-0.8 if i % 2 == 1 else 0.8) if i > 0 else -6.25, 0.35, 18.6 - ceilf(float(i) / 2) * 0.85)
		actor.phase = "BOARD_TRAIN"
		actor._train = train
		actor._queue_destination = train.queue_point(actor)
		actor._points.assign([actor._queue_destination])
	var min_distance := INF
	var max_crossing := 0
	var saw_threshold := false
	var crossing_state: Dictionary = {}
	var crossing_train: Dictionary = {}
	for frame in range(2400):
		var crossing := 0
		for actor in released:
			if actor.phase == "ENTER_TRAIN":
				crossing += 1
				if actor.position.z > 19.5 and actor.position.z < 20.15: saw_threshold = true
		if saw_threshold and crossing_state.is_empty():
			crossing_state = service.save_state()
			crossing_train = train.save_state()
		for i in range(released.size()):
			for j in range(i): min_distance = minf(min_distance, released[i].position.distance_to(released[j].position))
		max_crossing = maxi(max_crossing, crossing)
		if train.boarded_count == 6: break
		await physics_frame
	check(train.boarded_count == 6, "Six passengers physically walk through the same train doorway")
	check(max_crossing == 1 and min_distance >= 0.59, "Door admission and crowd spacing prevent overlapping passengers")
	check(saw_threshold, "Passengers remain rendered while crossing the actual train sill")
	check(is_instance_valid(released[0]) and released[0].phase == "BOARDED" and released[0].visible, "Boarding retains the visible passenger instead of despawning on the platform")
	var actor = released[0]
	var previous: Vector3 = actor.position
	train.vehicle.position.x += 2
	await physics_frame
	await physics_frame
	check(is_equal_approx(actor.position.x - previous.x, 2), "Boarded passengers move with the departing train")
	var state: Dictionary = service.save_state()
	service.load_state(state)
	await physics_frame
	var restored = station.get_node_or_null("Passenger_" + str(actor.profile.uid)) if is_instance_valid(actor) else null
	# Find by saved UID because the old node is freed during restoration.
	var saved: Dictionary = state.people[0]
	restored = station.get_node_or_null("Passenger_" + str(saved.uid))
	check(restored and restored.phase == "BOARDED" and restored.position.is_equal_approx(train.vehicle.to_global(restored.train_offset)), "Boarded interior positions survive checkpoint restoration")
	train.load_state(crossing_train)
	service.load_state(crossing_state)
	check(await wait_for(func() -> bool: return train.boarded_count == 6, 3000), "A checkpoint mid-doorway resumes boarding without dropping or duplicating passengers")
	var door: Dictionary = train._doors[0]
	train._set_doors(false, true)
	var closed: Vector3 = door.node.position
	train._set_doors(true)
	for i in range(10): await process_frame
	check(absf(door.node.position.z - closed.z) > 0.05 and is_equal_approx(door.node.position.x, closed.x), "Door moves outward before starting its sideways slide")
	for i in range(45): await process_frame
	check(is_equal_approx(door.node.position.x, closed.x + door.direction * 0.78) and is_equal_approx(absf(door.node.position.z - closed.z), 0.14), "Open leaves clear the side wall on both movement axes")
	train._set_doors(false)
	for i in range(20): await process_frame
	check(is_equal_approx(absf(door.node.position.z - closed.z), 0.14), "Closing doors slide back before pulling flush")
	for i in range(35): await process_frame
	check(door.node.position.is_equal_approx(closed), "Door closure restores the exact original transform")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(8): await physics_frame
	OS.delay_msec(150)
	await process_frame
	print("BETA FIX CHECKS: ", failures, " failures; closest crowd gap ", min_distance)
	quit(1 if failures else 0)
