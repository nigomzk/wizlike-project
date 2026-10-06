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

## 新しい `class_name` をクラスキャッシュ（`.godot/`）の更新に頼らず参照するため、`preload` で読む。
const SessionScript := preload("res://scripts/core/game_session.gd")
const RngScript := preload("res://scripts/services/rng_service.gd")

## 設定ファイルの区画とキー（PRS-405）。
const SETTINGS_SECTION := "settings"
const KEY_MASTER_VOLUME := "master_volume"
const KEY_FULLSCREEN := "fullscreen"
## マスター音量の範囲と初期値（PRS-400）。
const MIN_MASTER_VOLUME := 0
const MAX_MASTER_VOLUME := 100
const DEFAULT_MASTER_VOLUME := 70
## ウィンドウの最小サイズ（PRS-000）。
const MIN_WINDOW_SIZE := Vector2i(960, 540)

signal state_changed(new_state: State, old_state: State)
## 入力遮断の有無が切り替わったときに送る。
signal input_block_changed(blocked: bool)
## 設定（音量・フルスクリーン）が変わったときに送る。設定画面は、この通知で表示を更新する（ARC-205）。
signal settings_changed

var state: State = State.BOOT

## 設定（ARC-301, PRS-400）。進行中のセッションとは別に持ち、TITLEでも読み書きできる（FLW-112, FLW-301, PRS-405）。
## 画面はここから読み、コピーを持たない（ARC-204）。変更は `set_master_volume()` と `set_fullscreen()` で行う。
var master_volume: int = DEFAULT_MASTER_VOLUME
var fullscreen: bool = false

## 進行中のセッション（ARC-202）。`new_game()` が作る。TITLEの間は存在しない（FLW-108）。
var session: RefCounted = null

## テスト用の注入点（TST-106, TST-107）。
## 終了要求。空の Callable の場合は `SceneTree.quit()` を呼ぶ。
var quit_handler: Callable = Callable()
## 起動時の検証（FLW-015, DAT-900）。`database` が空の場合は Autoload の `GameDatabase` を使う。
## 読込元とログの出力先は `load_and_validate()` へそのまま渡す（TST-108）。ログの出力先が空の場合は `push_error` へ出る（DAT-908）。
var database: Node = null
var data_dir: String = GameDatabase.DEFAULT_DATA_DIR
var log_sink: Callable = Callable()
## 乱数系列の注入点（TST-100, TST-102）。空の場合は、`new_game()` が毎回、ランダムに初期化した `RngService` を作る。
## 注入した場合は、その `RngService` をセッションに渡す。
var rng_service: RefCounted = null
## セーブの置き場所と設定ファイルのパス。セーブと設定の実装が参照する。
var save_dir: String = "user://saves"
var settings_path: String = "user://settings.cfg"
## フルスクリーンの反映。空の Callable の場合は、ウィンドウのモードを切り替える。引数は ON かどうか（TST-107）。
var fullscreen_handler: Callable = Callable()

## 入力を遮断している理由の集合（FLW-204）。
var _input_blockers: Dictionary = {}
## 仮画面・設定などの「戻る」で復帰する状態（FLW-113, PRS-208）。
var _return_state: State = State.TITLE


func _ready() -> void:
	boot()


## BOOT から TITLE か BOOT_ERROR へ進む（FLW-015, FLW-016, DAT-900, ARC-300）。
## 起動時に、ウィンドウの最小サイズを設定し（PRS-000）、設定を読み込んで反映し（PRS-405）、データを検証する。
## 検証に失敗した場合は、TITLE を経由せず BOOT_ERROR へ進む。
func boot() -> void:
	if state == State.BOOT:
		get_window().min_size = MIN_WINDOW_SIZE
		load_settings()
		if database == null:
			database = GameDatabase
		if database.load_and_validate(data_dir, log_sink):
			_change_state(State.TITLE)
		else:
			_change_state(State.BOOT_ERROR)


# --- 設定（PRS-400, PRS-401, PRS-402, PRS-405） ---

## 設定ファイルを読んで反映する。ファイルがない、読めない、値が範囲外や型違いの場合は、その項目を初期値か範囲内の値にする。
## 読むだけで、ファイルは書かない（PRS-400, PRS-405）。
func load_settings() -> void:
	master_volume = DEFAULT_MASTER_VOLUME
	fullscreen = false
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		var volume = config.get_value(SETTINGS_SECTION, KEY_MASTER_VOLUME, DEFAULT_MASTER_VOLUME)
		if volume is int or volume is float:
			master_volume = clampi(roundi(volume), MIN_MASTER_VOLUME, MAX_MASTER_VOLUME)
		var on = config.get_value(SETTINGS_SECTION, KEY_FULLSCREEN, false)
		if on is bool:
			fullscreen = on
	_apply_master_volume()
	if fullscreen:
		_apply_fullscreen()
	elif _window_is_fullscreen():
		# コマンドラインの `--fullscreen` で起動した場合は、保存せずに、その状態を設定の値として扱う
		fullscreen = true


## マスター音量を 0〜100 に収めて、反映して保存する（PRS-400, PRS-401）。設定の変更で、セッションとゲームの状態は変えない（FLW-301）。
func set_master_volume(value: int) -> void:
	var next := clampi(value, MIN_MASTER_VOLUME, MAX_MASTER_VOLUME)
	if next == master_volume:
		return
	master_volume = next
	_apply_master_volume()
	_save_settings()
	settings_changed.emit()


## フルスクリーンの ON / OFF を、反映して保存する（PRS-001, PRS-401）。
func set_fullscreen(on: bool) -> void:
	if on == fullscreen:
		return
	fullscreen = on
	_apply_fullscreen()
	_save_settings()
	settings_changed.emit()


## F11 と設定画面から呼ぶ、フルスクリーンの切替（PRS-108）。
func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen)


## F11 は、どの画面でも、入力の遮断中でも受け付ける（PRS-108）。ゲームの状態に触れないため、遮断の対象にしない。
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		toggle_fullscreen()


## 音量をマスターバスへ反映する。0 は消音にする（dBでは表せないため）。
func _apply_master_volume() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_mute(bus, master_volume == MIN_MASTER_VOLUME)
	if master_volume > MIN_MASTER_VOLUME:
		AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume / float(MAX_MASTER_VOLUME)))


func _apply_fullscreen() -> void:
	if fullscreen_handler.is_valid():
		fullscreen_handler.call(fullscreen)
	elif fullscreen:
		get_window().mode = Window.MODE_FULLSCREEN
	else:
		get_window().mode = Window.MODE_WINDOWED


func _window_is_fullscreen() -> bool:
	return get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]


## 設定を即時に保存する（PRS-401）。失敗してもメモリ上の値は保ち、警告を出す。
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, KEY_MASTER_VOLUME, master_volume)
	config.set_value(SETTINGS_SECTION, KEY_FULLSCREEN, fullscreen)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	var error := config.save(settings_path)
	if error != OK:
		push_warning("Failed to save settings to %s (error %d)" % [settings_path, error])


func has_session() -> bool:
	return session != null


# --- TITLE の操作 ---

## 「はじめから」。既存のセーブスロットには触れない（FLW-002, SAV-003）。
func request_new_game() -> bool:
	return _leave_title(State.NEW_GAME)


## NEW_GAME でセッションを初期化し、保持する（FLW-002, ARC-301）。成功したら true。
## NEW_GAME 以外の状態、または初期化に失敗した場合は、何も変えず false。状態の遷移と画面は呼び出し側が行う。
func new_game() -> bool:
	if state != State.NEW_GAME or database == null:
		return false
	var rng: RefCounted = rng_service if rng_service != null else RngScript.new()
	var created: RefCounted = SessionScript.create_new(database, rng)
	if created == null:
		return false
	session = created
	return true


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
