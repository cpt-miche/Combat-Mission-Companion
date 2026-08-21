extends SceneTree

const UnitNotationFormatter = preload("res://scripts/domain/units/UnitNotationFormatter.gd")

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_check("hq", UnitNotationFormatter.format_unit({
		"id": "hq_1",
		"type": "headquarters",
		"size": "battalion",
		"battalion_number": 1,
		"regiment_number": 2
	}), "HQ/1-2")

	_check("company", UnitNotationFormatter.format_unit({
		"id": "co_a",
		"type": "infantry",
		"size": "company",
		"company_letter": "A",
		"battalion_number": 1,
		"regiment_number": 2
	}), "A/1-2")

	_check("platoon", UnitNotationFormatter.format_unit({
		"id": "plt_1",
		"type": "infantry",
		"size": "platoon",
		"company_letter": "A",
		"platoon_number": 1,
		"battalion_number": 1,
		"regiment_number": 2
	}), "1/A/1-2")

	_check("support", UnitNotationFormatter.format_unit({
		"id": "at_1",
		"type": "anti_tank",
		"size": "company",
		"battalion_number": 1,
		"regiment_number": 2
	}), "?/1-2")

	_check("local_battalion", UnitNotationFormatter.format_unit({
		"id": "bn_direct",
		"type": "infantry",
		"size": "battalion",
		"battalion_number": 1
	}), "1st Infantry Battalion")

	_check("local_hq", UnitNotationFormatter.format_unit({
		"id": "hq_bad",
		"type": "headquarters",
		"size": "battalion"
	}), "Battalion HQ")

	_check("local_company", UnitNotationFormatter.format_unit({
		"id": "co_direct",
		"type": "infantry",
		"size": "company",
		"company_letter": "A",
		"battalion_number": 1
	}), "A Company")

	_check("local_platoon", UnitNotationFormatter.format_unit({
		"id": "plt_bad",
		"type": "infantry",
		"size": "platoon",
		"company_letter": "A",
		"platoon_number": 1,
		"battalion_number": 1
	}), "1st Platoon")

	_check("attached_company", UnitNotationFormatter.format_unit({
		"id": "attached_tank_company",
		"type": "tank",
		"size": "company",
		"is_attached": true,
		"display_name": "1st Medium Tank Company (Attached)",
		"designation": {
			"battalion_number": 1,
			"regiment_number": 1,
			"attached_company_index": 1
		}
	}), "1st Medium Tank Company (Attached)")

	_check("attached_company_platoon", UnitNotationFormatter.format_unit({
		"id": "attached_tank_platoon",
		"type": "tank",
		"size": "platoon",
		"display_name": "1st Medium Tank Platoon",
		"designation": {
			"battalion_number": 1,
			"regiment_number": 1,
			"platoon_number": 1,
			"attached_company_index": 1
		}
	}), "1st Medium Tank Platoon")

	_check("counter_platoon_caps_at_battalion", UnitNotationFormatter.format_counter_unit({
		"size": "platoon",
		"designation": {
			"platoon_number": 1,
			"company_letter": "A",
			"battalion_number": 2,
			"regiment_number": 9,
			"division_number": 4
		}
	}), "1/A/2")

	_check("counter_company_caps_at_battalion", UnitNotationFormatter.format_counter_unit({
		"size": "company",
		"designation": {"company_letter": "B", "battalion_number": 3, "regiment_number": 7}
	}), "B/3")

	_check("counter_strips_saved_regiment_suffix", UnitNotationFormatter.format_counter_unit({
		"short_name": "2/C/1-8"
	}), "2/C/1")

	if _failures > 0:
		push_error("Unit notation check failed with %d assertion(s)." % _failures)
		quit(1)
		return

	print("Unit notation check: passed")
	quit(0)

func _check(case_name: String, actual: String, expected: String) -> void:
	if actual == expected:
		print("[PASS] %s => %s" % [case_name, actual])
		return
	_failures += 1
	push_error("[FAIL] %s => expected '%s', got '%s'" % [case_name, expected, actual])
