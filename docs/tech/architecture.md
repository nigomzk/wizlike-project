# 構成・責務

Godotプロジェクトの構成、シーンとスクリプトの責務、サービスの契約を定義する。

**この文書が扱わない範囲**

| 関心事 | 所在 |
| --- | --- |
| データ型と可変状態モデル | `tech/data-model.md` |
| マップの制作規約と3D生成 | `tech/map-authoring.md` |
| 画面のレイアウトと入力 | `tech/presentation.md`、`spec/screens/`（画面ごとの構成） |
| テストの実行方法 | `tech/testing.md` |
| 実装の順序 | `plan/milestones.md` |

---

## 1. 技術基盤（ARC-0xx）

| ID | 規則 |
| --- | --- |
| ARC-000 | Godot 4.5.1 Standard と GDScript を用いる。同一バージョンのExport Templatesを使用する。最新版という意味ではなく、確認できた安定版とAPIを基準に再現性を確保する選択である。 |
| ARC-001 | 書き出しの対象は Windows Desktop x86_64 とし、Compatibilityレンダラーを用いる。EXEと外部PCKで配布する。 |
| ARC-002 | 外部のゲーム用ライブラリを必須にしない。 |
| ARC-003 | エントリーシーンを `res://scenes/main.tscn` とする。 |
| ARC-004 | ゲームロジックを3DノードとUIから分離し、ヘッドレスで検証できる状態を保つ。 |
| ARC-005 | 制作用マップには `TileMapLayer` を用いる。独自のGDScriptで2Dセル情報を3Dへ変換する（MAP-3xx）。 |
| ARC-006 | プロジェクト内で秘密情報と絶対ローカルパスに依存しない。 |

公式資料：

- [Godot 4.5.1 配布アーカイブ](https://godotengine.org/download/archive/4.5.1-stable/)
- [TileMapLayer API](https://docs.godotengine.org/en/4.5/classes/class_tilemaplayer.html)
- [TileSet の custom data](https://docs.godotengine.org/en/4.5/tutorials/2d/using_tilesets.html#assigning-custom-metadata-to-the-tileset-s-tiles)
- [ResourceSaver](https://docs.godotengine.org/en/4.5/classes/class_resourcesaver.html)
- [Saving games](https://docs.godotengine.org/en/4.5/tutorials/io/saving_games.html)
- [RandomNumberGenerator](https://docs.godotengine.org/en/4.5/classes/class_randomnumbergenerator.html)
- [JSON](https://docs.godotengine.org/en/4.5/classes/class_json.html)
- [Windows export](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_windows.html)

以下の構成と数値はGodotの公式仕様ではなく、本プロジェクトで決定した設計上の選択である。

---

## 2. ディレクトリ構成（ARC-1xx）

```text
project.godot
export_presets.cfg
scenes/
  main.tscn
  ui/{title,settings,boot_error,text_screen,town,departure,save_slots}.tscn
  ui/{guild,temple,shop,inn,tavern}.tscn
  ui/{menu,inventory,equipment,map}.tscn
  ui/{battle,reward}.tscn
  ui/components/（共通UI部品。確認ダイアログを含む）
  dungeon/{dungeon_view,minimap}.tscn
  floors/{ruins_f1,ruins_f2,ruins_f3,depths_f1,depths_f2,depths_f3}.tscn
scripts/
  core/{game_flow,game_session,game_database,game_validator}.gd
  models/{character_state,inventory_state,quest_state,floor_state}.gd
  services/{save_service,rng_service,facility_service,quest_service}.gd
  rules/{battle_rules,battle_session,growth_rules,inventory_rules,exploration_rules}.gd
  dungeon/{floor_authoring,floor_compiler,dungeon_builder,dungeon_controller}.gd
  ui/（各画面のpresenter）
  definitions/（定義Resource型）
data/（固定データのCSV。件数と版は manifest.csv）
assets/
  portraits/ enemies/ backgrounds/ tiles/ icons/ audio/ fonts/
tests/
  run_all.gd
  test_maps.gd test_growth.gd test_inventory.gd test_battle.gd test_save.gd
  test_facility.gd test_flow.gd test_exploration.gd
  test_runner.gd test_core.gd
  fixtures/（ランナーの検証用のテストファイル。TST-109, 412）
docs/
THIRD_PARTY_NOTICES.md
README.md
```

---

## 3. シーン構成（ARC-2xx）

| ID | 規則 |
| --- | --- |
| ARC-200 | `main.tscn` のルートを `Node` とし、`GameFlow`、`ScreenHost(Control)`、`DungeonHost(Node3D)`、`ModalHost(CanvasLayer)`、`AudioHost` を子に持たせる。 |
| ARC-201 | Autoloadは `GameDatabase` と `SaveService` に限定する。 |
| ARC-202 | `GameSession` はニューゲームとロードの単位で置き換える `RefCounted` とする。`GameFlow` が所有し、画面へ渡す。 |
| ARC-203 | TITLEへ戻った時点で旧セッションを破棄する（FLW-108）。 |
| ARC-204 | 画面は状態のコピーを独自に保持して保存しない。セッションを参照し、サービスへコマンドを送る。 |
| ARC-205 | UIは更新の通知を受けて表示する。UIが直接モデルを書き換えない。 |
| ARC-207 | 共通UI部品（確認ダイアログ、一覧と詳細と戻るのテンプレート、所持金ヘッダー、フォーカス表示）を先に用意し、各画面はこれを利用する。画面ごとに同等の実装を重複させない。 |

---

## 4. 責務（ARC-3xx）

| ID | 単位 | 公開する操作と結果 |
| --- | --- | --- |
| ARC-300 | GameDatabase | `load_and_validate()`、IDから読み取り専用の定義への解決。失敗は開始不可のエラー画面とする |
| ARC-301 | GameFlow | `new_game()`、`load_slot(n)`、`go_town()`、`enter_floor(id, cell, facing)`、`start_battle(encounter)`、`return_title()`。状態ごとの遷移可否の判定（TWN-110）、入力遮断の保持（FLW-204）、設定の読込・保存・反映とF11（PRS-4xx, PRS-108） |
| ARC-302 | FacilityService | 登録・削除・編成・訓練・宿泊・治療・救済・購入・売却。条件の確認と更新を1操作で行う |
| ARC-303 | InventoryRules | 追加・削除・交換の差分を試算し、成功時のみ適用する。報酬のトランザクションに利用する。装備補正込みの能力値・攻撃力・守備力を算出する（BTL-002, BTL-003）。BattleRulesと画面はこの算出を用い、式を重複させない |
| ARC-304 | QuestService | 解禁条件の評価、受注、勝利時のカウント、報告の試算と確定 |
| ARC-305 | ExplorationRules | 通行判定、成功した歩の処理、踏破の記録、遭遇残数、イベントの発火。描画を持たない |
| ARC-306 | BattleSession | 入力の予約、実行の確定、ターンの解決、戦闘結果の生成。実行確定後の入力を拒否する |
| ARC-307 | BattleRules | 命中・ダメージ・状態異常・順序・逃走・終了の判定。乱数を引数で受け取る |
| ARC-308 | GrowthRules | 経験値の配分、レベルの判定、個別の成長乱数、成長ログ |
| ARC-309 | FloorCompiler | `TileMapLayer` とイベント定義を読み、`FloorGrid` へ変換して検証する |
| ARC-310 | DungeonBuilder | `FloorGrid` と永続状態から `MeshInstance3D` 等を生成する。セッションを変更しない |
| ARC-311 | SaveService | DTO化、検証、ファイルの書込み、スロット一覧、復元。UIを持たない |

---

## 5. サービスの契約（ARC-4xx）

| ID | 規則 |
| --- | --- |
| ARC-400 | サービスの結果を `{ok: bool, error_code: StringName, changes: Dictionary}` の形式で返す。 |
| ARC-401 | エラーコードは `NO_GOLD`、`NO_SPACE`、`INVALID_TARGET`、`PARTY_EMPTY`、`PARTY_FULL`、`ROSTER_FULL`、`INVALID_NAME`、`NO_LIVING_MEMBER`、`ALREADY_LEARNED`、`LOCKED`、`INVALID_SAVE` に限る。追加する場合は本表と `data/texts.csv` の `error_*` を同時に更新する。 |
| ARC-402 | エラーコードの日本語への翻訳はUI側で行い、`data/texts.csv` の `error_` + エラーコードの小文字を表示する。サービスは表示文言を持たない。 |
| ARC-403 | 失敗した操作は副作用を一切残さない（TWN-101）。 |
| ARC-404 | 乱数はサービスが内部で生成せず、`RngService` から系列を指定して取得する（GLS-2xx）。 |

---

## 6. 納品物（ARC-5xx）

| ID | 納品物 |
| --- | --- |
| ARC-500 | Godotプロジェクト一式 |
| ARC-501 | 6フロアの編集可能なシーン |
| ARC-502 | `data/` の全データ |
| ARC-503 | Windows向けのEXEとPCK |
| ARC-504 | 起動・操作・マップ編集の手順 |
| ARC-505 | テストの実施結果と、未検証事項の一覧 |
| ARC-506 | `THIRD_PARTY_NOTICES.md` によるライセンス一覧 |

---

## 7. 受け入れ条件

| ID | 前提・操作 | 合格条件 | 根拠 |
| --- | --- | --- | --- |
| A01 | `main.tscn` をインスタンス化する | ルートが `Node` で、子に GameFlow、ScreenHost（Control）、DungeonHost（Node3D）、ModalHost（CanvasLayer）、AudioHost を持つ。Autoloadが GameDatabase と SaveService の範囲に収まる | ARC-003, 200, 201 |
| A02 | 系列ごとに同じseedを注入した `RngService` を2つ作り、同じ順に引く | 系列ごとに同じ値の列が得られる | GLS-200, 204, ARC-404, TST-102 |
| A03 | ある系列から引く。画面の開閉、一覧の操作、冒険者作成の途中キャンセルを行う | 引いた系列以外のstateは変わらない。画面操作と途中キャンセルではどの系列のstateも変わらない | GLS-200, 202, 203, PTY-007 |
| A04 | 同じseedで冒険者を同じ順に作成する | 作成の確定時にのみ `creation` 系列から1回引き、冒険者ごとの `growth_rng` のseedが2回の実行で一致する | GLS-201, PTY-006 |
| A05 | ARC-401の全エラーコードとサービスの戻り値を確認する | 全コードについて `data/texts.csv` に `error_` + 小文字のIDが存在する。サービスの戻り値が `{ok, error_code, changes}` の形である | ARC-400〜402 |
