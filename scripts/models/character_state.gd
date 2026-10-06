class_name CharacterState
extends RefCounted
## DAT-510: 冒険者の可変状態。`base_stats` には装備補正を含めない（PTY-211, DAT-221）。
## 装備補正込みの値は `InventoryRules` が算出する（BTL-002, ARC-303）。

## 装備枠（INV-300）。`equipment` のキー
const EQUIPMENT_SLOTS: Array[StringName] = [&"weapon", &"armor", &"accessory"]

## 登録時に割り当てる単調増加の整数（GLS-403, PTY-006）。削除しても再利用しない
var id := 0
var name := ""
var job_id: StringName = &""
var portrait_id := ""
var level := 1
var total_exp := 0
## 基礎能力。レベルアップの成長だけが変える（PTY-309, PTY-311）
var base_stats: StatBlock
var current_hp := 0
var current_sp := 0
var poison := false
## 枠 -> 装備ID。空欄は空の `StringName`
var equipment: Dictionary = {&"weapon": &"", &"armor": &"", &"accessory": &""}
var learned_skill_ids: Array[StringName] = []
## 冒険者ごとの成長乱数（GLS-201）
var growth_rng: RandomNumberGenerator
