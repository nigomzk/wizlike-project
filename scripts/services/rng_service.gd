class_name RngService
extends RefCounted
## 用途別の乱数系列を、互いに独立して保持する（ARC-404, GLS-200）。
##
## 系列は `encounter`、`battle`、`loot`、`creation` の4つ。用途は GLS-202 に従う。
## サービスと規則は乱数を自分で作らず、ここから系列を指定して取り出す（ARC-404）。
## このクラスは値を引かない。引き置きをせず、判定を行う箇所でだけ呼び出し側が引く（GLS-204）。
## テストでは `seed_series()` で系列ごとに固定のseedを注入できる（TST-102）。

const ENCOUNTER := &"encounter"
const BATTLE := &"battle"
const LOOT := &"loot"
const CREATION := &"creation"
## GLS-200: 系列の一覧。並びは GLS-200 の記載順
const SERIES: Array[StringName] = [ENCOUNTER, BATTLE, LOOT, CREATION]

## 系列の名前 -> RandomNumberGenerator
var _series: Dictionary = {}


## 4系列をそれぞれ別の乱数で初期化する。
func _init() -> void:
	for id in SERIES:
		_series[id] = RandomNumberGenerator.new()
	randomize_all()


## 系列を返す。系列にない名前は null。呼び出し元が引いた分だけ、その系列の state が進む。
func series(id: StringName) -> RandomNumberGenerator:
	return _series.get(id)


## すべての系列を、それぞれ別の乱数で初期化し直す。
func randomize_all() -> void:
	for id in SERIES:
		_series[id].randomize()


## 1つの系列へ seed を注入する（TST-102）。他の系列は変わらない。系列にない名前は何もせず false。
## seed を設定すると、その系列の state も seed から決まる値になる。
func seed_series(id: StringName, seed_value: int) -> bool:
	if not _series.has(id):
		return false
	_series[id].seed = seed_value
	return true


## 系列の名前 -> seed の対応で、まとめて注入する。1つでも系列にない名前があれば、何も変えず false。
func seed_all(seeds: Dictionary) -> bool:
	for id in seeds:
		if not _series.has(id):
			return false
	for id in seeds:
		_series[id].seed = seeds[id]
	return true
