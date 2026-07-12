class_name MonsterRoamState
extends RefCounted
## Opening encounter profile: mobile, direct, and readable.

func state_id() -> GameManager.MonsterState:
	return GameManager.MonsterState.ROAM

func locomotion_multiplier() -> float:
	return 1.0

func cadence_multiplier() -> float:
	return 1.0

func cooldown_multiplier() -> float:
	return 1.0

func attack_pool(on_elevated_surface: bool) -> Array[StringName]:
	if on_elevated_surface:
		return [&"TENDRIL_WHIP", &"SHRAPNEL", &"TENDRIL_WHIP"]
	return [&"PILLAR_LEAP", &"TENDRIL_WHIP", &"ANCHOR_SWEEP"]
