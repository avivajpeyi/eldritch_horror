extends Node3D
func _ready() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("090713")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("403b68")
	environment.ambient_light_energy = 0.65
	world.environment = environment
	add_child(world)
	var light := OmniLight3D.new()
	light.light_color = Color("8d71ff")
	light.light_energy = 8.0
	light.omni_range = 28.0
	light.position = Vector3(0, 7, 0)
	add_child(light)
	_add_box(Vector3(0, -0.5, 0), Vector3(24, 1, 24), Color("17152b"))
	for i in 8:
		var angle := TAU * float(i) / 8.0
		_add_box(Vector3(cos(angle) * 11.0, 2.5, sin(angle) * 11.0), Vector3(1.2, 5, 1.2), Color("30284d"))

func _add_box(position: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = position
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(mesh)
	body.add_child(collision)
	add_child(body)
