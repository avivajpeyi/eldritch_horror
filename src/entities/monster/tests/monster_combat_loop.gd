extends SceneTree
## Headless regression check for anchor matching, collapse, and exposure damage cap.


func _initialize() -> void:
	var arena := load("res://src/environment/arena.tscn").instantiate() as Node3D
	root.add_child(arena)
	current_scene = arena
	_run.call_deferred(arena.get_node("MonsterCore"))


func _run(monster: CharacterBody3D) -> void:
	await physics_frame
	var initial_health: float = monster.health
	monster._on_anchor_hit(&"ANCHOR_RED", monster.anchor_max_health, GameManager.ElementType.KINETIC)
	monster._on_anchor_hit(&"ANCHOR_BLUE", monster.anchor_max_health, GameManager.ElementType.KINETIC)
	if monster.locomotion_mode != monster.LocomotionMode.COLLAPSED or not monster._core_exposed:
		push_error("Two severed anchors did not expose and collapse the monster")
		quit(1)
		return
	monster._on_eye_hit(monster.max_health, GameManager.ElementType.KINETIC)
	var expected_health: float = initial_health - monster.max_health * monster.max_health_per_exposure_ratio
	if not is_equal_approx(monster.health, expected_health):
		push_error("Exposure damage cap failed: expected %.1f, got %.1f" % [expected_health, monster.health])
		quit(1)
		return
	print("MONSTER_COMBAT_LOOP passed health=%.1f collapsed=%s exposed=%s" % [monster.health, str(monster.locomotion_mode == monster.LocomotionMode.COLLAPSED), str(monster._core_exposed)])
	quit()
