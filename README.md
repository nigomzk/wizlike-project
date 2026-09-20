# wizlike-project

探索・パーティ編成を楽しむ、一人称視点のダンジョン探索RPGプロジェクト。

Godot 4.5.1 / GDScript で制作する、Windows 11向けの1人用ダンジョンRPGです。初回版の仕様は確定しており、ゲーム本体は未実装です。

## 設計書

- **[docs/index.md](docs/index.md)** — 設計書の入口。読む順、規則IDの引き方、実装時の原則
- [docs/spec/](docs/spec/) — ゲームルール（用語・範囲・遷移・街・冒険者・所持品・探索・戦闘・クエスト・セーブ）
- [docs/tech/](docs/tech/) — 技術設計（構成・データモデル・マップ制作・画面・テスト）
- [data/](data/) — 数値・ID・文章の唯一の正。CSV形式
- [docs/plan/](docs/plan/) — マイルストーンとIssueの共通要件
- [docs/decisions/log.md](docs/decisions/log.md) — 決定記録

実装は `docs/index.md` から読み始め、`docs/plan/milestones.md` の順序に沿って進めてください。

## 版

| 対象 | 版 |
| --- | --- |
| 設計書 | v1.0 |
| 固定データ（`content_version`） | 0.1.0 |
| セーブ形式（`schema_version`） | 1 |
