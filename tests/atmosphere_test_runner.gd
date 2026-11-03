extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ",message)
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
	var audio = station.get_node("StationAmbience")
	audio.set_process(false)
	var delay: float = audio._wait
	audio._process(200)
	check(audio._wait == delay and not audio._event.playing, "Setup stays free of tension events")
	check(audio.get_node("TunnelAir").playing, "Tunnel air remains audible without station power")
	check(audio._power_gain <= -60, "Electrical hum starts silent")
	gm.turn_on_power()
	audio._process(4)
	check(audio._power_gain == -17, "Powered electrical hum fades in")
	check(station.find_children("HallLight_*", "SpotLight3D", false, false).size() == 9, "Public ceiling fixtures cast downward light pools")
	check(station.get_node("KioskTaskLight").light_energy > 0, "Kiosk has a warm readable task light")
	for source in audio.get_children():
		check(source.bus == "Ambience" and source.max_distance > 0, "Environmental sound uses volume-controlled spatial audio")
	gm.sign_in()
	audio._wait = 0
	audio._process(0.1)
	check(audio._event.playing and audio._wait >= 100, "Rare sound plays with a long enforced quiet interval")
	var stream = audio._event.stream
	audio.play_distant_event()
	check(audio._event.stream == stream, "Tension events never overlap")
	gm.powered = false
	station._apply_station_power(false)
	audio._process(4)
	check(audio._power_gain == -60 and station.get_node("KioskTaskLight").light_energy == 0, "Power loss fades machinery and extinguishes task lighting")
	check(station.get_node("WorldEnvironment").environment.ambient_light_energy < 0.026, "Blackout remains darker than powered shadow areas")
	station.queue_free()
	for i in range(8): await process_frame
	print("ATMOSPHERE: ",failures," failures")
	quit(0 if failures == 0 else 1)
