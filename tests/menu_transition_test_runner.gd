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
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	check(gm.notice_posted.get_connections().size() == 1, "Main menu registers its notification label")
	menu._new_game()
	for i in range(30): await physics_frame
	check(not is_instance_valid(menu), "Starting a shift frees the main menu")
	check(gm.notice_posted.get_connections().size() == 3, "Only the live HUD, pause menu and PA receive notifications")
	current_scene.get_node("StationJobs")._take("mop")
	check(gm.has_item("mop"), "Picking up an item after leaving the menu succeeds")
	change_scene_to_file("res://scenes/main_menu.tscn")
	for i in range(8): await process_frame
	check(gm.notice_posted.get_connections().size() == 1, "Returning to menu removes old station notification receivers")
	gm.notice_posted.emit("Menu notification after returning")
	current_scene.queue_free()
	for i in range(8): await process_frame
	check(gm.notice_posted.get_connections().is_empty(), "Freeing the final menu disconnects its label")
	gm.notice_posted.emit("No menus remain")
	print("MENU TRANSITION CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
