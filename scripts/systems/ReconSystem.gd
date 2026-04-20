extends RefCounted
class_name ReconSystem

static func resolve_recon(attacker: Dictionary, defender: Dictionary, modifier: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var base_roll := rng.randi_range(0, 100)
	var attacker_bonus := int(attacker.get("recon_bonus", 0))
	var defender_penalty := int(defender.get("concealment", 0))
	var total := clamp(base_roll + attacker_bonus + modifier - defender_penalty, 0, 100)
	return {
		"roll": base_roll,
		"total": total,
		"band": _band_for(total)
	}

static func _band_for(score: int) -> String:
	if score < 20:
		return "No Contact"
	if score < 45:
		return "Suspected"
	if score < 70:
		return "Partial Identification"
	if score < 90:
		return "Clear Identification"
	return "Full Intelligence"
