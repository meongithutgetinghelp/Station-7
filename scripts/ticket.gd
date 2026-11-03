class_name Ticket
extends RefCounted

## A passenger's ticket / QR code. The gate scanner reads one of these.
## `is_valid` is what the real ticket check at the booth will eventually decide
## (forged, expired, wrong line…). `used` flips once it has opened a gate.

var id: String = ""
var passenger_name: String = ""
var destination: String = ""
var is_valid: bool = true
var used: bool = false


static func make(p_id: String, p_name: String, p_dest: String, p_valid: bool = true) -> Ticket:
	var t := Ticket.new()
	t.id = p_id
	t.passenger_name = p_name
	t.destination = p_dest
	t.is_valid = p_valid
	return t
