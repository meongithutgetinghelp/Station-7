class_name TestPassenger
extends CharacterBody3D

## Placeholder passenger (a capsule) used to exercise the gates before real
## passenger NPCs exist: walks to its gate, scans its ticket, then either walks
## through to the platform (valid) or is rejected and walks back (invalid).

signal finished(admitted: bool)

enum S { TO_GATE, SCAN, WAIT, THROUGH, DENIED, LEAVE, DONE }

var gate: Gate
var ticket: Ticket
var platform_target: Vector3
var walk_speed: float = 1.6
var state: S = S.TO_GATE
var admitted: bool = false

var _home: Vector3
var _timer: float = 0.0
var _path: Array[Vector3] = []
var _idx: int = 0


func _ready() -> void:
	collision_layer = 2   # same layer as the player so gate sensors see us
	collision_mask = 1
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.7
	mi.mesh = cm
	mi.position.y = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.5, 0.2) if (ticket and ticket.is_valid) else Color(0.6, 0.2, 0.7)
	mi.material_override = mat
	add_child(mi)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	_home = global_position


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	var gp: Vector3 = gate.global_position
	match state:
		S.TO_GATE:
			if _move_to(Vector3(gp.x, global_position.y, gp.z - 0.9)):
				state = S.SCAN
				_timer = 0.6
		S.SCAN:
			_stop()
			_timer -= delta
			if _timer <= 0.0:
				admitted = gate.scan_ticket(ticket)
				if admitted:
					state = S.WAIT
					_timer = 0.5
				else:
					state = S.DENIED
					_timer = 1.8
		S.WAIT:
			_stop()
			_timer -= delta
			if _timer <= 0.0 and gate.state == Gate.State.OPEN:
				_path = [Vector3(gp.x, global_position.y, gp.z + 1.0), platform_target]
				_idx = 0
				state = S.THROUGH
		S.THROUGH:
			if _move_to(_path[_idx]):
				_idx += 1
				if _idx >= _path.size():
					state = S.DONE
					finished.emit(true)
		S.DENIED:
			_stop()
			_timer -= delta
			if _timer <= 0.0:
				state = S.LEAVE
		S.LEAVE:
			if _move_to(_home):
				state = S.DONE
				finished.emit(false)
		S.DONE:
			_stop()
	move_and_slide()


func _move_to(target: Vector3) -> bool:
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length() < 0.12:
		_stop()
		return true
	var d: Vector3 = to.normalized() * walk_speed
	velocity.x = d.x
	velocity.z = d.z
	return false


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
