extends SceneTree
## Headless regression check for procedural attack appendages and weakpoints.


func _initialize() -> void:
	var arena := load("res://src/environment/arena.tscn").instantiate() as Node3D
	root.add_child(arena)
	current_scene = arena
	_run.call_deferred(arena.get_node("MonsterCore"))


func _run(monster: CharacterBody3D) -> void:
	await physics_frame
	var tail: MeshInstance3D = monster.get_node("Tail")
	var attack_tendrils: MeshInstance3D = monster.get_node("AttackTendrils")
	var mouth: AnimatableBody3D = monster.get_node("Weakpoints/MouthWeakpoint")
	if tail.mesh.get_surface_count() == 0:
		push_error("Procedural tail did not build a render surface")
		quit(1)
		return
	if attack_tendrils.mesh.get_surface_count() == 0:
		push_error("Procedural attack tendrils did not build a render surface")
		quit(1)
		return
	if not mouth.collision_shape.disabled:
		push_error("Mouth weakpoint began exposed")
		quit(1)
		return

	var signal_bus := root.get_node("/root/SignalBus")
	signal_bus.attack_phase_changed.emit(&"Fleshy Shrapnel", &"TELEGRAPH", 1.0)
	await physics_frame
	if mouth.collision_shape.disabled or not monster._mouth_open:
		push_error("Mouth weakpoint did not open during artillery telegraph")
		quit(1)
		return
	var initial_health: float = monster.health
	mouth.projectile_hit_typed(10.0, GameManager.ElementType.KINETIC, Vector3.FORWARD)
	var expected_health: float = initial_health - 10.0 * monster.mouth_damage_multiplier
	if not is_equal_approx(monster.health, expected_health):
		push_error("Kinetic mouth weakpoint damage failed")
		quit(1)
		return

	signal_bus.attack_telegraphed.emit(&"Tendril Whip", Vector3(7.0, 1.0, 3.0), 1.0)
	signal_bus.attack_phase_changed.emit(&"Tendril Whip", &"ACTIVE", 0.32)
	await physics_frame
	if attack_tendrils._attack_phase != &"ACTIVE":
		push_error("Procedural tendrils did not enter whip attack phase")
		quit(1)
		return

	signal_bus.attack_phase_changed.emit(&"Tail Sweep", &"ACTIVE", 0.45)
	await physics_frame
	if tail._sweep_phase != &"ACTIVE":
		push_error("Tail did not react to the sweep attack phase")
		quit(1)
		return
	print("MONSTER_ANATOMY_SMOKE passed surfaces=%d tendril_surfaces=%d health=%.1f mouth_open=%s tail_phase=%s" % [
		tail.mesh.get_surface_count(),
		attack_tendrils.mesh.get_surface_count(),
		monster.health,
		str(monster._mouth_open),
		String(tail._sweep_phase),
	])
	quit()
