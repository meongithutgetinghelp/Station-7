extends RefCounted
## Replace a checkpoint only after its complete temporary file can be read back.
## Keep the preceding valid checkpoint separately for interrupted/corrupt writes.

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _point(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _number(value[0]) and _number(value[1]) and _number(value[2])

static func read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return {}
	var payload = parser.data
	if not payload is Dictionary or payload.get("version", 0) != 1: return {}
	var core = payload.get("core")
	if not core is Dictionary: return {}
	if not _number(core.get("night")): return {}
	if int(core.night) < 1 or int(core.night) > 7: return {}
	if payload.has("saved_at") and not _number(payload.saved_at): return {}
	for key in ["time", "state", "balance", "rescued", "lost", "signature_generation"]:
		if core.has(key) and not _number(core[key]): return {}
	if core.has("state") and (int(core.state) < 0 or int(core.state) > 3): return {}
	if core.has("signed_staff"):
		if not core.signed_staff is Array: return {}
		for id in core.signed_staff:
			if not _number(id): return {}
	for key in ["objectives", "inventory"]:
		if not core.get(key) is Dictionary: return {}
	for key in ["campaign", "rewards"]:
		if core.has(key) and not core[key] is Dictionary: return {}
	if core.get("campaign", {}).has("mystery"):
		if not core.campaign.mystery is Array: return {}
		for entry in core.campaign.mystery:
			if not entry is String: return {}
	if not payload.get("participants", {}) is Dictionary: return {}
	for participant in payload.get("participants", {}).values():
		if not participant is Dictionary: return {}
		for key in ["position"]:
			if participant.has(key) and not _point(participant[key]): return {}
		if participant.has("position") and participant.has("target") and not _point(participant.target): return {}
		if participant.has("people"):
			if not participant.people is Array: return {}
			for person in participant.people:
				if not person is Dictionary or not _point(person.get("position")): return {}
				if not person.get("uid") is String or not person.get("phase") is String or not _number(person.get("yaw")): return {}
				for key in ["train_offset", "visit_target", "queue_destination"]:
					if person.has(key) and not _point(person[key]): return {}
				if not person.get("points", []) is Array: return {}
				for point in person.get("points", []):
					if not _point(point): return {}
	for objective in core.objectives.values():
		if not objective is Dictionary or not objective.has("done") or not objective.has("text"): return {}
		if not objective.done is bool or not objective.text is String: return {}
	for count in core.inventory.values():
		if not _number(count) or float(count) < 0: return {}
	return payload


static func read(path: String) -> Dictionary:
	var payload := read_valid(path)
	if not payload.is_empty(): return payload
	payload = read_valid(path + ".bak")
	if not payload.is_empty(): payload["recovered_backup"] = true
	return payload


static func write(path: String, payload: Dictionary) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or read_valid(temporary).is_empty(): return false
	# Never replace the good backup with a damaged primary.
	if not read_valid(path).is_empty():
		var backup_temporary := ProjectSettings.globalize_path(path + ".bak.tmp")
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), backup_temporary) != OK: return false
		if DirAccess.rename_absolute(backup_temporary, ProjectSettings.globalize_path(path + ".bak")) != OK: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) == OK
