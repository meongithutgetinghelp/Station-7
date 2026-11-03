extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(2)
	gm.save_path = "user://qa-checkpoint-cost.json"
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	gm.restore_power()
	gm.sign_in()
	var service = station.get_node("PassengerService")
	service.set_process(false)
	for wave in [1,2]:
		service.round_number = wave
		service._spawn_wave()
	for actor in service.actors: actor.set_physics_process(false)
	var samples: Array[float] = []
	var successful := true
	for iteration in range(28):
		var start := Time.get_ticks_usec()
		successful = preload("res://checkpoint_store.gd").write(gm.save_path + ".auto", gm._checkpoint_payload()) and successful
		var milliseconds := (Time.get_ticks_usec() - start) / 1000.0
		if iteration >= 3: samples.append(milliseconds)
	var ordered := samples.duplicate()
	ordered.sort()
	var record := {"scope":"Headless CPU/filesystem cost, 24-passenger snapshot; not a rendered FPS measurement", "passengers":service.actors.size(), "samples":samples, "median_ms":ordered[12], "p95_ms":ordered[23], "maximum_ms":ordered[24], "all_writes_succeeded":successful, "bytes":FileAccess.get_file_as_bytes(gm.save_path + ".auto").size()}
	DirAccess.make_dir_recursive_absolute("res://builds/dinner-qa")
	FileAccess.open("res://builds/dinner-qa/checkpoint-cost.json",FileAccess.WRITE).store_string(JSON.stringify(record,"  "))
	print(JSON.stringify(record))
	for suffix in [".auto", ".auto.bak", ".auto.tmp", ".auto.bak.tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.save_path + suffix))
	for audio in station.find_children("*","AudioStreamPlayer3D",true,false): audio.stop()
	station.queue_free()
	for i in range(10): await process_frame
	OS.delay_msec(100)
	quit(0 if successful else 1)
