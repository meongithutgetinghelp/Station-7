extends SceneTree
var station: Node
var desk: Node
var samples: Array = []
func _init() -> void: call_deferred("run")
func snapshot(cycle: int) -> void:
	samples.append({"cycle": cycle, "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "static_bytes": OS.get_static_memory_usage(), "video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
func cycle_once(index: int) -> void:
	var profile: Dictionary = preload("res://passenger_cases.gd").for_night(1, 0)[0].duplicate(true)
	profile.uid = "document-stress-%d" % index
	desk.present_documents(profile)
	for frame in range(3): await process_frame
	desk._ink_ticket(index % 2 == 0)
	for frame in range(2): await process_frame
	desk.clear_documents()
	for frame in range(4): await process_frame
func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960,540)
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	gm.turn_on_power()
	for child in station.get_children():
		if child.name != "Player": child.set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	var player = station.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector3(-8.9,0.35,4)
	player.camera.look_at(Vector3(-7.68,1.235,4))
	player.camera.make_current()
	desk = station.get_node("BoothDesk")
	await create_timer(3).timeout
	for index in range(10): await cycle_once(index)
	snapshot(0)
	for index in range(100):
		await cycle_once(index+10)
		if (index+1) % 25 == 0: snapshot(index+1)
	var same_nodes: bool = samples[0].nodes == samples[-1].nodes
	var report := {"cycles_after_warmup":100,"stable_node_count":same_nodes,"samples":samples,"renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open("res://builds/qa-2026-11-02/document-stress.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("DOCUMENT STRESS: ", JSON.stringify(report))
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for frame in range(12): await process_frame
	OS.delay_msec(120)
	quit(0 if same_nodes else 1)
