class_name MonsterArtilleryState
extends RefCounted
## Mid encounter profile: controls space while continuing to traverse surfaces.

func state_id() -> GameManager.MonsterState:
	return GameManager.MonsterState.ARTILLERY

func locomotion_multiplier() -> float:
	return 0.92

func cadence_multiplier() -> float:
	return 1.12

func cooldown_multiplier() -> float:
	return 0.78

func attack_pool(on_elevated_surface: bool) -> Array[StringName]:
	if on_elevated_surface:
		return [&"SHRAPNEL", &"SHRAPNEL", &"TENDRIL_WHIP", &"EYE_SWARM"]
	return [&"SHRAPNEL", &"SHRAPNEL", &"TENDRIL_WHIP", &"ANCHOR_SWEEP"]
