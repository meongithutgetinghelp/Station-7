extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(file: String) -> void:
	for i in range(24): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/ui-refresh/" + file + ".png")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.4, true).timeout
	await capture("main-menu")
	menu._open_lobby(true)
	await capture("lobby")
	menu._lobby.close_panel()
	for child in menu.get_children():
		if child is CanvasLayer and child.is_in_group("pause_menu"):
			child.set_paused(true)
			await create_timer(0.35, true).timeout
			child._layout_sheet()
			await capture("settings")
			child._tabs[1].button_pressed = true
			child._tabs[1].pressed.emit()
			await capture("display-settings")
			child._tabs[2].button_pressed = true
			child._tabs[2].pressed.emit()
			await capture("sound-settings")
			child.set_paused(false)
	menu._new_game()
	for i in range(12): await physics_frame
	await capture("gameplay-hud")
	quit()
