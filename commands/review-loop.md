---
name: review-loop
description: コードレビューと修正を収束するまで繰り返すフィードバックループ。PR 前の品質向上、ボットレビュー対策、コード品質の段階的改善に使用する。/review-loop と呼ばれた時に使用する。
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# Review Loop - 収束型コードレビュー

ローカルの変更に対して「レビュー → 修正 → 再レビュー」を issue が 0 になる（または最大ラウンド数に達する）まで繰り返します。
LLM レビューは1回ごとに新しい視点で問題を発見するため、複数ラウンド回すことで品質が漸近的に向上します。

**Announce at start:** "Review Loop を開始します。変更を分析して、観点別の並列レビューを収束するまで繰り返します。"

## 引数

$ARGUMENTS

- `--max-rounds=N` (default: 5): 最大ラウンド数
- `--severity=critical|high|medium|all` (default: high): 修正対象とする最低重要度
- `--auto-fix` (default: true): 発見した問題を自動修正する。false なら報告のみ
- `--scope=staged|all|file=<path>` (default: all): レビュー対象
- `--codex` (default: false): OpenAI Codex にも並列でレビューさせる（モデル多様性）

## ワークフロー

### Phase 1: 変更の把握

1. `git diff HEAD --stat` で変更ファイル一覧を取得
2. `git diff HEAD` で全 diff を取得
3. プロジェクトの言語・フレームワークを検出（Cargo.toml, package.json, go.mod 等）
4. ビルドコマンドとテストコマンドを特定

### Phase 2: レビューループ

以下を `max-rounds` 回まで繰り返す:

#### Step 2a: 観点別並列レビュー

**各ラウンドで 3〜4 個のサブエージェントを同時起動する。** 各エージェントは異なる観点に特化し、独立コンテキストで動く。これにより広さと深さの両方を確保する。

**重要**: 毎ラウンド新しいサブエージェントを起動すること（前ラウンドの修正バイアスを避けるため）。

全サブエージェントを **1つのメッセージ内で並列に Agent ツール呼び出し** して同時起動すること。

##### Reviewer 1: セキュリティ & メモリ安全性

- **subagent_type**: `general-purpose`
- **model**: `opus`
- **prompt の観点**:
  - インジェクション (SQL, XSS, コマンド, パストラバーサル)
  - 認証・認可の不備、権限昇格
  - 機密情報のハードコード・ログ出力
  - バッファオーバーフロー、unbounded allocation、OOM
  - デッドロック、TOCTOU、競合状態
  - 暗号・乱数の誤用
  - FFI 安全性 (unsafe ブロック、null ポインタ、ライフタイム)

##### Reviewer 2: ロジック & 正確性

- **subagent_type**: `general-purpose`
- **model**: `opus`
- **prompt の観点**:
  - 境界値・エッジケースの未処理 (空配列、0、MAX、負数)
  - null/None/undefined の未チェック
  - エラーハンドリング不備 (unwrap/panic in production paths)
  - API 契約違反 (引数の型・範囲、戻り値の意味)
  - リソースリーク (未 close、未 dispose、未 drop)
  - 状態遷移の不整合、イベント順序の前提違反
  - off-by-one エラー、型変換の truncation/overflow

##### Reviewer 3: パフォーマンス & 設計

- **subagent_type**: `general-purpose`
- **model**: `opus`
- **prompt の観点**:
  - O(n^2) 以上のアルゴリズム、N+1 クエリ
  - 不要なクローン/コピー/アロケーション
  - ブロッキング I/O in async コンテキスト
  - 入力バリデーション不足 (外部入力の信頼)
  - timeout/上限なしのネットワーク・ファイル操作
  - ロック粒度の粗さ、ホットパスの非効率

##### Reviewer 4 (オプション: --codex 指定時): Codex レビュー

`--codex` が指定された場合、追加で Codex にもレビューさせる。
Bash ツールで `codex` CLI を呼び出し、diff を渡してレビュー結果を取得する。
異なるモデルファミリーは異なる盲点を持つため、多様性が品質を高める。

#### 各レビュワー共通の出力フォーマット指示

各サブエージェントのプロンプトに以下を含める:

```
あなたは {観点名} の専門レビュワーです。以下の diff をあなたの専門観点のみからレビューしてください。
他の観点（例: セキュリティ担当なのにスタイルを指摘する）は別のレビュワーが担当するので不要です。

## 対象コード

{diff の内容}

## プロジェクトコンテキスト

- 言語/フレームワーク: {検出結果}
- 変更ファイル数: {N}
- 変更行数: {M}

## 重要度の定義

- **critical**: 本番で確実に問題になる。データ損失、セキュリティ侵害、クラッシュ
- **high**: 高確率でバグになる。特定条件でのみ発現する可能性
- **medium**: 改善すべきだが直ちに問題にはならない
- **low**: あれば良い程度の改善（これは報告しなくてよい）

## 出力

各 issue を以下の JSON Lines で出力してください（説明テキスト不要、JSON のみ）:

{"severity":"critical|high|medium","file":"path/to/file.rs","line":42,"title":"短い要約","description":"問題の詳細と修正方針","fix_suggestion":"具体的なコード修正案（あれば）"}

issue がない場合は以下を出力:
{"severity":"none","title":"No issues found"}
```

#### Step 2b: 結果の統合 & 重複排除

1. 全レビュワーの出力を収集
2. JSON Lines をパース
3. 同一ファイル・同一行の重複 issue をマージ（複数レビュワーが同じ問題を指摘 → 確信度が高い）
4. severity でフィルタリング:
   - `--severity=critical` → critical のみ
   - `--severity=high` → critical + high (デフォルト)
   - `--severity=medium` → critical + high + medium
   - `--severity=all` → 全部
5. 複数レビュワーが指摘した issue は severity を1段階上げる（cross-validated）

#### Step 2c: 修正の適用

`--auto-fix` が true の場合:

1. 各 issue を severity 順（critical → high → medium）、次にファイル順に処理
2. 該当ファイルを Read で読み、Edit で修正を適用
3. 修正後、直ちにビルド確認:
   - Rust: `cargo check` (+ `cargo test` があれば実行)
   - TypeScript/JS: `npx tsc --noEmit` or `npm run build`
   - Python: `python -m py_compile`
   - Go: `go vet ./...` && `go build ./...`
4. ビルド/テストが壊れた場合は修正をリバートし、issue をスキップ

#### Step 2d: 収束判定

- 今ラウンドで severity >= threshold の issue が **0件** → **収束**。ループ終了
- issue が前ラウンドより増えた → 修正が新たな問題を生んでいる可能性。ユーザーに確認
- 最大ラウンドに到達 → 残存 issue を報告して終了

### Phase 3: 結果サマリー

最終的に以下を出力:

```markdown
## Review Loop Summary

**Rounds:** {completed}/{max}
**Status:** Converged | Max rounds reached | Stopped by user
**Reviewers:** Security(opus) + Logic(opus) + Performance(opus) [+ Codex]

### Issues by Round
| Round | Reviewers | Found | Fixed | Skipped | Cross-validated |
|-------|-----------|-------|-------|---------|-----------------|
| 1     | 3         | 8     | 7     | 1       | 3               |
| 2     | 3         | 2     | 2     | 0       | 0               |
| 3     | 3         | 0     | -     | -       | Converged       |

### Cross-validated Issues (複数レビュワーが同時指摘)
これらは複数の独立した視点が同じ問題を発見したため、信頼度が高い:
- **[file:line]** description (指摘元: Security + Logic)

### Remaining Issues (if any)
- [ ] **[file:line]** description (reason skipped)

### Changes Made
{git diff --stat の出力}
```

## 設計原則

1. **観点の分離**: 各レビュワーは自分の専門領域のみに集中。「セキュリティ担当がスタイルを指摘する」ような雑音を排除し、深いレビューを実現
2. **モデル多様性**: 異なるモデル（Opus + Codex）は異なる盲点を持つ。複数モデルで同じ問題を発見したら確信度が上がる
3. **並列実行**: 3〜4 レビュワーを同時起動し、待ち時間を最小化
4. **独立コンテキスト**: 各ラウンド・各レビュワーは新しいサブエージェント。修正バイアスを排除
5. **cross-validation**: 複数レビュワーが同じ問題を独立に発見 → severity を上げる。単独指摘より信頼度が高い
6. **段階的収束**: 各ラウンドは前回の修正コードをレビューするため、見落としが段階的に減る
7. **安全な修正**: ビルドが壊れたら即リバート。品質を下げる修正は適用しない
8. **コスト意識**: max-rounds で上限制御。ラウンドが進むにつれ issue は減るので、コストも漸減する
