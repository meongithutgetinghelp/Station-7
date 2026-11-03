extends SceneTree

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	var cases = preload("res://passenger_cases.gd")
	for night in range(1, 8):
		var valid := 0
		for wave in range(3):
			for person in cases.for_night(night, wave):
				if cases.errors(person).is_empty(): valid += 1
		check(valid > 0, "Night %d has at least one valid passenger for boarding" % night)
	check(cases.service_date(2) == "01 NOV 2026", "Service dates cross the month boundary")
	gm.start_night(6)
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for i in range(20): await physics_frame
	check(not gm.powered and station.has_node("StorageDoor_InteractiveDoor"), "Night 6 starts dark and adds its storage door")
	check(station.get_node("ElecDoor_InteractiveDoor").locked, "Later nights require the maintenance key")
	var nav = station.get_node("StationNavigation")
	check(nav.ready_for_paths, "Later-night navigation bakes successfully")
	gm.restore_power()
	gm.sign_in()
	gm.inspect_platform()
	var service = station.get_node("PassengerService")
	service.reviewed = service.total_cases()
	service.correct = service.reviewed
	station.get_node("StationJobs").cleanliness = 100
	station.get_node("PassengerEntity").banished = true
	var report = station.get_node("ShiftReport")
	report._show_report()
	check(report.heading.text.contains("NOT SECURED"), "A night cannot pass without train boarding")
	report.close_panel()
	paused = false
	station.get_node("TrainService").boarded_count = 1
	report._show_report()
	check(report.heading.text.contains("COMPLETE"), "A secured later night offers progression")
	report.close_panel()
	paused = false
	gm.objectives["fix_light"] = {"text": "Repair", "done": false}
	report._show_report()
	check(report.heading.text.contains("NOT SECURED"), "Outstanding maintenance blocks a successful report")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(8): await process_frame
	OS.delay_msec(100)
	print("CAMPAIGN CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
