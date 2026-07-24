extends Creature
class_name ForestGuardian

# ═══════════════════════════════════════════════════════════════════════════
#  СТРАЖ ЛЕСА — обучающий кристалльный босс (Западный Лес / Кристалл Земли)
# ───────────────────────────────────────────────────────────────────────────
#  Design-цель (GDD 9.2): обучающий бой — читать замах, не паниковать,
#  отступать в окно телеграфа. Никаких AoE-спамов, никакой нечестности.
#
#  Архитектура: ничего нового в FSM не добавляется — Creature уже даёт
#  IDLE/CHASE/ATTACK/STUNNED и т.д. Вся уникальность босса — переопределение
#  _do_attack(): вместо одиночного удара выбирается ОДИН паттерн из пула
#  по таймерам-кулдаунам (без вложенной FSM, как договорились).
#
#  Фазы: Фаза 1 (100%→50% HP) — Смэш + Корневой свип.
#        Фаза 2 (<50% HP)     — те же + Рывок-прыжок.
#
# ───────────────────────────────────────────────────────────────────────────
#  ЧЕКЛИСТ СЦЕНЫ (ForestGuardian.tscn) — что нужно руками в редакторе:
#    ForestGuardian (RapierCharacterBody2D, этот скрипт)
#      ├─ Skin (Sprite2D/AnimatedSprite2D)          — как у обычных Creature
#      ├─ HitBox (entity_HitBox)                    — обычный контактный урон
#      ├─ HealthBar (ProgressBar)                   — Creature ждёт этот путь
#      ├─ Drop (Dropper)                             — дроп Кристалла Земли
#      ├─ AnimationPlayer  → назначить в body_anim / hand_anim в инспекторе
#      ├─ optimizer (VisibleOnScreenEnabler2D)        — опционально, для throttle
#      └─ CollisionShape2D (тело)
#    Exports которые стоит проверить в инспекторе:
#      Entity_stats  → Resource stats с max_health (рекомендую 180–220 — обучающий)
#      attack_hitbox_scene → назначь свою BossAttackHitbox.tscn с VFX,
#                            либо оставь пустым — сработает code-fallback.
#    Анимации (все вызовы безопасны, если анимации нет — Creature._play_anim
#    просто промолчит): Awaken, Windup, Attack, JumpUp, Landing.
#    Можно временно повесить все пять на существующий клип "Attack" —
#    ничего не сломается, просто не будет разных телеграфов визуально.
# ═══════════════════════════════════════════════════════════════════════════


@export_category("Boss — Фазы")
## Порог HP (0..1), после которого начинается Фаза 2
@export_range(0.0, 1.0) var phase2_threshold: float = 0.5
var _phase: int = 1

@export_category("Boss — Паттерн: Смэш")
@export var smash_telegraph_time: float = 0.9
@export var smash_damage: float = 18.0
@export var smash_radius: float = 46.0
@export var smash_cooldown: float = 4.0

@export_category("Boss — Паттерн: Корневой свип")
@export var sweep_telegraph_time: float = 0.7
@export var sweep_damage: float = 12.0
@export var sweep_segment_count: int = 5
@export var sweep_segment_radius: float = 26.0
@export var sweep_arc_length: float = 160.0
@export var sweep_poise_damage: float = 25.0

@export var sweep_cooldown: float = 5.0

@export_category("Boss — Паттерн: Рывок-прыжок (Фаза 2)")
@export var dash_telegraph_time: float = 0.6
@export var dash_damage: float = 22.0
@export var dash_land_radius: float = 60.0
@export var dash_cooldown: float = 6.0

@export_category("Boss — Хитбоксы")
## Своя сцена BossAttackHitbox с VFX. Пусто = code-fallback без визуала.
@export var attack_hitbox_scene: PackedScene

# ── Внутреннее состояние ────────────────────────────────────────────────────
var _is_attacking: bool = false
var _last_pattern: String = ""
var _cooldowns: Dictionary = {
	"smash": 0.0,
	"sweep": 0.0,
	"dash": 0.0,
}


# ═══════════════════════════════════════════════════════════════════════════
#  INIT
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Боевые параметры босса — задаём ДО super._ready(), чтобы Creature
	# прочитала уже правильные значения (_resolve_behavior_type и т.д.)
	behavior = 1.0          # всегда агрессивен, детект стандартный из Creature
	can_flee = false
	use_fear = false
	max_poise = 300.0        # почти не стаггерится обычным оружием
	attack_radius = 90.0     # дотягивается паттернами дальше рядового врага
	attack_cooldown = 0.4    # реальный ритм задаёт _do_attack сам, это только гейт вызова

	super._ready()

	# «Пробуждение» — пауза перед тем как босс начнёт действовать.
	# Останавливаем весь _physics_process (детект/движение/атаки) на время анимации.
	set_physics_process(false)
	_play_anim("Awaken")
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(self):
		set_physics_process(true)


func _default_start_state() -> State:
	# Босс не бродит и не патрулирует — стоит и ждёт, пока Creature сама
	# не найдёт игрока (see _check_for_target, вызывается уже из Creature).
	return State.IDLE


func _process(delta: float) -> void:
	for key in _cooldowns.keys():
		_cooldowns[key] = maxf(0.0, _cooldowns[key] - delta)

	if _phase == 1 and Entity_stats.max_health > 0.0:
		var hp_ratio := Entity_stats.current_health / Entity_stats.max_health
		if hp_ratio <= phase2_threshold:
			_enter_phase_2()


func _enter_phase_2() -> void:
	_phase = 2
	DebugLog.log("Страж леса: Фаза 2 — рывок-прыжок разблокирован")
	var sprite := _get_sprite()
	if sprite:
		var flash := create_tween()
		flash.tween_property(sprite, "modulate", Color(1.3, 0.6, 0.6), 0.15)
		flash.tween_property(sprite, "modulate", Color.WHITE, 0.25)


func _get_sprite() -> CanvasItem:
	var s := get_node_or_null("Skin")
	if s is CanvasItem:
		return s
	return null


# ═══════════════════════════════════════════════════════════════════════════
#  ВЫБОР И ЗАПУСК ПАТТЕРНА (переопределяет Creature._do_attack)
# ═══════════════════════════════════════════════════════════════════════════

func _do_attack() -> void:
	if _is_attacking or not is_instance_valid(target):
		return

	var pattern := _pick_pattern()
	if pattern.is_empty():
		return  # все паттерны на кулдауне — Creature попробует снова через attack_cooldown

	_is_attacking = true
	_last_pattern = pattern

	match pattern:
		"smash":
			await _pattern_smash()
		"sweep":
			await _pattern_root_sweep()
		"dash":
			await _pattern_dash_jump()

	_is_attacking = false


func _pick_pattern() -> String:
	var pool: Array = []
	if _cooldowns["smash"] <= 0.0:
		pool.append("smash")
	if _cooldowns["sweep"] <= 0.0:
		pool.append("sweep")
	if _phase == 2 and _cooldowns["dash"] <= 0.0:
		pool.append("dash")

	# Не повторяем последний паттерн подряд, если есть из чего выбрать —
	# иначе игрок может словить два Смэша подряд, что не читается как честно.
	if pool.size() > 1 and _last_pattern in pool:
		pool.erase(_last_pattern)

	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


# ═══════════════════════════════════════════════════════════════════════════
#  ПАТТЕРН 1 — Тяжёлый оверхед-смэш
#  Одна точка удара под игроком в момент начала телеграфа (не следит дальше —
#  награда за то, что игрок ОТОЙДЁТ, увидев круг).
# ═══════════════════════════════════════════════════════════════════════════

func _pattern_smash() -> void:
	var strike_pos := target.global_position
	var telegraph := _spawn_telegraph(strike_pos, smash_radius, Color(1, 0.2, 0.2, 0.35))

	_play_anim("Windup")
	await get_tree().create_timer(smash_telegraph_time).timeout
	if is_instance_valid(telegraph):
		telegraph.queue_free()

	_play_anim("Attack")
	_spawn_hit_circle(strike_pos, smash_radius, smash_damage, 40.0)
	_cooldowns["smash"] = smash_cooldown

	await get_tree().create_timer(0.5).timeout  # recovery — окно для контратаки


# ═══════════════════════════════════════════════════════════════════════════
#  ПАТТЕРН 2 — Корневой свип по дуге
#  Несколько точек по дуге в сторону игрока, "срабатывают" одна за другой —
#  учит читать НАПРАВЛЕНИЕ дуги, а не просто убегать в случайную сторону.
# ═══════════════════════════════════════════════════════════════════════════

func _pattern_root_sweep() -> void:
	var base_dir := (target.global_position - global_position).normalized()
	var telegraphs: Array = []

	for i in sweep_segment_count:
		var t := float(i) / float(maxi(sweep_segment_count - 1, 1))
		var angle_offset = lerp(-40.0, 40.0, t)
		var offset := base_dir.rotated(deg_to_rad(angle_offset)) * sweep_arc_length * (0.4 + 0.6 * t)
		var pos := global_position + offset
		telegraphs.append(_spawn_telegraph(pos, sweep_segment_radius, Color(0.6, 0.9, 0.2, 0.35)))

	_play_anim("Windup")
	await get_tree().create_timer(sweep_telegraph_time).timeout

	# Сегменты бьют по очереди вдоль дуги, не одновременно — это и есть "свип"
	for tg in telegraphs:
		if not is_instance_valid(tg):
			continue
		var pos: Vector2 = tg.global_position
		tg.queue_free()
		_spawn_hit_circle(pos, sweep_segment_radius, sweep_damage, sweep_poise_damage)
		await get_tree().create_timer(0.06).timeout

	_play_anim("Attack")
	_cooldowns["sweep"] = sweep_cooldown

	await get_tree().create_timer(0.4).timeout


# ═══════════════════════════════════════════════════════════════════════════
#  ПАТТЕРН 3 — Рывок-прыжок (только Фаза 2)
#  Точка приземления фиксируется В МОМЕНТ начала прыжка — предсказуемо
#  честно, но требует реально уйти с места, а не просто отойти на полшага.
# ═══════════════════════════════════════════════════════════════════════════

func _pattern_dash_jump() -> void:
	var land_pos := target.global_position
	var telegraph := _spawn_telegraph(land_pos, dash_land_radius, Color(1, 0.5, 0.0, 0.4))

	_play_anim("JumpUp")
	await get_tree().create_timer(dash_telegraph_time).timeout

	global_position = land_pos + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	if is_instance_valid(telegraph):
		telegraph.queue_free()

	_play_anim("Landing")
	_spawn_hit_circle(land_pos, dash_land_radius, dash_damage, 55.0)
	_trigger_screen_shake(true)
	_cooldowns["dash"] = dash_cooldown

	await get_tree().create_timer(0.6).timeout


# ═══════════════════════════════════════════════════════════════════════════
#  ВСПОМОГАТЕЛЬНОЕ: ТЕЛЕГРАФ (чистый код, без арта) И ХИТБОКС
# ═══════════════════════════════════════════════════════════════════════════

## Процедурный круг-предупреждение — не требует новых спрайтов/арта.
## Пульсирует прозрачностью, пока не будет вручную удалён вызывающим кодом.
func _spawn_telegraph(pos: Vector2, radius: float, color: Color) -> Node2D:
	var indicator := Node2D.new()
	get_parent().add_child(indicator)
	indicator.global_position = pos

	var circle := Polygon2D.new()
	circle.polygon = _make_circle_points(radius)
	circle.color = color
	indicator.add_child(circle)

	var tween := indicator.create_tween()
	tween.set_loops()
	tween.tween_property(circle, "modulate:a", 0.15, 0.25)
	tween.tween_property(circle, "modulate:a", 0.55, 0.25)

	return indicator


func _make_circle_points(radius: float, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts


## Спавнит разовую зону урона (BossAttackHitbox) в точке на короткое время.
func _spawn_hit_circle(pos: Vector2, radius: float, damage: float, poise_damage: float) -> void:
	var hitbox: BossAttackHitbox
	if attack_hitbox_scene:
		hitbox = attack_hitbox_scene.instantiate()
	else:
		hitbox = BossAttackHitbox.new()

	get_parent().add_child(hitbox)
	hitbox.global_position = pos
	hitbox.setup(damage, poise_damage, radius)
