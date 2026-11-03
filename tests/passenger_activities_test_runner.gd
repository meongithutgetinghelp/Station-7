extends SceneTree

var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func wait_for(predicate: Callable, frames: int = 6000) -> bool:
	for i in range(frames):
		if predicate.call(): return true
		await physics_frame
	return false

func run() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night()
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	station.get_node("PassengerEntity").set_physics_process(false)
	station.get_node("TrainService").set_process(false)
	var service = station.get_node("PassengerService")
	# Keep this existing inspection/boarding fixture deterministic.
	service.passengers_per_round = 3
	service.pre_ticket_routines_enabled = false
	service.round_limit = 1
	gm.restore_power()
	gm.sign_in()
	var outside := true
	for person in service.actors:
		outside = outside and person.position.z < -33 and person.position.y > 4.6
		person.walk_speed = 6
	check(outside, "All arriving passengers originate on the outside street apron")
	var ready: bool = await wait_for(func() -> bool: return service.counter_ready)
	check(ready, "Passenger descends the entrance stairs and reaches the booth")
	if not ready:
		for person in service.actors: print("Arrival stuck at ", person.position)
		quit(1)
		return
	var actor: Node = service.current_actor
	actor.profile.vip = true
	service.decide(true)
	check(await wait_for(func() -> bool: return actor.phase == "SEATED"), "Admitted passenger reaches a platform seat")
	var pelvis: Vector3 = actor.visual.joint_world("Pelvis")
	actor._sit()
	check(actor.visual.joint_world("Pelvis").distance_to(pelvis) < 0.001, "Repeated sitting preserves the passenger pose")
	var knee: Vector3 = actor.visual.joint_world("Shin.L")
	var ankle: Vector3 = actor.visual.joint_world("Foot.L")
	check(knee.distance_to(ankle) >= 0.35 and ankle.y > 0.35 and ankle.y < 0.54, "Seated knees remain connected and feet reach the floor")
	actor._stand_up()
	var destinations := {"smoking": Vector3(-18, 0.35, -8), "bathroom": Vector3(17.7, 0.35, -4.5), "lounge": Vector3(9, 0.35, -18.2), "shop": Vector3(-13.8, 0.35, -12.3), "wander": Vector3(2, 0.35, -8)}
	for activity in destinations:
		actor.phase = "ACTIVITY"
		actor._visit_kind = activity
		actor._navigate_to(destinations[activity])
		var arrived: bool = await wait_for(func() -> bool: return actor.phase == "IDLE_ACTIVITY", 2400)
		check(arrived, "Passenger completes %s visit through real station collision" % activity)
		if not arrived: print("Activity stuck at ", actor.position, " phase ", actor.phase)
	check(station.get_node("StationServices").customer_sales.has(actor.profile.uid), "Passenger purchases a drink during a kiosk visit")
	actor.seat_anchor.set_meta("reserved", false)
	actor.seat_anchor = service._reserve_seat()
	actor.phase = "RETURN_SEAT"
	actor._navigate_to(actor.seat_anchor.global_position + actor.seat_anchor.global_basis.z * 0.75)
	check(await wait_for(func() -> bool: return actor.phase == "SEATED") and actor.position.z < 10, "Passenger can also sit in the concourse waiting area")
	actor._authorized = false
	actor.ticket.used = false
	var train = station.get_node("TrainService")
	train.phase = "BOARDING"
	train.elapsed = 1
	train.vehicle.position.x = 0
	train.vehicle.visible = true
	train._set_doors(true, true)
	actor.board_train(train)
	var actor_ref: WeakRef = weakref(actor)
	check(await wait_for(func() -> bool: return actor_ref.get_ref() != null and actor.phase == "BOARDED", 2400) and train.boarded_count == 1, "Concourse passenger passes the gate and boards the train")
	var leaving: Node = service.actors[1]
	leaving.reject()
	var leaving_ref: WeakRef = weakref(leaving)
	var exited: bool = await wait_for(func() -> bool: return leaving_ref.get_ref() == null, 2400)
	check(exited, "Rejected passenger climbs the stairs and exits outside")
	if not exited: print("Exit stuck at ", leaving.position, " route ", leaving._points)
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(12): await physics_frame
	# Let the audio mixer consume queued stop/free commands before engine shutdown.
	OS.delay_msec(100)
	await process_frame
	print("PASSENGER ACTIVITY CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
