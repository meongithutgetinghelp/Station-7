extends SceneTree

const InteractionComponent = preload("res://scripts/interactable.gd")

var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var manager := root.get_node("GameManager")
	manager.set_process(false)
	manager.start_night()
	var scene := load("res://scenes/station_builder.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var station := scene.instantiate()
	root.add_child(station)
	for i in range(30):
		await physics_frame
	var hall_light: Light3D
	for child in station.get_children():
		if child is Light3D and str(child.name).begins_with("HallLight_"):
			hall_light = child
	var player := station.get_node("Player") as Player
	check(player.is_on_floor(), "Player spawns on solid floor")
	check(player._stamina_progress != null, "Stamina HUD exists")
	check(not station.debug_bright_mode, "Scene starts in night lighting")
	check(station.has_node("TrackGuard"), "Track guard enabled by saved scene")
	check(station.has_node("NightHUD"), "Clock and objectives HUD exists")
	check(station.has_node("TStair_23") and station.has_node("StreetArrivalFloor"), "Entrance stairs connect to the outside arrival apron")
	var space := root.get_world_3d().direct_space_state
	var west_return := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-21.0, 1.8, 12.0), Vector3(-21.0, 1.8, 8.0)))
	check(not west_return.is_empty() and west_return.collider.name == "Platform_WestReturn", "Solid wall blocks the platform view and access to the removed empty area")
	# Probe the shared wall above the clear floor strip, away from the shelves.
	var booth_back := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-15.7, 1.8, 5.5), Vector3(-16.8, 1.8, 5.5)))
	check(not booth_back.is_empty() and booth_back.collider.name == "Conc_West", "Booth shares the station wall without an intermediate gap")
	var booth_south := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-15.5, 1.8, 0.5), Vector3(-15.5, 1.8, 2.0)))
	var booth_north := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-15.5, 1.8, 8.0), Vector3(-15.5, 1.8, 6.0)))
	check(not booth_south.is_empty() and not booth_north.is_empty(), "Extended booth walls seal both ends of the former gap")
	# Every shared junction must own its volume: adjoining wall meshes end at
	# its faces rather than overlapping it or hiding underneath a wider sleeve.
	var flush_joints: bool = true
	for joint: StaticBody3D in station._wall_bodies:
		if not str(joint.name).begins_with("CornerReturn_"):
			continue
		var joint_mesh := joint.get_child(0) as MeshInstance3D
		var joint_bounds: AABB = joint_mesh.global_transform * joint_mesh.get_aabb()
		for adjoining: StaticBody3D in station._wall_bodies:
			if adjoining == joint:
				continue
			for part in adjoining.get_children():
				if part is MeshInstance3D:
					var shared: AABB = joint_bounds.intersection(part.global_transform * part.get_aabb())
					if shared.size.x > 0.0001 and shared.size.y > 0.0001 and shared.size.z > 0.0001:
						flush_joints = false
	check(flush_joints, "Wall junctions meet edge-to-edge without overlapping corner sleeves")
	var counter := station.get_node("TB_Counter").get_child(0) as MeshInstance3D
	var counter_bounds: AABB = counter.global_transform * counter.get_aabb()
	var south_post := station.get_node("CornerReturn_BoothWindowSouth").get_child(0) as MeshInstance3D
	var north_post := station.get_node("CornerReturn_BoothWindowNorth").get_child(0) as MeshInstance3D
	var south_bounds: AABB = south_post.global_transform * south_post.get_aabb()
	var north_bounds: AABB = north_post.global_transform * north_post.get_aabb()
	check(is_equal_approx(counter_bounds.position.z, south_bounds.end.z) and is_equal_approx(counter_bounds.end.z, north_bounds.position.z), "Booth counter fits exactly between its wall ends")
	var cut_source := AABB(Vector3.ZERO, Vector3(4, 3, 2))
	var cut := AABB(Vector3(1, 0.5, 0.5), Vector3(2, 2, 1))
	var remainder: float = 0.0
	for piece: AABB in station._subtract_wall_box(cut_source, cut):
		remainder += piece.get_volume()
	check(is_equal_approx(remainder, cut_source.get_volume() - cut.get_volume()), "Wall fitting preserves all volume outside the shared junction")
	var structural_meshes: Array[MeshInstance3D] = []
	for mesh in station.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override == station.mat_wall or mesh.material_override == station.mat_ceiling:
			structural_meshes.append(mesh)
	var structure_fits: bool = true
	for i in range(structural_meshes.size()):
		for j in range(i + 1, structural_meshes.size()):
			var a := structural_meshes[i]
			var b := structural_meshes[j]
			if a.material_override != b.material_override:
				continue
			var shared := (a.global_transform * a.get_aabb()).intersection(b.global_transform * b.get_aabb())
			if shared.size.x > 0.0001 and shared.size.y > 0.0001 and shared.size.z > 0.0001:
				structure_fits = false
				push_error("Overlapping structure: %s / %s" % [a.get_parent().name, b.get_parent().name])
	check(structure_fits, "Whole station has no overlapping white-wall or ceiling slabs")
	var lower_roof_a := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 2.5, -21.99), Vector3(0, 4.5, -21.99)))
	var lower_roof_b := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 2.5, -22.01), Vector3(0, 4.5, -22.01)))
	check(not lower_roof_a.is_empty() and not lower_roof_b.is_empty() and absf(lower_roof_a.position.y - lower_roof_b.position.y) < 0.02, "Flat and sloped tunnel roofs join without a gap or height jump")
	var upper_roof_a := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 6.0, -29.67), Vector3(0, 9.0, -29.67)))
	var upper_roof_b := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 6.0, -29.69), Vector3(0, 9.0, -29.69)))
	check(not upper_roof_a.is_empty() and not upper_roof_b.is_empty() and absf(upper_roof_a.position.y - upper_roof_b.position.y) < 0.02, "Sloped roof joins the landing ceiling without a gap or height jump")
	var removed_floor := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-21.0, 0.8, 4.0), Vector3(-21.0, -1.0, 4.0)))
	check(removed_floor.is_empty(), "Unused west room floor is removed")
	var smoking_floor := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-18.0, 0.8, -8.0), Vector3(-18.0, -1.0, -8.0)))
	check(not smoking_floor.is_empty(), "Smoking room retains a solid floor")
	var window_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-6.5, 2.1, 2.0), Vector3(-7.15, 2.1, 2.0)))
	check(not window_hit.is_empty() and window_hit.collider.name == "TB_Front_Glass_A", "Clear booth window retains solid collision")
	var slot_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-6.5, 1.65, 4.0), Vector3(-7.15, 1.65, 4.0)))
	check(slot_hit.is_empty(), "Document slot stays open beneath the clear glass")
	var aisle_query := PhysicsRayQueryParameters3D.create(Vector3(0.0, 0.8, -14.0), Vector3(0.0, 0.8, 9.0))
	aisle_query.exclude = [player]
	check(space.intersect_ray(aisle_query).is_empty(), "Extra seating leaves the central gate approach clear")
	var seating_route := player.global_transform
	seating_route.origin = Vector3(14.4, 0.36, -14.0)
	check(not player.test_move(seating_route, Vector3(0, 0, 22.5)), "East side aisle stays clear for room access")
	seating_route.origin = Vector3(-24.0, 0.36, 11.8)
	check(not player.test_move(seating_route, Vector3(48, 0, 0)), "Platform walkway behind seating stays clear")
	seating_route.origin = Vector3(-24.0, 0.36, 17.0)
	check(not player.test_move(seating_route, Vector3(48, 0, 0)), "Platform path in front of seating stays behind safety line")
	seating_route.origin = Vector3(-14.0, 0.36, -8.0)
	check(not player.test_move(seating_route, Vector3(28, 0, 0)), "Hall cross aisle stays clear between paired seating blocks")
	var seat_anchors_aligned: bool = true
	for anchor: Marker3D in get_nodes_in_group("passenger_seats"):
		var point := anchor.global_position
		var seat_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3(0, 0.2, 0), point - Vector3(0, 0.2, 0)))
		if seat_hit.is_empty() or seat_hit.collider.get_parent() != anchor.get_parent():
			seat_anchors_aligned = false
	check(seat_anchors_aligned, "Seat anchors stay aligned with collision on rotated benches")
	var booth_route := player.global_transform
	booth_route.origin = Vector3(-10.0, 0.36, 1.8)
	check(not player.test_move(booth_route, Vector3(0.0, 0.0, 2.8)), "Staff entry route stays clear of booth storage")
	booth_route.origin = Vector3(-10.0, 0.36, 3.0)
	check(not player.test_move(booth_route, Vector3(1.2, 0.0, 0.0)), "Player can reach the service desk past the new furniture")
	var door := station.get_node("SmokingDoor_InteractiveDoor") as InteractiveDoor
	check(InteractionComponent.resolve(door._anim_body) != null, "Door collider resolves shared interaction")
	var electrical_door := station.get_node("ElecDoor_InteractiveDoor") as InteractiveDoor
	var electrical_interaction := InteractionComponent.resolve(electrical_door._anim_body)
	electrical_interaction.interact()
	check(electrical_door.is_open, "Steel Electrical Room door opens normally")
	for i in range(30):
		await physics_frame
	check(absf(electrical_door._anim_body.rotation.y) > 1.0, "Custom steel leaf swings with its hardware")
	electrical_interaction.interact()
	for i in range(30):
		await physics_frame
	check(not electrical_door.is_open and absf(electrical_door._anim_body.rotation.y) < 0.01, "Steel door closes fully")
	var lane := station.get_node("GateLane_0") as Gate
	check(InteractionComponent.resolve(lane.scanner) != null, "Gate scanner resolves shared interaction")
	check(not manager.powered and manager.state == manager.NightState.BLACKOUT, "Night starts with station power offline")
	manager.restore_power()
	check(lane.powered and lane.scan_employee(player), "Gate readers work after the opening repair")
	lane.close()
	check(manager.objectives["start_power"].done and not manager.objectives.has("restore_power"), "Routine startup completes without a repair task")
	var station_lights: Array[Light3D] = []
	var initial_lights_on: bool = true
	var fixture_count: int = 0
	for child in station.get_children():
		if child is Light3D and child.name != "DebugSunlight":
			station_lights.append(child)
			initial_lights_on = initial_lights_on and child.light_energy > 0.0
		if str(child.name).ends_with("_Fixture"):
			fixture_count += 1
	check(initial_lights_on, "Every mains-powered light turns on after repair")
	check(fixture_count >= 30, "Suspended ceiling fixtures cover the hall, concourse, platform and rooms")
	check(station.has_node("RoomLight_Electrical") and station.has_node("RoomLight_Restroom") and station.has_node("RoomLight_Booth"), "Previously unlit rooms have dedicated lighting")
	check(station.mat_light_fixture.emission_enabled, "Ceiling fixtures are lit after repair")
	check(player.flashlight.visible, "Player flashlight works at startup")
	manager.advance_clock(71.0)
	check(manager.powered and hall_light.light_energy > 0.0, "Passing 02:17 does not cause an automatic power failure")
	check(is_equal_approx(station.get_node("TB_ClockMinute").rotation.z, TAU * fmod(manager.time_minutes, 60.0) / 60.0), "Booth wall clock follows game time")
	# Check shift sign-in through the actual booth interaction and platform sensor.
	manager.inspect_platform()
	check(not manager.objectives.has("check_platform"), "Patrol cannot complete before signing in")
	player.set_process(false)
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	player.position = Vector3(-12.55, 0.36, 5.1)
	player.camera.look_at(Vector3(-12.55, 1.33, 6.25))
	await physics_frame
	var logbook := InteractionComponent.resolve(station.get_node("TB_LogbookInteraction"))
	check(player._get_interaction_target() == logbook, "Shift logbook is reachable by player raycast")
	logbook.interact()
	check(manager.signed_in and manager.objectives["sign_in"]["done"] and manager.objectives.has("check_platform"), "Signing logbook starts the platform patrol objective")
	player.position = Vector3(0, 0.36, 12)
	for i in range(3):
		await physics_frame
	check(manager.objectives["check_platform"]["done"], "Entering platform completes the patrol objective")
	var pause_menu := station.get_node("PauseMenu")
	var paused_time: float = manager.time_minutes
	manager.set_process(true)
	pause_menu.set_paused(true)
	manager.advance_clock(60.0)
	for i in range(3):
		await process_frame
	check(paused and manager.time_minutes == paused_time, "Pause freezes the night clock")
	check(pause_menu.can_process() and pause_menu._overlay.visible, "Pause menu stays operable while gameplay is paused")
	pause_menu.set_paused(false)
	manager.set_process(false)
	check(not paused and not pause_menu._overlay.visible, "Resume restores gameplay and hides the pause menu")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	check(paused and pause_menu._overlay.visible, "Escape opens the pause menu through real input dispatch")
	escape.echo = true
	Input.parse_input_event(escape)
	await process_frame
	check(paused, "Holding Escape cannot repeatedly toggle pause")
	escape.echo = false
	Input.parse_input_event(escape)
	await process_frame
	check(not paused, "Escape resumes the shift")
	# Isolate preference persistence from the player's real settings file.
	var old_volume: float = pause_menu._volume.value
	var old_sensitivity: float = pause_menu._sensitivity.value
	pause_menu.settings_path = "/private/tmp/station7_pause_settings_test.cfg"
	pause_menu.set_paused(true)
	pause_menu._volume.value = 37
	pause_menu._sensitivity.value = 4.1
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.37)), "Volume slider updates the master audio bus")
	check(is_equal_approx(player.mouse_sensitivity, 0.0041), "Sensitivity slider updates mouse look")
	pause_menu.set_paused(false)
	var saved_settings := ConfigFile.new()
	var loaded_settings: bool = saved_settings.load(pause_menu.settings_path) == OK
	check(loaded_settings and saved_settings.get_value("audio", "master_volume") == 37.0 and is_equal_approx(float(saved_settings.get_value("controls", "sensitivity")), 4.1), "Resume persists volume and sensitivity preferences")
	pause_menu._volume.value = old_volume
	pause_menu._sensitivity.value = old_sensitivity
	pause_menu.set_paused(false)
	pause_menu.settings_path = pause_menu.SETTINGS_PATH
	# Simulate a future entity-triggered event; ordinary gameplay never calls this.
	manager.cause_power_failure()
	check(not manager.powered and not lane.powered and hall_light.light_energy == 0.0, "Explicit failure event cuts station power")
	check(manager.objectives.has("restore_power"), "Repair task appears only after an actual failure event")
	var player_id := player.get_instance_id()
	var gate_id := lane.get_instance_id()
	station.debug_bright_mode = true
	check(hall_light.light_energy == 0.0 and not station.get_node("DebugSunlight").visible, "F1 cannot bypass electrical repair")
	check(not station.mat_light_fixture.emission_enabled, "F1 cannot turn on fixture glow")
	station.debug_bright_mode = false
	check(player.get_instance_id() == player_id and lane.get_instance_id() == gate_id, "Lighting toggle preserves player and gates")
	check(not manager.powered and hall_light.light_energy == 0.0, "Leaving inspection mode preserves blackout")
	player.set_process(false)
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	player.position = Vector3(23.0, 0.36, 6.5)
	player.camera.look_at(Vector3(24.85, 1.85, 6.5))
	await physics_frame
	var breaker := InteractionComponent.resolve(station.get_node("ElecPanel_1"))
	check(player._get_interaction_target() == breaker, "Breaker is reachable by player raycast")
	player._try_interact()
	check(not manager.powered, "Single E press cannot bypass repair hold")
	# Headless Godot cannot capture the mouse. Test the same hold state machine
	# with the target returned by the real physics raycast.
	player._advance_interaction_hold(player._get_interaction_target(), 0.7, true)
	check(not manager.powered, "Partial repair hold leaves power off")
	player._advance_interaction_hold(player._get_interaction_target(), 0.01, false)
	player._advance_interaction_hold(breaker, 1.0, true)
	player._advance_interaction_hold(null, 0.1, true)
	player._advance_interaction_hold(breaker, 0.7, true)
	check(not manager.powered, "Looking away resets repair progress")
	player._advance_interaction_hold(breaker, 0.01, false)
	breaker.enabled = false
	player._advance_interaction_hold(breaker, 2.0, true)
	check(not manager.powered, "Disabled interaction cannot restore power")
	breaker.enabled = true
	player._advance_interaction_hold(breaker, 0.01, false)
	player._advance_interaction_hold(player._get_interaction_target(), 0.9, true)
	check(not manager.powered, "Releasing E resets repair progress")
	player._advance_interaction_hold(player._get_interaction_target(), 0.7, true)
	var wires = station.get_node("StationJobs").wire_panel
	check(wires.is_open and not manager.powered, "Damaged breaker opens wire puzzle before power can return")
	wires.connect_wire(0, 0)
	wires.connect_wire(1, 1)
	wires.connect_wire(2, 2)
	wires.flip_switch()
	check(manager.powered and lane.powered, "Completed hold restores station and gates")
	check(manager.objectives["restore_power"]["done"], "Repair completes objective")
	check(hall_light.light_energy > 0.0, "Repair restores normal lighting")
	var all_on: bool = true
	for light in station_lights:
		all_on = all_on and light.light_energy > 0.0
	check(all_on and station.mat_light_fixture.emission_enabled, "Repair turns on all station lights and fixture glow")
	check(station.get_node("WorldEnvironment").environment.ambient_light_energy > 0.025 and station.get_node("WorldEnvironment").environment.ambient_light_energy < 0.2, "Powered station has brighter ambient fill")
	var normal_energy: float = hall_light.light_energy
	station.debug_bright_mode = true
	check(hall_light.light_energy > normal_energy, "F1 inspection lighting works after repair")
	station.debug_bright_mode = false
	check(is_equal_approx(hall_light.light_energy, normal_energy), "F1 returns to normal energy without drift")
	var valid_ticket := Ticket.make("VALID", "Test", "Station 7")
	check(lane.scan_ticket(valid_ticket), "Valid ticket opens gate after power repair")
	check(not lane.scan_ticket(valid_ticket), "Used ticket is rejected")
	lane.close()
	check(not lane.scan_ticket(Ticket.make("INVALID", "Test", "Station 7", false)), "Invalid ticket is rejected")
	lane.close()
	manager.advance_clock(60.0)
	check(manager.powered, "Power stays on after repair")
	# An early repair must also survive crossing 02:17.
	manager.start_night()
	check(not manager.powered and hall_light.light_energy == 0.0 and not manager.objectives["start_power"].done and not manager.needs_power_repair(), "New night resets with power switched off and no fault")
	manager.restore_power()
	manager.sign_in()
	manager.advance_clock(71.0)
	check(manager.powered and hall_light.light_energy > 0.0, "Restarted shift stays powered after 02:17")
	manager.advance_clock(100000.0)
	check(manager.state == manager.NightState.SHIFT_OVER and manager.clock_text() == "06:00 AM", "Clock stops at end of shift")
	var end_time: float = manager.time_minutes
	manager.advance_clock(60.0)
	check(manager.time_minutes == end_time, "Finished shift clock remains stopped")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	station.queue_free()
	for i in range(8):
		await physics_frame
	OS.delay_msec(80)
	print("CHECKS FINISHED: ", failures, " failures")
	quit(0 if failures == 0 else 1)
