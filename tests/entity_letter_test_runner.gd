extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func run() -> void:
	root.get_node("GameManager").set_process(false)
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	await process_frame
	var jobs = station.get_node("StationJobs")
	var player = station.get_node("Player")
	var notes = jobs.scattered_notes
	var prop = notes.get_child(0)
	var reader = jobs.entity_letter
	check(root.get_node("Coop").local_interaction(prop.get_node("Interaction")), "Letter inspection stays local in co-op")
	check(not reader.is_open and not reader.visible, "Letter reader starts closed")
	check(reader._root.get_node("LetterArtwork").size == Vector2(540, 636), "High-resolution letter fits the close-up without clipping")
	var material = prop.get_node("LetterArtwork").material_override
	check(material.albedo_texture == reader.ARTWORK, "World prop and close-up use approved letter texture")
	check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "Torn paper silhouette uses texture transparency")
	prop.get_node("Interaction").interact()
	check(reader.is_open and reader.visible and player.in_booth_inspection, "Read interaction opens letter and locks movement")
	check(jobs.clues.is_empty(), "Optional letter does not count toward the three required clues")
	jobs.open_journal()
	check(not reader.is_open and jobs.journal.is_open and player.in_booth_inspection, "Opening journal closes letter without unlocking the active modal")
	reader.open_panel()
	check(not jobs.journal.is_open and reader.is_open, "Reopening letter closes other world panels")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	reader._input(tab)
	check(not reader.is_open and not player.in_booth_inspection, "Tab puts down letter and restores movement")
	var ids: Array = []
	for night in range(1, 8):
		root.get_node("GameManager").night = night
		jobs._new_night(night)
		await physics_frame
		await process_frame
		check(notes.get_child_count() >= 1 and notes.get_child_count() <= 2, "Night %d has only 1-2 notes" % night)
		var positions: Array = []
		for note in notes.get_children():
			var id: int = note.get_meta("note_id")
			check(not ids.has(id), "Night %d adds a distinct message" % night)
			ids.append(id)
			check(not (note.position.x < -6 and note.position.x > -16 and note.position.z > 0 and note.position.z < 10), "Note is outside the ticket booth")
			check(root.get_node("Coop").local_interaction(note.get_node("Interaction")), "Every note reads locally for co-op players")
			var eye: Vector3 = note.global_position + Vector3(0.35, 1.05, 0.65)
			if night == 4: eye = note.global_position + Vector3(0.9, 1.05, 0.2)
			if id == 3: eye = note.global_position + Vector3(-0.8, 1.05, 0.1)
			var query := PhysicsRayQueryParameters3D.create(eye, note.global_position - Vector3.UP * 0.01, 9)
			var hit = station.get_world_3d().direct_space_state.intersect_ray(query)
			check(not hit.is_empty() and hit.collider == note, "Note is unobstructed and targetable from standing reach")
			var texture = note.get_node("LetterArtwork").material_override.albedo_texture
			note.get_node("Interaction").interact()
			check(reader._root.get_node("LetterArtwork").texture == texture, "Close-up matches this note's world artwork")
			positions.append(note.position)
		var first = notes.get_child(0)
		jobs.load_state(jobs.save_state())
		check(notes.get_child(0) == first and reader.is_open, "Same-night refresh neither duplicates notes nor closes reader")
		reader.close_panel()
		# Rebuild as a fresh load/client would, independently of the global RNG.
		notes.current_night = 0
		randf()
		notes.set_night(night)
		var restored: Array = []
		for note in notes.get_children(): restored.append(note.position)
		check(restored == positions, "Reload and co-op reconstruction keep identical placements")
	check(ids.size() == 10, "Ten unique handwritten notes are distributed across seven nights")
	check(station.get_node_or_null("EntityLetter") == null, "Old permanent booth letter is removed")
	print("Entity letter failures: ", failures)
	station.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
