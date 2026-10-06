class_name EnemyActionDef
extends Resource
## DAT-205: 敵の行動。SPを消費しない。

@export var id: StringName = &""
@export var name := ""
@export var target: StringName = &""
@export var priority := 0
@export var always_hit := false
@export var effects: Array[ActionEffect] = []
