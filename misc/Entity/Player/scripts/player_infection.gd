extends Node
class_name PlayerInfection
## Шкала заражения игрока — GDD 3.3 "Заражение".
##
## Отдельная шкала ПОВЕРХ жизни (не путать с player.corruption — это шкала
## проклятия/долга, другая система). Источник заражения — заражённые
## Harvestable-ресурсы: при ударе по ним осколки заражают игрока
## (см. Harvestable._infect_player()).
##
## Пороги (см. таблицу в GDD):
##   0–9%    без эффекта, без винетки
##   10–49%  без эффекта, слабая фиолетовая винетка
##   50–79%  −50% урона от атак игрока, средняя винетка
##   80–100% −80% скорости передвижения, сильная винетка
##   100%    смерть
##
## Лечение:
##   - еда со свойством "очищение"  → cure_infection()  (FoodData.cure_infection)
##   - Дух (за золото, мгновенно)   → full_cure()        (см. Spirit.gd)

signal infection_changed(new_value: float)
## tier: 0 = нет эффекта, 1 = слабая (10–49%), 2 = средняя (50–79%), 3 = сильная (80–100%)
signal tier_changed(new_tier: int)

const TIER_WEAK   := 10.0
const TIER_MEDIUM := 50.0
const TIER_STRONG := 80.0

## −50% урона от атак игрока (применяется через EffectManager.damage_modifier)
const MEDIUM_DAMAGE_PENALTY := -0.5
## −80% скорости передвижения (применяется через EffectManager.speed_modifier)
const STRONG_SPEED_PENALTY  := -0.8

@onready var player: Player = get_parent()

## Текущий уровень заражения, 0.0 … 100.0
var infection: float = 0.0 :
	set(v):
		var prev := infection
		infection = clampf(v, 0.0, 100.0)
		if not is_equal_approx(prev, infection):
			emit_signal("infection_changed", infection)
			_update_tier()

var _tier: int = 0
var _damage_penalty_active: bool = false
var _speed_penalty_active:  bool = false


func _ready() -> void:
	# force=true — на случай, если SaveSystem уже выставил infection
	# напрямую (через сеттер) ДО того, как этот _ready() успел отработать.
	_update_tier(true)


# ─────────────────────────────────────────────────────────────────────────────
#  Публичное API
# ─────────────────────────────────────────────────────────────────────────────

## Заразить игрока. Учитывает INFECTION_RESIST из EffectManager (зелья/еда/аксессуары).
func add_infection(amount: float) -> void:
	if amount <= 0.0:
		return
	var resist := 1.0
	if player and player.effect_manager:
		resist = player.effect_manager.infection_resist_mult
	infection += amount * resist

## Снять часть заражения (еда со свойством "очищение").
func cure_infection(amount: float) -> void:
	if amount <= 0.0:
		return
	infection -= amount

## Мгновенное полное очищение (услуга "Дух" за золото).
func full_cure() -> void:
	infection = 0.0

func get_tier() -> int:
	return _tier

func get_ratio() -> float:
	return infection / 100.0


# ─────────────────────────────────────────────────────────────────────────────
#  Пороги эффектов
# ─────────────────────────────────────────────────────────────────────────────

func _update_tier(force: bool = false) -> void:
	var new_tier := 0
	if infection >= TIER_STRONG:
		new_tier = 3
	elif infection >= TIER_MEDIUM:
		new_tier = 2
	elif infection >= TIER_WEAK:
		new_tier = 1

	if new_tier != _tier or force:
		_tier = new_tier
		emit_signal("tier_changed", _tier)
		_apply_tier_modifiers()

	if infection >= 100.0 and player and player.is_alive:
		player.die()


func _apply_tier_modifiers() -> void:
	if not player or not player.effect_manager:
		return
	var em := player.effect_manager

	var wants_damage_penalty := _tier >= 2
	var wants_speed_penalty  := _tier >= 3

	if wants_damage_penalty and not _damage_penalty_active:
		em.add_damage_modifier(MEDIUM_DAMAGE_PENALTY)
		_damage_penalty_active = true
	elif not wants_damage_penalty and _damage_penalty_active:
		em.remove_damage_modifier(MEDIUM_DAMAGE_PENALTY)
		_damage_penalty_active = false

	if wants_speed_penalty and not _speed_penalty_active:
		em.add_speed_modifier(STRONG_SPEED_PENALTY)
		_speed_penalty_active = true
	elif not wants_speed_penalty and _speed_penalty_active:
		em.remove_speed_modifier(STRONG_SPEED_PENALTY)
		_speed_penalty_active = false
