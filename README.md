# Monitor Panel iOS

**English** | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [한국어](README.ko.md) | [日本語](README.ja.md)

A native server monitoring app for iPhone and iPad. Connect your Komari, Nezha, and DStatus panels in one place, check server health at a glance, and manage Komari nodes on the go.

Built with SwiftUI. Supports iOS 16 and later, with Liquid Glass on iOS 26.

## Preview

<p align="center">
  <img src="docs/screenshots/en-preview.png" width="620" alt="Overview and node details">
</p>

## Features

- **Multiple backends** — Komari monitoring and management; read-only monitoring for Nezha V1, Nezha V0, and public DStatus panels.
- **Server overview** — Node status, CPU, memory, disk, traffic, network speeds, and available latency metrics.
- **Node details** — Hardware information and historical metrics, with smooth card-to-detail navigation.
- **Komari management** — Edit nodes, manage Ping tasks and alerts, send remote commands with confirmation, and view audit logs.
- **Personalization** — Search, reorder and hide nodes; choose light or dark appearance and custom accent colors.
- **Multilingual** — Simplified Chinese, Traditional Chinese, English, Japanese, and Korean.
- **Direct connections** — Credentials stored in the iOS Keychain. HTTPS by default, with no relay service or analytics SDK.

## Installation

Requires **iOS / iPadOS 16.0 or later**.

1. Download `Monitor-Panel-iOS-unsigned.ipa` from [Releases](https://github.com/Likhixang/Monitor-Panel-iOS/releases/latest).
2. Sign and install it with SideStore, AltStore, or your own signing certificate.
3. Open **Panels → Add Panel**, choose a backend, and enter its address and credentials. Public DStatus panels do not require an API key.

## Build

Requires **macOS, Xcode 26, and XcodeGen**. No third-party runtime dependencies.

```sh
brew install xcodegen
xcodegen generate
open KomariPanel.xcodeproj
```

To install a local build on a device, select your signing team and enable code signing in Xcode.
