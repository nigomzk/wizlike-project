extends RefCounted
## T04 用フィクスチャ。run() から呼んだ補助関数 _a() の中で実行時エラーが起きて打ち切られる。
## 呼び出し元の run() は最後まで到達し、_b() の check も実行される。

const IDS := ["X01", "X02", "X03"]


func run(t) -> void:
	_a(t)
	_b(t)


func _a(t) -> void:
	t.check("X01", 1, 1)
	var obj = null
	obj.no_such_method()
	t.check("X01", 1, 2)


func _b(t) -> void:
	t.check("X02", "a", "a")
	t.check("X03", 1, 1)
