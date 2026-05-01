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

	_check("invalid_hq", UnitNotationFormatter.format_unit({
		"id": "hq_bad",
		"type": "headquarters",
		"size": "battalion"
	}), "HQ/?")

	_check("invalid_platoon", UnitNotationFormatter.format_unit({
		"id": "plt_bad",
		"type": "infantry",
		"size": "platoon",
		"company_letter": "A"
	}), "?/A/?")

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
