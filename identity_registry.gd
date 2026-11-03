extends RefCounted
## Fictional in-game civil registry. This never queries real government data.
const Cases = preload("res://passenger_cases.gd")

static func lookup(number: String) -> Dictionary:
	for night in range(1, 8):
		for wave in range(3):
			for person in Cases.for_night(night, wave, 12):
				if not person.anomaly and person.id_number == number.strip_edges().to_upper():
					return {"name": person.id_name, "gender": person.gender, "identity": person.id_number, "status": "ACTIVE"}
	return {}

static func investigate(person: Dictionary) -> Dictionary:
	var record := lookup(str(person.id_number))
	if record.is_empty():
		return {"kind": "unverified_identity", "text": "NO CIVIL RECORD. Identity cannot be verified. Compare the live subject with CCTV; possible impersonation. Deny entry pending investigation."}
	if person.ticket_name != record.name or person.ticket_id_number != record.identity:
		return {"kind": "stolen_ticket", "text": "IDENTITY CONFIRMED: %s (%s). This ticket belongs to a different holder. A genuine person is using another person's ticket; this is a stolen-ticket case, not proof of an intruder." % [record.name, record.gender]}
	return {"kind": "verified", "text": "IDENTITY CONFIRMED: %s (%s). Ownership matches. Check date, service, stamp and gender marker before approval." % [record.name, record.gender]}
