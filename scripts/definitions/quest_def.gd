class_name QuestDef
extends Resource
## DAT-207: クエスト。`description` は `data/texts.csv` の `quest_{id}` から解決する（DAT-230）。
## 依頼文の本文は段階Gで作成するため、文章がなければ空文字になる。

const KINDS: Array[StringName] = [&"kill", &"deliver"]

@export var id: StringName = &""
@export var title := ""
@export var description := ""
@export var unlock: ConditionDef
@export var kind: StringName = &""
@export var target_id: StringName = &""
@export var target_count := 0
@export var reward: RewardDef
