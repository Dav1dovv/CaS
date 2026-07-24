# GenerationZone.gd
extends Resource
class_name GenerationZone

@export var zone_name: String = "Zone"
@export var dominant_items: Array[Generation]
@export_range(0.001,1) var noise_threshold: float = 0.5
@export var spawn_weight_multiplier: float = 2.0

## Уровень заражения (0..3), который получают чанки, попавшие в эту зону.
## 0 = зона сама заражение не задаёт — WorldMapGenerator посчитает его по
## отдельному шуму заражения вместо привязки к зоне.
@export_range(0, 3) var corruption_level: int = 0
