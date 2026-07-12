extends Entity
class_name Player

const ANIM_SPEED_SCALE      := 1.5
const HAND_ANIM_SPEED_SCALE := 1.0

# ─────────────────────────────────────────────────────────────────────────────
#  Скорость
# ─────────────────────────────────────────────────────────────────────────────

var standart_speed: float = 10.0
var slow_speed:     float = 7.0
var dash_speed:     float = 20.0

@export_range(0.01, 1.0, 0.01) var acceleration: float = 0.20
@export_range(0.01, 1.0, 0.01) var friction:     float = 0.45

var _current_velocity: Vector2 = Vector2.ZERO


# ─────────────────────────────────────────────────────────────────────────────
#  Exit walk (автоход после перехода через дверь)
# ─────────────────────────────────────────────────────────────────────────────

var _exit_walk_active:     bool    = false
var _exit_walk_timer:      float   = 0.0
var _exit_walk_direction:  Vector2 = Vector2.ZERO
var _exit_walk_speed_mult: float   = 0.7


# ─────────────────────────────────────────────────────────────────────────────
#  Lunge (рывок-атака)
# ─────────────────────────────────────────────────────────────────────────────

var _is_lunging:       bool    = false
var _lunge_timer:      float   = 0.0
var _lunge_direction:  Vector2 = Vector2.ZERO
var _lunge_hit_bodies: Array   = []


# ─────────────────────────────────────────────────────────────────────────────
#  Dodge / перекат (не зависит от оружия — базовое умение игрока)
# ─────────────────────────────────────────────────────────────────────────────

## Требует action "Dodge" в Input Map (например, Space или Shift)
@export_category("Dodge")
@export var dodge_speed:      float = 45.0
@export var dodge_duration:   float = 0.22
@export var dodge_cooldown:   float = 0.6
@export var dodge_invincible: bool  = true

var _is_dodging:            bool    = false
var _dodge_timer:           float   = 0.0
var _dodge_cooldown_timer:  float   = 0.0
var _dodge_direction:       Vector2 = Vector2.ZERO


# ─────────────────────────────────────────────────────────────────────────────
#  Ноды
# ─────────────────────────────────────────────────────────────────────────────

@onready var gui:              CanvasLayer      = $GUI
@onready var health_bar:       health_bar      = $GUI/HUD/HealthBar
@onready var skin                               = $Skin
@onready var hit_box:          player_HitBox    = %player_HitBox
@onready var defense_label:    Label            = $HUD/HBoxContainer/Deffense/Label
@onready var death_menu:       Control          = $HUD/DeathMenu
@onready var effect_display_ui: EffectDisplayUI = $GUI/HUD/EffectDisplayUI
@onready var _hand:            Node2D           = $Skin/Body/Hand
@onready var _hurt_col:        CollisionShape2D = $HurtBox/CollisionShape2D
@onready var curse_label:      Label            = $HUD/HealthBar/HBoxContainer/CurseIcon/CurseLabel
@onready var weapon_passive:   WeaponPassiveHandler = $WeaponPassiveHandler

@export var BodyAnimator:  AnimationPlayer
@export var HandAanimator: AnimationPlayer

var dir:       Vector2 = Vector2.ZERO
var mouse_pos: Vector2 = Vector2.ZERO
var is_attack: bool    = false

var corruption : float = 0

# ─────────────────────────────────────────────────────────────────────────────
#  Инициализация
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()

	Global.hotbar    = get_tree().get_first_node_in_group("Hotbar")    as Hotbar
	Global.inventory = get_tree().get_first_node_in_group("Inventory") as Inventory
	get_tree().get_first_node_in_group("DebugObject").update()
	gui.player = self

	SaveLoad.load_player(self)
	print("Player Corruption Level is: "  + str(corruption))

	if Entity_stats.current_health <= 0:
		Entity_stats.current_health = Entity_stats.max_health
		_on_health_changed(Entity_stats.current_health)

	health_bar.update_value(Entity_stats.current_health,Entity_stats.max_health, corruption)
	effect_display_ui.set_entity(self)
	_register_commands()

	if Global.get("pending_exit_walk") and Global.pending_exit_walk["active"]:
		var d                 := Global.pending_exit_walk
		_exit_walk_direction   = d["direction"]
		_exit_walk_timer       = d["duration"]
		_exit_walk_speed_mult  = d["speed_mult"]
		_exit_walk_active      = true
		Global.pending_exit_walk["active"] = false


func _register_commands() -> void:
	var c := Global.developer_console
	c.register_command("set_speed",     _cmd_set_speed,                      "Set player speed: set_speed [value]")
	c.register_command("tp",            _cmd_teleport,                       "Teleport: tp [x] [y]")
	c.register_command("multiply",      _cmd_set_standart_multipilier_speed, "Default movement multiplier: multiply [value]")
	c.register_command("slow_multiply", _cmd_set_slow_multipilier_speed,     "Slow multiplier: slow_multiply [value]")
	c.register_command("dash_multiply", _cmd_set_dash_multipilier_speed,     "Dash multiplier: dash_multiply [value]")
	c.register_command("scale",         _cmd_scale_change,                   "Player scale: scale [x] [y]")
	c.register_command("unkillable",    _cmd_unkillable,                     "Toggle damage immunity")


# ─────────────────────────────────────────────────────────────────────────────
#  Физика и движение
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	mouse_pos = get_global_mouse_position()

	if is_alive:
		_dodge_cooldown_timer = maxf(0.0, _dodge_cooldown_timer - delta)
		_update_dodge(delta)

		if not _is_dodging:
			_update_lunge(delta)
			if not _is_lunging:
				if _exit_walk_active:
					_update_exit_walk(delta)
				else:
					_movement(delta)
		_animate()

		if not is_attack:
			hit_box.look_at(mouse_pos)

		if velocity.length_squared() <= 1.0 or is_attack:
			skin.scale.x = scale.x if mouse_pos.x > position.x else -scale.x

	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Dodge") and _can_dodge():
		_start_dodge()


# ─────────────────────────────────────────────────────────────────────────────
#  Dodge / перекат
# ─────────────────────────────────────────────────────────────────────────────

func _can_dodge() -> bool:
	return is_alive and not _is_dodging and not _is_lunging \
		and _dodge_cooldown_timer <= 0.0 and not Global.is_opened_menu


func _start_dodge() -> void:
	_is_dodging           = true
	_dodge_timer          = dodge_duration
	_dodge_cooldown_timer = dodge_cooldown

	var input_dir := Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown").normalized()
	_dodge_direction = input_dir if input_dir != Vector2.ZERO else (mouse_pos - global_position).normalized()

	if dodge_invincible:
		_hurt_col.disabled = true

	if Vfx != null and Vfx.has_method("_dodge_vfx"):
		Vfx._dodge_vfx(self)


func _update_dodge(delta: float) -> void:
	if not _is_dodging:
		return

	_dodge_timer -= delta
	velocity = _dodge_direction * dodge_speed * standart_speed

	if _dodge_direction.x > 0:
		skin.scale.x = 1
	elif _dodge_direction.x < 0:
		skin.scale.x = -1

	if _dodge_timer <= 0.0:
		_end_dodge()


func _end_dodge() -> void:
	_is_dodging       = false
	_current_velocity = velocity * 0.4  # плавный выход из переката, а не резкий стоп

	if dodge_invincible:
		_hurt_col.disabled = false


func _movement(delta: float) -> void:
	if Global.is_opened_menu:
		_current_velocity = _current_velocity.lerp(Vector2.ZERO, friction)
		velocity = _current_velocity
		return

	dir = Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown").normalized()
	var target_velocity := dir * Entity_stats.move_speed * standart_speed

	if dir != Vector2.ZERO:
		_current_velocity = _current_velocity.lerp(target_velocity, acceleration)
	else:
		_current_velocity = _current_velocity.lerp(Vector2.ZERO, friction)

	velocity = _current_velocity

	if is_attack:
		skin.scale.x = scale.x if mouse_pos.x > position.x else -scale.x
	elif dir.x > 0:
		skin.scale.x = 1
	elif dir.x < 0:
		skin.scale.x = -1


func _animate() -> void:
	var looking_right   := mouse_pos.x > position.x
	var moving_backward := (looking_right and velocity.x < 0) or (not looking_right and velocity.x > 0)

	if velocity.length_squared() > 1.0:
		var spd := -1.0 if moving_backward else 1.0
		BodyAnimator.play("Walk", -1.0, spd)
		if not is_attack:
			HandAanimator.play("Walk", -1.0, spd)
	else:
		BodyAnimator.play("Idle")
		if not is_attack:
			HandAanimator.play("Idle")


# ─────────────────────────────────────────────────────────────────────────────
#  Lunge
# ─────────────────────────────────────────────────────────────────────────────

func _start_lunge(equip: equip_data) -> void:
	_is_lunging       = true
	_lunge_timer      = equip.lunge_duration
	_lunge_direction  = (mouse_pos - global_position).normalized()
	_lunge_hit_bodies = []

	if equip.lunge_invincible:
		_hurt_col.disabled = true

	if equip.lunge_trail_scene:
		var trail := equip.lunge_trail_scene.instantiate()
		get_parent().add_child(trail)
		if trail.has_method("start"):
			trail.start(self)

	hit_box.look_at(global_position + _lunge_direction)


func _update_lunge(delta: float) -> void:
	if not _is_lunging:
		return

	var equip := hit_box.equip as equip_data
	if not equip:
		_end_lunge()
		return

	_lunge_timer -= delta
	velocity = _lunge_direction * equip.lunge_speed

	if weapon_passive:
		weapon_passive.apply_lunge_damage(_lunge_hit_bodies, equip.Damage * equip.lunge_damage_multiplier)

	if _lunge_timer <= 0.0:
		_end_lunge()


func _end_lunge() -> void:
	_is_lunging       = false
	_lunge_timer      = 0.0
	_lunge_hit_bodies = []
	_current_velocity = velocity

	var equip := hit_box.equip as equip_data
	if equip and equip.lunge_invincible:
		_hurt_col.disabled = false


# ─────────────────────────────────────────────────────────────────────────────
#  Ввод
# ─────────────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("LMB") or is_attack or Global.is_opened_menu:
		return

	if hit_box.is_weapon and hit_box.equip is equip_data:
		var equip := hit_box.equip as equip_data
		hit_box.look_at(mouse_pos)
		is_attack             = true
		HandAanimator.speed_scale = equip.Atk_speed
		HandAanimator.play(equip.play_anim)

		if equip.lunge_enabled and not _is_lunging:
			_start_lunge(equip)

		if equip.play_anim == "Attack":
			call_deferred("_start_attack_cooldown", equip.one_shot_attack)
		elif equip.play_anim == "Shoot":
			_hand.look_at(mouse_pos)
			call_deferred("_start_shot_cooldown", equip.one_shot_attack)

	elif hit_box.equip is FoodData:
		is_attack = true
		HandAanimator.play(hit_box.equip.play_anim)
		call_deferred("_start_eat_cooldown")

	else:
		is_attack = true
		HandAanimator.play(hit_box.equip.play_anim)
		call_deferred("_start_attack_cooldown", true)


func _start_attack_cooldown(one_shot: bool) -> void:
	await HandAanimator.animation_finished
	is_attack = false
	hit_box.look_at(mouse_pos)

	if not one_shot and Input.is_action_pressed("LMB") \
			and hit_box.is_weapon and hit_box.equip is equip_data:
		var equip := hit_box.equip as equip_data
		is_attack = true
		HandAanimator.speed_scale = equip.Atk_speed
		HandAanimator.play(hit_box.play_anim)
		hit_box.look_at(mouse_pos)
		if equip.lunge_enabled and not _is_lunging:
			_start_lunge(equip)
		call_deferred("_start_attack_cooldown", false)


func _start_shot_cooldown(one_shot: bool) -> void:
	await HandAanimator.animation_finished
	is_attack = false
	_hand.look_at(mouse_pos)
	hit_box.look_at(mouse_pos)

	if not one_shot and Input.is_action_pressed("LMB") \
			and hit_box.is_weapon and hit_box.equip is equip_data:
		var equip := hit_box.equip as equip_data
		is_attack = true
		HandAanimator.speed_scale = equip.Atk_speed
		HandAanimator.play(hit_box.play_anim)
		hit_box.look_at(mouse_pos)
		call_deferred("_start_attack_cooldown", false)
	else:
		_hand.rotation = 0


func _start_eat_cooldown() -> void:
	await HandAanimator.animation_finished
	is_attack = false


# ─────────────────────────────────────────────────────────────────────────────
#  Стрельба
# ─────────────────────────────────────────────────────────────────────────────

func shoot() -> void:
	var equip := hit_box.equip as equip_data
	if not equip or not equip.projectile:
		return
	var marker   := $player_HitBox/Marker2D
	var base_dir  = (get_global_mouse_position() - marker.global_position).normalized()
	for i in equip.num_projectiles:
		var bullet := equip.projectile.instantiate() as Projectile
		bullet.shot_target = "Ennemy"
		bullet.setup(
			marker.global_position,
			base_dir.rotated((randf() - 0.5) * deg_to_rad(equip.spread_degrees)),
			equip.Damage,
			equip.projectile_speed,
		)
		get_parent().add_child(bullet)


func _on_weapon_hit(target: Node) -> void:
	if weapon_passive:
		weapon_passive.try_apply_on_hit_effect(target)


# ─────────────────────────────────────────────────────────────────────────────
#  Сохранение (вызывается через group "Save")
# ─────────────────────────────────────────────────────────────────────────────
#region save0
func save_game() -> void:
	SaveLoad.save_player(self)

#endregion
# ─────────────────────────────────────────────────────────────────────────────
#  Сигналы и смерть
# ─────────────────────────────────────────────────────────────────────────────

func _on_health_changed(new_health: float) -> void:
	health_bar.update_value(new_health,Entity_stats.max_health, corruption)
	if new_health <= corruption:
		die()

func _on_died() -> void:
	Global.play_game_over()
	get_parent().Die()
	HandAanimator.stop()
	BodyAnimator.play("Death")
	gui.call_death()

func respawn() -> void:
	Entity_stats.current_health = Entity_stats.max_health / 3.0
	_on_health_changed(Entity_stats.current_health)
	_current_velocity = Vector2.ZERO
	_is_lunging       = false
	is_alive          = true

func queue_exit_walk(direction: Vector2, duration: float, speed_mult: float) -> void:
	Global.pending_exit_walk = {
		"active":     true,
		"direction":  direction,
		"duration":   duration,
		"speed_mult": speed_mult,
	}

func _update_exit_walk(delta: float) -> void:
	if not _exit_walk_active:
		return

	_exit_walk_timer -= delta
	if _exit_walk_timer <= 0.0:
		_exit_walk_active = false
		return

	var target_vel := _exit_walk_direction * Entity_stats.move_speed \
		* standart_speed * _exit_walk_speed_mult
	_current_velocity = _current_velocity.lerp(target_vel, acceleration)
	velocity          = _current_velocity

	if _exit_walk_direction.x > 0:
		skin.scale.x = 1
	elif _exit_walk_direction.x < 0:
		skin.scale.x = -1

func curse(add_count : float):
	corruption += add_count
	health_bar.update_value(Entity_stats.current_health,Entity_stats.max_health, corruption)
	if corruption >= Entity_stats.max_health:
		die()
	DebugLog.log("Corrupt")
# ─────────────────────────────────────────────────────────────────────────────
#  Dev-команды
# ─────────────────────────────────────────────────────────────────────────────
#region Commands
func _cmd_set_speed(args: Array) -> String:
	if args.size() == 1 and args[0].is_valid_float():
		Entity_stats.move_speed = args[0].to_float()
		return "Speed set to " + str(Entity_stats.move_speed)
	return "Usage: set_speed [value]"

func _cmd_set_standart_multipilier_speed(args: Array) -> String:
	if args.size() == 1 and args[0].is_valid_float():
		standart_speed = args[0].to_float()
		return "Multiplier set to " + str(standart_speed)
	return "Usage: multiply [value]"

func _cmd_set_slow_multipilier_speed(args: Array) -> String:
	if args.size() == 1 and args[0].is_valid_float():
		slow_speed = args[0].to_float()
		return "Slow multiplier set to " + str(slow_speed)
	return "Usage: slow_multiply [value]"

func _cmd_set_dash_multipilier_speed(args: Array) -> String:
	if args.size() == 1 and args[0].is_valid_float():
		dash_speed = args[0].to_float()
		return "Dash multiplier set to " + str(dash_speed)
	return "Usage: dash_multiply [value]"

func _cmd_teleport(args: Array) -> String:
	if args.size() == 2 and args[0].is_valid_float() and args[1].is_valid_float():
		position = Vector2(args[0].to_float(), args[1].to_float())
		return "Teleported to " + str(position)
	return "Usage: tp [x] [y]"

func _cmd_scale_change(args: Array) -> String:
	if args.size() == 2 and args[0].is_valid_float() and args[1].is_valid_float():
		scale = Vector2(args[0].to_float(), args[1].to_float())
		return "Scale set to " + str(scale)
	return "Usage: scale [x] [y]"

func _cmd_unkillable(args: Array) -> String:
	_hurt_col.disabled = not _hurt_col.disabled
	return "Damage: " + ("OFF (unkillable)" if _hurt_col.disabled else "ON")
#endregion
