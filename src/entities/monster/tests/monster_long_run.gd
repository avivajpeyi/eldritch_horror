extends SceneTree
## Standalone long-duration visual smoke test.
##
## Run from the project root:
## godot --path . --script res://src/entities/monster/tests/monster_long_run.gd
##
## Optional arguments after `--`:
## --frames=7200 --capture-every=300 --output=user://monster_long_run

const STATE_NAMES := ["ROAM", "ARTILLERY", "NEST", "COLLAPSED"]

var total_frames := 3600
var capture_every := 300
var output_path := "user://monster_long_run"
var cycle_phases := false
var contact_test := false
var front_view := false
var arena: Node3D
var monster: CharacterBody3D
var player: CharacterBody3D
var attack_controller: Node
var capture_count := 0
var unsupported_frames := 0
var failed := false


func _initialize() -> void:
	_parse_arguments()
	seed(0xE1D817C)
	# Load after SceneTree initialization so project autoloads are registered before
	# the arena's dependent gameplay scripts compile.
	arena = load("res://src/environment/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	monster = arena.get_node("MonsterCore")
	player = arena.get_node("Player")
	attack_controller = monster.get_node("AttackController")
	var hud := arena.get_node_or_null("HUD")
	if hud != null:
		hud.visible = false
	_prepare_output_directory()
	_run.call_deferred()


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="):
			total_frames = maxi(int(argument.trim_prefix("--frames=")), 1)
		elif argument.begins_with("--capture-every="):
			capture_every = maxi(int(argument.trim_prefix("--capture-every=")), 1)
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument == "--cycle-phases":
			cycle_phases = true
		elif argument == "--contact-test":
			contact_test = true
		elif argument == "--front-view":
			front_view = true


func _prepare_output_directory() -> void:
	var absolute_path := ProjectSettings.globalize_path(output_path)
	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Could not create monster test output directory: %s" % absolute_path)
		failed = true
	print("MONSTER_LONG_RUN output=%s frames=%d capture_every=%d" % [absolute_path, total_frames, capture_every])


func _run() -> void:
	for frame in total_frames:
		await physics_frame
		if contact_test and frame == 90:
			player.global_position = monster.global_position + Vector3.RIGHT * 2.0
			player.velocity = Vector3.ZERO
		if cycle_phases and frame == total_frames / 3:
			monster.health = monster.max_health * 0.6
			SignalBus.monster_health_changed.emit(monster.health, monster.max_health)
			monster._update_encounter_phase()
		elif cycle_phases and frame == (total_frames * 2) / 3:
			monster.health = monster.max_health * 0.3
			SignalBus.monster_health_changed.emit(monster.health, monster.max_health)
			monster._update_encounter_phase()
		_validate_support()
		if frame == 1 or frame % capture_every == 0 or frame == total_frames - 1:
			await _capture(frame)
	if cycle_phases and total_frames >= 600 and player.health >= player.max_health:
		push_error("Phase-cycle run completed without damaging the player")
		failed = true
	if contact_test and total_frames > 120 and player.health >= player.max_health:
		push_error("Contact-damage run completed without damaging the player")
		failed = true
	print("MONSTER_LONG_RUN complete captures=%d failed=%s player_health=%.1f final_position=%s final_surface=%s" % [
		capture_count,
		str(failed),
		player.health,
		str(monster.global_position),
		str(monster.surface_up),
	])
	quit(1 if failed else 0)


func _validate_support() -> void:
	var normal_locomotion: bool = monster.locomotion_mode == 0
	var has_core_support: bool = not monster._find_core_surface_contact().is_empty()
	if normal_locomotion and not has_core_support and monster._planted_leg_count() == 0:
		unsupported_frames += 1
	else:
		unsupported_frames = 0
	if unsupported_frames == 60:
		push_error("Monster remained under-supported for 60 consecutive physics frames")
		failed = true


func _capture(frame: int) -> void:
	var camera := root.get_camera_3d()
	if camera == null:
		push_error("Monster long-run test could not find the player camera")
		failed = true
		return
	var angle := float(capture_count) * 1.17
	var surface_normal: Vector3 = monster.surface_up.normalized()
	var tangent: Vector3
	if front_view:
		# Match the side the real player is approaching from; a fixed local forward
		# can accidentally capture the back after wall/ceiling reorientation.
		tangent = (player.global_position - monster.global_position).slide(surface_normal).normalized()
		if tangent.length_squared() < 0.01:
			tangent = monster.global_basis.z.slide(surface_normal).normalized()
	else:
		tangent = surface_normal.cross(Vector3.UP).normalized()
		if tangent.length_squared() < 0.01:
			tangent = Vector3(cos(angle), 0.0, sin(angle))
		else:
			tangent = tangent.rotated(surface_normal, angle)
	camera.global_position = monster.global_position + surface_normal * (1.2 if front_view else 4.2) + tangent * (7.4 if front_view else 6.2)
	camera.look_at(monster.global_position, Vector3.UP if absf(surface_normal.y) < 0.94 else Vector3.FORWARD)
	await RenderingServer.frame_post_draw

	var state_name: String = STATE_NAMES[int(monster.current_state)]
	var attack_name := _safe_filename(String(attack_controller.get_attack_name()))
	var phase_name := String(attack_controller.get_phase_name())
	var filename := "monster_%06d_%s_%s_%s.png" % [
		frame,
		state_name.to_lower(),
		attack_name.to_lower(),
		phase_name.to_lower(),
	]
	var file_path := output_path.path_join(filename)
	var save_error := root.get_texture().get_image().save_png(file_path)
	if save_error != OK:
		push_error("Failed to save monster capture: %s" % ProjectSettings.globalize_path(file_path))
		failed = true
	capture_count += 1
	print("MONSTER_CAPTURE frame=%d pos=%s planted=%d stepping=%d state=%s attack=%s phase=%s remaining=%.2f player_health=%.1f surface=%s file=%s" % [
		frame,
		str(monster.global_position),
		monster._planted_leg_count(),
		monster._stepping_leg_count(),
		state_name,
		String(attack_controller.get_attack_name()),
		phase_name,
		attack_controller.get_time_remaining(),
		player.health,
		str(monster.surface_up),
		ProjectSettings.globalize_path(file_path),
	])


func _safe_filename(value: String) -> String:
	if value.is_empty():
		return "none"
	return value.to_lower().replace(" ", "_")
