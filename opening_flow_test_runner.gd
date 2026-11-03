extends SceneTree

var failures := 0
var openings := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	gm.save_path = "user://opening-flow-test.json"
	gm.new_campaign()
	gm.notice_posted.connect(func(text: String) -> void:
		if text == "The Station Is Now Open": openings += 1)
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for frame in range(20): await physics_frame
	var service = station.get_node("PassengerService")
	var jobs = station.get_node("StationJobs")
	var wires = jobs.wire_panel
	var hud = station.get_node("NightHUD")
	var logbook = preload("res://interactable.gd").resolve(station.get_node("TB_LogbookInteraction"))
	check(not gm.powered and gm.state == gm.NightState.BLACKOUT, "New campaign starts with station power switched off")
	var dark := true
	for light in get_nodes_in_group("station_lights"): dark = dark and light.light_energy == 0
	check(dark and not station.mat_light_fixture.emission_enabled, "Every mains light and fixture glow starts off")
	check(service.actors.is_empty() and not service.started, "No passengers exist before opening, including after deferred setup")
	check(load("res://shift_guidance.gd").next_step(gm, self).contains("switch on the main power"), "Opening guidance sends staff to switch on the station")
	logbook.interact()
	check(not gm.signed_in and openings == 0 and service.actors.is_empty(), "Logbook rejects sign-in while power is off")
	gm.advance_clock(100000)
	check(gm.time_minutes == gm.START_MINUTE, "Startup preparation does not consume the shift clock")
	service._wave_timer = 100
	service._process(100)
	service._spawn_wave()
	check(service.actors.is_empty(), "Passenger timers and direct wave requests cannot populate a closed station")
	check(gm.save_game(), "Closed station can be saved")
	check(not gm.needs_power_repair() and not gm.objectives.has("restore_power"), "Startup is not treated as an electrical fault")
	station._use_breaker()
	check(gm.powered and not wires.is_open and wires.connected.is_empty(), "The main power switch starts the station without a wire puzzle")
	check(gm.objectives.start_power.done and gm.balance == 20, "Routine startup completes without earning a repair reward")
	check(not gm.signed_in and service.actors.is_empty(), "Switching on the lights does not open the station")
	check(gm.load_game() and not gm.powered and not gm.signed_in and service.actors.is_empty(), "Loading a powered-off station preserves startup preparation")
	station._use_breaker()
	gm.save_game()
	gm.cause_power_failure()
	check(gm.load_game() and gm.powered and not gm.signed_in and service.actors.is_empty(), "Loading powered but unsigned preparation keeps arrivals stopped")
	check(not hud._opening_title.visible, "Loading preparation never displays the opening banner")
	logbook.interact()
	check(gm.signed_in and openings == 1 and service.actors.size() == 3, "Signing the powered station's logbook starts the first passenger wave exactly once")
	check(hud._opening_title.visible and hud._opening_title.text == "The Station Is Now Open", "Sign-in displays the exact requested opening text on screen")
	logbook.interact()
	check(openings == 1 and service.actors.size() == 3, "Repeated sign-in cannot replay the opening or duplicate passengers")
	gm.advance_clock(10)
	check(gm.time_minutes > gm.START_MINUTE, "The shift clock advances after opening")
	gm.save_game()
	hud._opening_tween.kill()
	hud._opening_title.hide()
	check(gm.load_game() and gm.signed_in and service.actors.size() == 3 and openings == 1 and not hud._opening_title.visible, "Loading an open station resumes passengers without a new opening announcement")
	gm.cause_power_failure()
	check(gm.needs_power_repair() and not gm.turn_on_power(), "The normal startup switch cannot bypass a genuine fault")
	station._use_breaker()
	check(wires.is_open and not wires.flip_switch(), "A genuine fault opens the wire repair puzzle")
	wires.connect_wire(0, 0)
	wires.connect_wire(1, 1)
	check(not wires.flip_switch() and not gm.powered, "Two wires cannot repair a genuine fault")
	wires.connect_wire(2, 2)
	check(wires.flip_switch() and gm.powered, "All three repaired wires and the main switch clear a genuine fault")
	logbook.interact()
	check(gm.signed_in and openings == 1 and service.actors.size() == 3, "Later outages and repairs never reopen or duplicate the station")
	for night in range(1, 8):
		gm.start_night(night)
		for frame in range(2): await process_frame
		check(not gm.powered and not gm.signed_in and service.actors.is_empty(), "Night %d resets to dark, closed and empty" % night)
		if night >= 4:
			jobs._take("maintenance_key")
			var door = station.get_node("ElecDoor_InteractiveDoor")
			door.interact()
			check(not door.locked and door.is_open, "Night %d breaker room remains accessible with Security's key while station power is off" % night)
			door.set_open(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.save_path))
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for frame in range(8): await process_frame
	print("OPENING FLOW CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
