extends RefCounted

const BRIEFINGS = [
	["FIRST SERVICE", "Tutorial shift: check 9 passengers in three small groups. Switch on the station lights in the Electrical Room, then sign the rear logbook to open the station. Compare names and service dates, then scan your staff ID and patrol the platform. After two inspections, check the EXIT SEAL beside the entrance stairs. The camera is evidence: a person missing from its feed must be denied."],
	["A FACE IN THE WINDOW", "Impersonators arrive earlier tonight. Compare the actual passenger with the booth camera before every verdict. A convincing document never overrides an empty camera feed. A CAM 04 line fault will need the LINE RESET junction in Security; other cameras stay live."],
	["BORROWED IDENTITIES", "Stolen tickets and missing stamps complicate the queue. Cross-check the ID number as well as the name. Keep genuine passengers moving so the train can carry them out. An unscheduled cancellation call must be checked against the TRAIN DISPATCH panel on the outside wall of the ticket booth. Select KEEP TRAIN RUNNING to reject the false order."],
	["AFTER THE LAST CALL", "The intruder can now hunt outside the queue. Collect all three reports, identify it at Security, and conserve flashlight charge. Collect the maintenance key before an Electrical Room emergency. A warned overload gives 18 seconds to prepare before the breaker trips."],
	["EVERYONE ACCOUNTED FOR", "No passenger losses are allowed from tonight onward. Respond to the red NEEDS HELP marker, then escort that passenger into Security or the booth. Split duties with your crew. The booth rear workbench ROLL CALL checks the admitted passenger count; assist anyone it identifies."],
	["FAILING INFRASTRUCTURE", "Repairs compete with inspections and rescues. Collect a cleaning tool and spare battery early. Restore the power and finish every damaged light, gate and door before the shift ends. Tonight, repair the hall light at Electrical panel 2, then the central gate reader."],
	["THE FINAL SERVICE", "Expect an impostor in every wave. Keep genuine passengers boarding, protect everyone, and contain the intruder. Your total losses across the campaign affect the ending. The final train waits for three clearances: all checks at the Booth, identity confirmed at Security, and boarding confirmed with PLATFORM READY at TRAIN DISPATCH outside the ticket booth."],
]

static func briefing(night: int) -> String:
	var entry: Array = BRIEFINGS[clampi(night - 1, 0, BRIEFINGS.size() - 1)]
	return "NIGHT %d / %s\n%s" % [night, entry[0], entry[1]]

static func next_step(gm: Node, tree: SceneTree) -> String:
	if not gm.powered:
		var key_hint := "Collect the maintenance key from Security first.\n" if gm.night >= 4 and not gm.has_item("maintenance_key") else ""
		var task := "reconnect all 3 wires, then main switch" if gm.needs_power_repair() else "switch on the main power"
		return "POWER: " + key_hint + "Electrical Room → " + task + ".\n[F] flashlight · [R] spare battery"
	if not gm.signed_in:
		var progress := "%d/%d staff signed" % [gm.staff_sign_in_count(), gm.required_staff().size()]
		if gm.local_staff_signed(): return "LOGBOOK: " + progress + ". Waiting for the rest of the crew to sign."
		return "OPEN THE STATION: Booth rear workbench → [E] sign the logbook.\n" + progress + ". Passengers arrive when everyone has signed."
	var service := tree.get_first_node_in_group("passenger_director")
	for actor in tree.get_nodes_in_group("passenger_actor"):
		if actor.phase == "DANGER": return "RESCUE: Reach the red NEEDS HELP marker and press [E].\nLead the passenger to Security or the booth."
	if service and service.reviewed < 3 and gm.night == 1: return booth_lesson(tree)
	if service and service.reviewed == 0: return "FIRST CHECK: Use the booth inspection desk.\nCompare name, ID, date, route and stamp; check the window camera."
	if not gm.objectives.get("check_platform", {}).get("done", false): return "PATROL: Use a gate scanner with [E] to scan your staff ID, then visit the platform."
	if gm.night >= 4 and not gm.entity_identified: return "INVESTIGATE: Read the 3 reports in the booth, Security and Electrical.\nUse Security's evidence terminal once all are collected."
	return "KEEP THE SHIFT MOVING: Check tickets, repair faults and keep cleanliness ≥70%.\n[J] night briefing · [Esc] controls and accessibility"


static func booth_lesson(tree: SceneTree) -> String:
	var desk := tree.get_first_node_in_group("booth_desk")
	var player := tree.get_first_node_in_group("player")
	if not player or not player.get_meta("seated_workstation", false):
		return "FIRST CHECK: Enter the staff side of the booth.\nLook at the chair and press [E] to sit at the desk."
	if desk and desk.computer_active:
		return "COMPUTER: Compare the registry record and camera with the passenger.\n[Tab / Esc] Return to the desk."
	if desk and is_instance_valid(desk.held):
		return "DOCUMENTS: Compare name, ID, date, route and issue stamp.\n[R] Put the paper down, then look at the computer and press [E]."
	if desk and desk.sliding:
		return "PASSENGER: Wait for the papers to slide onto the desk."
	return "DESK: Look at a paper and press [E] to pick it up.\nUse the computer, then [E] on the APPROVED or DENIED stamp. [Tab] Stand up."


static func compact_step(gm: Node, tree: SceneTree) -> String:
	if not gm.powered:
		if gm.night >= 4 and not gm.has_item("maintenance_key"):
			return "ACCESS: Collect the maintenance key from Security.\nThen unlock Electrical and use the main power switch."
		return "POWER: Electrical Room → reconnect wires, then main switch. [F] flashlight" if gm.needs_power_repair() else "STARTUP: Find ELECTRICAL beside CCTV / SECURITY.\n[E] Main power switch · [F] Flashlight"
	if not gm.signed_in:
		return "LOGBOOK: Sign at the booth rear workbench · %d/%d crew signed" % [gm.staff_sign_in_count(), gm.required_staff().size()]
	for actor in tree.get_nodes_in_group("passenger_actor"):
		if actor.phase == "DANGER": return "RESCUE: [E] Guide the marked passenger to Security or the booth."
	var events := tree.get_first_node_in_group("night_events")
	if events and events.started and not events.completed: return events.hint()
	var service := tree.get_first_node_in_group("passenger_director")
	if gm.night == 1 and service and service.reviewed < 3: return booth_lesson(tree)
	if service and service.reviewed == 0: return "INSPECT: Booth desk → compare documents with the window camera."
	if not gm.objectives.get("check_platform", {}).get("done", false): return "PATROL: Scan your staff ID at a gate, then visit the platform."
	if gm.night >= 4 and not gm.entity_identified: return "EVIDENCE: Read the three reports, then identify the intruder at Security."
	var entity := tree.get_first_node_in_group("station_entity")
	if gm.night >= 4 and entity and not entity.banished:
		return "CONTAIN: Keep a direct flashlight beam on the identified intruder. Use cover if it approaches."
	if service and service.reviewed >= service.total_cases():
		var blockers: PackedStringArray = gm.shift_blockers()
		return "Station secured. The shift will finish shortly." if blockers.is_empty() else "FINISH THE SHIFT: " + blockers[0] + " [J] All remaining duties"
	return "Continue inspections and keep the station running. [J] Full night log"
