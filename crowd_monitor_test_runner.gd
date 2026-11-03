extends SceneTree

var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func wait_for(predicate: Callable, frames: int = 9000) -> bool:
	for i in range(frames):
		if predicate.call(): return true
		await physics_frame
	return false

func run() -> void:
	seed(7441)
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(2) # Full-shift crowd fixture; Night 1 now has a smaller tutorial queue.
	gm.save_path = "/private/tmp/station7_crowd_save.json"
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for i in range(30): await physics_frame
	station.get_node("PassengerEntity").set_physics_process(false)
	station.get_node("TrainService").set_process(false)
	var service = station.get_node("PassengerService")
	check(not service.started and service.actors.is_empty() and not gm.signed_in, "Station stays empty until power repair and staff sign-in")
	gm.restore_power()
	gm.sign_in()
	check(service.started and service.actors.size() == 8, "Eight passengers begin arriving when the station opens")
	check(service.total_cases() == 24, "Default shift supports twenty-four passenger inspections")
	var plans: Dictionary = {}
	var all_visiting := true
	var in_apron := true
	for actor in service.actors:
		plans[str(actor.pre_ticket_plan)] = true
		all_visiting = all_visiting and actor.phase == "PRE_ENTRY" and actor.pre_ticket_plan.size() >= 2
		in_apron = in_apron and absf(actor.position.x) < 1 and actor.position.z > -37.5 and actor.position.z < -33
		actor.walk_speed = 6
	check(all_visiting and service._queue.is_empty(), "New arrivals visit facilities before joining the ticket line")
	check(plans.size() > 1, "Passengers receive varied itineraries")
	check(in_apron, "All eight spawn within the exterior arrival apron")
	service._wave_timer = 100
	service._process(0)
	check(service.actors.size() == 16 and service.reviewed == 0, "Another group arrives without waiting for ticket sales")
	service._wave_timer = 100
	service._process(0)
	check(service.actors.size() == 24, "Three groups populate the station with twenty-four people")
	service.set_process(false)
	for actor in service.actors: actor.walk_speed = 6
	check(gm.save_game(), "Crowd itineraries save")
	var first_plan: Array = service.actors[0].pre_ticket_plan.duplicate()
	check(gm.load_game() and service.actors.size() == 24 and service.actors[0].pre_ticket_plan == first_plan, "Loading restores the crowd and its remaining routines")
	for actor in service.actors: actor.walk_speed = 6
	var reached: bool = await wait_for(func() -> bool: return service.counter_ready)
	if not reached:
		for actor in service.actors: print("CROWD STALL ", actor.profile.uid, " ", actor.phase, " ", actor.position, " ", actor._points.slice(0, 2))
	check(reached, "A passenger completes pre-ticket activities and eventually reaches the booth")
	if reached:
		check(service.current_actor.activity_history.size() >= 3, "The passenger at the counter completed at least two pre-ticket activities")
	check(service._queue.size() <= 6, "Ticket queue stays bounded while others use the station")
	var services = station.get_node("StationServices")
	var monitor = services.cctv
	preload("res://interactable.gd").resolve(station.get_node("Rooms/Security/SecurityTerminal")).interact()
	check(monitor.is_open and monitor._image.size == root.get_visible_rect().size, "Security terminal raises a full-screen monitor directly")
	check(monitor.feeds.size() == 6 and monitor._camera_buttons.size() == 6, "Station map exposes six real camera feeds")
	monitor._camera_buttons[4].pressed.emit()
	check(monitor.selected == 4 and monitor._image.texture == monitor.feeds[4].viewport.get_texture(), "Clicking a map camera switches the live feed")
	check(monitor.feeds[4].viewport.size == Vector2i(1024, 576), "Active feed uses monitor resolution")
	gm.cause_power_failure()
	monitor._process(0.1)
	check(monitor.is_open and monitor._status.text.contains("SIGNAL LOST"), "Power loss displays a dead feed instead of a popup")
	var balance_before: int = gm.balance
	monitor.mark_suspicious()
	check(gm.balance == balance_before and monitor._feedback.text.contains("OFFLINE"), "An offline camera cannot award an incident-report reward")
	gm.restore_power()
	monitor._process(0.1)
	check(monitor._status.text.contains("LIVE"), "Restoring power recovers the monitor feed")
	monitor.close_button.pressed.emit()
	check(not monitor.is_open and not station.get_node("Player").in_booth_inspection, "Lowering the monitor returns first-person control")
	var wall_monitor: Node = get_nodes_in_group("cctv_console_targets")[2]
	preload("res://interactable.gd").resolve(wall_monitor).interact()
	check(monitor.is_open and monitor.selected == 2, "Using a physical wall monitor opens its corresponding camera")
	monitor.close_panel()
	check(station.CEIL_H - station.FLOOR_Y == 7, "Public ceiling is reduced to seven metres")
	check(station.has_node("Rooms/Restroom/Floor_BathroomExpansion"), "Expanded bathrooms have a real east-wing floor")
	var player = station.get_node("Player")
	player.set_physics_process(false)
	var space = station.get_world_3d().direct_space_state
	for section in [0, 1]:
		var entry_z: float = -6.6 if section == 0 else -3.4
		var aisle_z: float = -9 if section == 0 else -1
		var route := [Vector3(18, 0.36, entry_z), Vector3(27.3, 0.36, entry_z), Vector3(27.3, 0.36, aisle_z), Vector3(39.5, 0.36, aisle_z)]
		var clear := true
		for index in range(route.size() - 1):
			var transform: Transform3D = player.global_transform
			transform.origin = route[index]
			clear = clear and not player.test_move(transform, route[index + 1] - route[index])
		check(clear, "Expanded bathroom %d has a clear full-size player route and broad aisle" % section)
		var path := NavigationServer3D.map_get_path(station.get_world_3d().navigation_map, Vector3(18, 0.35, entry_z), Vector3(39.5, 0.35, aisle_z), true)
		check(not path.is_empty() and path[-1].distance_to(Vector3(39.5, 0.35, aisle_z)) < 0.4, "Navigation reaches the far end of bathroom %d" % section)
		var floor_z: float = -14 if section == 0 else 4
		var floor_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(40, 1, floor_z), Vector3(40, -1, floor_z), 1))
		check(not floor_hit.is_empty() and absf(floor_hit.position.y - 0.35) < 0.02, "New bathroom %d corner has a level solid floor" % section)
	var visit_points_clear := true
	for actor in service.actors:
		for attempt in range(4):
			var target: Vector3 = actor._choose_activity_target("bathroom")
			var shape := CapsuleShape3D.new()
			shape.radius = 0.3
			shape.height = 1.72
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform.origin = target + Vector3(0, 0.87, 0)
			query.collision_mask = 1
			visit_points_clear = visit_points_clear and space.intersect_shape(query).is_empty()
	check(visit_points_clear, "Passenger bathroom destinations avoid sinks, walls and stalls")
	var counters: Array[Node] = station.find_children("SinkCounter*", "StaticBody3D", true, false)
	var aligned: bool = counters.size() == 2
	for counter in counters:
		aligned = aligned and absf(counter.global_position.x - 33.1) < 0.01 and absf(counter.global_position.z + 5) < 1
	check(aligned, "Both sink rows face the toilet rows across the room")
	var stall = station.get_node("Stall_0_0_InteractiveDoor")
	check(stall.door_height > player.stand_height + 0.5, "Stall doors are comfortably taller than the player")
	var bench = get_nodes_in_group("passenger_seats")[0].get_parent()
	var seat_mesh: MeshInstance3D = bench.get_child(0).get_child(0)
	check(seat_mesh.mesh.size.x >= 2.5 and seat_mesh.mesh.size.z >= 0.7, "Wooden benches provide three adult-size seats")
	var housing: MeshInstance3D = station.get_node("Gate_0_Housing").get_child(0)
	check(housing.mesh.size.y >= 1.2 and station.get_node("GateLane_0/Scanner").position.y >= 1.3, "Gate housings and readers sit at adult waist height")
	# Sweep the player capsule through both doorway centers to catch bins in exits.
	for z in [-6.6, -3.4]:
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.3
		shape.height = 1.72
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, Vector3(14, 1.22, z))
		query.motion = Vector3(4, 0, 0)
		query.collision_mask = preload("res://collision_layers.gd").SOLID
		var motion: PackedFloat32Array = station.get_world_3d().direct_space_state.cast_motion(query)
		check(motion[0] > 0.99, "Restroom entrance at Z %.1f is clear of bins and walls" % z)
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(12): await physics_frame
	# Let the audio mixer release stopped playback buffers before fast headless exit.
	OS.delay_msec(120)
	print("CROWD / MONITOR CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
