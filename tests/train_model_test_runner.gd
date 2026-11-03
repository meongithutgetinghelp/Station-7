extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error(text)
func run() -> void:
	var train = load("res://scripts/train_service.gd").new()
	root.add_child(train)
	train.set_process(false)
	var model = train.vehicle.get_node("SubwayModel")
	check(model.find_children("Shell_*", "MeshInstance3D", true, false).size() == 4, "Supplied subway model replaces the old three-car train with four coaches")
	check(train._doors.size() == 48, "All 24 doorways have two functioning sliding leaves")
	var door = train._doors[0]
	var glass = door.node.find_children("DoorGlass_*", "MeshInstance3D", true, false)
	check(glass.size() == 1, "Original door glass is attached to its animated leaf")
	var closed: float = door.node.position.x
	var glass_closed: Vector3 = glass[0].global_position
	train._set_doors(true, true)
	check(is_equal_approx(door.node.position.x, closed + door.direction * 0.78), "Imported door opens with the existing service animation distance")
	check(is_equal_approx(absf(glass[0].global_position.x - glass_closed.x), 0.78), "Door glazing travels with its sliding leaf")
	train._set_doors(false, true)
	check(is_equal_approx(door.node.position.x, closed), "Imported door returns exactly to its closed position")
	check(train.boarding_point(Vector3(-6,0,14)).x == -6.25 and train.boarding_point(Vector3(24,0,14)).x == 22.75, "Boarding approaches line up with the supplied model's actual doorways")
	train.phase = "BOARDING"
	train.elapsed = 12
	train.vehicle.visible = true
	train.vehicle.position.x = 0
	var state: Dictionary = train.save_state()
	train.phase = "WAITING"
	train.load_state(state)
	check(train.phase == "BOARDING" and is_equal_approx(door.node.position.x, closed + door.direction * 0.78), "Loading a boarding checkpoint restores the imported train with open doors")
	train.queue_free()
	await process_frame
	print("SUBWAY MODEL CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
