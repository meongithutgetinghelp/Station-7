class_name GateScanner
extends StaticBody3D

const InteractionComponent = preload("res://scripts/interactable.gd")

## The card/QR reader on top of a gate pedestal. The player presses E on it to
## scan their employee ID; passengers (NPCs) call scan_ticket() directly.

var gate: Gate
var interact_prompt: String = "[E] Scan employee ID"
var done: bool = false   # always re-usable


func _ready() -> void:
	InteractionComponent.attach(self, interact, func() -> String: return interact_prompt)
	var size := Vector3(0.26, 0.12, 0.30)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.80, 0.15)
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color(0.92, 0.80, 0.15)
	mat.emission_energy_multiplier = 0.35
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)


func _process(_delta: float) -> void:
	get_node("Interaction").hold_seconds = 2.0 if gate and gate.jammed else 0.0
	if gate and gate.jammed:
		interact_prompt = "[Hold E] Repair gate reader"
	elif gate and not gate.powered:
		interact_prompt = "Reader offline — restore station power"
	elif gate and gate.state == Gate.State.OPEN:
		interact_prompt = "Gate open"
	else:
		interact_prompt = "[E] Scan employee ID"


func interact() -> void:
	if not gate:
		return
	if gate.jammed:
		gate.jammed = false
		get_node("/root/GameManager").complete_objective("fix_gate")
		return
	var who: Node = get_node("/root/Coop").interacting_player()
	gate.scan_employee(who)


func scan_ticket(ticket: Ticket) -> bool:
	return gate.scan_ticket(ticket) if gate else false
