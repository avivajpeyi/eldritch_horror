class_name MonsterNestState
extends RefCounted
## Final encounter profile: frantic anchoring and aggressive minion pressure.

func state_id() -> GameManager.MonsterState:
	return GameManager.MonsterState.NEST

func locomotion_multiplier() -> float:
	return 1.16

func cadence_multiplier() -> float:
	return 1.35

func cooldown_multiplier() -> float:
	return 0.72

func attack_pool(on_elevated_surface: bool) -> Array[StringName]:
	if on_elevated_surface:
		return [&"EYE_SWARM", &"SHRAPNEL", &"TENDRIL_WHIP"]
	return [&"EYE_SWARM", &"ANCHOR_SWEEP", &"TENDRIL_WHIP", &"SHRAPNEL"]
