extends SceneTree
var failures: int = 0
func _init() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func wait_for(predicate: Callable, limit: int = 6000) -> bool:
	for i in range(limit):
		if predicate.call(): return true
		await physics_frame
	return false
func run() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night()
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var service = station.get_node("PassengerService")
	# Keep this existing inspection/boarding fixture deterministic.
	service.passengers_per_round = 3
	service.pre_ticket_routines_enabled = false
	var train = station.get_node("TrainService")
	gm.restore_power()
	gm.sign_in()
	await wait_for(func() -> bool: return service.counter_ready)
	var actor: Node = service.current_actor
	service.decide(true)
	await wait_for(func() -> bool: return is_instance_valid(actor) and actor.phase == "SEATED")
	check(train.phase == "WAITING", "Train waits for its scheduled time")
	gm.time_minutes = 137
	gm.clock_changed.emit()
	await wait_for(func() -> bool: return train.phase == "BOARDING")
	check(train.vehicle.position.x == 0 and train.vehicle.visible, "02:17 train approaches and stops at the platform")
	var boarded: bool = await wait_for(func() -> bool: return train.boarded_count == 1)
	check(boarded, "Waiting passenger navigates to the train and boards")
	if not boarded and is_instance_valid(actor): print("Stuck boarding: ", actor.phase, " ", actor.position, " points ", actor._points)
	check(gm.powered, "Train arrival does not cause a power failure")
	await wait_for(func() -> bool: return train.phase == "WAITING")
	check(not train.vehicle.visible and train.next_arrival > 137, "Train closes doors, departs and schedules the next service")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(8): await physics_frame
	OS.delay_msec(150)
	await process_frame
	print("TRAIN CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
