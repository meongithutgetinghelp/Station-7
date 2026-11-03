extends "res://scripts/field_panel.gd"

var connected: Array[int] = []
var selected: int = -1
var _message: Label
var _switch: Button
var _source_buttons: Array[Button] = []


func _ready() -> void:
	super._ready()
	heading.text = "ELECTRICAL / MAIN BREAKER"
	paragraph("Isolate the damaged circuit, reconnect each coloured wire to its matching terminal, then flip the main switch. This repair is needed after an electrical fault. Normal station startup only needs the main power switch.")
	var colors := [Color(0.9, 0.3, 0.24), Color(0.35, 0.6, 0.95), Color(0.96, 0.82, 0.3)]
	var names := ["RED", "BLUE", "YELLOW"]
	for row in range(3):
		var line := HBoxContainer.new()
		body.add_child(line)
		var left := Button.new()
		left.text = names[row] + " WIRE"
		left.custom_minimum_size = Vector2(300, 55)
		left.modulate = colors[row]
		left.pressed.connect(_select.bind(row))
		line.add_child(left)
		_source_buttons.append(left)
		var target: int = [2, 0, 1][row]
		var right := Button.new()
		right.text = names[target] + " TERMINAL"
		right.custom_minimum_size = Vector2(300, 55)
		right.modulate = colors[target]
		right.pressed.connect(_connect_selected.bind(target))
		line.add_child(right)
	_message = paragraph("Select a wire on the left, then its matching terminal.")
	_switch = Button.new()
	_switch.text = "MAIN SWITCH / RESTORE POWER"
	_switch.disabled = true
	_switch.custom_minimum_size.y = 50
	_switch.pressed.connect(flip_switch)
	body.add_child(_switch)


func open_panel() -> void:
	connected.clear()
	selected = -1
	for button in _source_buttons:
		button.disabled = false
	_switch.disabled = true
	_message.text = "Match all three circuits before using the main switch."
	super.open_panel()


func _select(wire: int) -> void:
	selected = wire
	_message.text = "Wire selected. Choose its terminal."


func _connect_selected(target: int) -> void:
	connect_wire(selected, target)


func connect_wire(source: int, target: int) -> bool:
	if source < 0 or source > 2 or connected.has(source):
		return false
	if source != target:
		_message.text = "That terminal does not match. The circuit remains isolated."
		selected = -1
		return false
	connected.append(source)
	if Coop.active: Coop.request_action("wire", source)
	_source_buttons[source].disabled = true
	_message.text = "%d / 3 wires connected correctly." % connected.size()
	selected = -1
	_switch.disabled = connected.size() != 3
	return true


func flip_switch() -> bool:
	if connected.size() != 3:
		return false
	if Coop.active: Coop.request_action("restore")
	else: GameManager.restore_power()
	GameManager.notice_posted.emit("Main switch restored. Station power online.")
	close_panel()
	return true
