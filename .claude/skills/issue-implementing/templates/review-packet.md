# レビュー依頼の材料（packet.md）の型

手順5で、メインエージェントが `cycle-<c>/round-<r>/packet.md` として書き出す。レビュー担当はこのファイルから読み始める。`<>` の部分を埋める。該当しない節は「なし」と書き、節を削らない。

---

```markdown
# レビュー依頼：Issue #<N> サイクル<c> ラウンド<r>

## 対象

| 項目 | 値 |
| --- | --- |
| Issue | #<N> <タイトル> |
| ラベル | <area:..., type:...> |
| モード | 初回 / レビュー対応 |
| ブランチ | <{type}/{N}-{slug}> |
| 比較 | main...HEAD（<HEADの短いハッシュ>） |
| 起動したレビュー担当 | spec-conformance-reviewer, test-reviewer, architecture-reviewer<, screen-reviewer> |

## 材料（絶対パス）

| 材料 | パス |
| --- | --- |
| Issue本文 | <.../issue.md> |
| 差分 | <.../diff.patch> |
| テスト：先に書いたとき | <.../cycle-<c>/test-red.log> |
| テスト：実装後 | <.../cycle-<c>/test-green.log> |
| テスト：このラウンドの直前 | <.../round-<r>/test-latest.log> |
| Context7の調査ログ | <.../context7-log.md> |
| ID一覧の下書き | <.../round-<r>/id-table.md> |
| 出力の型 | .claude/skills/issue-implementing/templates/review-findings.md |
| 重大度の基準 | .claude/skills/issue-implementing/criteria/severity.md |
| Context7の運用 | .claude/skills/issue-implementing/criteria/context7.md |

## 変更ファイル

| ファイル | 変更の種類 | 対応するタスク |
| --- | --- | --- |
| <path> | 追加 / 変更 / 削除 | <Issueのタスクの要約> |

## テストの実行条件

| 実行 | 指定した受入ID | 終了コード |
| --- | --- | --- |
| 先に書いたとき | <DoDの自動検証ID> | <非0 / 実行不能 / 対象なし> |
| 実装後・このラウンドの直前 | <DoD＋壊してはいけないものの自動検証ID> | <0> |
| 全体（受入IDの指定なし） | — | <0> |

## 手動確認の対象（手動確認の受入ID）

- <ID>：<確認する内容。ユーザーが手順10で実施する>

## メインエージェントからの申し送り

- <判断に迷った点、Context7で「未確認」とした点、Issueと設計書の解釈で選んだ点>

## 前のラウンドの指摘の処置

<ラウンド2以降、またはレビュー対応モードの場合。pr-body.md の「指摘の処置」表の形>

## ユーザーの指摘（レビュー対応モードのみ）

| # | 投稿日時 | 場所（ファイル:行 / 全体） | 指摘 | 処置 |
| --- | --- | --- | --- | --- |
```
