extends HitBox
class_name BossAttackHitbox

# ═══════════════════════════════════════════════════════════════
#  BossAttackHitbox — универсальная разовая зона урона босса.
#  Не привязана к конкретному боссу/паттерну — переиспользуется
#  для смэша, свипа, приземления рывка и т.д.
#
#  Использование:
#    var hb: BossAttackHitbox = attack_hitbox_scene.instantiate()
#    get_parent().add_child(hb)
#    hb.global_position = point
#    hb.setup(damage, poise_damage, radius)
#
#  Если attack_hitbox_scene не назначена — ForestGuardian создаст
#  BossAttackHitbox.new() в коде (без спрайта, только урон).
#  Для полноценного VFX сделай свою .tscn: корень BossAttackHitbox
#  + CollisionShape2D (CircleShape2D) + свои частицы/спрайт.
# ═══════════════════════════════════════════════════════════════

## Урон за попадание
@export var damage: float = 15.0
## Poise-урон (стаггер) — см. Creature.add_poise_damage
@export var poise_damage: float = 30.0
## Сколько секунд хитбокс активен, прежде чем сам себя удалит
@export var active_time: float = 0.15

## Каждая цель получает урон только один раз за активацию —
## иначе стоя в зоне игрок получал бы урон каждый физ-кадр
var _already_hit: Dictionary = {}


func _ready() -> void:
	area_entered.connect(_on_area_entered)

	# Если сцена уже содержит свой CollisionShape2D (авторская .tscn) — не трогаем.
	# Если нет (fallback-создание через .new()) — строим круглый шейп сами.
	if get_child_count() == 0 or not (get_child(0) is CollisionShape2D):
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 20.0
		col.shape = shape
		add_child(col)

	get_tree().create_timer(active_time).timeout.connect(queue_free)


## Настройка после instantiate()/add_child(). radius затрагивает первый
## CollisionShape2D-ребёнок, если это CircleShape2D.
func setup(dmg: float, poise_dmg: float, radius: float = -1.0) -> void:
	damage = dmg
	poise_damage = poise_dmg
	if radius <= 0.0:
		return
	if get_child_count() > 0 and get_child(0) is CollisionShape2D:
		var shape: Shape2D = (get_child(0) as CollisionShape2D).shape
		if shape is CircleShape2D:
			(shape as CircleShape2D).radius = radius


func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("Player"):
		return

	var target_node := area.get_parent()
	if _already_hit.has(target_node):
		return
	_already_hit[target_node] = true

	if target_node.has_method("take_damage"):
		target_node.take_damage(damage, self, false, poise_damage)
