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
	gm.start_night()
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for i in range(30): await physics_frame
	var jobs = station.get_node("StationJobs")
	jobs.set_process(false)
	station.get_node("PassengerService").set_process(false)
	station.get_node("PassengerService")._reset()
	gm.objectives_changed.disconnect(station.get_node("PassengerService")._sync_shift)
	station.get_node("PassengerEntity").set_physics_process(false)
	check(jobs._messes.is_empty() and jobs.cleanliness == 100, "A new station starts with a clean floor")
	var pool_inactive := true
	for prop in jobs._mess_pool.values(): pool_inactive = pool_inactive and not prop.visible and prop.collision_layer == 0
	check(pool_inactive, "Prepared dirt props remain invisible and non-interactive until actually spawned")
	# Keep the passenger director inactive so this isolates visitor-gated spawning.
	gm.signed_in = true
	jobs._process(500)
	check(jobs._messes.is_empty(), "Even a long elapsed interval cannot create dirt without passengers")
	var visitor := Node3D.new()
	station.add_child(visitor)
	visitor.add_to_group("passenger_actor")
	visitor.position = Vector3(2, 0.35, -8)
	jobs._process(300)
	check(jobs._messes.size() == 1 and jobs.cleanliness == 90, "A visitor enables a random dirt patch after the random delay")
	check(jobs._next_mess_delay >= 150 and jobs._next_mess_delay <= 270, "Subsequent litter uses a bounded random interval")
	jobs._take("mop")
	var id: String = jobs._messes.keys()[0]
	jobs._clean(id)
	check(jobs.cleanliness == 100 and not jobs._messes[id].visible, "The redesigned mop still cleans through the existing pickup")
	# Reusing a cleaned spot must remain cleanable instead of exhausting the spawner.
	jobs._spawn_mess(int(id))
	jobs._update_cleanliness()
	check(not jobs.cleared.has(id) and jobs._messes[id].visible, "A cleaned location can receive fresh dirt later")
	var pooled_instance: int = jobs._messes[id].get_instance_id()
	var saved: Dictionary = jobs.save_state()
	jobs._new_night(1)
	jobs.load_state(saved)
	check(jobs._messes.has(id) and jobs.cleanliness == 90, "Randomly chosen dirt locations survive save/load")
	check(jobs._messes[id].get_instance_id() == pooled_instance, "Night resets and checkpoint loads reuse prepared dirt resources")
	var surface = jobs._messes[id].get_node("TexturedMess")
	check(surface.mesh.size.x >= 1.5 and surface.material_override is ShaderMaterial, "Mess patches are larger, irregular textured surfaces instead of small blocks")
	var visitors: Array[Node3D] = []
	for spot in jobs._spots:
		var person := Node3D.new()
		station.add_child(person)
		person.position = spot
		person.add_to_group("passenger_actor")
		visitors.append(person)
	for attempt in range(30): jobs._spawn_random_mess()
	var active: Array = []
	for mess_id in jobs._messes:
		if not jobs.cleared.has(mess_id): active.append(jobs._messes[mess_id])
	check(active.size() <= 3, "Automatic litter never exceeds three active patches")
	var separated := true
	for first in range(active.size()):
		for second in range(first + 1, active.size()):
			separated = separated and active[first].position.distance_to(active[second].position) >= 8
	check(separated, "Automatic litter does not cluster nearby patches")
	for person in visitors: person.queue_free()
	visitor.queue_free()
	await process_frame
	var count: int = jobs._messes.size()
	jobs._process(500)
	check(jobs._messes.size() == count and jobs._spawn_timer == 0, "Litter stops spawning after the last visitor leaves")
	check(get_nodes_in_group("trash_cans").size() == 8, "Eight trash cans are placed in passenger areas")
	# Validate bin clearance against existing station collision, excluding the floor.
	for bin in get_nodes_in_group("trash_cans"):
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.70, 0.90, 0.50)
		query.shape = shape
		query.transform = Transform3D(bin.global_basis, bin.global_position)
		query.exclude = [bin.get_rid()]
		query.collision_mask = preload("res://collision_layers.gd").SOLID
		var hits: Array = station.get_world_3d().direct_space_state.intersect_shape(query)
		for hit in hits: print("BIN CLEARANCE: ", bin.name, " near ", hit.collider.name)
		check(hits.is_empty(), "%s has clearance from walls, benches and doors" % bin.name)
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(12): await physics_frame
	print("CLEANING CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
