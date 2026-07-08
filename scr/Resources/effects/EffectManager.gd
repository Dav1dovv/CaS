extends Node
class_name EffectManager

# ─────────────────────────────────────────────────────────────────────────────
# EffectManager.gd  |  Caves & Swords  |  Content v1.3
#
# Изменения относительно предыдущей версии:
#   + BLEED       — DOT по % от max HP за тик
#   + CORRUPTION  — DOT + временный damage_bonus врагу
#   + FREEZE      — реальная логика: замедление + слабый DOT 1/сек
#   + PANIC       — потеря управления движением (от BURN), через таймер
#   + INVINCIBILITY — неуязвимость через Entity.is_invincible
#   + COLD_IMMUNITY — блокирует FREEZE пока активен
#   + INFECTION_RESIST — множитель на накопление заражения (используется
#                        снаружи, в Harvestable.gd или Player.gd)
#   + MINING_SPEED_BOOST — отдельный модификатор, не связанный с move_speed
#   + DOUBLE_LOOT — пассивный флаг, читается снаружи (Harvestable/DropTable)
#   POISON теперь проверяет иммунитет группы (golem/skeleton)
# ─────────────────────────────────────────────────────────────────────────────

class ActiveEffect:
	var effect: Effect
	var time_remaining: float
	var tick_timer: float
	var stacks: int = 1

	func _init(eff: Effect) -> void:
		effect         = eff
		time_remaining = eff.duration
		tick_timer     = 0.0


# ── Хранилище ────────────────────────────────────────────────────────────────
var active_effects: Dictionary = {}   # { EffectType: ActiveEffect }
var owner_entity: Entity

# ── Модификаторы ─────────────────────────────────────────────────────────────
var speed_modifier        : float = 0.0
var damage_modifier       : float = 0.0
var defense_modifier      : float = 0.0
var mining_speed_modifier : float = 0.0   # читает Harvestable.gd
var infection_resist_mult : float = 1.0   # читает Player.gd при накоплении
var double_loot_chance    : float = 0.0   # читает DropTable / Harvestable.gd
var is_invisible          : bool  = false

# ── Сигналы ──────────────────────────────────────────────────────────────────
signal effect_added(effect: Effect)
signal effect_removed(effect: Effect)
signal effect_tick(effect: Effect)


func _init(entity: Entity) -> void:
	owner_entity = entity

func _ready() -> void:
	set_process(true)


# ─── Главный цикл ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var to_remove: Array = []

	for effect_type in active_effects.keys():
		var ae: ActiveEffect = active_effects[effect_type]

		# Обратный отсчёт времени (duration -1 = бесконечный, снимается вручную)
		if ae.effect.duration > 0:
			ae.time_remaining -= delta
			if ae.time_remaining <= 0.0:
				to_remove.append(effect_type)
				continue

		# Тиковые эффекты
		if ae.effect.tick_interval > 0:
			ae.tick_timer += delta
			if ae.tick_timer >= ae.effect.tick_interval:
				ae.tick_timer = 0.0
				_process_tick(ae.effect)

	for et in to_remove:
		remove_effect_by_type(et)


# ─── Применить эффект ─────────────────────────────────────────────────────────

func apply_effect_instance(effect: Effect) -> void:
	if effect == null:
		return

	# COLD_IMMUNITY блокирует FREEZE
	if effect.effect_type == Effect.EffectType.FREEZE:
		if has_effect(Effect.EffectType.COLD_IMMUNITY):
			return

	var et = effect.effect_type

	if active_effects.has(et):
		var ae: ActiveEffect = active_effects[et]
		if ae.stacks < effect.max_stacks:
			ae.stacks += 1
			ae.time_remaining = effect.duration
			_apply_logic(effect, ae.stacks)
		else:
			ae.time_remaining = effect.duration   # просто обновляем время
		return

	var ae := ActiveEffect.new(effect)
	active_effects[et] = ae
	_apply_logic(effect, 1)
	_spawn_particles(effect)
	_play_sound(effect)
	emit_signal("effect_added", effect)


func _apply_logic(effect: Effect, stacks: int) -> void:
	match effect.effect_type:

		# ── На себя ──────────────────────────────────────────────
		Effect.EffectType.HEALTH_RESTORE:
			owner_entity.heal(effect.value * stacks)

		Effect.EffectType.SPEED_BOOST:
			add_speed_modifier(effect.value * stacks)

		Effect.EffectType.DAMAGE_BOOST:
			add_damage_modifier(effect.value * stacks)

		Effect.EffectType.DEFENSE_BOOST:
			add_defense_modifier(effect.value * stacks)

		Effect.EffectType.MINING_SPEED_BOOST:
			mining_speed_modifier += effect.value * stacks

		Effect.EffectType.INFECTION_RESIST:
			# Перемножаем (если стакается — каждый стак ещё раз снижает)
			infection_resist_mult *= effect.value

		Effect.EffectType.DOUBLE_LOOT:
			double_loot_chance += effect.value * stacks

		Effect.EffectType.INVISIBILITY:
			set_invisibility(true)

		Effect.EffectType.INVINCIBILITY:
			_start_invincibility(effect.duration)

		# ── На врага ─────────────────────────────────────────────
		Effect.EffectType.SLOW:
			add_speed_modifier(-effect.value * stacks)

		Effect.EffectType.FREEZE:
			# Замедление применяется сразу, DOT — в тике
			add_speed_modifier(-effect.value * stacks)

		Effect.EffectType.CORRUPTION:
			# Баф урона врага пока эффект активен
			if owner_entity.Entity_stats:
				owner_entity.Entity_stats.damage_modifier += effect.corruption_damage_bonus * stacks
				owner_entity.Entity_stats.damage_modifier = minf(
					owner_entity.Entity_stats.damage_modifier, 2.0   # кап x2
				)

		Effect.EffectType.BURN:
			# DOT в тике; PANIC запускаем отдельно
			_start_panic(1.5)   # 1.5 сек паники при применении

		# POISON, BLEED, REGENERATION — только тики, логика в _process_tick
		Effect.EffectType.POISON, Effect.EffectType.BLEED, Effect.EffectType.REGENERATION:
			pass


# ─── Тиковая логика ───────────────────────────────────────────────────────────

func _process_tick(effect: Effect) -> void:
	match effect.effect_type:

		Effect.EffectType.REGENERATION:
			owner_entity.heal(effect.value)

		Effect.EffectType.POISON:
			# Проверка иммунитета группы
			for grp in Effect.POISON_IMMUNE_GROUPS:
				if owner_entity.is_in_group(grp):
					return
			owner_entity.take_damage(effect.value)

		Effect.EffectType.BURN:
			owner_entity.take_damage(effect.value)

		Effect.EffectType.FREEZE:
			# Слабый DOT заморозки (~1 ед/сек)
			var freeze_dot := maxf(effect.value * 2.0, 1.0)
			# Если COLD_IMMUNITY активен — урон не наносится
			if not has_effect(Effect.EffectType.COLD_IMMUNITY):
				owner_entity.take_damage(freeze_dot)

		Effect.EffectType.BLEED:
			# Урон = bleed_percent от max HP цели
			var bleed_dmg := owner_entity.Entity_stats.max_health * effect.bleed_percent
			owner_entity.take_damage(bleed_dmg)

		Effect.EffectType.CORRUPTION:
			owner_entity.take_damage(effect.value)

	emit_signal("effect_tick", effect)


# ─── Снять эффект ─────────────────────────────────────────────────────────────

func remove_effect_instance(effect: Effect) -> void:
	remove_effect_by_type(effect.effect_type)

func remove_effect_by_type(et: Effect.EffectType) -> void:
	if not active_effects.has(et):
		return
	var ae: ActiveEffect = active_effects[et]
	_remove_logic(ae.effect, ae.stacks)
	active_effects.erase(et)
	emit_signal("effect_removed", ae.effect)

func _remove_logic(effect: Effect, stacks: int) -> void:
	match effect.effect_type:
		Effect.EffectType.SPEED_BOOST:
			remove_speed_modifier(effect.value * stacks)

		Effect.EffectType.DAMAGE_BOOST:
			remove_damage_modifier(effect.value * stacks)

		Effect.EffectType.DEFENSE_BOOST:
			remove_defense_modifier(effect.value * stacks)

		Effect.EffectType.MINING_SPEED_BOOST:
			mining_speed_modifier -= effect.value * stacks
			mining_speed_modifier  = maxf(mining_speed_modifier, 0.0)

		Effect.EffectType.INFECTION_RESIST:
			# Отменяем деление — возвращаем к 1.0 если нет других стаков
			if effect.value != 0.0:
				infection_resist_mult /= effect.value
			infection_resist_mult = clampf(infection_resist_mult, 0.1, 1.0)

		Effect.EffectType.DOUBLE_LOOT:
			double_loot_chance -= effect.value * stacks
			double_loot_chance  = maxf(double_loot_chance, 0.0)

		Effect.EffectType.INVISIBILITY:
			set_invisibility(false)

		Effect.EffectType.SLOW:
			remove_speed_modifier(-effect.value * stacks)

		Effect.EffectType.FREEZE:
			# Снимаем замедление от заморозки
			remove_speed_modifier(-effect.value * stacks)

		Effect.EffectType.CORRUPTION:
			# Снимаем баф урона
			if owner_entity.Entity_stats:
				owner_entity.Entity_stats.damage_modifier -= effect.corruption_damage_bonus * stacks
				owner_entity.Entity_stats.damage_modifier  = maxf(
					owner_entity.Entity_stats.damage_modifier,
					owner_entity.Entity_stats.base_damage_modifier
				)


# ─── Модификаторы ─────────────────────────────────────────────────────────────

func add_speed_modifier(value: float) -> void:
	speed_modifier += value
	_update_speed()

func remove_speed_modifier(value: float) -> void:
	speed_modifier -= value
	_update_speed()

func _update_speed() -> void:
	if owner_entity.Entity_stats:
		var base := owner_entity.Entity_stats.base_move_speed
		owner_entity.Entity_stats.move_speed = base * (1.0 + speed_modifier)

func add_damage_modifier(value: float) -> void:
	damage_modifier += value
	if owner_entity.Entity_stats:
		owner_entity.Entity_stats.damage_modifier = \
			owner_entity.Entity_stats.base_damage_modifier + damage_modifier

func remove_damage_modifier(value: float) -> void:
	damage_modifier -= value
	if owner_entity.Entity_stats:
		owner_entity.Entity_stats.damage_modifier = \
			owner_entity.Entity_stats.base_damage_modifier + damage_modifier

func add_defense_modifier(value: float) -> void:
	defense_modifier += value
	if owner_entity.Entity_stats:
		owner_entity.Entity_stats.defense_modifier = \
			owner_entity.Entity_stats.base_defense_modifier + defense_modifier

func remove_defense_modifier(value: float) -> void:
	defense_modifier -= value
	if owner_entity.Entity_stats:
		owner_entity.Entity_stats.defense_modifier = \
			owner_entity.Entity_stats.base_defense_modifier + defense_modifier

func set_invisibility(value: bool) -> void:
	is_invisible = value
	var sprite := owner_entity.get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate.a = 0.3 if value else 1.0


# ─── PANIC (потеря управления движением) ──────────────────────────────────────
# Вызывается при BURN. Если у игрока/существа есть метод set_panic — используем,
# иначе просто пропускаем (безопасный fallback).

func _start_panic(dur: float) -> void:
	if owner_entity.has_method("set_panic"):
		owner_entity.set_panic(true)
		await owner_entity.get_tree().create_timer(dur).timeout
		if is_instance_valid(owner_entity) and owner_entity.has_method("set_panic"):
			owner_entity.set_panic(false)


# ─── INVINCIBILITY ────────────────────────────────────────────────────────────

func _start_invincibility(dur: float) -> void:
	owner_entity.is_invincible = true
	await owner_entity.get_tree().create_timer(dur).timeout
	if is_instance_valid(owner_entity):
		owner_entity.is_invincible = false


# ─── Визуал / звук ────────────────────────────────────────────────────────────

func _spawn_particles(effect: Effect) -> void:
	if effect.particle == null:
		return
	var p = effect.particle.instantiate()
	owner_entity.add_child(p)
	if p is GPUParticles2D:
		p.emitting = true

func _play_sound(effect: Effect) -> void:
	if effect.sound_effect == null:
		return
	var ap := AudioStreamPlayer.new()
	owner_entity.add_child(ap)
	ap.stream = effect.sound_effect
	ap.play()
	ap.finished.connect(func(): ap.queue_free())


# ─── Вспомогательные методы ───────────────────────────────────────────────────

func get_active_effects() -> Array:
	return active_effects.values()

func has_effect(et: Effect.EffectType) -> bool:
	return active_effects.has(et)

func get_effect_time_remaining(et: Effect.EffectType) -> float:
	if not active_effects.has(et):
		return 0.0
	return active_effects[et].time_remaining

func clear_all_effects() -> void:
	for et in active_effects.keys().duplicate():
		remove_effect_by_type(et)
