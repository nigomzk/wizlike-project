# 構成・責務

Godotプロジェクトの構成、シーンとスクリプトの責務、サービスの契約を定義する。

**この文書が扱わない範囲**

| 関心事 | 所在 |
| --- | --- |
| データ型と可変状態モデル | `tech/data-model.md` |
| マップの制作規約と3D生成 | `tech/map-authoring.md` |
| 画面のレイアウトと入力 | `tech/presentation.md` |
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
  ui/{title,town,guild,temple,shop,inn,tavern,menu,save_slots}.tscn
  ui/{battle,reward,game_over,ending,confirm_dialog}.tscn
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
data/（固定データのCSVと、そこから生成する定義Resource）
assets/
  portraits/ enemies/ backgrounds/ tiles/ audio/ fonts/
tests/
  run_all.gd
  test_growth.gd test_battle.gd test_inventory.gd test_save.gd test_maps.gd
docs/
plan/
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
| ARC-206 | 入力できない状態を `GameFlow` と `BattleSession` が明示的に保持する（FLW-204）。 |
| ARC-207 | 共通UI部品（確認ダイアログ、一覧と詳細と戻るのテンプレート、所持金ヘッダー、フォーカス表示）を先に用意し、各画面はこれを利用する。画面ごとに同等の実装を重複させない。 |

---

## 4. 責務（ARC-3xx）

| ID | 単位 | 公開する操作と結果 |
| --- | --- | --- |
| ARC-300 | GameDatabase | `load_and_validate()`、IDから読み取り専用の定義への解決。失敗は開始不可のエラー画面とする |
| ARC-301 | GameFlow | `new_game()`、`load_slot(n)`、`go_town()`、`enter_floor(id, cell, facing)`、`start_battle(encounter)`、`return_title()` |
| ARC-302 | FacilityService | 登録・削除・編成・訓練・宿泊・治療・救済・購入・売却。条件の確認と更新を1操作で行う |
| ARC-303 | InventoryRules | 追加・削除・交換の差分を試算し、成功時のみ適用する。報酬のトランザクションに利用する |
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
| ARC-401 | 代表的なエラーコードは `NO_GOLD`、`NO_SPACE`、`INVALID_TARGET`、`PARTY_EMPTY`、`NO_LIVING_MEMBER`、`ALREADY_LEARNED`、`LOCKED`、`INVALID_SAVE` とする。 |
| ARC-402 | エラーコードの日本語への翻訳はUI側で行う。サービスは表示文言を持たない。 |
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
