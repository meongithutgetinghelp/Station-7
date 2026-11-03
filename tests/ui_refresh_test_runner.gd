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
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var settings = get_first_node_in_group("pause_menu")
	settings.settings_path = "user://ui-refresh-test.cfg"
	var settings_button = menu.get_node("MenuArtwork/MenuButtons/Settings")
	settings_button.grab_focus()
	settings.set_paused(true)
	await process_frame
	check(settings._overlay.visible and settings._resume.has_focus(), "Opening settings focuses its back control")
	check(settings._pages.get_tab_count() == 4 and not settings._tabs[3].visible, "Main menu shows three settings categories without shift actions")
	for index in range(3):
		settings._tabs[index].button_pressed = true
		settings._tabs[index].pressed.emit()
		check(settings._pages.current_tab == index, "Settings category %d opens its controls" % index)
	settings._show_fps.button_pressed = false
	settings._show_fps.button_pressed = true
	settings._process(0.3)
	check(settings._fps_counter.visible and settings._fps_counter.text.ends_with(" FPS"), "Display toggle immediately shows a live FPS counter while paused")
	settings.set_paused(false)
	var preferences := ConfigFile.new()
	check(preferences.load(settings.settings_path) == OK and preferences.get_value("display", "show_fps", false), "FPS preference saves with display settings")
	settings._show_fps.button_pressed = false
	check(not settings._fps_counter.visible, "Disabling the FPS toggle immediately hides the counter")
	settings._load_settings()
	check(settings._show_fps.button_pressed and settings._fps_counter.visible, "Reloading preferences restores the FPS counter")
	settings.set_paused(true)
	settings._volume.value = 63
	settings._sensitivity.value = 3.2
	settings._reduced_motion.button_pressed = true
	settings.set_paused(false)
	check(settings_button.has_focus(), "Closing settings restores keyboard focus")
	settings.set_paused(true)
	check(is_equal_approx(settings._overlay.modulate.a, 1.0), "Reduced motion opens settings without a fade")
	check(settings._volume.value == 63 and is_equal_approx(settings._sensitivity.value, 3.2), "Changing tabs and reopening preserves slider values")
	settings.set_paused(false)
	menu._open_lobby(true)
	await process_frame
	check(menu._lobby.is_open and menu._host_button.visible and not menu._join_button.visible, "Host lobby remains functional with the shared presentation")
	menu._lobby.close_panel()
	check(not menu._lobby.visible and settings_button.has_focus(), "Closing the lobby hides its backdrop and restores focus")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.settings_path))
	menu.queue_free()
	for frame in range(3): await process_frame
	print("UI REFRESH CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
