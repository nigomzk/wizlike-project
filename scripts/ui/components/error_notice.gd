extends Label
## 共通UI部品「エラー通知」（components.md, ARC-207）。サービスの `error_code` を、`data/texts.csv` の `error_*` の文で表示する（ARC-402）。
## 文を引く処理は `message()` の1か所に置く。サービスは表示文言を持たない（ARC-400）。

## エラーコードの文章IDの接頭辞。ID は `error_` + エラーコードの小文字（ARC-402）。
const TEXT_ID_PREFIX := "error_"


## `error_code`（`NO_GOLD` など）の日本語の文を返す。`params` は文の `{名前}` を置き換える（`error_invalid_name` の `{min}` `{max}` など）。
static func message(db, error_code: StringName, params := {}) -> String:
	return db.text(StringName(TEXT_ID_PREFIX + String(error_code).to_lower()), params)


## 失敗の結果（`{ok, error_code, changes}`）の理由を表示する。
func show_error(db, error_code: StringName, params := {}) -> void:
	text = message(db, error_code, params)


## 表示を消す。行の高さは残し、表示のたびに画面の配置が動かないようにする。
func clear() -> void:
	text = ""
