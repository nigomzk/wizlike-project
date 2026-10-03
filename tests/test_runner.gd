extends RefCounted
## TST-408: テスト基盤（T）のテスト。フィクスチャを子プロセスの Godot で実行し、終了コードと出力を判定する。

const IDS := ["T01", "T02", "T03"]

const FIXTURE_PASS := "res://tests/fixtures/fixture_pass.gd"
const FIXTURE_FAIL := "res://tests/fixtures/fixture_fail.gd"
const FIXTURE_SKIP := "res://tests/fixtures/fixture_skip.gd"


func run(t) -> void:
	_t01(t)
	_t02(t)
	_t03(t)


## 子プロセスの Godot で run_all.gd を実行する。`{exit_code, output}` を返す。
func _run_child(files: String, extra_args: Array = []) -> Dictionary:
	var args: Array = [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/run_all.gd",
		"--",
		"--files=" + files,
	]
	args.append_array(extra_args)
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), PackedStringArray(args), output, true)
	return {"exit_code": exit_code, "output": "".join(output), "args": args}


# T01: 全件が成功するフィクスチャを実行する（TST-002, 003, 005）
func _t01(t) -> void:
	var r := _run_child(FIXTURE_PASS)
	t.check("T01", 0, r.exit_code)
	t.check("T01", true, "failed=0" in r.output)
	# エディターを起動しない: エディターを開く引数を渡しておらず、完走して終了コードを返している
	t.check("T01", false, "--editor" in r.args or "-e" in r.args)


# T02: 1件だけ失敗するフィクスチャを実行する（TST-003, 004）
func _t02(t) -> void:
	var r := _run_child(FIXTURE_FAIL)
	t.check("T02", true, r.exit_code != 0 and r.exit_code != -1)
	t.check("T02", true, "X02" in r.output)
	t.check("T02", true, "expected=1" in r.output)
	t.check("T02", true, "actual=2" in r.output)
	# 成功したIDは失敗として出さない
	t.check("T02", false, "FAIL X01" in r.output)


# T03: スキップを含むフィクスチャを --require なしと、スキップしたIDを --require に指定して実行する（TST-006, 410, 411）
func _t03(t) -> void:
	var plain := _run_child(FIXTURE_SKIP)
	t.check("T03", 0, plain.exit_code)
	# スキップは成功件数に数えられず、一覧で報告される（明示のスキップも、報告がなくIDSにだけあるものも）
	t.check("T03", true, "passed=1" in plain.output)
	t.check("T03", true, "skipped=2" in plain.output)
	t.check("T03", true, "SKIP X02" in plain.output)
	t.check("T03", true, "SKIP X03" in plain.output)

	var required_skip := _run_child(FIXTURE_SKIP, ["--require=X02"])
	t.check("T03", true, required_skip.exit_code != 0 and required_skip.exit_code != -1)
	var required_unreported := _run_child(FIXTURE_SKIP, ["--require=X03"])
	t.check("T03", true, required_unreported.exit_code != 0 and required_unreported.exit_code != -1)
	# 成功したIDを指定した場合は0のまま
	var required_pass := _run_child(FIXTURE_SKIP, ["--require=X01"])
	t.check("T03", 0, required_pass.exit_code)
