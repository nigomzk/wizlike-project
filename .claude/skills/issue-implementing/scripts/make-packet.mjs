#!/usr/bin/env node
// issue-implementing の手順5-1で使う。レビューの材料（issue.md、diff.patch、head-sha.txt、2ラウンド目以降の
// diff-since-prev.patch）と、レビュー依頼の骨組み packet.md を、1回のコマンドで作る。
//
// 機械が決めるもの：対象の表、材料の一覧（フォルダと相対パス）、変更ファイルの一覧、テストの終了コード、
// 手動確認の受入IDの一覧、前ラウンドの処置表。
// 人が書くもの：packet.md の「（要記入）」の箇所（変更ファイルに対応するタスク、申し送り）。
// 書き終えたら check で、「（要記入）」が残っていないことを確かめる。
//
// 使い方:
//   node make-packet.mjs make --root <issue-N のフォルダ> --issue <N> --cycle <c> --round <r> --branch <名前>
//        --reviewers "<起動する担当と、起動しない担当の理由>" [--mode 初回|レビュー対応]
//        [--red-ids <先に書いたときに指定したID>] [--latest-ids <このラウンドの直前に指定したID>]
//        [--user-findings <ユーザーの指摘を書いたファイル>] [--base origin/main] [--head HEAD] [--cwd <リポジトリ>]
//        [--repo nigomzk/wizlike-project]
//   node make-packet.mjs check --file <packet.md>
//
// 前提のファイル（先に作っておく）：
//   <root>/cycle-<c>/test-red.log、test-green.log（初回モード）、<root>/context7-log.md
//   <root>/cycle-<c>/round-<r>/test-latest.log、id-table.md、rules-excerpt.md（draft-id-table.mjs draft が作る）
//
// 終了コード: 0 = 成功 / 1 = check で「（要記入）」が残っている / 2 = 引数や git の誤り

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const FILL = "（要記入）";

function usage(message) {
  console.error("誤り: " + message);
  console.error("使い方: node make-packet.mjs make --root <dir> --issue <N> --cycle <c> --round <r> --branch <名前> --reviewers <文> [--mode ..] [--red-ids ..] [--latest-ids ..] [--user-findings <file>] [--base origin/main] [--head HEAD] [--cwd <dir>] [--repo <owner/name>]");
  console.error("        node make-packet.mjs check --file <packet.md>");
  process.exit(2);
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (command !== "make" && command !== "check") usage("最初の引数は make か check");
  const args = { command, base: "origin/main", head: "HEAD", cwd: process.cwd(), repo: "nigomzk/wizlike-project", mode: "初回" };
  for (let i = 0; i < rest.length; i += 2) {
    if (!rest[i].startsWith("--")) usage("不明な引数: " + rest[i]);
    const name = rest[i].slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (rest[i + 1] === undefined) usage(rest[i] + " に値がない");
    args[name] = rest[i + 1];
  }
  if (command === "check" && !args.file) usage("--file は必須");
  if (command === "make") {
    for (const key of ["root", "issue", "cycle", "round", "branch", "reviewers"]) if (!args[key]) usage("--" + key + " は必須");
    args.cycle = Number(args.cycle);
    args.round = Number(args.round);
    if (!Number.isInteger(args.cycle) || args.cycle < 1 || !Number.isInteger(args.round) || args.round < 1) usage("--cycle と --round は1以上の整数");
  }
  return args;
}

function run(cmd, cmdArgs, cwd) {
  try {
    return execFileSync(cmd, cmdArgs, { cwd, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  } catch (e) {
    console.error(cmd + " " + cmdArgs.join(" ") + " が失敗した: " + (e.stderr || e.message));
    process.exit(2);
  }
}

function readIfExists(path) {
  return existsSync(path) ? readFileSync(path, "utf8") : null;
}

/** ログの終了コード（`exit=<n>` の行）。なければ null */
function exitCode(path) {
  const log = readIfExists(path);
  if (log === null) return null;
  const m = log.match(/^exit=(\d+)\s*$/m);
  return m ? Number(m[1]) : "記録なし";
}

function make(args) {
  const root = resolve(args.root);
  const cycleDir = join(root, `cycle-${args.cycle}`);
  const roundDir = join(cycleDir, `round-${args.round}`);
  mkdirSync(roundDir, { recursive: true });
  const git = (...a) => run("git", a, args.cwd);

  // 材料：Issue本文、差分、HEADのコミット
  const issue = JSON.parse(run("gh", ["issue", "view", args.issue, "--repo", args.repo, "--json", "title,body,labels,comments"], args.cwd));
  const labels = issue.labels.map((l) => l.name);
  writeFileSync(
    join(roundDir, "issue.md"),
    `# ${issue.title}\n\nラベル: ${labels.join(", ")}\n\n${issue.body}\n\nコメント: ${JSON.stringify(issue.comments)}\n`,
    "utf8",
  );
  writeFileSync(join(roundDir, "diff.patch"), git("diff", `${args.base}...${args.head}`), "utf8");
  const headSha = git("rev-parse", args.head).trim();
  writeFileSync(join(roundDir, "head-sha.txt"), headSha + "\n", "utf8");

  // 2ラウンド目以降：前ラウンドからの差分と処置表
  const prevDir = args.round >= 2 ? join(cycleDir, `round-${args.round - 1}`) : null;
  const prevSha = prevDir ? (readIfExists(join(prevDir, "head-sha.txt")) || "").trim() : "";
  let sinceFiles = null;
  if (prevSha) {
    writeFileSync(join(roundDir, "diff-since-prev.patch"), git("diff", `${prevSha}..${args.head}`), "utf8");
    sinceFiles = new Set(git("diff", "--name-only", `${prevSha}..${args.head}`).split("\n").filter(Boolean));
  } else if (args.round >= 2) {
    console.error("前ラウンドの head-sha.txt がない。2ラウンド目以降は、前ラウンドの材料を先に作る");
    process.exit(2);
  }
  const triage = prevDir ? readIfExists(join(prevDir, "triage.md")) : null;

  // 変更ファイル（2ラウンド目以降は、前ラウンドからの修正だけ）
  const status = git("diff", "--name-status", "-M", `${prevSha ? prevSha + ".." : args.base + "..."}${args.head}`)
    .split("\n").filter(Boolean).map((row) => {
      const cols = row.split("\t");
      return { kind: { A: "追加", M: "変更", D: "削除", R: "改名" }[cols[0][0]] || cols[0], path: cols[cols.length - 1] };
    });

  // テストの実行条件
  const red = exitCode(join(cycleDir, "test-red.log"));
  const green = exitCode(join(cycleDir, "test-green.log"));
  const latest = exitCode(join(roundDir, "test-latest.log"));
  const all = exitCode(join(roundDir, "test-all.log"));
  const show = (code) => (code === null ? "ログなし" : String(code));

  // 手動確認の受入ID（id-table.md の末尾の一覧）
  const idTable = readIfExists(join(roundDir, "id-table.md")) || "";
  const manual = (idTable.split("## 手動確認の受入ID")[1] || "").split("\n").filter((l) => l.startsWith("- "));

  const lines = [];
  lines.push(`# レビュー依頼：Issue #${args.issue} サイクル${args.cycle} ラウンド${args.round}`, "");
  lines.push("## 対象", "", "| 項目 | 値 |", "| --- | --- |");
  lines.push(`| Issue | #${args.issue} ${issue.title} |`);
  lines.push(`| ラベル | ${labels.join(", ")} |`);
  lines.push(`| モード | ${args.mode} |`);
  lines.push(`| ブランチ | ${args.branch} |`);
  lines.push(`| 比較 | ${args.base}...HEAD（${headSha.slice(0, 7)}） |`);
  lines.push(`| 起動したレビュー担当 | ${args.reviewers} |`);
  lines.push(`| 確認の範囲 | ${args.round === 1 ? "全体（1ラウンド目）" : "前ラウンドの修正のみ"} |`, "");

  lines.push("## 材料", "");
  lines.push(`**材料のフォルダ（絶対パス）：** \`${roundDir}\``, "");
  lines.push("下の相対パスは、このフォルダからのもの。", "", "| 材料 | 相対パス |", "| --- | --- |");
  lines.push("| Issue本文 | issue.md |", "| 差分 | diff.patch |");
  if (prevSha) lines.push("| 前ラウンドからの差分 | diff-since-prev.patch（このラウンドで読むのは、これと前ラウンドの処置表だけ） |");
  if (triage) lines.push(`| 前ラウンドの処置表 | ../round-${args.round - 1}/triage.md |`);
  lines.push("| **規則IDと受入IDの原文** | rules-excerpt.md（設計書を開き直さず、まずここを読む） |");
  lines.push("| ID一覧の下書き | id-table.md |");
  if (existsSync(join(cycleDir, "test-red.log"))) lines.push("| テスト：先に書いたとき | ../test-red.log |");
  if (existsSync(join(cycleDir, "test-green.log"))) lines.push("| テスト：実装後 | ../test-green.log |");
  lines.push("| テスト：このラウンドの直前 | test-latest.log |");
  if (existsSync(join(roundDir, "test-all.log"))) lines.push("| テスト：全体 | test-all.log |");
  lines.push("| Context7の調査ログ | ../../context7-log.md |");
  lines.push("| 出力の型 | .claude/skills/issue-implementing/templates/review-findings.md（リポジトリ内） |");
  lines.push("| 重大度の基準 | .claude/skills/issue-implementing/criteria/severity.md（リポジトリ内） |");
  lines.push("| Context7の運用 | .claude/skills/issue-implementing/criteria/context7.md（リポジトリ内） |", "");

  lines.push("## 変更ファイル" + (prevSha ? "（前ラウンドからの修正）" : ""), "", "| ファイル | 変更の種類 | " + (prevSha ? "対応する指摘" : "対応するタスク") + " |", "| --- | --- | --- |");
  for (const f of status) lines.push(`| ${f.path} | ${f.kind} | ${FILL} |`);
  lines.push("");

  lines.push("## テストの実行条件", "", "| 実行 | 指定した受入ID | 終了コード |", "| --- | --- | --- |");
  if (args.round === 1) lines.push(`| 先に書いたとき | ${args.redIds || FILL} | ${show(red)} |`);
  lines.push(`| このラウンドの直前 | ${args.latestIds || FILL} | ${show(latest)} |`);
  lines.push(`| 全体（受入IDの指定なし） | — | ${show(all)} |`, "");

  lines.push("## 手動確認の対象（手動確認の受入ID）", "");
  lines.push(...(manual.length ? manual.map((m) => `${m}：${FILL}`) : ["なし"]), "");

  lines.push("## メインエージェントからの申し送り", "", `- ${FILL}`, "");
  lines.push("## 前のラウンドの指摘の処置", "", triage ? triage.trim() : args.round === 1 ? "なし（1ラウンド目）" : "なし", "");
  lines.push("## ユーザーの指摘（レビュー対応モードのみ）", "");
  const userFindings = args.userFindings ? readIfExists(resolve(args.userFindings)) : null;
  lines.push(userFindings ? userFindings.trim() : "なし", "");

  const out = join(roundDir, "packet.md");
  writeFileSync(out, lines.join("\n"), "utf8");
  const todo = lines.filter((l) => l.includes(FILL)).length;
  console.log(`書き出した: ${out}`);
  console.log(`材料：issue.md、diff.patch、head-sha.txt${prevSha ? "、diff-since-prev.patch" : ""}。「${FILL}」が ${todo} 行ある。Edit で埋めて、check で確かめる`);
}

function check(args) {
  const text = readFileSync(args.file, "utf8");
  const rows = text.split("\n").filter((l) => l.includes(FILL));
  if (rows.length) {
    console.error(`「${FILL}」が ${rows.length} 行に残っている:\n- ` + rows.map((r) => r.slice(0, 80)).join("\n- "));
    process.exit(1);
  }
  console.log(`検査に通った（「${FILL}」なし）`);
}

const args = parseArgs(process.argv.slice(2));
if (args.command === "make") make(args);
else check(args);
