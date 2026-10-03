# 設計書

Godot 4.5.1 / GDScript で制作する、Windows 11向けの1人用ダンジョンRPG「迷宮踏査録」（仮題）の設計書。

状態：初回版の仕様は確定。ゲーム本体は未実装。

---

## 読む順

はじめて読む場合は上から順に読む。既に把握している場合は、必要な文書だけを開く。

| # | 文書 | 内容 |
| --- | --- | --- |
| 1 | [spec/00-glossary.md](spec/00-glossary.md) | 用語・記法・乱数系列・ID体系。**全文書の前提。常に参照する** |
| 2 | [spec/01-scope.md](spec/01-scope.md) | 初回版に含めるもの、含めないもの |
| 3 | [spec/10-flow.md](spec/10-flow.md) | 状態遷移、入力の遮断、未保存の扱い、クリア処理 |
| 4 | [spec/20-town.md](spec/20-town.md) | 5施設、料金、ゲーム日数、救済、ボスの復活 |
| 5 | [spec/30-party.md](spec/30-party.md) | 冒険者の作成と編成、能力、経験値と成長、スキル |
| 6 | [spec/35-inventory.md](spec/35-inventory.md) | 所持品の容量、装備、アイテムの使用 |
| 7 | [spec/40-dungeon.md](spec/40-dungeon.md) | 移動、歩数、遭遇、ミニマップ、イベント、帰還 |
| 8 | [spec/50-battle.md](spec/50-battle.md) | ターン進行、計算式、状態異常、逃走、報酬 |
| 9 | [spec/60-quest.md](spec/60-quest.md) | クエストの状態、進捗、報告 |
| 10 | [spec/70-save.md](spec/70-save.md) | セーブ形式、保存手順、読込検証、障害対応 |
| 11 | [spec/screens/README.md](spec/screens/README.md) | 画面ごとの遷移・表示・操作・文言・手動確認。**画面を実装するIssueはここから読む** |

| # | 文書 | 内容 |
| --- | --- | --- |
| 12 | [tech/architecture.md](tech/architecture.md) | 技術基盤、ディレクトリ、シーン構成、責務、サービス契約 |
| 13 | [tech/data-model.md](tech/data-model.md) | 定義Resource型、可変状態モデル、バリデータ |
| 14 | [tech/map-authoring.md](tech/map-authoring.md) | TileMapLayerの編集規約、コンパイル検証、3D生成、仮マップ |
| 15 | [tech/presentation.md](tech/presentation.md) | 解像度、キー割り当て、演出、設定、素材、フォント（全画面に共通するもの） |
| 16 | [tech/testing.md](tech/testing.md) | テストの実行方法、注入点、受け入れ条件IDの索引 |

| # | 文書 | 内容 |
| --- | --- | --- |
| 17 | [../data/README.md](../data/README.md) | 数値・ID・文章の唯一の正。CSVの一覧と記法 |
| 18 | [plan/milestones.md](plan/milestones.md) | 段階A〜H、依存関係、Issueの共通要件 |
| 19 | [decisions/log.md](decisions/log.md) | 決定記録。なぜこの仕様になったか |

---

## 規則の引き方

規範的な規則には `PREFIX-NNN` 形式のIDが付いている。Issue、テスト、コードコメントからはこのIDで引用する。IDは再採番されない（GLS-004）ので、設計書を改訂しても、これらの引用はずれない。

```
BTL-306  複数の騎士が同一の味方をかばっている場合、
         パーティ順が先の有効な騎士1人のみが作用する。
```

プレフィックスと文書の対応は [spec/00-glossary.md](spec/00-glossary.md) §1 にある。受け入れ条件IDの索引は [tech/testing.md](tech/testing.md) §4 にある。

---

## 実装時の原則

| 原則 | 内容 |
| --- | --- |
| 数値は `data/` が正 | 仕様文書に数値表を複写しない。バランス調整は `data/` のCSVのみを変更する（SCP-401） |
| 仕様を推測で上書きしない | 矛盾を見つけた場合は [decisions/log.md](decisions/log.md) と照合する。解消できない場合は実装を進めず判断を仰ぐ（SCP-402） |
| 記載のないものを追加しない | 職業・スキル・装備・アイテム・敵・クエストを実装者の判断で増やさない（SCP-105） |
| 未完了を完了としない | 未実装の機能と未実施のテストを完了として扱わない（TST-411） |
| 依存を勝手に増やさない | 外部のゲーム用ライブラリを必須にしない（ARC-002） |

---

## 実装エージェントへの引き渡し文

> `docs/index.md` から始まる設計書に従って、Godot 4.5.1 と GDScript で Windows 11 向けゲームを実装してください。まず `spec/00-glossary.md` と `spec/01-scope.md` を読み、`plan/milestones.md` の段階と、GitHubのIssueの順序に沿って進めてください。画面を実装する場合は `spec/screens/` の該当する画面文書から読んでください。数値は `data/` のCSVを唯一の正とし、仕様文書の規則IDを実装とテストから引用してください。初期データと編集可能な6フロアの仮マップを含め、開始からクリア・保存・再開まで動く状態を完成させてください。受け入れ条件の実施結果、未検証事項、起動・操作・マップ編集の手順を記録してください。未実装の機能と未実施のテストを完了として扱わず、仕様の変更が必要な場合は理由と影響を明示してください。

---

## 版

| 対象 | 版 |
| --- | --- |
| 本文書群 | v1.0 |
| `data/` の固定データ（`content_version`） | 0.1.0 |
| セーブファイル形式（`schema_version`） | 1 |

用途の異なる3つの版番号である。混同しない（GLS-5xx）。
