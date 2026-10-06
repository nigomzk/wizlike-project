class_name CellEventDef
extends Resource
## DAT-211: セルイベント。`kind` ごとの必須欄は DAT-225 に従い、表にない欄は空とする。
## 空の欄は、`StringName` が空、`link_facing` が `UNSET_FACING`、セルが `UNSET_CELL`、`reward` が null で表す。

## DAT-123
const KINDS: Array[StringName] = [
	&"town_exit", &"stairs", &"link", &"door", &"shortcut", &"chest", &"inscription", &"boss", &"warp",
]
## 0 以上の座標と区別するため、空のセルは負の値で表す
const UNSET_CELL := Vector2i(-1, -1)
const UNSET_FACING := -1

@export var id: StringName = &""
@export var cell := Vector2i.ZERO
@export var kind: StringName = &""
@export var link_floor_id: StringName = &""
@export var link_cell := UNSET_CELL
@export var link_facing := UNSET_FACING
## chest のみ（`chest_rewards.csv`）
@export var reward: RewardDef
@export var enemy_id: StringName = &""
@export var unlock_from := UNSET_CELL
@export var warp_id: StringName = &""
@export var text_id: StringName = &""
