extends RefCounted

const SERVICE_DATE: String = "31 OCT 2026"
const LINE: String = "LINE 7"
const DESTINATION: String = "NORTH TERMINAL"


static func service_date(night: int) -> String:
	var day := Time.get_date_dict_from_unix_time(int(Time.get_unix_time_from_datetime_string("2026-10-31T00:00:00")) + (night - 1) * 86400)
	return "%02d %s %d" % [day.day, ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"][int(day.month) - 1], day.year]


static func night_one() -> Array[Dictionary]:
	return [
		{"uid": "P01", "name": "Nora Vale", "greeting": "Good evening. North Terminal, please. My documents are here.",
		"ticket_name": "NORA VALE", "id_name": "NORA VALE", "ticket_number": "T7-1041", "id_number": "NV-1042", "ticket_id_number": "NV-1042",
		"date": SERVICE_DATE, "line": LINE, "destination": DESTINATION, "stamped": true,
		"skin": Color(0.73, 0.49, 0.34), "hair": Color(0.17, 0.10, 0.08), "coat": Color(0.36, 0.53, 0.48), "style": 0},
		{"uid": "P02", "name": "Eli Ward", "greeting": "One moment... yes, this is the ticket I brought. Is everything in order?",
		"ticket_name": "EVAN WARD", "id_name": "ELI WARD", "ticket_number": "T7-1042", "id_number": "EW-2075", "ticket_id_number": "EW-2075",
		"date": SERVICE_DATE, "line": LINE, "destination": DESTINATION, "stamped": true,
		"skin": Color(0.91, 0.72, 0.57), "hair": Color(0.24, 0.18, 0.13), "coat": Color(0.34, 0.42, 0.57), "style": 1},
		{"uid": "P03", "name": "Mara Quinn", "greeting": "I kept the ticket in my bag. I hope I haven't missed the service.",
		"ticket_name": "MARA QUINN", "id_name": "MARA QUINN", "ticket_number": "T7-1043", "id_number": "MQ-3108", "ticket_id_number": "MQ-3108",
		"date": "30 OCT 2026", "line": LINE, "destination": DESTINATION, "stamped": true,
		"skin": Color(0.51, 0.32, 0.23), "hair": Color(0.10, 0.09, 0.10), "coat": Color(0.58, 0.34, 0.30), "style": 2},
	]


static func errors(profile: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	if str(profile.ticket_name).strip_edges().to_upper() != str(profile.id_name).strip_edges().to_upper():
		result.append("Ticket name does not match the identity card.")
	if profile.ticket_id_number != profile.id_number:
		result.append("Ticket ID number does not match the identity card.")
	if profile.date != profile.get("expected_date", SERVICE_DATE):
		result.append("Ticket is for a different service date.")
	if profile.line != LINE or profile.destination != DESTINATION:
		result.append("Ticket is for a different line or destination.")
	if not profile.stamped:
		result.append("Ticket has no issue stamp.")
	if profile.get("ticket_gender", "") != profile.get("gender", ""):
		result.append("Ticket gender marker does not match the identity card.")
	if profile.get("anomaly", false):
		result.append("The person is absent from the window camera feed.")
	return result


static func for_night(night: int, wave: int = 0, count: int = 3) -> Array[Dictionary]:
	var cases := night_one()
	var names := [["Nora Vale", "Eli Ward", "Mara Quinn"], ["Owen Shaw", "Iris Chen", "Leah Reed"], ["Samir Khan", "Ada Moss", "Leon Park"]]
	for i in range(cases.size()):
		var person: Dictionary = cases[i]
		person.uid = "N%dR%dP%d" % [night, wave + 1, i + 1]
		person.name = names[wave % 3][i]
		person.id_name = str(person.name).to_upper()
		person.ticket_name = person.id_name
		person.ticket_number = "T7-%d%d%d" % [night, wave + 1, i + 1]
		person.id_number = "ID-%d%d%d" % [night, wave + 1, i + 1]
		person.ticket_id_number = person.id_number
		person.expected_date = service_date(night)
		person.date = person.expected_date
		person.stamped = true
		person.gender = [["F", "M", "F"], ["M", "F", "F"], ["M", "F", "M"]][wave % 3][i]
		person.ticket_gender = person.gender
		person.vip = i == 0 and wave == 1
		person.anomaly = i == 0 and ((night >= 2 and wave % 2 == 0) or (night == 1 and wave == 2))
		person.case_kind = "genuine"
	if (night + wave - 1) % 3 == 0:
		cases[1].ticket_name = "EVAN WARD" if wave == 0 and night == 1 else "ALEX MORROW"
	elif (night + wave - 1) % 3 == 1:
		cases[1].stamped = false
	else:
		cases[1].ticket_id_number = "ID-0000"
	if wave % 2 == 0: cases[2].date = "30 OCT 2026" if night == 1 else service_date(night - 1)
	else: cases[2].line = "LINE 3"
	if night >= 7:
		cases[0].anomaly = true
		if wave == 1:
			cases[1].ticket_name = cases[1].id_name
			cases[1].ticket_id_number = cases[1].id_number
			cases[1].stamped = true
	for person in cases:
		if person.anomaly:
			person.case_kind = "impersonation"
			person.id_number = "UNVERIFIED-%s" % person.uid
			person.ticket_name = "ALEX MORROW"
		elif person.ticket_name != person.id_name or person.ticket_id_number != person.id_number:
			person.case_kind = "stolen_ticket"
	# Gender is explicit document data; presentation never determines identity.
	if night >= 3 and wave == 1 and night < 7:
		cases[1].ticket_gender = "F" if cases[1].gender == "M" else "M"
	var extra_names := ["June Ellis", "Theo Marsh", "Amira Bell", "Felix Stone", "Rosa Lin", "Ben Harlow", "Mina Cho", "Luca Wells", "Yara Holt", "Noah Birch", "Zoe Patel", "Ivan Brooks", "Sofia Grant", "Arun Blake", "Eva Moore"]
	while cases.size() < clampi(count, 3, 12):
		var index := cases.size()
		var person: Dictionary = cases[index % 3].duplicate(true)
		person.uid = "N%dR%dP%d" % [night, wave + 1, index + 1]
		person.name = extra_names[((index - 3) + wave * 5) % extra_names.size()]
		person.id_name = str(person.name).to_upper()
		person.ticket_name = person.id_name
		person.id_number = "ID-%d%d%d" % [night, wave + 1, index + 1]
		person.ticket_id_number = person.id_number
		person.ticket_number = "T7-%d%d%d" % [night, wave + 1, index + 1]
		person.gender = "F" if index % 2 == 1 else "M"
		person.ticket_gender = person.gender
		person.date = service_date(night)
		person.line = LINE
		person.destination = DESTINATION
		person.stamped = true
		person.anomaly = false
		person.case_kind = "genuine"
		person.vip = index % 4 == 0
		person.coat = [Color(0.42, 0.48, 0.62), Color(0.62, 0.42, 0.30), Color(0.30, 0.49, 0.42), Color(0.52, 0.35, 0.48), Color(0.59, 0.57, 0.38)][(index + wave) % 5]
		person.greeting = "Hello. One ticket for North Terminal, please. Here are my documents."
		cases.append(person)
	return cases
