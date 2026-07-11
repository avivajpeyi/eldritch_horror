extends Area3D

## Short-lived physical attack volume. It reports damage through SignalBus so the
## volume never needs a reference to the player scene.
var damage := 20.0
var impulse_strength := 10.0
var active_time := 0.25
var one_hit := true
var _hit_ids: Dictionary = {}

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	active_time -= delta
	if active_time <= 0.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or _hit_ids.has(body.get_instance_id()):
		return
	_hit_ids[body.get_instance_id()] = true
	var direction := body.global_position - global_position
	direction.y = maxf(direction.y, 0.25)
	SignalBus.player_damage_requested.emit(damage, global_position, direction.normalized() * impulse_strength)
	if one_hit:
		monitoring = false
