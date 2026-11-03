extends RefCounted

## Identity-derived details are identical on ID portraits and every co-op machine.
static func describe(profile: Dictionary) -> Dictionary:
	var value: int = 17
	var identity := str(profile.get("id_name", profile.get("name", "PASSENGER"))).to_upper()
	for code in identity.length():
		value = (value * 31 + identity.unicode_at(code)) % 2147483647
	return {
		"seed": value,
		"hair_style": value % 4,
		"glasses": (value / 7) % 4 == 0,
		"bag": (value / 13) % 3 == 0,
		"height": 0.96 + (value % 5) * 0.015,
		"face_width": 0.94 + (value % 4) * 0.04,
		"shirt": [Color(0.81, 0.78, 0.67), Color(0.64, 0.70, 0.70), Color(0.73, 0.68, 0.62)][(value / 19) % 3],
		"trousers": [Color(0.10, 0.13, 0.18), Color(0.19, 0.18, 0.17), Color(0.16, 0.20, 0.17)][(value / 23) % 3],
	}
