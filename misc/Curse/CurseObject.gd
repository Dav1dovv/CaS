extends RapierArea2D
class_name CurseObject

# ═══════════════════════════════════════════════════════════════════════════════
#  CurseObject — «Волейбол тьмы»
#
#  Спавнится когда игрок разрушает Harvestable киркой ниже нужного tier.
#  Ведёт себя как мяч: медленно движется к игроку, можно отбить оружием,
#  направить на врага или ресурс. Сильное оружие уничтожает мгновенно.
#
#  СЛОИ (настроить в Godot Inspector → Node → Collision):
#    Layer  6 — CurseObject (PlayerHitBox должен иметь Mask 6)
#    Mask   5 — Player HurtBox (реальный layer HurtBox игрока = 16 → бит 5!)
#    Mask   6 — Enemy HurtBox (чтобы попасть во врага)
#    Mask   2 — Harvestable   (чтобы заразить ресурс)
#  ⚠ ВАЖНО: HurtBox игрока в player.tscn имеет collision_layer = 16 (слой 5),
#  а НЕ слой 4, как можно было бы предположить. Если CurseObject не заражает
#  игрока — проверь Collision Mask в его сцене: должен быть включён слой 5.
# ═══════════════════════════════════════════════════════════════════════════════

## Урон заражением при попадании в игрока. Устанавливается Harvestable при спавне.
var infection_damage: float = 8.0

## Порог урона оружия для МГНОВЕННОГО уничтожения (damage >= threshold → destroy)
const DESTROY_THRESHOLD: int = 7

## Сколько раз можно отбить до принудительного взрыва
@export_range(1, 8, 1) var hits_remaining: int = 4

## Время жизни в секундах
@export_range(2.0, 10.0, 0.5) var lifetime: float = 6.0

## Начальная скорость движения к игроку (px/сек)
@export_range(40.0, 200.0, 10.0) var base_speed: float = 60.0

## Насколько быстро затухает скорость после отбития (0 = не затухает, 1 = мгновенно)
@export_range(0.0, 0.5, 0.01) var velocity_decay: float = 0.15

## Corruption value добавляемый Harvestable-ресурсу при попадании
@export_range(5.0, 50.0, 5.0) var resource_corruption_add: float = 25.0

## Сколько заражения получает игрок за КАЖДЫЙ удар по заражённому объекту
## Финальное значение умножается на armor_curse_multiplier из брони/амулетов
@export_range(0.0, 20.0, 0.5) var infection_per_hit : float = 2.0

# ── Internal ──────────────────────────────────────────────────────────────────
var _velocity: Vector2 = Vector2.ZERO
var _lifetime_timer: float = 0.0
var _spawn_pause: float = 0.3   # секунд зависания на месте после спавна
var _is_active: bool = false     # false пока идёт пауза после спавна
var _player: Node = null
var _tween: Tween


func _ready() -> void:
	add_to_group("CurseObject")

	_player = get_tree().get_first_node_in_group("Player")
	_lifetime_timer = lifetime

	# Подключаем сигналы детекции
	area_entered.connect(_on_area_entered)

	# Визуальная пульсация при спавне
	_pulse_spawn_animation()

	# Ждём паузу перед началом движения
	await get_tree().create_timer(_spawn_pause).timeout
	_is_active = true


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	_lifetime_timer -= delta

	# Принудительный взрыв по таймеру или hits_remaining
	if _lifetime_timer <= 0.0 or hits_remaining <= 0:
		_explode_on_nearest()
		return

	# Затухание скорости
	var current_speed := _velocity.length()
	if current_speed > base_speed * 0.5:
		_velocity = _velocity.lerp(Vector2.ZERO, velocity_decay * delta * 10.0)
	else:
		# Скорость упала — ползём к игроку
		_home_toward_player(delta)

	global_position += _velocity * delta

	# Визуально темнеем по мере уменьшения lifetime
	var ratio := _lifetime_timer / lifetime
	modulate = Color(
		lerp(0.8, 0.2, 1.0 - ratio),
		lerp(0.1, 0.0, 1.0 - ratio),
		lerp(0.8, 0.0, 1.0 - ratio),
		1.0
	)


# ─── Публичный API ────────────────────────────────────────────────────────────

## Вызывается из PlayerHitBox.apply_damage когда оружие попадает по CurseObject.
## weapon_damage — урон оружия, hit_direction — направление от игрока к курсору.
func on_weapon_hit(weapon_damage: int, hit_direction: Vector2) -> void:
	if not _is_active:
		return

	if weapon_damage >= DESTROY_THRESHOLD:
		# Сильное оружие → мгновенное уничтожение
		_destroy_clean()
		return

	# Слабое оружие → отбиваем в направлении удара
	hits_remaining -= 1
	var new_speed := weapon_damage * 80.0
	_velocity = hit_direction * new_speed

	# ── Заражение игрока при каждом ударе по corrupted объекту ────────────────
	if _player and _player.has_method("curse"):
		var mult: float = _get_armor_curse_multiplier()
		_player.curse(infection_per_hit * mult)

	# Короткая вспышка при отбитии
	_flash(Color(0.6, 0.6, 1.0))


# ─── Детекция попаданий ───────────────────────────────────────────────────────

func _on_area_entered(area: Area2D) -> void:
	if not _is_active:
		return

	# Попали в игрока (PlayerHurtBox)
	if area.is_in_group("PlayerHurtBox") or area.get_parent().is_in_group("Player"):
		_hit_player()
		return

	# Попали во врага (Enemy HurtBox)
	if area.is_in_group("Ennemy"):
		_hit_enemy(area)
		return

	# Попали в ресурс (Harvestable)
	if area.is_in_group("Harvestable"):
		_hit_harvestable(area)
		return


func _hit_player() -> void:
	if _player and _player.has_method("curse"):
		_player.curse(infection_damage)
	_explode_dark()


func _hit_enemy(area: Area2D) -> void:
	# Наносим урон заражением
	var enemy = area.get_parent()
	if enemy and enemy.has_method("take_damage"):
		enemy.take_damage(infection_damage, self)

	# Накладываем CORRUPTED дебафф если у врага есть apply_effect
	if enemy and enemy.has_method("apply_effect_instance"):
		# TODO: создать EffectResource с типом CORRUPTION для врага
		pass

	_explode_dark()


func _hit_harvestable(area: Area2D) -> void:
	## Ресурс ЗАРАЖАЕТСЯ — теперь даёт двойную выгоду при добыче
	var harvestable = area as Harvestable
	if harvestable == null:
		return

	if not harvestable.is_corrupted:
		harvestable.is_corrupted = true
		# Визуально заражаем
		if harvestable.corrupted_texture:
			harvestable.get_node("Sprite2D").texture = harvestable.corrupted_texture
		else:
			harvestable.modulate = Color(0.733, 0.325, 0.745, 1.0)
		# Запускаем эффекты заражения если они есть
		var point_light = harvestable.get_node_or_null("PointLight2D")
		var corr_effect = harvestable.get_node_or_null("Corruption Effect")
		if point_light:
			point_light.visible = true
		if corr_effect:
			corr_effect.emitting = true
		# Увеличиваем прочность (заражённый объект тяжелее бить)
		harvestable.durability += 10.0

	_explode_dark()


# ─── Движение ─────────────────────────────────────────────────────────────────

func _home_toward_player(delta: float) -> void:
	if not _player:
		return
	var dir := (global_position.direction_to(_player.global_position))
	_velocity = _velocity.lerp(dir * base_speed, delta * 2.0)


func _explode_on_nearest() -> void:
	## Когда время вышло — летим к ближайшей цели
	if _player:
		var dir := global_position.direction_to(_player.global_position)
		_velocity = dir * 300.0
		# Один кадр даём долететь
		await get_tree().process_frame
	_hit_player()


# ─── Визуальные эффекты ───────────────────────────────────────────────────────

func _pulse_spawn_animation() -> void:
	## Пульсация при появлении
	scale = Vector2(0.3, 0.3)
	var tw = create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.25)


func _flash(color: Color) -> void:
	## Краткая вспышка цветом при отбитии
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate", color, 0.05)
	_tween.tween_property(self, "modulate", Color(0.5, 0.0, 0.5, 1.0), 0.1)


func _destroy_clean() -> void:
	## Уничтожение сильным оружием — вспышка чистого света
	_is_active = false
	var tw = create_tween()
	tw.tween_property(self, "modulate", Color(1.5, 1.5, 1.5, 0.0), 0.2)
	tw.tween_callback(queue_free)
	# TODO: заспавнить VFX вспышки чистого света в global_position


func _explode_dark() -> void:
	## Взрыв тёмными частицами при попадании в цель
	_is_active = false
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2(2.0, 2.0), 0.1)
	tw.tween_property(self, "modulate", Color(0.2, 0.0, 0.2, 0.0), 0.15)
	tw.tween_callback(queue_free)
	# TODO: заспавнить VFX тёмного взрыва в global_position


func _get_armor_curse_multiplier() -> float:
	# Пример: если у игрока есть метод get_curse_resistance — используем его
	if _player.has_method("get_curse_resistance"):
		return 1.0 - clamp(_player.get_curse_resistance(), 0.0, 1.0)
	return 1.0
