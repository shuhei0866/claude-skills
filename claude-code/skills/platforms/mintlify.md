---
name: mintlify
description: ドキュメントサイトの更新、新ページの追加、ナビゲーション変更、または /mintlify と呼ばれた時に使用する。Mintlify ベースのドキュメント管理を支援する。
---

# Mintlify ドキュメント管理スキル

このスキルはプロジェクトのMintlifyドキュメント管理を支援します。

## ドキュメントの場所

```
docs/
├── mint.json           # 設定ファイル（ナビゲーション、テーマなど）
├── introduction.mdx    # トップページ
├── guide/              # ガイド
├── architecture/       # アーキテクチャ
├── strategy/           # 戦略・ロードマップ
├── flow/               # フロー図
├── design/             # デザイン
├── logo/               # ロゴ画像
└── favicon.svg         # ファビコン
```

## ホスティング

- **URL**: <your-docs-url>
- **プラットフォーム**: Mintlify（Hobbyプラン）
- **デプロイ**: mainブランチへのプッシュで自動デプロイ

## ページの追加方法

### 1. MDXファイルを作成

```bash
# 例: 新しいガイドページを追加
touch docs/guide/new-feature.mdx
```

### 2. フロントマターとコンテンツを記述

```mdx
---
title: '新機能ガイド'
description: '新機能の使い方を説明します'
---

# 新機能ガイド

ここにコンテンツを記述...
```

### 3. mint.jsonのnavigationに追加

```json
{
  "navigation": [
    {
      "group": "ガイド",
      "pages": [
        "guide/design-guide",
        "guide/new-feature"  // ← 追加（.mdx拡張子は不要）
      ]
    }
  ]
}
```

## mint.json の主要設定

### ナビゲーション

```json
{
  "navigation": [
    {
      "group": "グループ名",
      "pages": ["path/to/page"]
    }
  ]
}
```

### カラー設定

```json
{
  "colors": {
    "primary": "#4F46E5",    // Indigo（ブランドカラー）
    "light": "#6366F1",
    "dark": "#4F46E5",
    "anchors": {
      "from": "#4F46E5",
      "to": "#F59E0B"        // Amber（アクセント）
    }
  }
}
```

### トップバー

```json
{
  "topbarLinks": [
    { "name": "サポート", "url": "mailto:<your-support-email>" }
  ],
  "topbarCtaButton": {
    "name": "アプリを開く",
    "url": "<your-website-url>"
  }
}
```

## MDXコンポーネント

Mintlifyが提供する組み込みコンポーネント:

### カード

```mdx
<Card title="タイトル" icon="icon-name" href="/path">
  説明文
</Card>

<CardGroup cols={2}>
  <Card title="カード1" icon="book" href="/guide">説明1</Card>
  <Card title="カード2" icon="code" href="/api">説明2</Card>
</CardGroup>
```

### タブ

```mdx
<Tabs>
  <Tab title="タブ1">
    コンテンツ1
  </Tab>
  <Tab title="タブ2">
    コンテンツ2
  </Tab>
</Tabs>
```

### アコーディオン

```mdx
<Accordion title="クリックで展開">
  詳細なコンテンツ
</Accordion>

<AccordionGroup>
  <Accordion title="FAQ 1">回答1</Accordion>
  <Accordion title="FAQ 2">回答2</Accordion>
</AccordionGroup>
```

### コールアウト

```mdx
<Note>補足情報</Note>
<Warning>警告</Warning>
<Info>情報</Info>
<Tip>ヒント</Tip>
```

### コードブロック

```mdx
```typescript title="example.ts"
const greeting = "Hello, World!";
```
```

## ローカルプレビュー

```bash
cd docs
npx mintlify dev
# http://localhost:3000 でプレビュー
```

## デプロイ

mainブランチにプッシュすると自動デプロイされます。

```bash
git add docs/
git commit -m "docs: ドキュメントを更新"
git push
```

デプロイ状況はMintlifyダッシュボードで確認可能。

## アイコン

Mintlifyは[Font Awesome](https://fontawesome.com/icons)アイコンを使用。
アイコン名は小文字のケバブケースで指定：

```json
{ "icon": "book" }
{ "icon": "github" }
{ "icon": "rocket" }
```

## 画像の追加

```mdx
![代替テキスト](/images/screenshot.png)
```

画像ファイルは `docs/images/` に配置。

## チェックリスト

ドキュメント更新時に確認すること：

- [ ] mint.jsonのnavigationにページを追加したか
- [ ] フロントマター（title, description）を設定したか
- [ ] ローカルプレビューで表示を確認したか
- [ ] リンク切れがないか
- [ ] 日本語で記述しているか（UIは日本語）
