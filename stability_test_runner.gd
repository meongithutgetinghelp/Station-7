extends SceneTree

const Store = preload("res://checkpoint_store.gd")
const Cases = preload("res://passenger_cases.gd")
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func write_raw(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	gm.save_path = "user://stability-recovery-test.json"
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.save_path + suffix))
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for path in ["PassengerDialogueEvents", "NightEvents", "TrainService"]: station.get_node(path).set_process(false)
	for i in range(12): await physics_frame
	var service = station.get_node("PassengerService")
	check(service.passengers_per_round == 3 and service.total_cases() == 9, "Tutorial has nine checks, down from twenty-four")
	var valid := 0
	var anomaly := 0
	for wave in range(service.round_limit):
		for profile in Cases.for_night(1, wave, service.passengers_per_round):
			if Cases.errors(profile).is_empty(): valid += 1
			if profile.anomaly: anomaly += 1
	check(valid >= 1 and anomaly == 1, "Smaller tutorial retains boarding candidates and the final camera lesson")
	check(Cases.for_night(1, 0, 3)[0].anomaly == false, "First tutorial passenger is genuine")
	gm.restore_power()
	gm.sign_in()
	service.set_process(false)
	check(service.actors.size() == 3, "Opening the tutorial spawns just three passengers")
	check(gm.save_game(), "First checkpoint commits successfully")
	check(Store.read_valid(gm.save_path).core.time == gm.START_MINUTE, "Committed checkpoint reads back intact")
	gm.time_minutes += 10
	check(gm.save_game(), "A second checkpoint replaces the first")
	check(Store.read_valid(gm.save_path + ".bak").core.time == gm.START_MINUTE, "Previous valid checkpoint is retained as backup")
	check(not FileAccess.file_exists(gm.save_path + ".tmp"), "Successful save leaves no incomplete temporary file")
	write_raw(gm.save_path, "{\"version\":1,\"core\":")
	check(gm.read_checkpoint().get("recovered_backup", false), "Truncated primary selects the valid backup")
	check(gm.load_game() and gm.time_minutes == gm.START_MINUTE, "Recovery restores a coherent earlier game state")
	check(service.actors.size() == 3 and service.total_cases() == 9, "Recovered tutorial keeps its queue and workload")
	write_raw(gm.save_path, '{"version":1,"core":{"night":1,"objectives":[],"inventory":{}}}')
	check(gm.read_checkpoint().get("recovered_backup", false), "Malformed state types cannot bypass backup recovery")
	check(gm.save_game(), "Saving after recovery succeeds")
	check(Store.read_valid(gm.save_path + ".bak").core.time == gm.START_MINUTE, "Saving over a corrupt primary preserves the valid backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.save_path))
	check(gm.read_checkpoint().get("recovered_backup", false), "Missing primary also recovers from backup")
	check(gm.save_game(), "Missing primary can be recreated safely")
	var complete: Dictionary = Store.read_valid(gm.save_path)
	var invalid: Dictionary = complete.duplicate(true)
	invalid.participants.Player.position = [1, 2]
	write_raw(gm.save_path, JSON.stringify(invalid))
	check(gm.read_checkpoint().get("recovered_backup", false), "Malformed player coordinates choose backup before mutating live state")
	invalid = complete.duplicate(true)
	invalid.core.state = 99
	write_raw(gm.save_path, JSON.stringify(invalid))
	check(gm.read_checkpoint().get("recovered_backup", false), "Unknown saved game states cannot strand the loaded shift")
	invalid = complete.duplicate(true)
	invalid.core.inventory.battery = "broken"
	write_raw(gm.save_path, JSON.stringify(invalid))
	check(gm.read_checkpoint().get("recovered_backup", false), "Malformed inventory counts are rejected before loading")
	write_raw(gm.save_path, JSON.stringify(complete))
	var before := FileAccess.get_file_as_string(gm.save_path)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(gm.save_path + ".tmp"))
	check(not gm.save_game(), "An unwritable temporary target reports save failure")
	check(FileAccess.get_file_as_string(gm.save_path) == before, "Failed save preserves the last committed checkpoint")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.save_path + ".tmp"))
	var jobs = station.get_node("StationJobs")
	jobs.open_journal()
	var journal_text := ""
	for child in jobs.journal.body.get_children():
		if child is Label: journal_text += child.text + "\n"
	check(journal_text.contains("STILL TO DO") and journal_text.contains("No passengers boarded") and journal_text.contains("ticket checks remaining"), "Journal explains actual outstanding shift requirements")
	jobs.journal.close_panel()
	var saved: Dictionary = service.save_state()
	var legacy: Dictionary = saved.duplicate(true)
	legacy.people_per_round = 8
	service.load_state(legacy)
	check(service.total_cases() == 24, "An existing longer tutorial save keeps its original passengers and target")
	service.load_state(saved)
	check(service.total_cases() == 9, "New tutorial saves retain the reduced target")
	for suffix in ["", ".bak"]: write_raw(gm.save_path + suffix, "damaged")
	gm.kill_player()
	var report = station.get_node("ShiftReport")
	check(report.is_open and paused, "Death screen is active before a failed load")
	report._load_saved()
	check(report.is_open and paused and gm.state == gm.NightState.DEAD, "Failed load keeps the death screen and retry controls available")
	check(gm.read_checkpoint().is_empty(), "Two invalid checkpoints fail cleanly")
	report.close_panel()
	paused = false
	gm.start_night(2)
	check(service.total_cases() == 24 and service.passengers_per_round == 8, "Night 2 retains the normal full-shift workload")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.save_path + suffix))
	station.queue_free()
	for i in range(8): await process_frame
	print("STABILITY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
