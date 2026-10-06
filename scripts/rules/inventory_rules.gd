class_name InventoryRules
extends RefCounted
## 所持品の容量判定、装備の着脱、装備補正込みの能力値・攻撃力・守備力の算出（ARC-303）。
##
## 画面を持たない。追加・削除・交換は、差分を先に試算し（`plan_*`）、成功した場合にだけ `apply` で適用する
## （INV-200）。試算は入力を変更しない（ARC-403）。結果は `{ok, error_code, changes}`（ARC-400）。
## 失敗は `NO_SPACE` と `INVALID_TARGET` に限る（ARC-401）。
##
## `db` は `GameDatabase`（`item_or_equipment(id)` を持つもの）。
## `inventory` は `Array[ItemStackState]`、冒険者は `CharacterState`。
## 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、`preload` で読む。

const StackState := preload("res://scripts/models/inventory_state.gd")
const Character := preload("res://scripts/models/character_state.gd")

## INV-100: 共有の所持品の枠数。パーティと待機者で共通
const CAPACITY := 30

const NO_SPACE := &"NO_SPACE"
const INVALID_TARGET := &"INVALID_TARGET"

const _STAT_FIELDS: Array[String] = ["hp", "sp", "str", "vit", "tec", "agi", "luc"]


## 所持品が占める枠数。武器・防具・装飾品は1個につき1枠（INV-102）、消耗品と素材は同一IDごとに
## `max_stack` 個で1枠（INV-103）。装備中の品と重要アイテムは、渡す配列に含めない（INV-101, INV-105）。
static func slot_count(db, inventory: Array) -> int:
	var totals := {}
	var order: Array[StringName] = []
	for stack in inventory:
		if not totals.has(stack.item_id):
			totals[stack.item_id] = 0
			order.append(stack.item_id)
		totals[stack.item_id] += stack.quantity
	var slots := 0
	for id in order:
		var size := _stack_size(db, id)
		slots += ceili(float(totals[id]) / size)
	return slots


## 追加と削除を1つの取引として試算する（INV-200）。削除を先に、追加をあとに反映した所持品で容量を判定する。
## 容量が不足する場合は全体を成立させない（INV-201）。
## 成功時の `changes` は `{inventory: Array[ItemStackState]}`（適用後の所持品。入力とは別の配列）。
## `adds` と `removes` は `ItemStackDef` の配列。
static func plan_transaction(db, inventory: Array, adds: Array, removes: Array) -> Dictionary:
	var next := _copy_stacks(inventory)
	for def in removes:
		if not _remove(db, next, def.item_id, def.quantity):
			return _failure(INVALID_TARGET)
	for def in adds:
		if not _add(db, next, def.item_id, def.quantity):
			return _failure(INVALID_TARGET)
	if slot_count(db, next) > CAPACITY:
		return _failure(NO_SPACE)
	return _success({"inventory": next})


## 装備の着脱を試算する（INV-303）。`item_id` が空なら、その枠の装備を外す。
## 外した品は所持品へ戻り、着ける品は所持品から減る。差分で容量を判定する。
## 職業の制限（INV-301）、枠の違い、所持していない品は `INVALID_TARGET`。死亡している冒険者も変更できる（INV-204）。
## 成功時の `changes` は `{inventory, equipment, current_hp, current_sp}`。最大HPが下がった場合、現在HPを
## 新しい最大HPへ丸める（INV-304）。上がった場合は増やさない（INV-305）。最大SPも同様。
static func plan_equip(db, inventory: Array, character, slot: StringName, item_id: StringName) -> Dictionary:
	if not character.equipment.has(slot):
		return _failure(INVALID_TARGET)
	var removes: Array = []
	var adds: Array = []
	var equipped: StringName = character.equipment[slot]
	if item_id != &"":
		var def = db.item_or_equipment(item_id)
		if not def is EquipmentDef or def.slot != slot or not def.allowed_jobs.has(character.job_id):
			return _failure(INVALID_TARGET)
		removes.append(_stack_def(item_id, 1))
	elif equipped == &"":
		return _failure(INVALID_TARGET)
	if equipped != &"":
		adds.append(_stack_def(equipped, 1))
	var plan := plan_transaction(db, inventory, adds, removes)
	if not plan.ok:
		return plan

	var equipment: Dictionary = character.equipment.duplicate()
	equipment[slot] = item_id
	var stats := _effective_stats(db, character.base_stats, equipment)
	return _success({
		"inventory": plan.changes.inventory,
		"equipment": equipment,
		"current_hp": mini(character.current_hp, stats.hp),
		"current_sp": mini(character.current_sp, stats.sp),
	})


## 装備補正込みの能力値（BTL-002）。装備の `stat_bonus` のHPとSPは最大値への加算（INV-309）。
## 返す `StatBlock` は新しい値で、基礎能力とは別に管理する（PTY-211）。
static func effective_stats(db, character) -> StatBlock:
	return _effective_stats(db, character.base_stats, character.equipment)


## 味方の攻撃力は `STR + 武器の攻撃力`（BTL-003）。武器がなければ武器の攻撃力を0とする（INV-306）。
static func attack_power(db, character) -> int:
	var weapon := _equipped(db, character.equipment, &"weapon")
	return effective_stats(db, character).str + (weapon.attack if weapon != null else 0)


## 味方の守備力は `VIT + 防具の防御力`（BTL-003）。VIT には装飾品を含む装備の補正を加える。
## 防具がなければ防御力の加算を0とする（INV-307）。
static func defense_power(db, character) -> int:
	var armor := _equipped(db, character.equipment, &"armor")
	return effective_stats(db, character).vit + (armor.defense if armor != null else 0)


## 成功した試算を適用する。失敗した試算は何も変更しない（ARC-403）。適用したら true。
## `inventory` は内容を置き換える。`character` は装備の試算（`plan_equip`）のときに渡す。
## 装備の試算に `character` がなければ、所持品だけが変わって食い違うため、何も変更せず false を返す。
static func apply(plan: Dictionary, inventory: Array, character = null) -> bool:
	if not plan.ok:
		return false
	var changes: Dictionary = plan.changes
	var is_equip := changes.has("equipment")
	if is_equip and character == null:
		return false
	inventory.assign(changes.inventory)
	if is_equip:
		character.equipment = changes.equipment.duplicate()
		character.current_hp = changes.current_hp
		character.current_sp = changes.current_sp
	return true


static func _effective_stats(db, base: StatBlock, equipment: Dictionary) -> StatBlock:
	var result := base.duplicate() as StatBlock
	for slot in Character.EQUIPMENT_SLOTS:
		var def := _equipped(db, equipment, slot)
		if def == null:
			continue
		for field in _STAT_FIELDS:
			result.set(field, result.get(field) + def.stat_bonus.get(field))
	return result


## 装備枠に着けている品の定義。空欄と、定義のないIDは null
static func _equipped(db, equipment: Dictionary, slot: StringName) -> EquipmentDef:
	var id: StringName = equipment.get(slot, &"")
	if id == &"":
		return null
	return db.item_or_equipment(id) as EquipmentDef


## 1枠に格納できる個数。装備は1、アイテムは `max_stack`（INV-102, INV-103）。定義のないIDも1
static func _stack_size(db, id: StringName) -> int:
	var def = db.item_or_equipment(id)
	if def is ItemDef:
		return maxi(1, def.max_stack)
	return 1


## 同種の品は、部分的に埋まっているスタックから先に詰め、残りを新しい枠へ置く（INV-104）。
## 存在しないID、1個未満は false
static func _add(db, stacks: Array, id: StringName, quantity: int) -> bool:
	if db.item_or_equipment(id) == null or quantity < 1:
		return false
	var size := _stack_size(db, id)
	var remaining := quantity
	for stack in stacks:
		if remaining == 0:
			break
		if stack.item_id == id and stack.quantity < size:
			var moved := mini(remaining, size - stack.quantity)
			stack.quantity += moved
			remaining -= moved
	while remaining > 0:
		var moved := mini(remaining, size)
		stacks.append(StackState.new(id, moved))
		remaining -= moved
	return true


## 後ろの枠から減らし、0個になった枠を取り除く。存在しないID、1個未満、所持数が足りない場合は false
static func _remove(db, stacks: Array, id: StringName, quantity: int) -> bool:
	if db.item_or_equipment(id) == null or quantity < 1:
		return false
	var owned := 0
	for stack in stacks:
		if stack.item_id == id:
			owned += stack.quantity
	if owned < quantity:
		return false
	var remaining := quantity
	for i in range(stacks.size() - 1, -1, -1):
		if remaining == 0:
			break
		if stacks[i].item_id != id:
			continue
		var taken := mini(remaining, stacks[i].quantity)
		stacks[i].quantity -= taken
		remaining -= taken
		if stacks[i].quantity == 0:
			stacks.remove_at(i)
	return true


static func _copy_stacks(inventory: Array) -> Array:
	var copied: Array = []
	for stack in inventory:
		copied.append(stack.copy())
	return copied


static func _stack_def(id: StringName, quantity: int) -> ItemStackDef:
	var def := ItemStackDef.new()
	def.item_id = id
	def.quantity = quantity
	return def


static func _success(changes: Dictionary) -> Dictionary:
	return {"ok": true, "error_code": &"", "changes": changes}


static func _failure(error_code: StringName) -> Dictionary:
	return {"ok": false, "error_code": error_code, "changes": {}}
