extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.new_campaign()
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var robot = station.get_node("KioskRobot")
	check(robot.is_in_group("kiosk_robot") and not robot.is_in_group("passengers") and not station.has_node("Shopkeeper"), "Automated kiosk operator is separate from passenger simulation")
	check(not robot.powered and not robot._status.visible, "Robot starts offline with station power")
	var cameras = get_nodes_in_group("station_cameras")
	check(cameras.size() == 6, "All six live feeds have a physical camera")
	var entries = station.get_node("StationJobs")._camera_screens
	for i in range(6):
		var hardware = entries[i].hardware
		var feed: Camera3D = entries[i].camera
		check(hardware.optical_center.global_position.is_equal_approx(feed.global_position), "Camera %d lens matches its feed position" % (i+1))
		check((feed.cull_mask & hardware.hardware_layer) == 0 and (station.get_node("Player").camera.cull_mask & hardware.hardware_layer) != 0, "Camera %d visible to player without blocking own feed" % (i+1))
		var isolated := true
		for visual in hardware.find_children("*", "VisualInstance3D", true, false):
			isolated = isolated and visual.layers == hardware.hardware_layer
		check(isolated, "Camera %d all housing parts use its exclusion layer" % (i+1))
		feed.rotation.y += 0.3
		feed.rotation.x -= 0.15
		hardware._process(0)
		check(hardware.head.global_basis.is_equal_approx(feed.global_basis), "Camera %d housing tracks live pan and tilt" % (i+1))
		check(not hardware._led.emission_enabled, "Camera %d starts with recording LED off" % (i+1))
	gm.turn_on_power()
	check(robot.powered and robot._status.visible and robot._indicator.emission_enabled, "Robot wakes with station power")
	var all_lit := true
	for camera in cameras: all_lit = all_lit and camera._led.emission_enabled
	check(all_lit, "All camera recording LEDs follow station power")
	var services = station.get_node("StationServices")
	gm.balance = 100
	var stock_before: int = services.stock.battery
	check(services.purchase("battery") and services.stock.battery == stock_before-1 and gm.balance == 100-services.prices.battery, "Robot kiosk retains purchase and stock accounting")
	gm.balance = 0
	check(not services.purchase("battery") and services.stock.battery == stock_before-1, "Unaffordable purchase preserves stock")
	services.open_shop()
	check(services.shop.is_open and services.shop.body.get_child_count() >= 4, "Original counter shop still opens its product list")
	services.shop.close_panel()
	robot._power_changed(false)
	for camera in cameras: camera._power_changed(false)
	check(not robot._status.visible and not robot._indicator.emission_enabled, "Robot shuts its display off when power drops")
	station.queue_free()
	for frame in range(8): await process_frame
	print("ROBOT CAMERA CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
