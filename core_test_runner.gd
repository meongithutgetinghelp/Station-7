extends SceneTree

var failures: int = 0


func _init() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func run() -> void:
	var manager := root.get_node("GameManager")
	manager.set_process(false)
	manager.start_night()
	manager.save_path = "/private/tmp/station7_core_save.json"
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var nav = station.get_node("StationNavigation")
	for i in range(200):
		await physics_frame
		if nav.ready_for_paths: break
	check(nav.ready_for_paths, "Runtime station navigation is baked")
	var route := NavigationServer3D.map_get_path(root.get_world_3d().navigation_map, Vector3(-10, 0.35, 3), Vector3(0, 0.35, 13), true)
	check(route.size() >= 2, "Navigation connects booth and platform through the gate opening")
	manager.restore_power()
	manager.sign_in()
	manager.give_item("mop")
	manager.advance_clock(12)
	var player = station.get_node("Player")
	player.position = Vector3(-10, 0.36, 3)
	await physics_frame
	var service = station.get_node("PassengerService")
	var old_time: float = manager.time_minutes
	var old_position: Vector3 = player.position
	check(manager.save_game(), "Shift and participant state save successfully")
	manager.cause_power_failure()
	manager.inventory.clear()
	player.position = Vector3(10, 0.4, -10)
	manager.advance_clock(100)
	check(manager.load_game(), "Saved shift loads")
	check(manager.powered and manager.signed_in and is_equal_approx(manager.time_minutes, old_time), "Clock, sign-in and power are restored")
	check(manager.has_item("mop") and manager.has_item("employee_id"), "Inventory survives save/load")
	check(player.position.distance_to(old_position) < 0.01, "Player position is restored")
	check(service.started and service.actors.size() == 3 and service.reviewed == 0, "Tutorial passenger queue is restored without duplicates")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	station.queue_free()
	for i in range(8):
		await physics_frame
	OS.delay_msec(50)
	print("CORE CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
