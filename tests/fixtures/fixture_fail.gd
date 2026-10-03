extends RefCounted
## T02 用フィクスチャ。X02 だけが失敗する（期待値 1、実測値 2）。

const IDS := ["X01", "X02"]


func run(t) -> void:
	t.check("X01", 1, 1)
	t.check("X02", 1, 2)
