extends RefCounted
## T04 用フィクスチャ。run() 直下で実行時エラーが起きて打ち切られる。
## X01・X02 の1回目は成功する。X02 の2回目（本来は失敗する）と X03 は実行されない。

const IDS := ["X01", "X02", "X03"]


func run(t) -> void:
	t.check("X01", 1, 1)
	t.check("X02", "a", "a")
	var obj = null
	obj.no_such_method()
	t.check("X02", 1, 2)
	t.check("X03", 1, 1)
