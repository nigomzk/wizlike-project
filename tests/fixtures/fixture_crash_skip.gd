extends RefCounted
## T04 用フィクスチャ。X01 を明示的にスキップしたあと、実行時エラーで打ち切られる。
## X01 はスキップのまま、X02（check 済み）と X03（未実行）は失敗になる。

const IDS := ["X01", "X02", "X03"]


func run(t) -> void:
	t.skip("X01", "fixture skip")
	t.check("X02", "a", "a")
	var obj = null
	obj.no_such_method()
	t.check("X03", 1, 1)
