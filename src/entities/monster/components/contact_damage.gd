extends Area3D
## Persistent close-contact pressure. Damage is reported through SignalBus and
## rate-limited per overlapping body so the monster cannot erase the player in a
## single physics frame.

@export var damage := 9.0
@export var repeat_cooldown := 1.05
@export var impulse_strength := 7.0

var _cooldowns: Dictionary = {}


func _ready() -> void:
	monitoring = true
	collision_layer = 0


func _physics_process(delta: float) -> void:
	var active_ids: Dictionary = {}
	for body in get_overlapping_bodies():
		if not body.is_in_group("player"):
			continue
		var body_id := body.get_instance_id()
		active_ids[body_id] = true
		var remaining: float = maxf(float(_cooldowns.get(body_id, 0.0)) - delta, 0.0)
		if remaining <= 0.0:
			var direction := body.global_position - global_position
			direction.y = maxf(direction.y, 0.3)
			SignalBus.player_damage_requested.emit(damage, global_position, direction.normalized() * impulse_strength)
			remaining = repeat_cooldown
		_cooldowns[body_id] = remaining
	for body_id in _cooldowns.keys():
		if not active_ids.has(body_id):
			_cooldowns.erase(body_id)
