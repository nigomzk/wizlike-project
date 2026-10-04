extends RefCounted
## TST-406: 状態遷移（FL）のテスト。
## 未実装のIDは run_all.gd が自動でスキップとして報告する（TST-410）。

const IDS := ["FL01", "FL02", "FL03", "FL04", "FL06", "FL07", "FL08"]

const MAIN_SCENE := "res://scenes/main.tscn"
const GAME_FLOW_SCRIPT := "res://scripts/core/game_flow.gd"
const TITLE_ITEMS := ["はじめから", "つづきから", "設定", "終了"]
const SLOT_COUNT := 5


func run(t) -> void:
	await _fl07(t)


# FL07: TITLEで各項目を選ぶ（FLW-001, FLW-108, FLW-112, SAV-003）
func _fl07(t) -> void:
	var tmp_root := "user://test_flow_fl07"
	var save_dir := tmp_root + "/saves"
	_make_slots(save_dir)
	var before := _snapshot(save_dir)
	t.check("FL07", SLOT_COUNT, before.size())

	_fl07_game_flow(t, save_dir, before)
	await _fl07_screens(t, save_dir, before)

	_remove_dir(tmp_root)


## GameFlow だけで、状態・入力遮断・終了の差し替え点を確かめる（FLW-204, TST-106, TST-107）。
func _fl07_game_flow(t, save_dir: String, before: Dictionary) -> void:
	var script := load(GAME_FLOW_SCRIPT) as GDScript
	t.check("FL07", true, script != null)
	if script == null:
		return
	var s = script.State
	var flow: Node = script.new()
	flow.save_dir = save_dir
	var quits := [0]
	flow.quit_handler = func(): quits[0] += 1
	var history: Array = []
	flow.state_changed.connect(func(new_state, old_state): history.append([old_state, new_state]))
	t.root.add_child(flow)

	# 起動するとTITLEになる。TITLEの間はセッションが存在しない（FLW-108, FLW-112）
	t.check("FL07", s.TITLE, flow.state)
	t.check("FL07", false, flow.has_session())

	# 「はじめから」→ NEW_GAME。既存スロットは変更されない（FLW-002, SAV-003）
	t.check("FL07", true, flow.request_new_game())
	t.check("FL07", s.NEW_GAME, flow.state)
	t.check("FL07", before, _snapshot(save_dir))
	# NEW_GAME から「はじめから」や「つづきから」は受け付けない（FLW-102）
	t.check("FL07", false, flow.request_new_game())
	t.check("FL07", false, flow.open_load())
	t.check("FL07", s.NEW_GAME, flow.state)
	t.check("FL07", true, flow.go_back())
	t.check("FL07", s.TITLE, flow.state)
	t.check("FL07", false, flow.has_session())

	# 「つづきから」→ LOAD。有効なセーブがなくても選べる（FLW-003）
	t.check("FL07", true, flow.open_load())
	t.check("FL07", s.LOAD, flow.state)
	t.check("FL07", true, flow.go_back())
	t.check("FL07", s.TITLE, flow.state)

	# 「設定」→ SETTINGS。閉じるとTITLEへ戻る。TOWNへは遷移しない（FLW-111, FLW-112, FLW-113）
	t.check("FL07", true, flow.open_settings())
	t.check("FL07", s.SETTINGS, flow.state)
	t.check("FL07", false, flow.has_session())
	t.check("FL07", true, flow.go_back())
	t.check("FL07", s.TITLE, flow.state)
	# TITLEとMENU以外からSETTINGSは開けない（FLW-111）
	t.check("FL07", true, flow.request_new_game())
	t.check("FL07", false, flow.open_settings())
	t.check("FL07", s.NEW_GAME, flow.state)
	flow.go_back()

	# 「終了」→ 差し替えた終了要求が1回呼ばれる。ランナーは止まらない（FLW-001, TST-106）
	t.check("FL07", 0, quits[0])
	flow.quit_app()
	t.check("FL07", 1, quits[0])

	# 遷移の履歴：TITLEを起点に、押した順にたどる
	t.check("FL07", [
		[s.BOOT, s.TITLE],
		[s.TITLE, s.NEW_GAME], [s.NEW_GAME, s.TITLE],
		[s.TITLE, s.LOAD], [s.LOAD, s.TITLE],
		[s.TITLE, s.SETTINGS], [s.SETTINGS, s.TITLE],
		[s.TITLE, s.NEW_GAME], [s.NEW_GAME, s.TITLE],
	], history)

	# 入力遮断は理由の集合で保持する。1つでも残っている間は遮断が続き、遷移の要求を受け付けない（FLW-204）
	t.check("FL07", false, flow.is_input_blocked())
	flow.block_input(&"modal")
	flow.block_input(&"animation")
	t.check("FL07", true, flow.is_input_blocked())
	t.check("FL07", false, flow.request_new_game())
	t.check("FL07", false, flow.open_load())
	t.check("FL07", false, flow.open_settings())
	t.check("FL07", s.TITLE, flow.state)
	flow.unblock_input(&"modal")
	t.check("FL07", true, flow.is_input_blocked())
	flow.unblock_input(&"animation")
	t.check("FL07", false, flow.is_input_blocked())
	t.check("FL07", true, flow.request_new_game())
	flow.go_back()

	t.check("FL07", before, _snapshot(save_dir))
	t.root.remove_child(flow)
	flow.free()


## main.tscn の配線のまま、TITLE画面の4項目と仮画面「準備中」を確かめる（PRS-208, PRS-700）。
func _fl07_screens(t, save_dir: String, before: Dictionary) -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	t.check("FL07", true, packed != null)
	if packed == null:
		return
	var main := packed.instantiate()
	var flow: Node = main.get_node_or_null("GameFlow")
	var host: Control = main.get_node_or_null("ScreenHost")
	t.check("FL07", true, flow != null and host != null)
	if flow == null or host == null:
		main.free()
		return
	var s = flow.State
	flow.save_dir = save_dir
	var quits := [0]
	flow.quit_handler = func(): quits[0] += 1
	t.root.add_child(main)
	# 初期フォーカスは遅延して置かれるため、1フレーム待つ
	await t.process_frame

	# 起動直後のTITLE：ゲーム名と4項目を、この順で表示する（FLW-001, PRS-700）
	t.check("FL07", s.TITLE, flow.state)
	var screen: Control = host.current_screen
	t.check("FL07", true, screen != null)
	if screen != null:
		t.check("FL07", ["迷宮踏査録"], _label_texts(screen))
		var buttons := _buttons(screen)
		t.check("FL07", TITLE_ITEMS, buttons.map(func(b): return b.text))
		# 最初の項目にフォーカスがある（キーボードのみで巡回できる。PRS-007）
		t.check("FL07", true, buttons[0].has_focus())
		# マウスを載せた項目へフォーカス枠が移る。押さずにマウスだけで4項目を巡回できる（U03）
		for button in buttons:
			button.mouse_entered.emit()
			t.check("FL07", true, button.has_focus())
		# ↑ / ↓ も Tab / Shift+Tab と同じく、端から反対の端へ巡回する（U03）
		for i in buttons.size():
			var next_button: Control = buttons[(i + 1) % buttons.size()]
			var previous_button: Control = buttons[(i + buttons.size() - 1) % buttons.size()]
			t.check("FL07", next_button, buttons[i].find_valid_focus_neighbor(SIDE_BOTTOM))
			t.check("FL07", previous_button, buttons[i].find_valid_focus_neighbor(SIDE_TOP))
			t.check("FL07", next_button, buttons[i].find_next_valid_focus())
			t.check("FL07", previous_button, buttons[i].find_prev_valid_focus())

	# 項目を押して、遷移先と、仮画面「準備中」と戻るを確かめる（PRS-208）
	var expected_states := [s.NEW_GAME, s.LOAD, s.SETTINGS]
	for i in expected_states.size():
		_press(host.current_screen, TITLE_ITEMS[i])
		t.check("FL07", expected_states[i], flow.state)
		var placeholder: Control = host.current_screen
		t.check("FL07", ["準備中"], _label_texts(placeholder))
		t.check("FL07", ["戻る"], _buttons(placeholder).map(func(b): return b.text))
		t.check("FL07", false, flow.has_session())
		await t.process_frame
		t.check("FL07", true, _buttons(placeholder)[0].has_focus())
		if i == 0:
			# Esc でも遷移元へ戻る。画面が差し替わった後に、外れたノードの処理で止まらない（PRS-208）
			t.root.push_input(_action_event(&"ui_cancel"))
		else:
			_press(placeholder, "戻る")
		t.check("FL07", s.TITLE, flow.state)
		t.check("FL07", TITLE_ITEMS, _buttons(host.current_screen).map(func(b): return b.text))

	# 入力の遮断中は、背景の入力を止める（FLW-200, FLW-204）
	var blocker: Control = host.input_blocker
	t.check("FL07", false, blocker.visible)
	flow.block_input(&"modal")
	t.check("FL07", true, blocker.visible)
	t.check("FL07", Control.MOUSE_FILTER_STOP, blocker.mouse_filter)
	_press(host.current_screen, TITLE_ITEMS[0])
	t.check("FL07", s.TITLE, flow.state)
	flow.unblock_input(&"modal")
	t.check("FL07", false, blocker.visible)

	# 「終了」→ 確認なしで終了要求が呼ばれる（U04）
	t.check("FL07", 0, quits[0])
	_press(host.current_screen, TITLE_ITEMS[3])
	t.check("FL07", 1, quits[0])

	t.check("FL07", before, _snapshot(save_dir))
	t.root.remove_child(main)
	main.free()


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _buttons(root: Node) -> Array:
	return root.find_children("*", "Button", true, false)


func _label_texts(root: Node) -> Array:
	return root.find_children("*", "Label", true, false).map(func(l): return l.text)


func _press(root: Node, text: String) -> void:
	for button in _buttons(root):
		if button.text == text:
			button.pressed.emit()
			return


## 5つのスロットに見立てたファイルを、内容を変えて作る。
func _make_slots(save_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	for i in range(1, SLOT_COUNT + 1):
		var file := FileAccess.open("%s/slot_%02d.json" % [save_dir, i], FileAccess.WRITE)
		file.store_string('{"slot": %d}' % i)
		file.close()


## ファイル名 -> [内容, 更新時刻]
func _snapshot(dir_path: String) -> Dictionary:
	var result := {}
	for file_name in DirAccess.get_files_at(dir_path):
		var path := dir_path + "/" + file_name
		result[file_name] = [FileAccess.get_file_as_string(path), FileAccess.get_modified_time(path)]
	return result


func _remove_dir(dir_path: String) -> void:
	for file_name in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path + "/" + file_name)
	for sub in DirAccess.get_directories_at(dir_path):
		_remove_dir(dir_path + "/" + sub)
	DirAccess.remove_absolute(dir_path)
