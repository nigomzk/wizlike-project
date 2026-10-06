class_name SkillDef
extends Resource
## DAT-201: 味方のスキル。

## DAT-116
const TARGETS: Array[StringName] = [
	&"SELF", &"LIVING_ALLY", &"DEAD_ALLY", &"OTHER_LIVING_ALLY", &"ALL_LIVING_ALLIES",
	&"LIVING_ENEMY", &"ALL_LIVING_ENEMIES", &"PARTY",
]
## DAT-117
const CONTEXTS: Array[StringName] = [&"town", &"exploration", &"battle"]

@export var id: StringName = &""
@export var name := ""
@export var job_id: StringName = &""
@export var required_level := 1
## DAT-223: 初期スキルは 0
@export var learn_cost := 0
@export var sp_cost := 0
@export var target: StringName = &""
@export var contexts: Array[StringName] = []
## DAT-222: 防御とかばうを 100、その他を 0 とする
@export var priority := 0
@export var always_hit := false
@export var effects: Array[ActionEffect] = []
