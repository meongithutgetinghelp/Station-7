extends Node3D

const ServicePanel = preload("res://field_panel.gd")
const Registry = preload("res://identity_registry.gd")
var cctv: CanvasLayer
var phone: CanvasLayer
var registry: CanvasLayer
var shop: CanvasLayer
var stock := {"drink": 24, "food": 24, "battery": 12}
var prices := {"drink": 3, "food": 5, "battery": 8}
var customer_sales: Dictionary = {}
var customer_wallets: Dictionary = {}
var till_balance: int = 0
var photos: Array[String] = []
var phone_charge: float = 100
var _station: Node3D
var _seated_origin := Vector3.ZERO
var _seated_rotation := Vector3.ZERO
var _seated_head_rotation := Vector3.ZERO
var _sitting: bool = false
var _registry_number: LineEdit
var _registry_result: Label

func _ready() -> void:
	add_to_group("station_services")
	add_to_group("save_participant")
	_station = get_parent()
	cctv = preload("res://cctv_console.gd").new()
	add_child(cctv)
	phone = ServicePanel.new()
	add_child(phone)
	registry = ServicePanel.new()
	add_child(registry)
	shop = ServicePanel.new()
	add_child(shop)
	var interaction = preload("res://interactable.gd")
	interaction.attach(_station.get_node("Rooms/Security/SecurityTerminal"), cctv.open_panel, func() -> String: return "[E] Raise security monitor")
	for frame in get_tree().get_nodes_in_group("cctv_console_targets"):
		interaction.attach(frame, _raise_monitor.bind(int(frame.get_meta("camera_index"))), func() -> String: return "[E] Use security monitor")
	interaction.attach(_station.get_node("TB_Keyboard"), open_registry, func() -> String: return "[E] Civil identity and ticket ownership records")
	interaction.attach(_station.get_node("TB_Chair_Seat"), sit_at_desk, func() -> String: return "[E] Sit and check passenger documents")
	_build_charging()
	_build_janitor()
	_build_shop()
	var equipment := preload("res://player_equipment.gd").new()
	equipment.name = "Equipment"
	get_tree().get_first_node_in_group("player").camera.add_child(equipment)

func _button(panel: CanvasLayer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.pressed.connect(action)
	panel.body.add_child(button)

func _box(n: String, size: Vector3, point: Vector3, color: Color) -> Node3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	return _station.box(n, size, point, material)

func _sign(n: String, text: String, point: Vector3, yaw: float = 0) -> void:
	var backing := _box(n + "Backing", Vector3(1.8, 0.42, 0.025), point, Color(0.87, 0.88, 0.78))
	backing.rotation_degrees.y = yaw
	var normal := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3.FORWARD * -1
	var label: Label3D = _station._booth_label(n, text, point + normal * 0.018, yaw)
	label.font_size = 38
	label.pixel_size = 0.0018

func _input(event: InputEvent) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		if phone.is_open: phone.close_panel()
		elif not get_tree().get_first_node_in_group("player").in_booth_inspection: open_phone()
		get_viewport().set_input_as_handled()

func _security_menu() -> void:
	registry.clear_body()
	registry.heading.text = "SECURITY WORKSTATION"
	_button(registry, "Live CCTV / manual camera controls", cctv.open_panel)
	_button(registry, "Review entity evidence", _station.get_node("StationJobs")._identify)
	registry.open_panel()

func _raise_monitor(index: int) -> void:
	cctv.open_panel()
	cctv.select_feed(index)

func open_registry() -> void:
	registry.clear_body()
	registry.heading.text = "CIVIL IDENTITY / TICKET OWNERSHIP"
	registry.paragraph("Authorized station access. Enter the national identity number printed on the ID, or investigate the current passenger. Check the ownership result before deciding whether to approve entry.")
	_registry_number = LineEdit.new()
	_registry_number.placeholder_text = "National identity number"
	registry.body.add_child(_registry_number)
	_button(registry, "Search civil record", _lookup_number)
	_button(registry, "Investigate current passenger and ticket", investigate_current)
	_registry_result = registry.paragraph("")
	registry.open_panel()

func _lookup_number() -> void:
	var record := Registry.lookup(_registry_number.text)
	_registry_result.text = "NO MATCHING CIVIL RECORD" if record.is_empty() else "%s / %s / %s\nStatus: %s" % [record.name, record.identity, record.gender, record.status]

func investigate_current() -> Dictionary:
	var director := get_tree().get_first_node_in_group("passenger_director")
	var profile: Dictionary = director.current_profile()
	if profile.is_empty():
		if is_instance_valid(_registry_result): _registry_result.text = "No passenger is currently presenting documents."
		return {}
	var result := Registry.investigate(profile)
	_registry_number.text = profile.id_number
	_registry_result.text = result.text
	if result.kind != "verified": GameManager.reward_once("investigation/" + str(profile.uid), 4)
	return result

func sit_at_desk() -> void:
	if _sitting: return
	if not GameManager.signed_in:
		GameManager.notice_posted.emit("Sign the rear logbook before using the desk.")
		return
	var player := get_tree().get_first_node_in_group("player")
	_seated_origin = player.global_position
	_seated_rotation = player.rotation
	_seated_head_rotation = player.head.rotation
	_sitting = true
	player.set_meta("seated_workstation", true)
	player.global_position = Vector3(-8.9, 0.35, 4)
	player.rotation.y = -PI * 0.5
	player.head.rotation.x = 0
	player.head.position.y = 1.48
	player.velocity = Vector3.ZERO
	player.is_sprinting = false
	player.camera.position = player._camera_initial_pos
	player.camera.fov = player.base_fov
	player.collision_shape.set_deferred("disabled", true)
	get_tree().get_first_node_in_group("passenger_director").ui.open_desk()

func stand_from_desk() -> void:
	if not _sitting: return
	var player := get_tree().get_first_node_in_group("player")
	_sitting = false
	player.set_meta("seated_workstation", false)
	player.global_position = _seated_origin
	player.rotation = _seated_rotation
	player.head.rotation = _seated_head_rotation
	player.head.position.y = player.stand_camera_y
	player.collision_shape.set_deferred("disabled", false)

func _build_charging() -> void:
	var station := _box("ChargingCounter", Vector3(0.55, 0.95, 2.2), Vector3(-15.6, 0.825, -9.4), Color(0.75, 0.79, 0.74))
	_sign("ChargingSign", "CHARGING POINT\nUSB / STAFF EQUIPMENT", Vector3(-15.86, 2.1, -9.4), 90)
	for z in [-10.1, -9.4, -8.7]:
		_box("ChargingSocket", Vector3(0.04, 0.16, 0.22), Vector3(-15.855, 1.6, z), Color(0.15, 0.22, 0.21))
	preload("res://interactable.gd").attach(station, charge_equipment, func() -> String: return "[Hold E] Charge phone and flashlight" if GameManager.powered else "Charging point has no power", 3)

func charge_equipment() -> bool:
	if not GameManager.powered: return false
	phone_charge = 100
	get_tree().get_first_node_in_group("player").flashlight_charge = 100
	GameManager.notice_posted.emit("Phone and flashlight fully charged.")
	return true

func _build_janitor() -> void:
	var jobs := _station.get_node("StationJobs")
	var mop: Node3D = jobs._pickups.mop
	mop.global_position = Vector3(24.6, 1.2, -11)
	jobs._build_pickup("broom", Vector3(24.6, 0.35, -12))
	var holder := _box("JanitorMopHolder", Vector3(0.3, 0.12, 0.7), Vector3(24.725, 1.8, -11), Color(0.3, 0.4, 0.36))
	preload("res://interactable.gd").attach(holder, return_mop, func() -> String: return "[E] Hang mop on wall holder" if GameManager.has_item("mop") else "Mop wall holder")
	var broom_holder := _box("JanitorBroomHolder", Vector3(0.3, 0.12, 0.7), Vector3(24.725, 1.8, -12), Color(0.3, 0.4, 0.36))
	preload("res://interactable.gd").attach(broom_holder, return_tool.bind("broom"), func() -> String: return "[E] Hang broom on wall holder")
	_sign("JanitorHolderSign", "RETURN CLEANING TOOLS HERE", Vector3(24.86, 2.15, -11.5), -90)
	for z in [-14.3, -13.1]:
		for side in [-1, 1]:
			_box("JanitorShelfSide", Vector3(0.7, 1.8, 0.05), Vector3(24.4, 1.25, z + side * 0.425), Color(0.43, 0.54, 0.48))
		_box("JanitorShelfBack", Vector3(0.04, 1.8, 0.8), Vector3(24.73, 1.25, z), Color(0.43, 0.54, 0.48))
		for y in [0.5, 1.1, 1.7, 2.13]:
			_box("JanitorShelf", Vector3(0.66, 0.04, 0.8), Vector3(24.38, y, z), Color(0.50, 0.59, 0.53))
			if y > 2: continue
			var bottle := _box("JanitorDetergent", Vector3(0.20, 0.3, 0.20), Vector3(24.22, y + 0.17, z), Color(0.32, 0.52, 0.62))
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.06
			mesh.bottom_radius = 0.09
			mesh.height = 0.3
			mesh.radial_segments = 12
			bottle.get_child(0).mesh = mesh

	_box("JanitorUtilitySink", Vector3(0.8, 0.8, 1.1), Vector3(22.5, 0.75, -10.8), Color(0.75, 0.8, 0.76))

func return_mop() -> bool:
	return return_tool("mop")


func return_tool(item: String) -> bool:
	if item not in ["mop", "broom"] or not GameManager.has_item(item): return false
	GameManager.inventory[item] = 0
	var jobs := _station.get_node("StationJobs")
	jobs.collected.erase(item)
	jobs._pickups[item].visible = true
	jobs._pickups[item].collision_layer = 8
	GameManager.notice_posted.emit(item.capitalize() + " returned to the janitor room.")
	return true

func _build_shop() -> void:
	_box("ShopCounter", Vector3(3.0, 1.0, 0.55), Vector3(-13.8, 0.85, -13.4), Color(0.58, 0.65, 0.55))
	_box("ShopCanopy", Vector3(3.2, 0.2, 2.2), Vector3(-13.8, 2.95, -14.3), Color(0.27, 0.43, 0.37))
	for x in [-15.25, -12.35]:
		_box("ShopPost", Vector3(0.08, 2.5, 0.08), Vector3(x, 1.6, -14.9), Color(0.27, 0.43, 0.37))
	_sign("ShopSign", "NIGHT KIOSK\nFOOD • DRINKS • BATTERIES", Vector3(-13.8, 2.45, -13.35))
	for x in [-14.45, -13.15]:
		_box("ShopSignHanger", Vector3(0.025, 0.19, 0.025), Vector3(x, 2.755, -13.35), Color(0.27, 0.43, 0.37))
	for i in range(6):
		var goods := _box("ShopGoods", Vector3(0.18, 0.25, 0.18), Vector3(-14.9 + i * 0.42, 1.475, -13.4), Color(0.7, 0.41 + (i % 2) * 0.2, 0.26))
		if i % 2 == 0:
			var bottle := CylinderMesh.new()
			bottle.top_radius = 0.045
			bottle.bottom_radius = 0.075
			bottle.height = 0.25
			bottle.radial_segments = 12
			goods.get_child(0).mesh = bottle
	var vendor := preload("res://kiosk_robot.gd").new()
	vendor.name = "KioskRobot"
	vendor.position = Vector3(-13.8, 0.35, -14.5)
	_station.add_child(vendor)
	preload("res://interactable.gd").attach(_station.get_node("ShopCounter"), open_shop, func() -> String: return "[E] Buy food, drinks or batteries")

func open_shop() -> void:
	shop.clear_body()
	shop.heading.text = "NIGHT KIOSK"
	shop.paragraph("Balance: %d credits. Food and drinks restore stamina; batteries refill the flashlight with R." % GameManager.balance)
	for item in prices:
		_button(shop, "%s — %d credits (%d available)" % [str(item).capitalize(), prices[item], stock[item]], _buy_and_refresh.bind(item))
	shop.open_panel()

func purchase(item: String) -> bool:
	if not prices.has(item) or stock[item] <= 0 or not GameManager.spend(prices[item]): return false
	stock[item] -= 1
	till_balance += prices[item]
	GameManager.give_item(item)
	return true

func _buy_and_refresh(item: String) -> void:
	if Coop.active:
		Coop.request_action("purchase", item)
		return
	if not purchase(item): GameManager.notice_posted.emit("Insufficient funds or item out of stock.")
	open_shop()

func passenger_purchase(uid: String, item: String = "drink") -> bool:
	if item not in ["food", "drink"] or customer_sales.has(uid) or stock[item] <= 0: return false
	var wallet: int = int(customer_wallets.get(uid, 12))
	if wallet < prices[item]: return false
	customer_wallets[uid] = wallet - prices[item]
	stock[item] -= 1
	till_balance += prices[item]
	customer_sales[uid] = item
	return true

func open_phone() -> void:
	phone.clear_body()
	phone.heading.text = "STATION PHONE"
	phone.paragraph("Balance: %d credits\nPhone charge: %d%%\nPhotos saved: %d" % [GameManager.balance, int(phone_charge), photos.size()])
	_button(phone, "Take photograph", take_photo)
	_button(phone, "Eat food", consume.bind("food"))
	_button(phone, "Drink", consume.bind("drink"))
	for path in photos.slice(maxi(0, photos.size() - 4)): phone.paragraph(path.get_file())
	phone.open_panel()

func consume(item: String) -> bool:
	if Coop.active:
		Coop.request_action("consume", item)
		return true
	if item not in ["food", "drink"] or not GameManager.has_item(item): return false
	GameManager.inventory[item] -= 1
	var player := get_tree().get_first_node_in_group("player")
	player.current_stamina = minf(player.max_stamina, player.current_stamina + (60 if item == "food" else 30))
	open_phone()
	return true

func take_photo() -> void:
	if phone_charge < 2:
		GameManager.notice_posted.emit("Phone battery empty. Use the charging point.")
		return
	if DisplayServer.get_name() == "headless":
		GameManager.notice_posted.emit("Photos require a rendered game window.")
		return
	phone.visible = false
	await RenderingServer.frame_post_draw
	if not phone.is_open: return
	DirAccess.make_dir_recursive_absolute("user://photos")
	var path := "user://photos/station7_%d_%d.png" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	var error := get_viewport().get_texture().get_image().save_png(path)
	phone.visible = true
	if error == OK:
		photos.append(path)
		phone_charge -= 2
		open_phone()
	else: GameManager.notice_posted.emit("Could not save photograph.")

func save_state() -> Dictionary:
	return {"stock": stock, "customer_sales": customer_sales, "customer_wallets": customer_wallets, "till": till_balance, "photos": photos, "phone_charge": phone_charge}

func load_state(data: Dictionary) -> void:
	stock = data.get("stock", {"drink": 24, "food": 24, "battery": 12})
	customer_sales = data.get("customer_sales", {})
	customer_wallets = data.get("customer_wallets", {})
	till_balance = int(data.get("till", 0))
	photos.assign(data.get("photos", []))
	phone_charge = clampf(float(data.get("phone_charge", 100)), 0, 100)
