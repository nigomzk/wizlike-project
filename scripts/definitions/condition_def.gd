class_name ConditionDef
extends Resource
## DAT-208: 解禁条件。

const KINDS: Array[StringName] = [&"always", &"floor_visited", &"boss_first_defeated", &"warp_unlocked"]

@export var kind: StringName = &"always"
@export var target_id: StringName = &""
