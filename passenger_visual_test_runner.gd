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
	var appearance = load("res://passenger_appearance.gd")
	var cases = load("res://passenger_cases.gd").for_night(4, 0, 8)
	var world := Node3D.new()
	root.add_child(world)
	var people: Array = []
	var hair_styles: Dictionary = {}
	for wave in range(3):
		for profile in load("res://passenger_cases.gd").for_night(4, wave, 8):
			var visual = load("res://passenger_visual.gd").new()
			visual.profile = profile
			world.add_child(visual)
			people.append(visual)
			hair_styles[visual.appearance.hair_style] = true
	check(people.size() == 24 and hair_styles.size() == 4, "Full crowd uses all four hair silhouettes")
	var a: Node3D = people[0]
	var b = load("res://passenger_visual.gd").new()
	b.profile = cases[0].duplicate(true)
	world.add_child(b)
	check(a.appearance == b.appearance, "Independent instances derive the same saved passenger identity")
	var altered: Dictionary = cases[0].duplicate(true)
	altered.ticket_name = "STOLEN NAME"
	check(appearance.describe(altered) == a.appearance, "A forged ticket cannot change its owner's appearance")
	var meshes_a = a.find_children("*", "MeshInstance3D", true, false)
	var meshes_b = b.find_children("*", "MeshInstance3D", true, false)
	var shared := true
	var hair_visible := 0
	var visible_triangles := 0
	var layers_correct := true
	for index in range(meshes_a.size()):
		shared = shared and meshes_a[index].mesh == meshes_b[index].mesh
		if str(meshes_a[index].name).begins_with("HairStyle") and meshes_a[index].visible: hair_visible += 1
		if meshes_a[index].visible:
			for surface in range(meshes_a[index].mesh.get_surface_count()):
				visible_triangles += meshes_a[index].mesh.surface_get_array_index_len(surface) / 3
	for person in people:
		for mesh in person.find_children("*", "MeshInstance3D", true, false):
			layers_correct = layers_correct and mesh.layers == (2 if person.profile.anomaly else 1)
	var detail = meshes_a.filter(func(mesh: Node) -> bool: return str(mesh.name) == "Detail")[0]
	check(detail.get_active_material(0).vertex_color_use_as_albedo, "Human pupils, lips and eyeglass frames retain their authored colors")
	check(shared, "Passengers reuse imported mesh resources instead of duplicating geometry")
	check(hair_visible == 1, "Only the selected hair variant is visible")
	check(visible_triangles > 500 and visible_triangles < 12000, "Visible passenger geometry stays within the crowd budget (%d triangles)" % visible_triangles)
	check(layers_correct, "Every anomaly surface is absent from the camera's normal layer")
	var foot: Vector3 = a.joint_world("Foot.L")
	check(foot.y > 0.06 and foot.y < 0.12 and a.joint_world("Head").y > 1.4, "Imported rest transforms preserve human proportions with feet at floor level")
	var initial: Vector3 = a.joint_world("Foot.L")
	for frame in range(24): a.update_motion(1.0 / 60.0, 1.7)
	check(a.joint_world("Foot.L").distance_to(initial) > 0.03, "Walking moves the skinned leg joints")
	a.set_seated(true, .56)
	var pelvis: Vector3 = a.joint_world("Pelvis")
	check(absf(pelvis.y - .62) < .02, "Seated pelvis rests above the bench surface")
	check(a.joint_world("Shin.L").z > .3 and a.joint_world("Foot.L").y < .12, "Sitting bends thighs forward while feet reach the floor")
	a.set_seated(true, .56)
	check(a.joint_world("Pelvis").distance_to(pelvis) < .001, "Repeated seat snapshots do not accumulate pose offsets")
	a.set_seated(false)
	check(a.joint_world("Foot.L").distance_to(foot) < .001, "Standing restores original leg length and pose")
	world.queue_free()
	await process_frame
	print("PASSENGER VISUAL CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
