class_name ActionEffect
extends Resource
## DAT-105: スキル・アイテム・敵行動の効果1件。配列順に適用する（DAT-114）。

## DAT-110
const KINDS: Array[StringName] = [
	&"DAMAGE", &"HEAL", &"RESTORE_SP", &"REVIVE", &"CURE_POISON",
	&"APPLY_STATUS", &"COVER", &"SUPPRESS_ENCOUNTERS", &"RETURN_TOWN", &"NO_OP",
]
## DAT-111
const DAMAGE_MODELS: Array[StringName] = [&"PHYSICAL", &"MAGICAL", &"NONE"]
## DAT-112
const ELEMENTS: Array[StringName] = [&"physical", &"fire", &"ice", &"lightning", &"none"]
## DAT-119
const STATUS_IDS: Array[StringName] = [&"poison", &"paralysis", &"sleep"]

@export var kind: StringName = &"NO_OP"
@export var damage_model: StringName = &"NONE"
@export var element: StringName = &"none"
@export var power := 0
## DAT-113: 倍率の既定値は1
@export var multiplier := 1.0
@export var defense_ratio := 1.0
@export var status_id: StringName = &""
@export var status_chance := 0.0
@export var restore_ratio := 0.0
@export var restore_flat := 0
## DAT-115: 探索効果にのみ用いる
@export var duration_steps := 0
## DAT-114: 既定値は false
@export var requires_previous_hit := false
