extends SceneTree
## Accelerated rule/navigation run, not a human-input or usability playthrough.
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	seed(17)
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var service = station.get_node("PassengerService")
	service.pre_ticket_routines_enabled = false
	var player = station.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector3(-9.3, 0.35, 3.2)
	station.get_node("PassengerDialogueEvents").set_process(false)
	for i in range(15): await physics_frame
	gm.restore_power()
	gm.sign_in()
	gm.inspect_platform()
	var events = station.get_node("NightEvents")
	for frame in range(36000):
		await physics_frame
		gm._process(1.0 / 60.0)
		if events.started and not events.completed: events.resolve("exit")
		if service.counter_ready:
			var errors = service.Cases.errors(service.current_profile())
			service.decide(errors.is_empty())
		if gm.state == gm.NightState.SHIFT_OVER: break
	check(service.reviewed == 9 and service.correct == 9, "All nine tutorial passengers can reach the counter and receive a decision")
	check(service.round_number == 2, "All three small tutorial groups arrive")
	check(events.completed, "Exit-seal tutorial duty remains completable")
	check(station.get_node("PassengerEntity").banished, "Final camera lesson can contain the intruder")
	check(station.get_node("TrainService").boarded_count >= 1, "A genuine tutorial passenger walks to and boards the train")
	check(gm.shift_blockers().is_empty(), "Reduced tutorial satisfies every actual shift requirement")
	check(gm.state == gm.NightState.SHIFT_OVER and station.get_node("ShiftReport").is_open, "Tutorial reaches its successful end-of-night report")
	if failures: print("Remaining duties: ", gm.shift_blockers())
	paused = false
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(8): await process_frame
	OS.delay_msec(100)
	print("TUTORIAL PLAYTHROUGH CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
