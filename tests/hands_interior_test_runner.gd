extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ",message)
	else:
		failures += 1
		push_error(message)
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var player = station.get_node("Player")
	player.set_physics_process(false)
	var equipment = player.camera.get_node("Equipment")
	var hands = equipment.hands
	check(hands.rigs.size() == 2,"HTML hand rig supplies both articulated hands")
	check(hands.rigs[0].skeleton.get_bone_count() == 18 and hands.rigs[1].skeleton.get_bone_count() == 18,"Each hand has fifteen finger joints, wrist and two fixed-length arm segments")
	for rig in hands.rigs:
		check(rig.model.transform.basis.determinant() > 0,"Mirrored hand uses baked geometry without negative runtime scale")
		var visual = rig.skeleton.get_node("ReferenceHand")
		check(visual.mesh.get_surface_count() == 3 and visual.skin.get_bind_count() == 18 and visual.layers == 4,"Skin, nails and uniform are batched and omitted from CCTV")
	for pose in hands.POSES:
		hands.set_pose(pose,true)
		var q: Quaternion = hands.rigs[0].skeleton.get_bone_pose_rotation(hands.rigs[0].thumb[0])
		check(q.is_finite() and is_equal_approx(q.length(),1),"Supplied pose is valid: "+pose)
	hands.set_pose("flashlight",true)
	var right = hands.rigs[0]
	var left = hands.rigs[1]
	var base: Vector3 = right.skeleton.get_bone_global_pose(right.fingers[0][0]).origin
	check(base.is_equal_approx(Vector3(2.55,8,0)),"Finger roots retain the supplied anatomical positions instead of collapsing onto the wrist")
	var next_joint: Vector3 = right.skeleton.get_bone_global_pose(right.fingers[0][1]).origin
	check(is_equal_approx(base.distance_to(next_joint),4.1),"Articulated finger segments retain their authored lengths")
	var angles: Array = hands.F.flashlight[0]
	var expected := Basis.from_euler(Vector3(deg_to_rad(angles[0]),0,0),EULER_ORDER_ZXY).get_rotation_quaternion()
	check(absf(right.skeleton.get_bone_pose_rotation(right.fingers[0][0]).dot(expected)) > 0.999,"Torch fingers retain the supplied angle table")
	hands.set_pose("document",true)
	var thumb: Array = hands.T.document
	var mirrored := Basis.from_euler(Vector3(deg_to_rad(thumb[0]+14),-deg_to_rad(thumb[1]),deg_to_rad(52+thumb[2])),EULER_ORDER_ZXY).get_rotation_quaternion()
	check(absf(left.skeleton.get_bone_pose_rotation(left.thumb[0]).dot(mirrored)) > 0.999,"Left thumb mirrors ZXY rotations correctly")
	var barrel = equipment._items.flashlight.get_node("Barrel")
	var lens = equipment._items.flashlight.get_node("Lens")
	check(barrel.mesh is CylinderMesh and is_equal_approx(barrel.mesh.height,0.27) and is_equal_approx(barrel.mesh.top_radius,0.0375) and barrel.position.is_equal_approx(Vector3(0.23,-0.23,-0.5)),"Preferred flashlight barrel geometry and placement are preserved")
	check(is_equal_approx(lens.mesh.height,0.015) and lens.position.is_equal_approx(Vector3(0.23,-0.23,-0.64)) and player.flashlight.position.is_equal_approx(Vector3(0.23,-0.23,-0.66)),"Preferred lens and beam alignment are preserved")
	player.set_flashlight(false,false)
	equipment._process(0.1)
	check(hands.active_pose == "relaxed" and not equipment._items.flashlight.visible,"Unlit idle holsters the torch and relaxes the hands")
	player.set_flashlight(true,false)
	equipment._process(0.1)
	check(hands.active_pose == "flashlight" and equipment._items.flashlight.visible,"Lighting the torch restores its existing model and proper grip")
	for pair in [["phone","phone"],["mop","cleaning"],["broom","cleaning"],["battery","reach"]]:
		gm.inventory[pair[0]] = 1
		equipment.equip(pair[0],false)
		equipment._process(0.1)
		check(hands.active_pose == pair[1],"Equipment selects its contextual grip: "+pair[0])
	var desk = station.get_node("BoothDesk")
	equipment.play_hand_action("stamp",desk._stamp_models[0],null,0.9)
	hands.set_pose("stamp",true)
	var contact: Vector3 = right.wrist.global_transform * Vector3(0,0.06,0)
	check(contact.distance_to(desk._stamp_models[0].to_global(Vector3(0,0.12,0))) < 0.001,"Stamp hand aligns to the actual moving world prop")
	desk._stamp_models[0].position.y += 0.15
	hands.set_pose("stamp",true)
	contact = right.wrist.global_transform * Vector3(0,0.06,0)
	check(contact.distance_to(desk._stamp_models[0].to_global(Vector3(0,0.12,0))) < 0.001,"Hand follows the stamp throughout its slide and press")
	equipment.play_hand_action("keyboard",station.get_node("TB_Keyboard"),null,0.6)
	equipment._process(0.1)
	check(hands.active_pose == "keyboard" and not equipment._items.battery.visible,"Keyboard reach holsters equipment while typing")
	equipment.cancel_hand_action()
	equipment._process(0.1)
	check(hands.active_pose == "reach" and equipment._items.battery.visible,"Cancelled action returns to the equipped item")
	var train = station.get_node("TrainService")
	train.set_process(false)
	check(train.interior.seats.size() == 64,"All four coaches contain sixty-four usable seats")
	check(train.interior.get_node("SeatsRailsAndStraps").get_aabb().end.y <= 2.53,"Interior grab rails and bulkheads stay below the imported carriage roof")
	check(train.interior.get_node("SeatsRailsAndStraps").mesh.get_surface_count() == 4,"Seats, poles, overhead rails and straps use four batched material surfaces")
	var clear := true
	for seat in train.interior.seats:
		for centre in train.interior.CAR_CENTRES:
			for door in [-4.0,0.0,4.0]:
				if absf(seat.x-centre-door) < 1.055: clear=false
	check(clear,"Seat shells leave the original door openings clear")
	for i in range(train.interior.seats.size()):
		for j in range(i):
			if train.interior.seats[i].distance_to(train.interior.seats[j]) < 0.65: clear=false
	check(clear,"Reserved seat positions have adult passenger spacing")
	gm.turn_on_power()
	var service = station.get_node("PassengerService")
	service.pre_ticket_routines_enabled = false
	service.set_process(false)
	gm.sign_in()
	for actor in service.actors: actor.set_physics_process(false)
	var passenger = service.actors[0]
	passenger.position = Vector3(-5.85,0.35,4)
	passenger.phase = "COUNTER"
	service._on_counter_ready(passenger)
	player.position = Vector3(-9.3,0.35,3.2)
	service.open_desk()
	for i in range(65): await physics_frame
	var rest: Transform3D = player.camera.transform
	var fov: float = player.camera.fov
	check(desk._computer_prompt() == "[E] Use Computer", "Computer interaction uses the requested Use Computer prompt")
	desk.verify_record()
	for i in range(24): await physics_frame
	check(desk.computer_active and player.camera.global_position.distance_to(desk.get_node("BoothComputerScreen").global_position) < 0.8 and is_equal_approx(player.camera.fov,50), "Using the computer smoothly brings the physical screen closer")
	var proportions := true
	for rig in hands.rigs:
		for bone in range(rig.skeleton.get_bone_count()):
			proportions = proportions and rig.skeleton.get_bone_pose_scale(bone).is_equal_approx(Vector3.ONE)
	check(proportions,"Every hand and sleeve bone keeps fixed proportions during computer use")
	var yaw: float = player.rotation.y
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(40,20)
	player._unhandled_input(look)
	check(is_equal_approx(player.rotation.y,yaw),"Mouse look cannot fight the computer close-up camera")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	service.ui._input(tab)
	for i in range(20): await physics_frame
	check(not desk.computer_active and service.ui.is_open and player.get_meta("seated_workstation",false),"Tab returns from the computer to the seated desk")
	check(player.camera.transform.is_equal_approx(rest) and is_equal_approx(player.camera.fov,fov),"Returning restores the exact previous camera transform and FOV")
	for repeat in range(3):
		desk.verify_record()
		for i in range(6): await physics_frame
		desk.exit_computer()
		for i in range(3): await physics_frame
		desk.verify_record()
		desk.exit_computer(true)
	check(player.camera.transform.is_equal_approx(rest),"Rapid repeated computer use cannot accumulate camera offsets")
	desk.verify_record()
	desk.clear_documents()
	check(not desk.computer_active and not player.get_meta("computer_focus",false) and player.camera.transform.is_equal_approx(rest),"Clearing transient desk state cancels the zoom and restores controls")
	train.phase = "BOARDING"
	train.vehicle.position.x = 0
	var traveller = service.actors[-1]
	traveller.train_offset = train.interior.seats[0]
	traveller.position = train.seat_approach(traveller.train_offset)
	check(train.board(traveller) and traveller.visual.seated and traveller.seat_anchor == null,"Boarding passengers sit in the furnished carriage and release their old station seat")
	var uid: String = traveller.profile.uid
	var snapshot: Dictionary = service.save_state()
	service.load_state(snapshot)
	var restored = station.get_node("Passenger_"+uid)
	check(restored.phase == "BOARDED" and restored.visual.seated,"Checkpoint restoration preserves the seated train pose")
	var paint_count := 0
	var door_paint_moves := true
	train._set_doors(false,true)
	var before: Array[Vector3] = []
	for entry in train._doors:
		var paint: Array = entry.node.find_children("DoorStripe_*","MeshInstance3D",true,false)
		paint.append_array(entry.node.find_children("DoorPinstripe_*","MeshInstance3D",true,false))
		paint_count += paint.size()
		for stripe in paint: before.append(stripe.global_position)
	train._set_doors(true,true)
	var cursor := 0
	for entry in train._doors:
		var paint: Array = entry.node.find_children("DoorStripe_*","MeshInstance3D",true,false)
		paint.append_array(entry.node.find_children("DoorPinstripe_*","MeshInstance3D",true,false))
		for stripe in paint:
			var distance: Vector3 = stripe.global_position-before[cursor]
			door_paint_moves = door_paint_moves and is_equal_approx(absf(distance.x),0.78) and is_equal_approx(absf(distance.z),0.14)
			cursor += 1
	check(paint_count == 96 and door_paint_moves,"Both coloured stripes move outward and sideways with every door leaf")
	var openings_clear := true
	for mesh in train.vehicle.get_node("SubwayModel").find_children("*","MeshInstance3D",true,false):
		if not (str(mesh.name).begins_with("Stripe_") or str(mesh.name).begins_with("Pinstripe_")): continue
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for triangle in range(0,faces.size(),3):
			var x1: float = (mesh.global_transform*faces[triangle]).x
			var x2: float = (mesh.global_transform*faces[triangle+1]).x
			var x3: float = (mesh.global_transform*faces[triangle+2]).x
			for door_x in [-22.75,-18.75,-14.75,-10.25,-6.25,-2.25,2.25,6.25,10.25,14.75,18.75,22.75]:
				if minf(x1,minf(x2,x3)) < door_x+0.70 and maxf(x1,maxf(x2,x3)) > door_x-0.70: openings_clear=false
	check(openings_clear,"Static body stripes no longer bridge any open doorway")
	for audio in station.find_children("*","AudioStreamPlayer3D",true,false): audio.stop()
	station.queue_free()
	for i in range(8): await physics_frame
	OS.delay_msec(150)
	await process_frame
	print("HANDS / INTERIOR CHECKS: ",failures," failures")
	quit(1 if failures else 0)
