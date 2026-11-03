extends SceneTree

var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	gm.new_campaign()
	gm.save_path = "/private/tmp/station7_update_save.json"
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for i in range(40): await physics_frame
	var services = station.get_node("StationServices")
	var player = station.get_node("Player")
	var entity = station.get_node("PassengerEntity")
	var jobs = station.get_node("StationJobs")
	check(station.CEIL_H - station.FLOOR_Y == 7, "Station hall has seven metres of clear height")
	check(station.get_node("StorageDoor_InteractiveDoor").locked == false, "Janitor room is accessible on Night 1")
	jobs._take("mop")
	check(services.return_mop() and not gm.has_item("mop") and jobs._pickups.mop.visible, "Mop can be hung back on its janitor-room holder")
	jobs._take("mop")
	check(gm.has_item("mop"), "Returned mop can be picked up again")
	jobs._take("broom")
	check(gm.has_item("broom") and services.return_tool("broom") and not gm.has_item("broom"), "Broom can also be picked up and returned to its own holder")
	gm.restore_power()
	player.flashlight_charge = 10
	check(services.charge_equipment() and player.flashlight_charge == 100, "Charging point replenishes equipment")
	gm.cause_power_failure()
	player.flashlight_charge = 20
	check(not services.charge_equipment() and player.flashlight_charge == 20, "Charging cannot bypass a power outage")
	gm.restore_power()
	var old_balance: int = gm.balance
	check(gm.reward_once("test", 7) and not gm.reward_once("test", 7) and gm.balance == old_balance + 7, "Duty rewards cannot be repeated for extra money")
	old_balance = gm.balance
	var old_stock: int = services.stock.battery
	check(services.purchase("battery") and gm.balance == old_balance - 8 and services.stock.battery == old_stock - 1, "Shop purchase charges money and deducts stock")
	gm.balance = 0
	check(not services.purchase("battery"), "Shop rejects an unaffordable purchase")
	check(services.passenger_purchase("customer") and not services.passenger_purchase("customer"), "Passenger purchases are recorded once per visit")
	check(services.customer_wallets.customer == 9, "Passenger purchase deducts their own money")
	var cases = preload("res://scripts/passenger_cases.gd")
	var registry = preload("res://scripts/identity_registry.gd")
	check(registry.investigate(cases.for_night(1, 0)[1]).kind == "stolen_ticket", "Registry confirms genuine people holding stolen tickets")
	check(registry.investigate(cases.for_night(2, 0)[0]).kind == "unverified_identity", "Impersonation produces a distinct unverified-identity result")
	var mismatch: Dictionary = cases.for_night(1, 0)[0]
	mismatch.ticket_gender = "M"
	check("Ticket gender marker does not match the identity card." in cases.errors(mismatch), "Document gender inconsistency is detectable")
	services.open_registry()
	services._registry_number.text = ""
	services._registry_number.grab_focus()
	for key in [KEY_I, KEY_P]:
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = key
		event.unicode = key
		Input.parse_input_event(event)
		await process_frame
	check(services._registry_number.text.to_upper() == "IP" and services.registry.is_open, "Inventory and phone shortcuts do not intercept identity-number typing")
	services.registry.close_panel()
	var equipment = player.camera.get_node("Equipment")
	check(equipment.equip("mop") and equipment.equipped == "mop", "Picked-up cleaning tool can be equipped in first person")
	check(equipment.equip("phone") and equipment.equipped == "phone", "Phone has a selectable first-person model")
	gm.restore_power()
	gm.sign_in()
	var original: Vector3 = player.position
	services.sit_at_desk()
	check(player.get_meta("seated_workstation") and player.in_booth_inspection, "Booth chair starts the seated inspection workstation")
	gm.save_game()
	station.get_node("PassengerService").ui.close_desk()
	check(not player.get_meta("seated_workstation") and player.position.distance_to(original) < 0.01, "Leaving the desk stands the player back in a safe position")
	player.position = Vector3(0, 0.36, -14)
	gm.load_game()
	await physics_frame
	check(player.position.distance_to(original) < 0.02 and not player.get_meta("seated_workstation"), "Loading a seated checkpoint restores a safe standing position")
	services.cctv.open_panel()
	var camera: Camera3D = services.cctv.feeds[0].camera
	var old_yaw: float = camera.rotation.y
	services.cctv.pan(0.5, 0)
	services.cctv._process(0.2)
	check(camera.rotation.y != old_yaw, "CCTV camera responds smoothly to manual pan input")
	var suspect = load("res://scripts/passenger_actor.gd").new()
	suspect.profile = cases.for_night(2, 0)[0]
	suspect.position = Vector3(0, 0.35, -3)
	station.add_child(suspect)
	suspect.set_physics_process(false)
	await physics_frame
	var balance_before_report: int = gm.balance
	services.cctv.mark_suspicious()
	services.cctv.mark_suspicious()
	check(gm.balance == balance_before_report + 5, "A camera anomaly rewards one report, not repeated clicks")
	suspect.profile.uid = "occluded-test"
	var blocked_point: Vector3 = suspect.global_position + Vector3.UP
	var blocker = station.box("TestCameraBlocker", Vector3(3, 3, 0.2), camera.global_position.lerp(blocked_point, 0.5))
	blocker.look_at(camera.global_position)
	await physics_frame
	balance_before_report = gm.balance
	services.cctv.mark_suspicious()
	check(gm.balance == balance_before_report, "CCTV cannot reward an intruder hidden behind an opaque wall")
	suspect.queue_free()
	blocker.queue_free()
	services.cctv.close_panel()
	player.position = Vector3(12, 0.36, -15.5)
	player.rotation.y = 0
	await physics_frame
	equipment._process(1)
	check(equipment.rotation.y > 0.5, "Held tools retract near a wall instead of projecting through it")
	player.position = Vector3(0, 0.36, -14)
	player.rotation.y = PI
	await physics_frame
	equipment._process(1)
	check(absf(equipment.rotation.y) < 0.01, "Held tools return to their normal pose away from a wall")
	check(not station.has_node("RestroomDoor_InteractiveDoor") and station.has_node("Rooms/Restroom/RestroomWomen_JambL") and station.has_node("Rooms/Restroom/RestroomMen_JambL"), "Restrooms have separate doorless signed entrances")
	var bowls: Array = station.find_children("CeramicBowl", "MeshInstance3D", true, false)
	check(bowls.size() == 8 and bowls[0].mesh is ArrayMesh, "Eight toilets use shaped ceramic bowl geometry")
	var pa = station.get_node("StationPA")
	pa.recordings = pa.recordings.duplicate()
	pa.recordings.approach = preload("res://scripts/mechanical_audio.gd").door_action(true, false)
	pa.announce("approach")
	# A real welcome recording may still be ahead of this clip in the PA queue.
	for i in range(900):
		await physics_frame
		if pa._speakers[0].stream == pa.recordings.approach: break
	check(pa._speakers[0].stream == pa.recordings.approach, "PA plays a custom recording after its chime")
	entity.phase = "HUNT"
	entity.position = player.position
	entity._physics_process(30)
	check(gm.state != gm.NightState.DEAD and not entity.visible, "Night 1 cannot attack even if old state says HUNT")
	gm.night = 3
	entity.hear_noise(player.position, 20)
	entity._physics_process(30)
	check(gm.state != gm.NightState.DEAD and not entity.visible, "Night 3 remains observation only")
	check(gm.save_game(), "Updated systems can be saved")
	var saved_balance: int = gm.balance
	var charge: float = services.phone_charge
	services.phone_charge = 0
	gm.balance = 500
	check(gm.load_game() and gm.balance == saved_balance and services.phone_charge == charge, "Economy and phone state survive save/load")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(12): await physics_frame
	# Allow the audio mixer to drain queued playback cleanup before shutdown.
	OS.delay_msec(100)
	await process_frame
	print("UPDATE SYSTEM CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
