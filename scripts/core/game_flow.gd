extends Node
## ゲーム全体の状態と遷移、入力の遮断を保持する（ARC-301, FLW-0xx, FLW-204）。
## 画面は判断を持たず、ここへ要求を送って状態の変化を表示する（ARC-204, ARC-205）。
## `class_name` は付けない。クラス登録のキャッシュがない状態でも、パスの `preload` で参照できるようにするため。

## 状態（FLW-001, FLW-002, FLW-003, FLW-004, FLW-005, FLW-006, FLW-007, FLW-008, FLW-009, FLW-010, FLW-011, FLW-012, FLW-013, FLW-014, FLW-015, FLW-016）
enum State {
	BOOT,
	BOOT_ERROR,
	TITLE,
	NEW_GAME,
	LOAD,
	TOWN,
	FACILITY,
	DEPARTURE,
	EXPLORATION,
	EVENT,
	BATTLE,
	REWARD,
	GAME_OVER,
	ENDING,
	MENU,
	SETTINGS,
}

signal state_changed(new_state: State, old_state: State)
## 入力遮断の有無が切り替わったときに送る。
signal input_block_changed(blocked: bool)

var state: State = State.BOOT

## 進行中のセッション（ARC-202）。セッションの実装までは常に null で、TITLEの間は存在しない（FLW-108）。
var session: RefCounted = null

## テスト用の注入点（TST-106, TST-107）。
## 終了要求。空の Callable の場合は `SceneTree.quit()` を呼ぶ。
var quit_handler: Callable = Callable()
## セーブの置き場所と設定ファイルのパス。セーブと設定の実装が参照する。
var save_dir: String = "user://saves"
var settings_path: String = "user://settings.cfg"

## 入力を遮断している理由の集合（FLW-204）。
var _input_blockers: Dictionary = {}
## 仮画面・設定などの「戻る」で復帰する状態（FLW-113, PRS-208）。
var _return_state: State = State.TITLE


func _ready() -> void:
	boot()


## BOOT から TITLE へ進む（FLW-015）。データベースの読込と設定の読込は、それぞれの実装時にここへ加える。
func boot() -> void:
	if state == State.BOOT:
		_change_state(State.TITLE)


func has_session() -> bool:
	return session != null


# --- TITLE の操作 ---

## 「はじめから」。既存のセーブスロットには触れない（FLW-002, SAV-003）。
func request_new_game() -> bool:
	return _leave_title(State.NEW_GAME)


## 「つづきから」。ロードはTITLEからのみ開ける（FLW-102）。
func open_load() -> bool:
	return _leave_title(State.LOAD)


## 設定を開く。呼び出し元を記録し、閉じると必ずそこへ戻る（FLW-111, FLW-112, FLW-113）。
func open_settings() -> bool:
	if is_input_blocked() or (state != State.TITLE and state != State.MENU):
		return false
	_return_state = state
	_change_state(State.SETTINGS)
	return true


## 「終了」。TITLEにはセッションがないため、未保存の確認は出さない（FLW-001）。
func quit_app() -> void:
	if quit_handler.is_valid():
		quit_handler.call()
	else:
		get_tree().quit()


## 仮画面や設定の「戻る」。記録した呼び出し元の状態へ戻る（PRS-208, FLW-113）。
func go_back() -> bool:
	if is_input_blocked() or state not in [State.NEW_GAME, State.LOAD, State.SETTINGS]:
		return false
	_change_state(_return_state)
	return true


# --- 入力の遮断（FLW-204） ---

## 理由ごとに遮断を積む。同じ理由の重複は1つとして数える。
func block_input(reason: StringName) -> void:
	var was_blocked := is_input_blocked()
	_input_blockers[reason] = true
	if not was_blocked:
		input_block_changed.emit(true)


func unblock_input(reason: StringName) -> void:
	if _input_blockers.erase(reason) and not is_input_blocked():
		input_block_changed.emit(false)


func is_input_blocked() -> bool:
	return not _input_blockers.is_empty()


func _leave_title(next: State) -> bool:
	if is_input_blocked() or state != State.TITLE:
		return false
	_return_state = State.TITLE
	_change_state(next)
	return true


func _change_state(next: State) -> void:
	var old := state
	state = next
	state_changed.emit(next, old)
