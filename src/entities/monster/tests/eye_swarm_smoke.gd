extends SceneTree
## Runtime smoke test for spawning, flock state exchange, movement, and rendering.

const FRAME_COUNT := 300
const OUTPUT_PATH := "user://eye_swarm_smoke.png"


func _initialize() -> void:
	var arena := load("res://src/environment/arena.tscn").instantiate() as Node3D
	root.add_child(arena)
	current_scene = arena
	_run.call_deferred(arena)


func _run(arena: Node3D) -> void:
	await physics_frame
	var controller: Node = arena.get_node("MonsterCore/AttackController")
	controller.set_attack_enabled(false)
	controller._spawn_eye_swarm(Vector3(0.0, 7.0, 2.0))
	await physics_frame
	var starting_positions: Dictionary = {}
	for eye in get_nodes_in_group("eye_swarm"):
		starting_positions[eye.get_instance_id()] = eye.global_position
	for _frame in FRAME_COUNT:
		await physics_frame
	var eyes := get_nodes_in_group("eye_swarm")
	if eyes.is_empty():
		push_error("Eye swarm disappeared before the smoke test completed")
		quit(1)
		return
	var greatest_displacement := 0.0
	var shared_neighbour_state := false
	for eye in eyes:
		if starting_positions.has(eye.get_instance_id()):
			greatest_displacement = maxf(
				greatest_displacement,
				eye.global_position.distance_to(starting_positions[eye.get_instance_id()])
			)
		shared_neighbour_state = shared_neighbour_state or not eye._neighbours.is_empty()
	if greatest_displacement < 2.0 or not shared_neighbour_state:
		push_error("Eye swarm did not move or exchange flock state")
		quit(1)
		return
	await _capture(arena, eyes)
	print(
		"EYE_SWARM_SMOKE passed count=%d displacement=%.2f image=%s"
		% [eyes.size(), greatest_displacement, ProjectSettings.globalize_path(OUTPUT_PATH)]
	)
	quit()


func _capture(arena: Node3D, eyes: Array[Node]) -> void:
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.global_position = Vector3(0.0, 8.0, 18.0)
	var center := Vector3.ZERO
	for eye in eyes:
		center += eye.global_position
	center /= float(eyes.size())
	camera.look_at(center, Vector3.UP)
	camera.current = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT_PATH)
