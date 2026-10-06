class_name RewardDef
extends Resource
## DAT-103: 経験値・お金・アイテムの報酬。

@warning_ignore("shadowed_global_identifier")
@export var exp := 0
@export var gold := 0
@export var items: Array[ItemStackDef] = []
