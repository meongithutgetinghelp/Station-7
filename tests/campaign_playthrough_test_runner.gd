extends SceneTree
## A scripted crew exercises real NPC navigation, decisions, boarding, beam
## containment, repairs, checkpoints and scene transitions. Not a human playtest.
var failures := 0
var seed_number := 17
var station: Node

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): seed_number = int(argument.trim_prefix("--seed="))
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	seed(seed_number)
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.save_path = "user://campaign-playthrough-%d.json" % seed_number
	gm.new_campaign()
	var root_baseline := root.get_child_count()
	station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for number in range(1, 8):
		var service = station.get_node("PassengerService")
		var jobs = station.get_node("StationJobs")
		var train = station.get_node("TrainService")
		var entity = station.get_node("PassengerEntity")
		var player = station.get_node("Player")
		var events = station.get_node("NightEvents")
		# Keep natural pre-ticket visits; only optional conversation offers are off.
		station.get_node("PassengerDialogueEvents").set_process(false)
		player.set_physics_process(false)
		for i in range(15): await physics_frame
		print("NIGHT BASELINE: ", JSON.stringify({"night": number, "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)), "static_bytes": OS.get_static_memory_usage()}))
		check(gm.night == number, "Campaign enters night %d without skipping a scene" % number)
		gm.restore_power()
		gm.sign_in()
		gm.give_item("mop")
		player.position = Vector3(-5, 0.35, 15)
		gm.inspect_platform()
		if number >= 4:
			for clue in ["camera", "power", "light"]:
				station.get_node("Clue_" + clue + "/Interaction").interact()
				jobs.journal.close_panel()
			jobs._identify()
		var resumed := false
		var simulation_seconds := 0.0
		for frame in range(72000):
			await physics_frame
			gm._process(1.0 / 60.0)
			simulation_seconds += 1.0 / 60.0
			if gm.state in [gm.NightState.SHIFT_OVER, gm.NightState.DEAD]: break
			if not gm.powered:
				for wire in range(3): jobs.wire_panel.connect_wire(wire, wire)
				jobs.wire_panel.flip_switch()
			if gm.objectives.has("fix_light") and not gm.objectives.fix_light.done: jobs.repair_light()
			if gm.objectives.has("fix_door") and not gm.objectives.fix_door.done: station.get_node("ElecDoor_InteractiveDoor").interact()
			if gm.objectives.has("fix_gate") and not gm.objectives.fix_gate.done: station.get_node("GateLane_1").scanner.interact()
			if service.counter_ready:
				service.decide(service.Cases.errors(service.current_profile()).is_empty())
			if events.started and not events.completed:
				match number:
					1: events.resolve("exit")
					2: events.resolve("camera")
					3: events.resolve("keep")
					5:
						if events.stage != "ESCORT": events.resolve("roster")
					7:
						for point in ["booth", "security", "platform"]: events.resolve(point)
			var escorting := false
			for actor in get_nodes_in_group("passenger_actor"):
				if actor.phase == "DANGER": actor._rescue()
				if actor.phase == "FOLLOW": escorting = true
			if number >= 4 and not entity.banished and entity.phase != "DORMANT":
				player.position = entity.position + Vector3(0, 0, -6)
				player.position.y = 0.35
				player.camera.look_at(entity.position + Vector3.UP * entity.EYE_HEIGHT)
				player.set_flashlight(true, false)
			elif escorting:
				player.position = Vector3(-10, 0.35, 4)
			for id in jobs._messes.keys(): jobs._clean(str(id))
			var desk = station.get_node("BoothDesk")
			if not resumed and service.reviewed >= ceili(service.total_cases() / 2.0) and not desk.stamping and not desk.sliding and not desk._returning:
				var reviewed: int = service.reviewed
				var balance: int = gm.balance
				check(gm.save_game() and gm.load_game() and service.reviewed == reviewed and gm.balance == balance, "Night %d resumes midway without duplicate verdicts or rewards" % number)
				resumed = true
		check(resumed, "Night %d reaches its midpoint checkpoint" % number)
		check(service.reviewed == service.total_cases() and service.correct == service.reviewed, "Night %d completes every real passenger check" % number)
		check(train.boarded_count > 0, "Night %d has actual passenger boarding" % number)
		check(events.completed and entity.banished, "Night %d finishes its authored duty and contains the intruder" % number)
		check(gm.shift_blockers().is_empty() and gm.state == gm.NightState.SHIFT_OVER, "Night %d reaches a successful report in %.1f simulated seconds" % [number, simulation_seconds])
		if failures:
			print("BLOCKERS: ", gm.shift_blockers())
			print("COUNTER: ", service.counter_ready, " current=", service.current_actor, " queue=", service._queue, " release=", service._queue_release)
			for actor in get_nodes_in_group("passenger_actor"): print(actor.profile.uid, " ", actor.phase, " ", actor.position, " points=", actor._points, " pending=", actor._path_pending, " announced=", actor._counter_announced)
			break
		if number < 7:
			var old_station_id: int = station.get_instance_id()
			var report = station.get_node("ShiftReport")
			report._next_night()
			report._next_night() # Fast repeated input must not skip another night.
			for i in range(30): await process_frame
			station = current_scene
			check(station.get_instance_id() != old_station_id and gm.night == number + 1 and gm.campaign.nights_completed == number, "Night %d transition accepts only one advance" % number)
		else:
			var heading: String = station.get_node("ShiftReport").heading.text
			check(heading == "SAFE DAWN", "Seven-night zero-loss campaign reaches SAFE DAWN")
			gm.record_night()
			var campaign: Dictionary = gm.campaign.duplicate(true)
			gm.record_night()
			check(gm.campaign == campaign and gm.campaign.nights_completed == 7, "Final campaign totals cannot be counted twice")
	paused = false
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(12): await process_frame
	OS.delay_msec(100)
	check(root.get_child_count() == root_baseline, "Campaign scene transitions leave no extra root-level scene or hand nodes")
	for suffix in ["", ".bak", ".auto", ".auto.bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.save_path + suffix))
	print("CAMPAIGN PLAYTHROUGH seed ", seed_number, ": ", failures, " failures")
	quit(1 if failures else 0)
