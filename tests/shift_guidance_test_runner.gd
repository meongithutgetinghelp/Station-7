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
	gm.start_night(4)
	var guidance = load("res://scripts/shift_guidance.gd")
	check(guidance.next_step(gm, self).contains("switch on the main power"), "New staff receive the station startup instruction")
	check(guidance.compact_step(gm, self).contains("maintenance key from Security"), "Later-night startup names the key prerequisite before the locked breaker room")
	gm.start_night(1)
	check(guidance.compact_step(gm, self).contains("beside CCTV / SECURITY"), "First-night startup gives a usable landmark for finding Electrical")
	gm.start_night(4)
	var briefings: Dictionary = {}
	for night in range(1, 8): briefings[guidance.briefing(night)] = true
	check(briefings.size() == 7, "Each night has its own replayable briefing")
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for frame in range(10): await physics_frame
	gm.restore_power()
	gm.sign_in()
	gm.cause_power_failure()
	check(guidance.next_step(gm, self).contains("3 wires"), "Outage guidance takes priority over routine inspections")
	check("Power offline" in "\n".join(gm.shift_blockers()), "Failure checklist identifies the power outage")
	gm.restore_power()
	gm.inspect_platform()
	var service = station.get_node("PassengerService")
	service.reviewed = service.total_cases()
	service.correct = service.reviewed
	station.get_node("StationJobs").cleanliness = 100
	station.get_node("PassengerEntity").banished = true
	check("No passengers boarded" in "\n".join(gm.shift_blockers()), "Failure report explains missing train boarding")
	station.get_node("TrainService").boarded_count = 1
	check(gm.shift_blockers().is_empty(), "Completed station has no blocking duties")
	gm.lost_passengers = 2
	check("loss limit" in "\n".join(gm.shift_blockers()), "Loss limit uses the same canonical completion checklist")
	var settings = station.get_node("PauseMenu")
	settings.settings_path = "user://test-accessibility.cfg"
	settings._reduced_flashes.button_pressed = true
	settings._reduced_motion.button_pressed = true
	check(not settings._player.enable_head_bob, "Reduced motion disables player head bob")
	settings._text_scale.value = 1.25
	settings._bus_sliders.Ambience.value = 35
	settings._dirty = true
	settings.set_paused(false)
	var config := ConfigFile.new()
	check(config.load(settings.settings_path) == OK and config.get_value("display", "reduced_flashes") == true and is_equal_approx(config.get_value("display", "hud_text_scale"), 1.25), "Accessibility preferences save locally")
	settings._reduced_flashes.button_pressed = false
	settings._load_settings()
	check(settings.reduced_flashes() and settings._bus_sliders.Ambience.value == 35, "Flashing and independent audio preferences reload")
	var light = get_nodes_in_group("station_lights").filter(func(node: Node) -> bool: return str(node.name).begins_with("HallLight"))[0]
	var before: float = light.light_energy
	station.get_node("StationJobs").trigger_fault("flicker")
	check(is_equal_approx(light.light_energy, before), "Reduced flashing suppresses the decorative flicker sequence")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.settings_path))
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for frame in range(8): await process_frame
	print("SHIFT GUIDANCE CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
