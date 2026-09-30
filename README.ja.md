# Monitor Panel iOS

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [한국어](README.ko.md) | **日本語**

iPhoneとiPad向けのネイティブサーバー監視アプリです。Komari、Nezha、DStatusのパネルをまとめて接続し、サーバーの稼働状況を確認したり、モバイルからKomariのノードを管理したりできます。

SwiftUIで構築され、iOS 16以降に対応しています。iOS 26ではLiquid Glassのインターフェースを利用できます。

## プレビュー

<p align="center">
  <img src="docs/screenshots/en-preview.png" width="620" alt="サーバー概要とノード詳細">
</p>

## 主な機能

- **複数のバックエンド** — Komariの監視・管理に加え、Nezha V1・V0と公開DStatusパネルの読み取り専用監視に対応。
- **サーバー概要** — ノードの状態、CPU、メモリ、ディスク、通信量、リアルタイムの通信速度、バックエンドが提供する遅延指標を確認。
- **ノード詳細** — ハードウェア情報や過去の指標を表示し、カードから詳細画面へ滑らかに遷移。
- **Komari管理** — ノード編集、Pingタスクやアラートの管理、確認付きのリモートコマンド実行、監査ログの閲覧。
- **カスタマイズ** — ノードの検索・並べ替え・非表示、ライト・ダークテーマ、アクセントカラーの変更。
- **多言語対応** — 中国語（簡体字・繁体字）、英語、日本語、韓国語に対応。
- **直接接続とプライバシー** — 認証情報はiOS Keychainに保存。標準でHTTPSを使用し、中継サービスや分析・追跡SDKは使用しません。

## ダウンロードとインストール

**iOS / iPadOS 16.0以降**が必要です。

1. [Releases](https://github.com/Likhixang/Monitor-Panel-iOS/releases/latest)から`Monitor-Panel-iOS-unsigned.ipa`をダウンロードします。
2. SideStore、AltStore、または自身の署名証明書を使って署名し、インストールします。
3. **パネル → パネルを追加**からバックエンドを選び、アドレスと認証情報を入力します。公開DStatusパネルにはAPI keyは不要です。

## ローカルビルド

**macOS、Xcode 26、XcodeGen**が必要です。サードパーティ製のランタイム依存関係はありません。

```sh
brew install xcodegen
xcodegen generate
open KomariPanel.xcodeproj
```

実機にインストールする場合は、Xcodeで自身の署名チームを選択し、コード署名を有効にしてください。
